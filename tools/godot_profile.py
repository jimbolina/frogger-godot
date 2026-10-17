"""Local-only receiver for Godot 4's built-in debugger profiler packets.

Uses the documented Variant encoding and remote_debugger_peer.cpp framing.
Only scalar/array profiler data is decoded; object deserialization is forbidden.
"""
import json
import socket
import struct
import threading
from collections import defaultdict


def encode(value):
    if isinstance(value, bool):
        return struct.pack('<II', 1, int(value))
    if isinstance(value, int):
        return struct.pack('<Iq', 2 | (1 << 16), value)
    if isinstance(value, str):
        raw = value.encode('utf-8')
        return struct.pack('<II', 4, len(raw)) + raw + bytes(-len(raw) % 4)
    if isinstance(value, list):
        return struct.pack('<II', 28, len(value)) + b''.join(map(encode, value))
    raise ValueError('Unsupported outbound profiler value')


def decode(raw):
    offset = 0

    def take(fmt):
        nonlocal offset
        values = struct.unpack_from('<' + fmt, raw, offset)
        offset += struct.calcsize('<' + fmt)
        return values[0] if len(values) == 1 else values

    def value():
        nonlocal offset
        header = take('I')
        kind, wide = header & 0xffff, bool(header & (1 << 16))
        if kind == 0:
            return None
        if kind == 1:
            return bool(take('I'))
        if kind == 2:
            return take('q' if wide else 'i')
        if kind == 3:
            return take('d' if wide else 'f')
        if kind in (4, 21):
            length = take('I')
            result = raw[offset:offset + length].decode('utf-8')
            offset += length + (-length % 4)
            return result
        if kind == 28:
            if header >> 16:
                raise ValueError('Typed arrays are not profiler wire arrays')
            return [value() for _ in range(take('I') & 0x7fffffff)]
        if kind in (30, 31, 32, 33):
            return [take({30: 'i', 31: 'q', 32: 'f', 33: 'd'}[kind]) for _ in range(take('I'))]
        if kind == 34:
            result = []
            for _ in range(take('I')):
                length = take('I')
                result.append(raw[offset:offset + length].rstrip(b'\0').decode('utf-8'))
                offset += length + (-length % 4)
            return result
        raise ValueError(f'Unsupported profiler Variant type {kind}')

    result = value()
    if offset != len(raw):
        raise ValueError('Trailing profiler packet bytes')
    return result


class ProfileCapture:
    def __init__(self, output):
        self.output = output
        self.messages = []
        self.error = None
        self.listener = socket.socket()
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen(1)
        self.listener.settimeout(30)
        self.port = self.listener.getsockname()[1]
        self.thread = threading.Thread(target=self._receive, daemon=True)
        self.thread.start()

    def _receive(self):
        try:
            with self.listener.accept()[0] as peer:
                peer.settimeout(1200)
                buffer = bytearray()
                while chunk := peer.recv(65536):
                    buffer.extend(chunk)
                    while len(buffer) >= 4:
                        size = struct.unpack_from('<I', buffer)[0]
                        if size > 8 * 1024 * 1024:
                            raise ValueError('Oversized profiler packet')
                        if len(buffer) < size + 4:
                            break
                        message = decode(buffer[4:size + 4])
                        self.messages.append(message)
                        if message[0] == 'set_pid':
                            for command in [['profiler:servers', message[1], [True, [2048, True]]],
                                            ['profiler:visual', message[1], [True]]]:
                                packet = encode(command)
                                peer.sendall(struct.pack('<I', len(packet)) + packet)
                        del buffer[:size + 4]
        except (OSError, ValueError, struct.error) as error:
            self.error = str(error)
        finally:
            self.listener.close()

    def finish(self):
        self.thread.join(15)
        self.output.write_text(json.dumps(self.messages))
        if self.thread.is_alive() or self.error:
            raise RuntimeError('Profiler capture failed: ' + str(self.error))
        if not any(message[0] == 'servers:profile_frame' for message in self.messages):
            raise RuntimeError('Godot did not return script profiler data')
        names = {m[2][1]: m[2][0] for m in self.messages if m[0] == 'servers:function_signature'}
        begin = next((m[2][0] for m in self.messages if m[0] == 'terrain:measurement_begin'), 0)
        end = next((m[2][0] for m in self.messages if m[0] == 'terrain:measurement_end'), 2**63)
        totals = defaultdict(lambda: [0, 0.0, 0.0, 0.0])
        count = 0
        for message in self.messages:
            if message[0] != 'servers:profile_frame':
                continue
            frame = message[2]
            if not begin < frame[0] <= end:
                continue
            count += 1
            offset = 7
            for _ in range(frame[6]):
                offset += 2 + frame[offset + 1]
            size = frame[offset]
            for index in range(offset + 1, offset + 1 + size, 5):
                row = frame[index:index + 5]
                for column in range(4):
                    totals[row[0]][column] += row[column + 1]
        rows = [dict(function=names[key], calls=values[0], self_seconds=values[1],
                     total_seconds=values[2], native_seconds=values[3]) for key, values in totals.items()]
        rows.sort(key=lambda row: row['self_seconds'], reverse=True)
        self.output.with_suffix('.summary.json').write_text(json.dumps(dict(frames=count, functions=rows), indent=2))

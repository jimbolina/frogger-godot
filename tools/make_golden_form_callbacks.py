#!/usr/bin/env python3
"""Verify code identity facts for the five independently inspected v3.0e callbacks."""
import argparse
import hashlib
import json
import struct
from pathlib import Path

OUTPUT = Path(__file__).resolve().parents[1] / 'tests/golden/pc-retail-v3.0e/form_callbacks.json'
FUNCTIONS = (
    ('GenBlockCollPrimCallback', 0x428390, 0x4284d8, 'collision'),
    ('GenBlockWaterFallCollPrimCallback', 0x4287a0, 0x4287b8, 'collision'),
    ('GenBlockFallCollPrimCallback', 0x4287c0, 0x428942, 'collision'),
    ('OrgFlyCallBack', 0x4231d0, 0x4231e0, 'bonus'),
    ('GenButterFlyCallBack', 0x4284e0, 0x4284fc, 'bonus'),
)


def facts(executable):
    """Locate PE sections independently; retain hashes and addresses, never bytes."""
    data = executable.read_bytes()
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError('Expected a PE executable')
    count = struct.unpack_from('<H', data, pe + 6)[0]
    optional_size = struct.unpack_from('<H', data, pe + 20)[0]
    image_base = struct.unpack_from('<I', data, pe + 52)[0]
    sections = pe + 24 + optional_size
    rows = []
    for name, start, end, kind in FUNCTIONS:
        for index in range(count):
            at = sections + index * 40
            virtual_size, rva, size, offset = struct.unpack_from('<IIII', data, at + 8)
            relative = start - image_base - rva
            if 0 <= relative and relative + end - start <= size:
                body = data[offset + relative:offset + relative + end - start]
                rows.append(dict(name=name, address=start, file_offset=offset + relative, length=end - start, kind=kind,
                                 sha256=hashlib.sha256(body).hexdigest()))
                break
        else:
            raise ValueError(f'Function {name} is outside executable sections')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', required=True, type=Path)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = json.dumps(facts(args.exe), indent=2) + '\n'
    if args.write:
        OUTPUT.write_text(text, encoding='utf-8')
    elif OUTPUT.read_text(encoding='utf-8') != text:
        raise ValueError('Callback code identities differ from the verified v3.0e functions')
    print(f'Verified {len(FUNCTIONS)} v3.0e FORM callback code identities.')


if __name__ == '__main__':
    main()

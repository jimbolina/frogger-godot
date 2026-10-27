"""Read v3.0e SCORE_BOOK independently and derive frozen score-operation facts."""
import argparse
import json
import struct
from pathlib import Path


def table(executable):
    data = executable.read_bytes()
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    count = struct.unpack_from('<H', data, pe + 6)[0]
    optional = struct.unpack_from('<H', data, pe + 20)[0]
    base = struct.unpack_from('<I', data, pe + 52)[0]
    for index in range(count):
        at = pe + 24 + optional + index * 40
        _, rva, length, offset = struct.unpack_from('<IIII', data, at + 8)
        relative = 0x472b80 - base - rva
        if 0 <= relative and relative + 24 * 12 <= length:
            return [dict(zip(('value', 'texture', 'flags'), struct.unpack_from('<iII', data, offset + relative + row * 12))) for row in range(24)]
    raise ValueError('SCORE_BOOK lies outside PE sections')


def operations():
    rows = []
    for score, threshold, lives, amount, clamp in [(0, 10000, 3, -500, True), (9999, 10000, 3, 5, False), (0, 10000, 3, 30000, False), (99999990, 10000, 10, 25, False), (2147483640, 10000, 3, 50, False), (20000, 20000, 10, 0, False)]:
        new = ((score + amount + 2**31) % 2**32) - 2**31
        if new > 99999999:
            new -= 99999999
        bonus = (new & 0xffffffff) >= threshold
        rows.append(dict(score=score, threshold=threshold, lives=lives, amount=amount, clamp=clamp,
                         expected_score=max(0, new) if clamp else new,
                         expected_threshold=(threshold + 10000) & 0xffffffff if bonus else threshold,
                         expected_lives=min(lives + 1, 10) if bonus else lives))
    return rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / 'tests/golden'
    (root / 'pc-retail-v3.0e/rewards.json').write_text(json.dumps(table(args.exe), indent=2) + '\n')
    (root / 'synthetic/rewards.json').write_text(json.dumps(operations(), indent=2) + '\n')

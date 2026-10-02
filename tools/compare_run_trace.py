"""Compare complete integer P7 JSONL traces, with first-divergence diagnostics."""
import argparse
import json
from pathlib import Path
import sys


def read(path):
    rows = [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line.strip()]
    if not rows or not isinstance(rows[0], dict) or rows[0].get('schema') != 'terrain-run-v1':
        raise ValueError(f'{path}: missing terrain-run-v1 metadata')
    limit = rows[0].get('tick_limit')
    if type(limit) is not int or not 0 <= limit <= 100000:
        raise ValueError(f'{path}: invalid metadata tick_limit {limit!r}')
    phases = ('control', 'move', 'collision', 'camera', 'final')
    for index, row in enumerate(rows[1:]):
        if not isinstance(row, dict):
            raise ValueError(f'{path}: phase record must be an object')
        key = (row.get('tick'), row.get('phase'))
        expected = (index // len(phases), phases[index % len(phases)])
        if type(key[0]) is not int or key != expected:
            raise ValueError(f'{path}: expected ordered tick/phase {expected}, got {key}')
        if row.get('error'):
            raise ValueError(f'{path}: unsupported execution: {row["error"]}')
        if not isinstance(row.get('state'), dict):
            raise ValueError(f'{path}: missing state object at tick/phase {key}')
        if index % len(phases) == 4 and row['state'].get('completed') is True and index != len(rows) - 2:
            raise ValueError(f'{path}: phase records follow completed execution at tick {key[0]}')
    count = len(rows) - 1
    if count % len(phases):
        raise ValueError(f'{path}: incomplete final tick: {count} phase records')
    ticks = count // len(phases)
    if ticks > limit or (ticks < limit and (not ticks or rows[-1].get('state', {}).get('completed') is not True)):
        raise ValueError(f'{path}: truncated execution: {ticks} ticks of tick_limit {limit} without terminal completion')
    return rows


def difference(expected, actual, field=''):
    if type(expected) is not type(actual):
        return field, expected, actual
    if isinstance(expected, dict):
        if expected.keys() != actual.keys():
            return field + '.keys', sorted(expected), sorted(actual)
        for key in expected:
            result = difference(expected[key], actual[key], field + '.' + key)
            if result:
                return result
    elif isinstance(expected, list):
        if len(expected) != len(actual):
            return field + '.length', len(expected), len(actual)
        for index, (left, right) in enumerate(zip(expected, actual)):
            result = difference(left, right, f'{field}[{index}]')
            if result:
                return result
    elif expected != actual:
        return field, expected, actual
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('expected', type=Path)
    parser.add_argument('actual', type=Path)
    parser.add_argument('--reproduce', default='Repeat the recorded scenario, seed and command stream with tools/run_terrain.py')
    args = parser.parse_args()
    expected, actual = read(args.expected), read(args.actual)
    for index in range(max(len(expected), len(actual))):
        left = expected[index] if index < len(expected) else '<extra row>'
        right = actual[index] if index < len(actual) else '<missing row>'
        mismatch = difference(left, right)
        if mismatch:
            field, wanted, got = mismatch
            location = left if isinstance(left, dict) else right
            print(f'First difference: row {index}, tick {location.get("tick", "metadata")}, phase {location.get("phase", "metadata")}, field {field}')
            print(f'Expected {wanted!r}; actual {got!r}; bound: exact integer/value equality')
            print('Recent commands, grid identities and RNG consumers:')
            for row in actual[max(1, index - 10):index + 1]:
                state = row.get('state', {})
                print(json.dumps({key: row.get(key) for key in ('tick', 'phase', 'pressed', 'held', 'rng_consumers')} |
                                 {'cell': state.get('cell'), 'square': state.get('square_index'), 'source': state.get('source_id')}))
            print('Reproduce: ' + args.reproduce)
            return 1
    print(f'Exact match: {len(expected) - 1} phase records plus metadata')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, TypeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)

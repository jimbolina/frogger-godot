#!/usr/bin/env python3
"""Independent synthetic facts for frozen scripter.c UpdateScriptInfo motion."""
import argparse
import copy
import json
import math
from pathlib import Path

OUTPUT = Path(__file__).resolve().parents[1] / 'tests/golden/synthetic/script_motion.json'


def short(value):
    """Store one signed-short source field."""
    return (value + 32768) % 65536 - 32768


def signed(value):
    """Store one signed-long source field."""
    return (value + 2147483648) % 4294967296 - 2147483648


def rounded(value):
    """Frozen rounded trigonometry, with ties away from zero."""
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def step(state):
    """Update source translation and angle fields, without a GDScript dependency."""
    for position, delta, count, destination, rotation in [
        ('offsets', 'deltas', 'counts', 'destinations', False),
        ('angles', 'angular_deltas', 'angular_counts', 'angular_destinations', True),
    ]:
        for axis in range(3):
            velocity = state[delta][axis]
            remaining = state[count][axis]
            if remaining == 0 or (remaining < 0 and velocity == 0):
                continue
            value = short(state[position][axis] + (velocity if rotation else velocity >> 8))
            if remaining > 0:
                if rotation:
                    value &= 4095
                state[count][axis] = short(remaining - 1)
                if state[count][axis] == 0:
                    state[delta][axis] = 0
            elif (velocity > 0 and value >= state[destination][axis]) or (velocity < 0 and value <= state[destination][axis]):
                value = state[destination][axis]
                if rotation:
                    value &= 4095
                state[delta][axis] = state[count][axis] = 0
            state[position][axis] = value


def matrix(state, base, authored=None):
    """Frozen path postmultiplication and matrix-mode authored premultiplication."""
    current = [base[i:i + 3] for i in range(0, 9, 3)] if authored is None else [[4096, 0, 0], [0, 4096, 0], [0, 0, 4096]]
    for axis, angle in enumerate(state['angles']):
        if not angle:
            continue
        cosine = rounded(math.cos((angle & 4095) * math.tau / 4096) * 4096)
        sine = rounded(math.sin((angle & 4095) * math.tau / 4096) * 4096)
        rotations = [
            [[4096, 0, 0], [0, cosine, -sine], [0, sine, cosine]],
            [[cosine, 0, sine], [0, 4096, 0], [-sine, 0, cosine]],
            [[cosine, -sine, 0], [sine, cosine, 0], [0, 0, 4096]],
        ]
        current = [[short(signed(sum(current[r][k] * rotations[axis][k][c] for k in range(3))) >> 12)
                    for c in range(3)] for r in range(3)]
    if authored is not None:
        if any(state['angles']):
            current = [[short(signed(sum(current[r][k] * authored[k * 3 + c] for k in range(3))) >> 12)
                        for c in range(3)] for r in range(3)]
        else:
            current = [base[i:i + 3] for i in range(0, 9, 3)]
    origin = base if authored is None else authored
    return sum(current, []) + [signed(origin[9 + i] + state['offsets'][i]) for i in range(3)]


def facts():
    """Invented states cover duration, destination, wrapping and noncommuting axes."""
    definitions = [
        ('duration', dict(deltas=[256, -512, 1024], counts=[1, 2, 3], angular_deltas=[512, -256, 128], angular_counts=[2, 3, 4])),
        ('destinations', dict(deltas=[768, -1024, 0], counts=[-1, -1, -1], destinations=[5, -7, 4], angular_deltas=[600, -600, 0], angular_counts=[-1, -1, -1], angular_destinations=[1024, -1024, 500])),
        ('narrowing', dict(offsets=[32767, -32768, 10], deltas=[256, -256, -1], counts=[2, 2, 2], angles=[32760, -32760, 4090], angular_deltas=[32, -32, 128], angular_counts=[-1, -1, 2], angular_destinations=[32767, -32768, 0])),
        ('stopped', dict(offsets=[8, -16, 32], deltas=[1024, -2048, 4096], angles=[257, 511, 1023], angular_deltas=[128, 256, -512])),
    ]
    output = []
    for name, initial in definitions:
        state = {key: [0, 0, 0] for key in ['offsets', 'deltas', 'counts', 'destinations', 'angles', 'angular_deltas', 'angular_counts', 'angular_destinations']}
        state.update(initial)
        initial = copy.deepcopy(state)
        base = [0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 2147483640, 200, -2147483640]
        rows = []
        for _ in range(5):
            step(state)
            rows.append(dict(state=copy.deepcopy(state), matrix=matrix(state, base)))
        output.append(dict(name=name, initial=initial, base=base, expected=rows))
        state = copy.deepcopy(initial)
        current = base[:]
        rows = []
        for _ in range(5):
            step(state)
            current = matrix(state, current, base)
            rows.append(dict(state=copy.deepcopy(state), matrix=current))
        output.append(dict(name='matrix_' + name, initial=initial, base=base, entity_type=1, expected=rows))
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = json.dumps(facts(), indent=2) + '\n'
    if args.write:
        OUTPUT.write_text(text, encoding='utf-8')
    elif OUTPUT.read_text(encoding='utf-8') != text:
        raise ValueError('Script motion facts differ from the independent source model')
    print('Script motion facts verified.')


if __name__ == '__main__':
    main()

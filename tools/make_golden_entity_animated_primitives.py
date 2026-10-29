#!/usr/bin/env python3
"""Invented animated-model primitive contacts, from frozen MR_COLL.C and MR_ANIM.C.

An independent Python reading of MRCheckCollPrimWithWorldPoint for a cuboid
framed by an animated part's stored LW transform: the frog point comes from
its own stored part transform; the entity LW is MRMulMatrixABC(root, part)
with the part translation rotated and added; the collision rotation is
LW x cp_matrix (the matrix translation is ignored) or LW alone; cp_offset is
rotated by LW only; the point offset narrows to a short; the local vector is
transpose(rotation) times that offset; the cuboid test is strict.

Sequences model the MRColl_lw_ptr/MRColl_matrix_ptr/MRColl_transmatrix
globals: the rotation is rebuilt only when the frame or matrix identity
changes, and a disabled primitive returns before touching them.

No retail bytes are used. By default the script verifies the committed file;
--write regenerates it.
Usage: python3 tools/make_golden_entity_animated_primitives.py [--write]
"""
import argparse
import copy
import json
import random
import sys
from pathlib import Path

IDENTITY = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]
PLANT_ROTATION = [4096, 0, 0, 0, 4094, 103, 0, -103, 4094]
DISABLED = 256
OUTPUT = Path(__file__).resolve().parents[1] / 'tests/golden/synthetic/entity_animated_primitives.json'


def signed(value, bits):
    return (value + (1 << (bits - 1))) % (1 << bits) - (1 << (bits - 1))


def dot(a, b):
    return signed(sum(x * y for x, y in zip(a, b)), 32) >> 12


def row(matrix, r):
    return matrix[r * 3:r * 3 + 3]


def column(matrix, c):
    return [matrix[c], matrix[3 + c], matrix[6 + c]]


def mul_abc(a, b):
    """MRMulMatrixABC rotation: signed32 sums shifted by 12, stored as shorts."""
    return [signed(dot(row(a, r), column(b, c)), 16) for r in range(3) for c in range(3)]


def lw_transform(root, part):
    rotation = mul_abc(root, part)
    translation = [signed(dot(row(root, r), part[9:12]) + root[9 + r], 32) for r in range(3)]
    return rotation + translation


def frog_point(case):
    lw = lw_transform(case['frog_root'], case['frog_part'])
    return [signed(signed(dot(row(lw, r), case['vertex']), 16) + lw[9 + r], 16) for r in range(3)]


def narrow(point, lw, rotation, primitive):
    offset = [dot(row(lw, r), primitive['offset']) for r in range(3)]
    delta = [signed(point[r] - lw[9 + r] - offset[r], 16) for r in range(3)]
    local = [dot(column(rotation, c), delta) for c in range(3)]
    hit = not primitive['flags'] & DISABLED and all(abs(v) < length for v, length in zip(local, primitive['half_size']))
    return delta, local, bool(hit)


def collision_rotation(lw, primitive):
    return mul_abc(lw, primitive['matrix'][:9]) if primitive['matrix'] else lw[:9]


def evaluate(case):
    point = frog_point(case)
    lw = lw_transform(case['entity_root'], case['part_frame'])
    rotation = collision_rotation(lw, case['primitive'])
    delta, local, hit = narrow(point, lw, rotation, case['primitive'])
    return dict(world=point, lw=lw, rotation=rotation, delta=delta, local=local, hit=hit)


def aim(case, local):
    """Chooses an identity-frog vertex near the given primitive-axis position."""
    lw = lw_transform(case['entity_root'], case['part_frame'])
    rotation = collision_rotation(lw, case['primitive'])
    centre = [lw[9 + r] + dot(row(lw, r), case['primitive']['offset']) for r in range(3)]
    case['vertex'] = [centre[r] + dot(row(rotation, r), local) for r in range(3)]


def primitive(offset=(0, 0, 0), half_size=(10, 20, 30), matrix=None, flags=2):
    return dict(offset=list(offset), half_size=list(half_size), flags=flags,
                matrix=(list(matrix[:9]) + [11, -22, 33]) if matrix else [])


def base_case(name):
    return dict(name=name, frog_root=IDENTITY[:], frog_part=IDENTITY[:], vertex=[0, 0, 0],
                entity_root=IDENTITY[:], part_frame=IDENTITY[:], primitive=primitive())


def cases():
    result = []
    case = base_case('matrix-rotated-offset')
    case['entity_root'] = [0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 100, 200, 300]
    case['part_frame'] = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 5, -7, 9]
    case['primitive'] = primitive((10, 20, 30), (6, 5, 4), [4096, 0, 0, 0, 0, -4096, 0, 4096, 0])
    aim(case, [2, 1, -1])
    result.append(case)
    rotated = [0, -4096, 0, 4096, 0, 0, 0, 0, 4096]
    for axis in range(3):
        for sign in (-1, 1):
            for inset in (0, 1):
                case = base_case('strict-face-%d-%d-inset-%d' % (axis, sign, inset))
                case['primitive'] = primitive((0, 0, 0), (10, 20, 30), rotated)
                local = [0, 0, 0]
                local[axis] = sign * ([10, 20, 30][axis] - inset)
                case['vertex'] = [dot(row(rotated, r), local) for r in range(3)]
                result.append(case)
    case = base_case('double-truncation')
    case['entity_root'] = [2047, 0, 2049, 0, 4096, 0, -2049, 0, 2047, 3, 4, 5]
    case['part_frame'] = [4095, 7, 0, -7, 4095, 0, 0, 0, 4096, 1, 1, 1]
    case['primitive'] = primitive((3, -5, 7), (40, 40, 40), [2895, -2896, 0, 2896, 2895, 0, 0, 0, 4096])
    case['vertex'] = [37, -11, 23]
    result.append(case)
    case = base_case('short-offset-wrap')
    case['entity_root'][9] = 65536
    case['primitive'] = primitive((0, 0, 0), (2, 2, 2), PLANT_ROTATION)
    case['vertex'] = [1, 0, 0]
    result.append(case)
    case = base_case('negative-fraction-shift')
    case['entity_root'][4] = 2048
    case['primitive'] = primitive((0, -3, 0), (1, 2, 1), [4096, 0, 0, 0, 4095, 1, 0, -1, 4095])
    case['vertex'] = [0, -1, 0]
    result.append(case)
    case = base_case('plant-103-rotation')
    case['entity_root'] = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -1200, 64, 3000]
    case['part_frame'] = [4096, 0, 0, 0, 3547, -2048, 0, 2048, 3547, 0, 180, -40]
    case['primitive'] = primitive((0, -60, 500), (80, 90, 60), PLANT_ROTATION)
    aim(case, [20, -70, 15])
    result.append(case)
    case = base_case('plant-103-rotation-without-matrix')
    case.update(copy.deepcopy(result[-1]))
    case['name'] = 'plant-103-rotation-without-matrix'
    case['primitive']['matrix'] = []
    result.append(case)
    case = base_case('disabled')
    case['primitive'] = primitive(matrix=PLANT_ROTATION, flags=258)
    result.append(case)
    rng = random.Random(1997)
    headings = [IDENTITY[:9], [0, 0, 4096, 0, 4096, 0, -4096, 0, 0], [-4096, 0, 0, 0, 4096, 0, 0, 0, -4096],
                [0, 0, -4096, 0, 4096, 0, 4096, 0, 0], PLANT_ROTATION, [4096, 0, 0, 0, 3547, -2048, 0, 2048, 3547]]
    for index in range(48):
        case = base_case('invented-%d' % index)
        case['frog_root'] = rng.choice(headings) + [rng.randrange(-100, 101) for _ in range(3)]
        case['frog_part'] = rng.choice(headings) + [rng.randrange(-50, 51) for _ in range(3)]
        case['vertex'] = [rng.randrange(-64, 65) for _ in range(3)]
        case['entity_root'] = rng.choice(headings) + [rng.randrange(-100, 101) for _ in range(3)]
        case['part_frame'] = rng.choice(headings) + [rng.randrange(-60, 61) for _ in range(3)]
        case['primitive'] = primitive([rng.randrange(-32, 33) for _ in range(3)], [rng.randrange(10, 201) for _ in range(3)],
                                      rng.choice(headings) if rng.randrange(4) else None)
        result.append(case)
    for case in result:
        case['expected'] = evaluate(case)
    return result


def check(frame, primitive_record, frame_key, matrix_key, point):
    return dict(frame=frame, primitive=primitive_record, frame_key=frame_key, matrix_key=matrix_key, point=point)


def sequences():
    """Each check uses frame_key/matrix_key identities; [] means no primitive matrix."""
    first = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]
    turned = [0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 40, 0, -20]
    other = [-4096, 0, 0, 0, 4096, 0, 0, 0, -4096, 5, 5, 5]
    long_x = primitive((0, 0, 0), (60, 10, 10))
    long_x_matrix = primitive((0, 0, 0), (60, 10, 10), PLANT_ROTATION)
    long_x_turn = primitive((0, 0, 0), (60, 10, 10), [0, 0, -4096, 0, 4096, 0, 4096, 0, 0])
    disabled = primitive((0, 0, 0), (60, 10, 10), flags=258)
    lw_a = ['lw', 3, 1, 4]
    lw_b = ['lw', 7, 1, 0]
    m_a = [318, 4, 0]
    m_b = [355, 4, 0]
    result = [
        dict(name='same-keys-mutated-contents', checks=[
            check(first, long_x_matrix, lw_a, m_a, [50, 0, 0]),
            check(turned, long_x_matrix, lw_a, m_a, [90, 0, -20])]),
        dict(name='different-frame-between', checks=[
            check(first, long_x_matrix, lw_a, m_a, [50, 0, 0]),
            check(other, long_x, lw_b, [], [0, 0, 0]),
            check(turned, long_x_matrix, lw_a, m_a, [90, 0, -20])]),
        dict(name='different-matrix-between', checks=[
            check(first, long_x, ['live', 2, 0], [], [50, 0, 0]),
            check(turned, long_x_turn, ['live', 2, 0], m_b, [40, 0, -70]),
            check(turned, long_x, ['live', 2, 0], [], [90, 0, -20])]),
        dict(name='matrix-to-none', checks=[
            check(first, long_x_matrix, lw_a, m_a, [50, 0, 0]),
            check(turned, long_x, lw_a, [], [90, 0, -20])]),
        dict(name='disabled-leaves-cache', checks=[
            check(first, long_x, ['map', 9], [], [50, 0, 0]),
            check(other, disabled, ['map', 1], [], [5, 5, 5]),
            check(turned, long_x, ['map', 9], [], [90, 0, -20])]),
    ]
    for sequence in result:
        keys = None
        rotation = None
        for item in sequence['checks']:
            prim = item['primitive']
            if prim['flags'] & DISABLED:
                item['expected'] = dict(status='disabled', rotation=[], hit=False, local=[0, 0, 0])
                continue
            identity = (tuple(item['frame_key']), tuple(item['matrix_key']))
            if identity != keys:
                keys = identity
                rotation = collision_rotation(item['frame'], prim)
            fresh = collision_rotation(item['frame'], prim)
            _delta, local, hit = narrow(item['point'], item['frame'], rotation, prim)
            item['expected'] = dict(status='contact' if hit else 'miss', rotation=rotation, stale=rotation != fresh,
                                    hit=hit, local=local)
    return result


def document():
    return dict(schema='entity-animated-primitives-v1', cases=cases(), sequences=sequences())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--write', action='store_true', help='regenerate the committed golden file')
    parser.add_argument('--output', type=Path, default=OUTPUT)
    args = parser.parse_args()
    text = json.dumps(document(), indent=1) + '\n'
    if args.write:
        with open(args.output, 'w', encoding='utf-8', newline='\n') as handle:
            handle.write(text)
        print('wrote %s' % args.output)
        return 0
    if not args.output.exists() or args.output.read_text(encoding='utf-8') != text:
        print('MISMATCH: %s differs from the independent evaluation' % args.output, file=sys.stderr)
        return 1
    print('verified %s' % args.output)
    return 0


if __name__ == '__main__':
    sys.exit(main())

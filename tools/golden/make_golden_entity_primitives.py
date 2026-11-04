#!/usr/bin/env python3
"""Invented numeric probes/cuboids: independent Python, checked by frozen C."""
import argparse
import copy
import csv
import io
import json
import os
from pathlib import Path
import random
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT

IDENTITY = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]


def signed(value, bits):
    return (value + (1 << (bits - 1))) % (1 << bits) - (1 << (bits - 1))


def dot(a, b):
    return signed(sum(x*y for x, y in zip(a, b)), 32) >> 12


def evaluate(case):
    root, part, vertex, owner = (case[k] for k in ('root', 'part', 'vertex', 'owner'))
    rotation = [signed(dot(root[r*3:r*3+3], part[c:9:3]), 16)
                for r in range(3) for c in range(3)]
    translation = [signed(dot(root[r*3:r*3+3], part[9:12])+root[9+r], 32) for r in range(3)]
    world = [signed(signed(dot(rotation[r*3:r*3+3], vertex), 16)+translation[r], 16)
             for r in range(3)]
    offset = [dot(owner[r*3:r*3+3], case['offset']) for r in range(3)]
    delta = [signed(world[r]-owner[9+r]-offset[r], 16) for r in range(3)]
    local = [dot(owner[c:9:3], delta) for c in range(3)]
    hit = not case['flags'] & 256 and all(abs(v) < length for v, length in zip(local, case['half_size']))
    return dict(world=world, hit=bool(hit))


def cases():
    base = dict(name='origin', root=IDENTITY[:], part=IDENTITY[:], vertex=[0, 0, 0],
                owner=IDENTITY[:], offset=[0, 0, 0], half_size=[10, 20, 30], flags=2, reaction=1)
    result = [copy.deepcopy(base)]
    for axis in range(3):
        for sign in (-1, 1):
            for inset in (0, 1):
                case = copy.deepcopy(base)
                case['name'] = f'face-{axis}-{sign}-inset-{inset}'
                case['vertex'][axis] = sign*(case['half_size'][axis]-inset)
                result.append(case)
    case = copy.deepcopy(base)
    case.update(name='rotated-offset', owner=[0,0,4096,0,4096,0,-4096,0,0,100,200,300],
                offset=[10,20,30], half_size=[6,5,4], vertex=[133,224,285])
    result.append(case)
    case = copy.deepcopy(base)
    case.update(name='short-displacement-wrap', vertex=[1,0,0])
    case['owner'][9] = 65536
    result.append(case)
    case = copy.deepcopy(base)
    case.update(name='world-short-wrap', vertex=[1,-1,3])
    case['root'][9] = 32767
    case['owner'][9] = -32768
    result.append(case)
    case = copy.deepcopy(base)
    case.update(name='composed-rotation-short-store', vertex=[2,0,0], half_size=[4,1,1])
    case['root'][0], case['root'][9], case['part'][0] = 8192, 10, 20000
    result.append(case)
    case = copy.deepcopy(base)
    case.update(name='negative-fraction-shift', vertex=[0,-1,0], half_size=[1,1,1])
    case['root'][4] = 2048
    result.append(case)
    case = copy.deepcopy(base)
    case.update(name='disabled', flags=258)
    result.append(case)
    case = copy.deepcopy(base)
    case.update(name='zero-half-extent', half_size=[0,20,30])
    result.append(case)
    rng = random.Random(1997)
    headings = [IDENTITY[:9], [0,0,4096,0,4096,0,-4096,0,0],
                [-4096,0,0,0,4096,0,0,0,-4096], [0,0,-4096,0,4096,0,4096,0,0]]
    for index in range(48):
        case = copy.deepcopy(base)
        case.update(name=f'invented-{index}', root=rng.choice(headings)+[rng.randrange(-100,101) for _ in range(3)],
                    part=rng.choice(headings)+[rng.randrange(-50,51) for _ in range(3)],
                    vertex=[rng.randrange(-64,65) for _ in range(3)],
                    owner=rng.choice(headings)+[rng.randrange(-100,101) for _ in range(3)],
                    offset=[rng.randrange(-32,33) for _ in range(3)],
                    half_size=[rng.randrange(10,201) for _ in range(3)])
        result.append(case)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--oracle', required=True, type=Path)
    parser.add_argument('--work-directory', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=REPO_ROOT/'tests/golden/synthetic/entity_primitives.json')
    args = parser.parse_args()
    repo = REPO_ROOT
    work = args.work_directory.resolve()
    for protected in (repo, repo.parent/'froggy'):
        if work == protected or protected in work.parents:
            parser.error('Work directory must be outside both repositories')
    work.mkdir(parents=True, exist_ok=True)
    invented = cases()
    keys = ('root','part','vertex','owner','offset','half_size')
    rows = [[v for key in keys for v in case[key]]+[case['flags'],case['reaction']] for case in invented]
    source = work/'entity-primitive-input.txt'
    source.write_text(str(len(rows))+'\n'+''.join(' '.join(map(str,row))+'\n' for row in rows), encoding='ascii')
    run = subprocess.run([str(args.oracle.resolve()), str(source)], text=True, capture_output=True,
                         timeout=30, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    (work/'entity-primitive-output.csv').write_text(run.stdout, encoding='utf-8')
    if run.returncode:
        raise ValueError(f'Frozen primitive oracle failed: {run.returncode}: {run.stderr}')
    lines = run.stdout.splitlines()
    header = lines.index('case,x,y,z,hit')
    actual = list(csv.DictReader(io.StringIO('\n'.join(lines[header:]))))
    if len(actual) != len(invented):
        raise ValueError('Frozen primitive oracle row count changed')
    for index, (case, row) in enumerate(zip(invented, actual)):
        expected = evaluate(case)
        found = dict(world=[int(row[k]) for k in 'xyz'], hit=bool(int(row['hit'])))
        if int(row['case']) != index or found != expected:
            raise ValueError(f'Frozen C/Python mismatch {case["name"]}: {found} != {expected}')
        case['expected'] = expected
    args.output.write_text(json.dumps(dict(schema='entity-primitives-v1', cases=invented), indent=2)+'\n', encoding='utf-8')
    print(f'{len(invented)} independent Python/frozen-C primitive and probe cases matched')


if __name__ == '__main__':
    main()

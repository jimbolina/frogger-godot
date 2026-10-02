#!/usr/bin/env python3
"""Independent UpdateFrogMatrix terrain facts cross-checked with frozen C."""
import argparse
import csv
import io
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
from make_golden_grid import normal, normalize, cross

HEIGHTS = [[0,0,0,0],[0,256,0,256],[-3,257,-131,121],[100,120,80,80],[300,-200,-100,400]]
FIELDS = ['scenario','direction','flags','square'] + [f'm{i}{j}' for i in range(3) for j in range(3)] + ['tx','ty','tz']

def expected():
    for scenario in range(7):
        for direction in range(4):
            previous = [[4096,0,0],[0,4096,0],[0,0,4096]]
            if scenario >= 5:
                previous = [[3000,1000,0],[0,3500,-1000],[100,0,3500]]
            if scenario == 6:
                matrix = previous
            else:
                if scenario == 5:
                    n = normalize([-previous[i][1] for i in range(3)])
                else:
                    h = HEIGHTS[scenario]
                    v = [[-256,h[0],0],[0,h[1],0],[-256,h[2],-256],[0,h[3],-256]]
                    if scenario == 3:
                        v[3] = v[2]
                    n = normal(v)
                facing = [[0,0,4096],[4096,0,0],[0,0,-4096],[-4096,0,0]][direction]
                x = normalize(cross(facing,n))
                z = cross(n,x)
                matrix = [[x[i],-n[i],z[i]] for i in range(3)]
            yield [scenario,direction,2049|(128 if scenario==6 else 0),-1 if scenario==5 else 5] + [n for row in matrix for n in row] + [-128,0,-128]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--c-oracle',required=True)
    parser.add_argument('--output',default='tests/golden/synthetic/terrain_matrix.csv')
    parser.add_argument('--verify',action='store_true')
    args = parser.parse_args()
    process = subprocess.run([args.c_oracle,'--matrix'],capture_output=True,text=True,check=True)
    lines = process.stdout.splitlines()
    start = next(i for i,line in enumerate(lines) if line.startswith('scenario,direction,'))
    stream = io.StringIO(newline='')
    writer = csv.writer(stream,lineterminator='\n')
    writer.writerow(FIELDS);writer.writerows(expected())
    text = stream.getvalue()
    actual = list(csv.reader(lines[start:])); facts = list(csv.reader(text.splitlines()))
    if actual != facts:
        for i,(a,b) in enumerate(zip(actual,facts)):
            if a != b:
                raise ValueError(f'Frozen C row {i}: {a} != independent Python {b}')
        raise ValueError('Frozen C record count differs')
    target = Path(args.output)
    if args.verify:
        if target.read_text() != text:
            raise ValueError('Golden facts differ')
    else:
        target.write_text(text,encoding='utf-8')
    print(f'Independent Python matched {len(facts)-1} frozen C matrix records.')

if __name__ == '__main__':
    main()

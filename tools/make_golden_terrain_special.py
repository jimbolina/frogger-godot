#!/usr/bin/env python3
"""Independent fixed grid-slip callback scenarios, checked against actual C."""
import argparse
import csv
import io
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
from make_golden_grid import normal, normalize, cross

FIELDS = ['scenario','tick','x16','y16','z16','vx16','vy16','vz16','grid_x','grid_z','count','flags','mode','direction','square','target_x','target_y','target_z','animation_requests','sound_requests','score_requests'] + [f'm{i}{j}' for i in range(3) for j in range(3)] + ['tx','ty','tz']
SPEEDS = [1,1,2,2,3,3,4,4,5]

def trunc(n,d):
    return (abs(n)//d)*(-1 if n<0 else 1)

def expected():
    for scenario in range(8):
        simple = scenario>=4
        kind = scenario%4
        vertices = []
        flags = [3]*16
        for i in range(16):
            x,z = -512+(i%4)*256,-512+(i//4)*256
            heights = [0]*4
            if i == 5 and kind == 1:
                heights = [128,128,-128,-128]
            if i == 9 and kind == 3:
                heights = [-449]*4
            vertices.append([[x,heights[0],z+256],[x+256,heights[1],z+256],[x,heights[2],z],[x+256,heights[3],z]])
        flags[5] = 1025 if simple else 17
        if kind == 2:
            flags[9] = 0
        position = [-128*65536,0,-128*65536]
        velocity = [0,0,0]
        cell = [1,1]; square = 5; count = 0; frogflags = 2049; mode = 0
        target = [0,0,0]; animations = 0
        matrix = [[4096,0,0],[0,4096,0],[0,0,4096]]
        translation = [-128,0,-128]

        def setup():
            nonlocal cell,square,count,frogflags,mode,target,velocity,animations
            delta = [0,1]; count = 10
            if not simple:
                sensed = [(translation[0]+((matrix[0][2]*25)>>12)+512)>>8,
                          (translation[2]+((matrix[2][2]*25)>>12)+512)>>8]
                idx = sensed[1]*4+sensed[0]
                h = sum(v[1] for v in vertices[idx])>>2
                if flags[idx]&1 and abs(translation[1]-h)<=448:
                    cell,square = sensed,idx
                n = normal(vertices[square])
                delta = [1 if n[0]>256 else -1 if n[0]<-256 else 0,
                         1 if n[2]>256 else -1 if n[2]<-256 else 0]
                if delta == [0,0]:
                    delta = [(-1 if velocity[0]<0 else 1),0] if velocity[0] else [0,(-1 if velocity[2]<0 else 1)] if velocity[2] else [0,1]
                else:
                    count = SPEEDS[max((-n[1])>>9,0)]
            dest = [cell[0]+delta[0],cell[1]+delta[1]]
            idx = dest[1]*4+dest[0]
            h = sum(v[1] for v in vertices[idx])>>2
            if flags[idx]&1 and translation[1]-h<=(448 if simple else 496) and h-translation[1]<=256:
                frogflags &= ~66
                cell,square = dest,idx
                target = [cell[0]*256-384,h,cell[1]*256-384]
                velocity = [trunc(target[i]*65536-position[i],count) for i in range(3)]
                animations += 1
            else:
                count = 0
                mode = 0
                target = [p>>16 for p in position]
                if not simple:
                    frogflags &= ~82422
                    velocity = [0,0,0]
            mode = 267 if simple else 258

        def row(tick):
            return [scenario,tick]+position+velocity+cell+[count,frogflags,mode,0,square]+target+[animations,0,0]+[n for r in matrix for n in r]+translation

        setup()
        yield row(-1)
        for tick in range(15):
            if mode in (258,267):
                react = count == 0
                if react:
                    position = [v*65536 for v in target]
                    mode = 0
                    animations += 1
                else:
                    position = [p+v for p,v in zip(position,velocity)]
                    count -= 1
                n = normal(vertices[square])
                x = normalize(cross([0,0,4096],n));z = cross(n,x)
                matrix = [[x[i],-n[i],z[i]] for i in range(3)]
                translation = [p>>16 for p in position]
                cell = [(translation[0]+512)>>8,(translation[2]+512)>>8]
                if react and flags[square] in (17,1025):
                    setup()
            yield row(tick)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--c-oracle',required=True)
    parser.add_argument('--output',default='tests/golden/synthetic/terrain_special.csv')
    parser.add_argument('--verify',action='store_true')
    args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--special'],capture_output=True,text=True,check=True)
    lines=process.stdout.splitlines();start=next(i for i,s in enumerate(lines) if s.startswith('scenario,tick,'))
    stream=io.StringIO(newline='');writer=csv.writer(stream,lineterminator='\n');writer.writerow(FIELDS);writer.writerows(expected())
    text=stream.getvalue();actual=list(csv.reader(lines[start:]));facts=list(csv.reader(text.splitlines()))
    if actual!=facts:
        for i,(a,b) in enumerate(zip(actual,facts)):
            if a!=b:
                raise ValueError(f'Frozen C row {i}: {a} != independent Python {b}')
        raise ValueError('Frozen C record count differs')
    target=Path(args.output)
    if args.verify:
        if target.read_text()!=text: raise ValueError('Golden facts differ')
    else: target.write_text(text,encoding='utf-8')
    print(f'Independent Python matched {len(facts)-1} frozen C grid-slip records.')

if __name__=='__main__':main()

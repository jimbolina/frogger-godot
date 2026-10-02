#!/usr/bin/env python3
"""Independent freeform movement callback facts; controls are a separate family."""
import argparse
import csv
import io
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode=True
from make_golden_grid import normal, normalize, cross, surface
from make_golden_terrain_special import FIELDS

def expected():
    for scenario in range(5):
        position=[-128*65536,0,-128*65536];velocity=[0,0,8*65536]
        cell=[1,1];count=0;flags=2049;mode=262;direction=0;square=5;animations=0
        matrix=[[4096,0,0],[0,4096,0],[0,0,4096]];translation=[-128,0,-128]
        heights=[128,128,-128,-128] if scenario==1 else [0]*4
        vertices=[[-256,heights[0],0],[0,heights[1],0],[-256,heights[2],-256],[0,heights[3],-256]]
        def row(tick):
            return [scenario,tick]+position+velocity+cell+[count,flags,mode,direction,square,0,0,0,animations,0,0]+[n for r in matrix for n in r]+translation
        yield row(-1)
        for tick in range(8):
            old=position[:]
            if mode==262:
                if scenario==3:
                    flags|=128|8192;count=0x7ffffff;square=-1;mode=1
                else:
                    info=surface(vertices,translation[0],translation[2])
                    acceleration=cross(info[1:4],info[4:7])
                    for axis in (0,2):
                        value=velocity[axis]+(acceleration[axis]<<3)
                        velocity[axis]=min(value,0x500000) if velocity[axis]>0 else max(value,-0x500000)
                    velocity[1]+=0x80000
                    n=normalize([-matrix[i][1] for i in range(3)])
                    facing=[[0,0,4096],[4096,0,0],[0,0,-4096],[-4096,0,0]][direction]
                    x=normalize(cross(facing,n));z=cross(n,x);matrix=[[x[i],-n[i],z[i]] for i in range(3)]
                    newdirection=(1 if velocity[0]>0 else 3) if abs(velocity[0])>abs(velocity[2]) else (0 if velocity[2]>0 else 2)
                    changed=newdirection!=direction;direction=newdirection
                    position=[p+v for p,v in zip(position,velocity)]
                    if position[1]>(info[0]<<16):position[1]=info[0]<<16;velocity[1]=0
                    if scenario==4:
                        position=old
                        if not flags&8:flags=9;animations+=1;velocity=[0,0,0]
                    elif scenario==2:
                        mode=0
                    translation=[p>>16 for p in position]
                    cell=[(translation[0]+512)>>8,(translation[2]+512)>>8]
                    if changed:
                        n=normal(vertices);facing=[[0,0,4096],[4096,0,0],[0,0,-4096],[-4096,0,0]][direction]
                        x=normalize(cross(facing,n));z=cross(n,x);matrix=[[x[i],-n[i],z[i]] for i in range(3)]
            elif mode==1:
                count-=1;velocity[1]+=0x100000
                if flags&8192 and translation[1]>=0:animations+=1;flags&=~8192
                position=[p+v for p,v in zip(position,velocity)]
                translation=[p>>16 for p in position]
                cell=[(translation[0]+512)>>8,(translation[2]+512)>>8]
            yield row(tick)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--c-oracle',required=True)
    parser.add_argument('--output',default='tests/golden/synthetic/terrain_freeform.csv');parser.add_argument('--verify',action='store_true');args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--freeform'],capture_output=True,text=True,check=True)
    lines=process.stdout.splitlines();start=next(i for i,s in enumerate(lines) if s.startswith('scenario,tick,'))
    stream=io.StringIO(newline='');writer=csv.writer(stream,lineterminator='\n');writer.writerow(FIELDS);writer.writerows(expected())
    text=stream.getvalue();actual=list(csv.reader(lines[start:]));facts=list(csv.reader(text.splitlines()))
    if actual!=facts:
        for i,(a,b) in enumerate(zip(actual,facts)):
            if a!=b:raise ValueError(f'Frozen C row {i}: {a} != independent Python {b}')
        raise ValueError('Frozen C record count differs')
    target=Path(args.output)
    if args.verify:
        if target.read_text()!=text:raise ValueError('Golden facts differ')
    else:target.write_text(text,encoding='utf-8')
    print(f'Independent Python matched {len(facts)-1} frozen C freeform records.')

if __name__=='__main__':main()

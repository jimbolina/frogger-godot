#!/usr/bin/env python3
"""Independent terrain wall rebound facts, checked against actual JumpFrog/MoveFrog."""
import argparse
import csv
import io
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode=True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden.make_golden_terrain_special import FIELDS, trunc
from tools.golden.make_golden_grid import cross,normalize

def expected():
    for scenario in range(5):
        direction=0 if scenario==4 else scenario
        delta=[[0,1],[1,0],[0,-1],[-1,0]][direction]
        position=[-128*65536,0,-128*65536];velocity=[trunc(delta[0]*256*65536,6),-0x380000,trunc(delta[1]*256*65536,6)]
        count=6;flags=2049;mode=261;animations=1;target=[-128,0,-128];translation=[-128,0,-128]
        matrix=[4096,0,0,0,4096,0,0,0,4096]
        def row(tick):return [scenario,tick]+position+velocity+[1,1,count,flags,mode,direction,5]+target+[animations,0,0]+matrix+translation
        yield row(-1)
        for tick in range(8):
            if mode==261:
                count-=1
                if count==0:
                    position=[-128*65536,0,-128*65536];velocity=[0,0,0];mode=0;animations+=1
                else:
                    if count==3:velocity[0]=-velocity[0];velocity[2]=-velocity[2]
                    velocity[1]+=0x100000;position=[p+v for p,v in zip(position,velocity)]
                translation=[p>>16 for p in position]
            n=[0,-4096,0];facing=[[0,0,4096],[4096,0,0],[0,0,-4096],[-4096,0,0]][direction]
            x=normalize(cross(facing,n));z=cross(n,x);matrix=[v for i in range(3) for v in [x[i],-n[i],z[i]]]
            yield row(tick)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--c-oracle',required=True);parser.add_argument('--output',default='tests/golden/synthetic/terrain_wall.csv');parser.add_argument('--verify',action='store_true');args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--wall'],capture_output=True,text=True,check=True)
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
    print(f'Independent Python matched {len(facts)-1} frozen C wall records.')

if __name__=='__main__':main()

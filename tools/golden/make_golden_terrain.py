#!/usr/bin/env python3
"""Independent fixed-scenario integer component facts, cross-checked with frozen C."""
import argparse
import csv
import io
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode=True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.inspection.compare_terrain_trace import FIELDS,read


def expected():
    """FROG.C stationary/jumping rules for exactly the three declared flat fixtures."""
    rows=[]
    for scenario in range(3):
        x=y=z=0
        x=z=-128*65536
        vx=vy=vz=0
        gx=gz=1; count=0; flags=2049; mode=0; current=direction=0
        animation=sound=score=buffered=buffered_count=0
        target_x=target_z=0
        for tick in range(16):
            pressed=held=1 if tick==0 else 0
            if scenario==2 and 2<=tick<=8:
                pressed=2 if tick==2 else 0; held=2
            if mode==1:
                if pressed: buffered=1
            else:
                intent=128
                if buffered and held==2:
                    intent=1; buffered_count+=1
                else:
                    buffered_count=max(0,buffered_count-1)
                    if pressed==1: intent=0
                buffered=0
                current=intent
                if intent!=128:
                    if scenario==1:
                        animation+=1
                    else:
                        direction=intent
                        gx+=1 if intent==1 else 0
                        gz+=1 if intent==0 else 0
                        target_x=(gx*256-512+128)*65536
                        target_z=(gz*256-512+128)*65536
                        vx=(target_x-x)//6; vz=(target_z-z)//6
                        vy=-56*65536;count=6;flags=2113;mode=1
                        animation+=1;sound+=1;score+=1
            def emit(component):
                return [scenario,tick,component,x,y,z,vx,vy,vz,gx,gz,count,flags,mode,
                        current,direction,animation,sound,score,buffered,buffered_count,pressed,held]
            rows.append(emit('control'))
            if mode==1:
                count-=1
                if count:
                    vy+=16*65536;x+=vx;y+=vy;z+=vz
                else:
                    x,z=target_x,target_z;y=0;vx=vy=vz=0;flags=2049;mode=0;animation+=1
                gx=(x//65536+512) >> 8;gz=(z//65536+512) >> 8
            rows.append(emit('move'))
    return rows


def generate(executable):
    proc=subprocess.run([executable],text=True,capture_output=True,check=True,
                        creationflags=0x08000000 if os.name=='nt' else 0)
    text=proc.stdout[proc.stdout.index('scenario,tick,component,'):]
    actual=list(csv.reader(io.StringIO(text)))
    if actual.pop(0)!=FIELDS: raise ValueError('Frozen C schema differs')
    want=expected()
    if len(actual)!=len(want): raise ValueError('Frozen C row count differs')
    for i,(a,b) in enumerate(zip(actual,want)):
        for field,value,wanted in zip(FIELDS,a,b):
            if value!=str(wanted):
                raise ValueError('Frozen C disagreement row %d %s: Python %r C %r' % (i+2,field,wanted,value))
    output=io.StringIO(newline='')
    writer=csv.writer(output,lineterminator='\n');writer.writerow(FIELDS);writer.writerows(want)
    return output.getvalue()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--c-oracle',required=True)
    parser.add_argument('--output',default='tests/golden/synthetic/terrain_components.csv')
    parser.add_argument('--verify',action='store_true')
    args=parser.parse_args()
    result=generate(args.c_oracle);target=Path(args.output)
    if args.verify:
        if target.read_text(encoding='utf-8-sig')!=result: raise ValueError('Terrain golden differs')
    else:
        target.parent.mkdir(parents=True,exist_ok=True);target.write_text(result,encoding='utf-8')
    read(target)
    print('Independent Python and frozen C match all 96 component records and represented fields.')


if __name__=='__main__': main()

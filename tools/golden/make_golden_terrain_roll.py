#!/usr/bin/env python3
"""Independent bounce/cliff callback facts checked against frozen MoveFrog."""
import argparse
import csv
import io
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden.make_golden_terrain_special import FIELDS, trunc

def expected():
    for scenario in range(5):
        position=[-128*65536,0,-128*65536];velocity=[0,0,0]
        cell=[1,1];count=0;flags=2049;mode=269;square=5;target=[0,0,0]
        animations=sounds=scores=0;translation=[-128,0,-128]
        matrix=[4096,0,0,0,4096,0,0,0,4096]
        if scenario==0:
            count=15;flags|=64;mode=268;cell=[1,3];square=13;target=[-128,0,384]
            velocity=[0,-0x800000,trunc(512*65536,15)];animations=sounds=scores=1
        elif scenario==1:
            flags=9;animations=1
        elif scenario==2:
            count=20;cell=[1,2];square=9;target=[-128,128,128]
            velocity=[0,trunc(128*65536,20),trunc(256*65536,20)];animations=1
        else:
            square=-1
        def row(tick):
            return [scenario,tick]+position+velocity+cell+[count,flags,mode,0,square]+target+[animations,sounds,scores]+matrix+translation
        yield row(-1)
        for tick in range(24):
            update=False
            if mode==268:
                if count==0:
                    position=[v*65536 for v in target];mode=0;animations+=1
                else:
                    position=[p+v for p,v in zip(position,velocity)];count-=1
                update=True
            elif mode==269:
                if square<0:
                    mode=1;count=65535;velocity=[0,0,0];flags=(flags&~82422)|128;animations+=2
                elif count==0:
                    position=[v*65536 for v in target]
                    if not flags&8:flags=9;animations+=1;velocity=[0,0,0]
                else:
                    position=[p+v for p,v in zip(position,velocity)];count-=1;update=True
            elif mode==1:
                count-=1;velocity[1]+=0x100000;position=[p+v for p,v in zip(position,velocity)];update=True
            if update:
                translation=[p>>16 for p in position]
                cell=[(translation[0]+512)>>8,(translation[2]+512)>>8]
            yield row(tick)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--c-oracle',required=True)
    parser.add_argument('--output',default='tests/golden/synthetic/terrain_roll.csv');parser.add_argument('--verify',action='store_true');args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--roll'],capture_output=True,text=True,check=True)
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
    print(f'Independent Python matched {len(facts)-1} frozen C bounce/cliff records.')

if __name__=='__main__':main()

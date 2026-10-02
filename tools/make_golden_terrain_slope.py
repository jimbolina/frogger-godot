#!/usr/bin/env python3
"""Independent positive/negative grid-slip slope threshold fixtures."""
import argparse,csv,io,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True
from make_golden_terrain_special import FIELDS,SPEEDS,trunc
from make_golden_grid import normal

def expected():
    for scenario,rise in enumerate([16,17,-16,-17]):
        n=normal([[-256,rise,0],[0,rise,0],[-256,0,-256],[0,0,-256]])
        dz=1 if n[2]>256 else -1 if n[2]<-256 else 1
        count=SPEEDS[max((-n[1])>>9,0)] if abs(n[2])>256 else 10
        cell=[1,1+dz];square=cell[1]*4+1;target=[-128,0,cell[1]*256-384]
        yield [scenario,-1,-128*65536,0,-128*65536,0,0,trunc(dz*256*65536,count)]+cell+[count,2049,258,0,square]+target+[1,0,0]+[4096,0,0,0,4096,0,0,0,4096,-128,0,-128]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--c-oracle',required=True);parser.add_argument('--output',default='tests/golden/synthetic/terrain_slope.csv');parser.add_argument('--verify',action='store_true');args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--slope'],capture_output=True,text=True,check=True)
    lines=process.stdout.splitlines();start=next(i for i,s in enumerate(lines) if s.startswith('scenario,tick,'))
    stream=io.StringIO(newline='');writer=csv.writer(stream,lineterminator='\n');writer.writerow(FIELDS);writer.writerows(expected());text=stream.getvalue()
    actual=list(csv.reader(lines[start:]));facts=list(csv.reader(text.splitlines()))
    if actual!=facts:
        for i,(a,b) in enumerate(zip(actual,facts)):
            if a!=b:raise ValueError(f'Frozen C row {i}: {a} != independent Python {b}')
        raise ValueError('Frozen C record count differs')
    target=Path(args.output)
    if args.verify:
        if target.read_text()!=text:raise ValueError('Golden facts differ')
    else:target.write_text(text,encoding='utf-8')
    print('Independent Python matched 4 frozen C slope-threshold records.')
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Independent single-start bounce/rest component; no HUD-completion invention."""
import argparse
import csv
import io
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode=True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden.make_golden_terrain_special import FIELDS, trunc

def expected():
    position=[-128*65536,-6400*4096,-128*65536];velocity=[0,0,0]
    mode=265;flags=2049;translation=[-128,-400,-128]
    def row(tick):
        return [0,tick]+position+velocity+[1,1,0,flags,mode,0,5,0,0,0,0,0,0]+[4096,0,0,0,4096,0,0,0,4096]+translation
    yield row(-1)
    for tick in range(80):
        advance=True
        if mode==265:
            if 0<(translation[1]<<16):
                velocity[1]=trunc(-2*velocity[1],3);flags|=32768
                if velocity[1]>-(16<<16):
                    velocity=[0,0,0];mode=266;advance=False
            if advance:
                velocity[1]+=0x100000;position=[p+v for p,v in zip(position,velocity)]
        else:
            if 0<=(translation[1]<<16):position[1]=0;velocity=[0,0,0]
            else:velocity[1]+=0x100000;position=[p+v for p,v in zip(position,velocity)]
        translation=[p>>16 for p in position]
        yield row(tick)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--c-oracle',required=True)
    parser.add_argument('--output',default='tests/golden/synthetic/terrain_startup.csv');parser.add_argument('--verify',action='store_true');args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--startup'],capture_output=True,text=True,check=True)
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
    print(f'Independent Python matched {len(facts)-1} frozen C startup records.')

if __name__=='__main__':main()

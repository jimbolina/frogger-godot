#!/usr/bin/env python3
"""Independent source map-specific freefall/dying/death selection facts."""
import argparse,csv,io,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True
from make_golden_terrain_special import FIELDS,trunc
from make_golden_grid import normalize,cross

FIELDS=['scenario','tick','x16','y16','z16','vx16','vy16','vz16','count','flags','mode','animation_requests','last_animation','death_equate','death_count']
def signed32(value):return ((value+0x80000000)&0xffffffff)-0x80000000

def expected():
    for scenario in range(12):
        position=[-128*65536,0,-128*65536];velocity=[0,0,0];count=30 if scenario<4 else 0
        flags=2177 if scenario<4 else 2049 if scenario<6 or scenario==10 else 9
        mode=1 if scenario<4 else 2 if scenario<6 else 3 if scenario>=10 else 0
        animations=1 if scenario<4 or 6<=scenario<8 else 2 if 8<=scenario<10 else 1 if scenario==11 else 0
        animation=2 if scenario==11 else -1 if scenario==10 else 11 if scenario in [1,2] else 6 if scenario<4 else -1 if scenario<6 else 12 if scenario==7 else 8
        death=2 if scenario==11 else 0 if scenario==10 else 0 if scenario<4 else 2 if scenario<6 else 8 if scenario%2==0 else 12
        deathcount=50 if 4<=scenario<6 else 0
        if 4<=scenario<6:velocity=[131073,-65537,400000001]
        for tick in range(3):
            if scenario<4:
                count-=1;velocity[1]+=0x100000;position=[signed32(p+v) for p,v in zip(position,velocity)]
            elif scenario<6:
                deathcount-=1;position=[signed32(p+v) for p,v in zip(position,velocity)]
                if scenario==5:velocity=[signed32(v*14)>>4 for v in velocity]
            yield [scenario,tick]+position+velocity+[count,flags,mode,animations,animation,death,deathcount]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--c-oracle',required=True);parser.add_argument('--output',default='tests/golden/synthetic/terrain_map_branches.csv');parser.add_argument('--verify',action='store_true');args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--map-branches'],capture_output=True,text=True,check=True)
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
    print(f'Independent Python matched {len(facts)-1} frozen C map-branch records.')
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Independent held freeform steering and MoveFrog flat-grid facts."""
import argparse,csv,io,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden.make_golden_terrain_special import FIELDS
from tools.golden.make_golden_grid import cross,normalize

def expected():
    for scenario in range(4):
        position=[-128*65536,0,-128*65536];velocity=[0,0,8*65536]
        cell=[1,1];mode=262;direction=0;square=5;animations=0
        matrix=[[4096,0,0],[0,4096,0],[0,0,4096]];translation=[-128,0,-128]
        def row(tick):return [scenario,tick]+position+velocity+cell+[0,2049,mode,direction,square,0,0,0,animations,0,0]+[v for r in matrix for v in r]+translation
        def apply(v):return [sum(matrix[i][j]*v[j] for j in range(3))>>12 for i in range(3)]
        def align():
            n=[0,-4096,0];facing=[[0,0,4096],[4096,0,0],[0,0,-4096],[-4096,0,0]][direction]
            x=normalize(cross(facing,n));z=cross(n,x)
            return [[x[i],-n[i],z[i]] for i in range(3)]
        yield row(-1)
        for tick in range(8):
            if mode==262:
                relative=(scenario-direction)&3
                speed=apply([-15,0,0] if relative==3 else [15,0,0] if relative==1 else [0,0,10] if relative==0 else [0,0,-15])
                if relative in (1,3):
                    velocity[0]+=speed[0]<<14;velocity[2]+=speed[2]<<14;animations+=1
                elif relative==0:
                    velocity[0]+=speed[0]<<14;velocity[2]+=speed[2]<<14
                else:
                    for axis in (0,2):
                        if speed[axis]:
                            value=velocity[axis]+(speed[axis]<<13)
                            velocity[axis]=max(value,0) if velocity[axis]>0 else min(value,0)
            yield row(tick*2)
            if mode==262:
                cachedcell=[(translation[0]+512)>>8,(translation[2]+512)>>8]
                for axis in (0,2):velocity[axis]=min(velocity[axis],0x500000) if velocity[axis]>0 else max(velocity[axis],-0x500000)
                velocity[1]+=0x80000
                newdirection=(1 if velocity[0]>0 else 3) if abs(velocity[0])>abs(velocity[2]) else (0 if velocity[2]>0 else 2)
                direction=newdirection
                position=[p+v for p,v in zip(position,velocity)]
                if position[1]>0:position[1]=0;velocity[1]=0
                square=cachedcell[1]*4+cachedcell[0]
                if square!=5:mode=0
                translation=[p>>16 for p in position]
                cell=[(translation[0]+512)>>8,(translation[2]+512)>>8]
            matrix=align()
            yield row(tick*2+1)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--c-oracle',required=True);parser.add_argument('--output',default='tests/golden/synthetic/terrain_steering.csv');parser.add_argument('--verify',action='store_true');args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--steering'],capture_output=True,text=True,check=True)
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
    print(f'Independent Python matched {len(facts)-1} frozen C steering records.')
if __name__=='__main__':main()

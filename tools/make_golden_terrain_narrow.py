#!/usr/bin/env python3
"""Independent signed32 hop-delta wrap and forced-search pointer carry prefixes."""
import argparse,csv,io,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True
from make_golden_terrain_special import FIELDS,trunc
from make_golden_grid import normalize,cross,surface,normal

def signed32(value):return ((value+0x80000000)&0xffffffff)-0x80000000

def freeform_boundary():
    position=[-128*65536,-32768*65536,-128*65536];velocity=[0,0,8*65536]
    matrix=[[4096,0,0],[0,4096,0],[0,0,4096]];translation=[p>>16 for p in position];direction=0
    vertices=[[-256,32767,0],[0,-32768,0],[-256,-32768,-256],[0,-32768,-256]]
    def row(tick):return [3,tick]+position+velocity+[(translation[0]+512)>>8,(translation[2]+512)>>8]+[0,2049,262,direction,5,0,0,0,0,0,0]+[n for r in matrix for n in r]+translation
    yield row(-1)
    for tick in range(5):
        info=surface(vertices,translation[0],translation[2]);acceleration=cross(info[1:4],info[4:7])
        for axis,slope in ((0,info[2]),(2,info[5])):
            if (velocity[axis]>0 and slope<-3500) or (velocity[axis]<0 and slope>3500):velocity[axis]=trunc(velocity[axis],3)
            value=velocity[axis]+(acceleration[axis]<<3)
            velocity[axis]=min(value,0x500000) if velocity[axis]>0 else max(value,-0x500000)
        velocity[1]=signed32(velocity[1]+0x80000)
        n=normalize([-matrix[i][1] for i in range(3)]);facing=[[0,0,4096],[4096,0,0],[0,0,-4096],[-4096,0,0]][direction]
        x=normalize(cross(facing,n));z=cross(n,x);matrix=[[x[i],-n[i],z[i]] for i in range(3)]
        newdirection=(1 if velocity[0]>0 else 3) if abs(velocity[0])>abs(velocity[2]) else (0 if velocity[2]>0 else 2)
        changed=newdirection!=direction;direction=newdirection
        position=[signed32(p+v) for p,v in zip(position,velocity)]
        floor=signed32(info[0]<<16)
        if position[1]>floor:position[1]=floor;velocity[1]=0
        translation=[p>>16 for p in position]
        if changed:
            n=normal(vertices);facing=[[0,0,4096],[4096,0,0],[0,0,-4096],[-4096,0,0]][direction]
            x=normalize(cross(facing,n));z=cross(n,x);matrix=[[x[i],-n[i],z[i]] for i in range(3)]
        yield row(tick)

def expected():
    for scenario in range(3):
        base=[-128,-32640] if scenario==0 else [-512,-512]
        position=[0,0,32512*65536] if scenario==0 else [-128*65536,32767*65536,-128*65536]
        target=[0,0,-32512] if scenario==0 else [-128,0,384]
        count=15 if scenario==1 else 6
        delta=[signed32(target[0]*65536-position[0]),signed32(target[2]*65536-position[2])]
        velocity=[trunc(delta[0],count),-(0x100000*(count+1)>>1),trunc(delta[1],count)]
        cell=[0,256] if scenario==0 else [1,3];square=-1 if scenario==0 else 12
        if scenario==2:
            position=[-128*65536,-32768*65536,-128*65536];target=[-128,0,-128]
            velocity=[0,trunc(signed32(65535*65536),7)-(0x100000*7>>1),trunc(256*65536,6)]
            cell=[1,1];square=5
        matrix=[4096,0,0,0,4096,0,0,0,4096];translation=[p>>16 for p in position]
        def row(tick):return [scenario,tick]+position+velocity+cell+[count,2049,261 if scenario==2 else 1,0,square]+target+[1,0 if scenario==2 else 1,0 if scenario==2 else 1]+matrix+translation
        yield row(-1)
        for tick in range(5):
            count-=1
            if scenario==2 and count==3:velocity[0]=-velocity[0];velocity[2]=-velocity[2]
            velocity[1]+=0x100000;position=[signed32(p+v) for p,v in zip(position,velocity)]
            translation=[p>>16 for p in position];cell=[(translation[0]-base[0])>>8,(translation[2]-base[1])>>8]
            yield row(tick)

    yield from freeform_boundary()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--c-oracle',required=True);parser.add_argument('--output',default='tests/golden/synthetic/terrain_narrow.csv');parser.add_argument('--verify',action='store_true');args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--narrow'],capture_output=True,text=True,check=True)
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
    print(f'Independent Python matched {len(facts)-1} frozen C hop narrowing/forced-search records.')
if __name__=='__main__':main()

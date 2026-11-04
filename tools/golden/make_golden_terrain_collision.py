#!/usr/bin/env python3
"""Independent synthetic FROG.C/COLLIDE.C facts, verified against frozen objects."""
import argparse
import csv
import io
from pathlib import Path
import subprocess

FIELDS='scenario,tick,component,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,input,direction,animation_requests,sound_requests,score_requests,old_y,target_y,lives,death_count,death_equate,matrix_y,game_mode'.split(',')
HEIGHTS=[512,513,1024,1025,1025,0,0,0,0,0,0,0]
FLAGS=[3,3,3,3,259,7,5,4097,9,3,3,5]


def expected(tick_count=90):
    rows=[]
    for scenario in range(12):
        s=dict(pos=[-128<<16,0,-128<<16],vel=[0,0,0],cell=[1,1],count=0,flags=2049,
               mode=0,key=0,anim=0,sound=0,score=0,old=0,y=0,lives=3,death=0,equate=0,
               matrix_y=0,game=10,target=[-128<<16,0,128<<16])
        height,gs=HEIGHTS[scenario],FLAGS[scenario]
        empty=scenario==10

        def kill(equate,down=False):
            if s['mode']==2 or s['flags']&8:
                return
            s['flags'] &= ~2048
            if s['lives']>0:
                s['lives']-=1
            if s['lives']==0:
                s['flags'] &= ~1
            s['flags'] |= 8
            s['anim']+=1
            s['equate']=equate
            if down:
                s['vel']=[0,65536,0]
            elif s['mode']!=1 or not s['flags']&64:
                s['vel']=[0,0,0]

        def react():
            if not gs&1 or gs&2:
                return
            if gs&4:
                kill(12 if scenario==11 else 8,scenario!=11)
                s['sound']+=1
            elif gs&4096:
                kill(23)
                s['sound']+=1
            elif gs&8:
                kill(8,True)
                s['sound']+=1

        def land():
            if not gs&(4|8|4096):
                s['pos']=[-128<<16,height<<16,128<<16]
            s['y']=s['pos'][1]>>16
            distance=s['y']-s['old']
            s['mode']=0
            if gs&256 or distance<=512:
                s['anim']+=1
            elif distance<=1024:
                s['mode']=6
                s['count']=45
                s['anim']+=1
                s['sound']+=1
            else:
                kill(2)
            s['vel']=[0,0,0]
            s['old']=s['y']
            s['flags'] &= ~(2|4|16|32|64|128|256|65536|16384)

        def update_world():
            s['matrix_y']=s['pos'][1]>>16
            s['cell']=[((s['pos'][0]>>16)+512)>>8,((s['pos'][2]>>16)+512)>>8]

        def jumping(react_on_land=True):
            s['count']-=1
            if s['count']==0:
                s['pos'][0]=s['target'][0]
                s['pos'][2]=s['target'][2]
                if s['flags']&64:
                    land()
                    update_world()
                    if react_on_land:
                        react()
                else:
                    s['flags'] &= ~(32|64)
                    s['flags'] |= 128|8192
                    s['count']=0x7ffffff
                    s['vel'][0]=s['vel'][2]=0
            else:
                s['vel'][1]+=0x100000
                if s['flags']&(128|8192)==128|8192 and s['matrix_y']-s['old']>=0:
                    s['anim']+=1
                    s['flags'] &= ~8192
                s['pos']=[a+b for a,b in zip(s['pos'],s['vel'])]

        def row(tick,phase):
            rows.append([scenario,tick,phase]+s['pos']+s['vel']+s['cell']+
                [s['count'],s['flags'],s['mode'],s['key'],0,s['anim'],s['sound'],s['score'],
                 s['old'],s['y'],s['lives'],s['death'],s['equate'],s['matrix_y'],s['game']])

        for tick in range(tick_count):
            if s['flags']&8:
                s['flags'] &= ~8
                if s['mode']!=1 or not s['flags']&64:
                    s['count']=0
                s['mode']=2
                s['death']=70
            if s['flags']&2048 and s['mode']==0:
                s['key']=0 if tick==0 else 128
                if tick==0:
                    s['mode']=1
                    s['cell']=[1,2]
                    s['count']=6
                    if height<=256 and not empty:
                        s['flags'] |= 64
                    s['vel']=[0,-3670016,2796202]
                    s['anim']+=1;s['sound']+=1;s['score']+=1
            row(tick,'control')
            if s['mode']==1:
                jumping();update_world()
            elif s['mode']==6:
                s['count']-=1
                if s['count']==0:
                    s['mode']=0;s['anim']+=1
            elif s['mode']==2:
                s['death']-=1
                if s['death']==0:
                    s['flags'] &= ~2048
                    s['game']=3
                if s['count']:
                    jumping(False);s['mode']=2
                else:
                    s['pos']=[a+b for a,b in zip(s['pos'],s['vel'])]
                update_world()
            row(tick,'move')
            if s['mode']!=2 and not s['flags']&8:
                if scenario==9:
                    kill(2)
                elif s['flags']&128 and not empty and s['matrix_y']>height:
                    land();update_world();react()
                elif s['matrix_y']>(100 if empty else 30000):
                    s['matrix_y']=100 if empty else 30000
                    s['vel']=[0,0,0]
                    kill(8,True);s['sound']+=1
            row(tick,'collision')
    return rows


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--c-oracle',required=True)
    parser.add_argument('--output',default='tests/golden/synthetic/terrain_collision.csv')
    parser.add_argument('--verify',action='store_true')
    args=parser.parse_args()
    process=subprocess.run([args.c_oracle,'--collision'],text=True,capture_output=True,check=True)
    lines=process.stdout.splitlines()
    start=next(i for i,line in enumerate(lines) if line.startswith('scenario,tick,component,'))
    actual=list(csv.reader(lines[start:]))
    stream=io.StringIO(newline='')
    writer=csv.writer(stream,lineterminator='\n');writer.writerow(FIELDS);writer.writerows(expected())
    text=stream.getvalue();facts=list(csv.reader(text.splitlines()))
    if actual!=facts:
        for index,(a,b) in enumerate(zip(actual,facts)):
            if a!=b:
                raise ValueError(f'Frozen C row {index}: {a} != independent Python {b}')
        raise ValueError('Frozen C record count differs')
    target=Path(args.output)
    if args.verify:
        if target.read_text()!=text:
            raise ValueError('Golden facts differ')
    else:
        target.parent.mkdir(parents=True,exist_ok=True);target.write_text(text,encoding='utf-8')
    print(f'Independent Python matched {len(facts)-1} frozen C collision records.')


if __name__=='__main__':
    main()

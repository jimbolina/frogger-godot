#!/usr/bin/env python3
"""Independent default CAMERA.C integer facts, exhaustively checked with frozen C."""
import argparse
import csv
import io
import math
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode=True

FIELDS='scenario,tick,mode,move_timer,twist_counter,current_x,current_y,current_z,source_ofs_x,source_ofs_y,source_ofs_z,target_ofs_x,target_ofs_y,target_ofs_z,source_x,source_y,source_z,target_x,target_y,target_z,controller_up,current_ytheta,delta_ytheta,dest_ytheta,flags,shake_timer,shake_amp_x,shake_amp_y,shake_freq_x,shake_freq_y,rng_seed,shake_draw_1,shake_draw_2'.split(',')
TICKS=[122,16,16,16,47,16,47,47]


def cdiv(a,b): return (abs(a)//b)*(1 if a>=0 else -1)
def rounded(v): return int(math.copysign(math.floor(abs(v)+0.5),v))
def trig(angle,cos=False):
    return rounded((math.cos if cos else math.sin)((angle&4095)*2*math.pi/4096)*4096)
def damp(value,dest,rate=None):
    delta=dest-value
    threshold=24 if rate else 5
    if abs(delta)<threshold: return dest
    step=24 if rate else abs(delta) >> 1
    return value+(step if delta>=0 else -step)


def expected():
    rows=[]
    for scenario,ticks in enumerate(TICKS):
        current=[0,0,0];source=[200,-400,400];target=[0,100,0]
        next_source=[0,-500,-500];next_target=[0,0,0]
        mode=3;timer=30;twist=0;angle=0;controller=0
        if scenario:
            mode=0;timer=0;source=next_source.copy();target=next_target.copy()
        if scenario in (2,3): twist=1 if scenario==2 else -1;timer=8
        if scenario==4: timer=45;next_source=[0,-1000,-100]
        seed=12345;draw1=draw2=shake_timer=amp_x=amp_y=freq_x=freq_y=camera_flags=0
        fixed_world_source=[0,-500,-500]
        if scenario==5:
            mode=4;current=[5,-20,15];fixed_world_source=[5,-520,-485]
        if scenario>=6:
            if scenario==7: mode=4
            seed=(1*0x41c64e6d+0x3039)&0xffffffff;draw1=(seed>>16)&32767
            seed=(seed*0x41c64e6d+0x3039)&0xffffffff;draw2=(seed>>16)&32767
            theta=(draw1&511)-256
            amp_x=(trig(theta)*128)>>8;amp_y=(trig(theta,True)*128)>>8
            freq_x=20480;freq_y=freq_x+draw2%(freq_x>>3);shake_timer=45;camera_flags=1
        for tick in range(ticks):
            origin=[100,-200,60] if scenario==1 and tick==0 else [200,-260,100] if scenario==1 else [0,0,0]
            if mode==3:
                if max(0,90-tick)<=timer: mode=2
            elif mode==2:
                timer-=1
                if not timer: mode=0;current=origin.copy()
                else:
                    source=[a+cdiv(b-a,timer) for a,b in zip(source,next_source)]
                    target=[a+cdiv(b-a,timer) for a,b in zip(target,next_target)]
            elif mode==0:
                if timer:
                    source=[a+cdiv(b-a,timer) for a,b in zip(source,next_source)]
                    target=[a+cdiv(b-a,timer) for a,b in zip(target,next_target)]
                    timer-=1
                if twist:
                    angle=cdiv(twist*1024,8)
                    twist+=1 if twist>0 else -1
                    if abs(twist)>8: twist=0
                current=[damp(current[0],origin[0]),damp(current[1],min(origin[1],0),True),damp(current[2],origin[2])]
            # Sweep's final call uses origin directly; current is copied on transition.
            if mode==0 and not (scenario==0 and tick==90):
                cos=trig(angle,True);sin=trig(angle)
                rotated=[(cos*source[0]+sin*source[2]) >> 12,source[1],(-sin*source[0]+cos*source[2]) >> 12]
                world_source=[a+b for a,b in zip(current,rotated)]
                world_target=current.copy()
                dx,dz=-rotated[0],-rotated[2]
                controller=(0 if dz>0 else 2) if abs(dz)>abs(dx) else (1 if dx>0 else 3)
            elif mode==4:
                world_source=fixed_world_source.copy();world_target=current.copy()
            else:
                world_source=[a+b for a,b in zip(origin,source)]
                world_target=[a+b for a,b in zip(origin,target)]
            if shake_timer:
                elapsed=45-shake_timer
                sx=cdiv(trig(cdiv(elapsed*freq_x,45))*amp_x*shake_timer,45)>>16
                sy=cdiv(trig(cdiv(elapsed*freq_y,45))*amp_y*shake_timer,45)>>16
                world_source=[world_source[0]+sx,world_source[1]+((2896*sy)>>12),world_source[2]+((-2896*sy)>>12)]
                if mode==4: fixed_world_source=world_source.copy()
                shake_timer-=1
                if not shake_timer: camera_flags=0
            rows.append([scenario,tick,mode,timer,twist]+current+source+target+world_source+world_target+[controller,0,0,0,camera_flags,shake_timer,amp_x,amp_y,freq_x,freq_y,seed,draw1,draw2])
    return rows


def generate(executable):
    proc=subprocess.run([executable,'--camera'],text=True,capture_output=True,check=True,
                        creationflags=0x08000000 if os.name=='nt' else 0)
    actual=list(csv.reader(io.StringIO(proc.stdout[proc.stdout.index('scenario,tick,mode,'):])))
    if actual.pop(0)!=FIELDS: raise ValueError('Camera C schema differs')
    want=expected()
    if len(actual)!=len(want): raise ValueError('Camera C count differs')
    for i,(a,b) in enumerate(zip(actual,want)):
        for field,got,value in zip(FIELDS,a,b):
            if got!=str(value): raise ValueError('Camera C disagreement row %d %s Python=%s C=%s' % (i+2,field,value,got))
    output=io.StringIO(newline='');writer=csv.writer(output,lineterminator='\n')
    writer.writerow(FIELDS);writer.writerows(want)
    return output.getvalue()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--c-oracle',required=True)
    parser.add_argument('--output',default='tests/golden/synthetic/camera_components.csv')
    parser.add_argument('--verify',action='store_true')
    args=parser.parse_args();result=generate(args.c_oracle);target=Path(args.output)
    if args.verify:
        if target.read_text(encoding='utf-8-sig')!=result: raise ValueError('Camera golden differs')
    else: target.parent.mkdir(parents=True,exist_ok=True);target.write_text(result,encoding='utf-8')
    print('Independent Python and actual C match all 327 camera records and represented fields.')


if __name__=='__main__': main()

#!/usr/bin/env python3
"""Independent bounded ORG1 script state from frozen scripter.c semantics."""
import math

import make_golden_exe_tables as tables
import make_golden_paths as paths
from org1_round_trip import apply


def short(value):return paths.signed(value,16)


def instruction(words,cursor):
    """Decode one complete known-width instruction, rejecting invalid cursors."""
    if not 0<=cursor<len(words) or type(words[cursor]) is not int or not 0<=words[cursor]<len(tables.OPCODES):
        raise ValueError('invalid script instruction/cursor')
    op,count=tables.OPCODES[words[cursor]];args=words[cursor+1:cursor+count+1]
    if len(args)!=count or any(type(v) is not int for v in args):raise ValueError('truncated or invalid script operands')
    return op,args,cursor+count+1


class Script:
    """Detached instruction, callback, animation and sound-owner state."""
    def __init__(self,programs,root,registers,actions):
        self.programs=programs;self.root=self.program=root;self.cursor=0
        self.start=self.end=-1;self.timer=0;self.registers=registers
        self.deviation=self.delta=self.destination=self.remaining=0
        self.callbacks={};self.moving_sound=False
        self.actions=actions;self.action=0 if actions else -1;self.cel=-1
        self.colours=[0,0,0];self.ambient=[0,0,0];self.no_fade=False
        self.requests=[]

    def update(self,seed,matrix,frog,hit=False,carry=False,form_id=0,fade=None,no_display=False,allocation=True):
        """Run until a source yield, then deviation, callbacks and timer."""
        sounds=[];sprites=[];drown=False;self.requests=[]
        def value(mode,operand):
            if mode not in (0,1) or (mode and not 0<=operand<len(self.registers)):raise ValueError('invalid register operand')
            return self.registers[operand] if mode else operand
        for _ in range(4096):
            if self.program not in self.programs:raise ValueError('unknown script target')
            words=self.programs[self.program];op,args,following=instruction(words,self.cursor)
            stop=False
            if op=='PREPARE_REGISTERS':
                if args not in ([12,3],[32,2]) or len(self.registers)!=args[1]:raise ValueError('unaudited register payload')
            elif op=='SET_ENTITY_TYPE':
                if args!=[0]:raise ValueError('unaudited script entity type')
            elif op=='REGISTER_CALLBACK':
                slot,callback,condition,kind=args
                if slot not in (0,1) or callback not in (0,1,2,8) or condition not in (0,7) or kind not in (0,1):raise ValueError('unaudited callback')
                self.callbacks[slot]=(callback,condition,kind,2)
            elif op=='SETLOOP':
                self.start=following;end=following
                while instruction(words,end)[0]!='ENDLOOP':
                    if instruction(words,end)[0]=='SETLOOP':raise ValueError('nested loop')
                    end=instruction(words,end)[2]
                self.end=end+1
            elif op=='ENDLOOP':
                if self.start<0:raise ValueError('ENDLOOP without SETLOOP')
                following=self.start;stop=True
            elif op=='RESTART':self.program=self.root;following=0
            elif op=='STOP':following=self.cursor;stop=True
            elif op=='SET_ACTION':
                if not 0<=args[0]<len(self.actions):raise ValueError('invalid entity action')
                self.action=args[0];self.cel=-1
            elif op=='SET_TIMER':self.timer=value(*args)&65535
            elif op=='WAIT_UNTIL_TIMER':
                if self.timer<value(*args):following=self.cursor;stop=True
            elif op=='DEVIATE':
                if args[:2]!=[0,1]:raise ValueError('unaudited deviation')
                self.destination,self.delta,self.remaining=map(short,args[2:])
            elif op=='WAIT_DEVIATED':
                if self.remaining:following=self.cursor;stop=True
            elif op=='SCRIPT_IF':
                if args[:2]!=[0,6] or args[3]<=0 or args[2] not in self.programs:raise ValueError('unaudited branch')
                seed=(seed*0x41c64e6d+0x3039)&0xffffffff
                if ((seed>>16)&32767)%args[3]==1:
                    self.program=args[2];following=0;self.start=self.end=-1
            elif op=='PLAY_MOVING_SOUND':
                if not self.moving_sound and allocation:
                    self.moving_sound=(args[0],value(args[1],args[2]),value(args[1],args[3]))
                    self.requests.append('moving:'+':'.join(map(str,self.moving_sound)))
            elif op=='PLAY_SOUND_DISTANCE':
                if args[3] not in (0,1,2):raise ValueError('invalid sound coordinate')
                offset=[0,0,0];offset[args[3]]=short(args[4])
                local=[short(v) for v in apply(matrix,offset)]
                point=[short(local[k]+matrix[9+k]) for k in range(3)]
                distance=math.isqrt(sum(short(frog[k]-point[k])**2 for k in range(3)))
                threshold=value(args[0],args[1]);eligible=(threshold<math.isqrt(distance)) if args[0] else (threshold>math.isqrt(distance))
                if eligible and allocation:
                    sounds.append(value(args[0],args[2]));self.requests.append(f'sound:{sounds[-1]}:0:0:0')
            elif op=='CREATE_3D_SPRITE':
                if form_id not in (19,20,21):raise ValueError('unaudited turtle splash form')
                sprites=[(0,-64,-(form_id-19)*128+j*256) for j in range(form_id-18)]
                self.requests += ['sprite:'+':'.join(map(str,p))+':1:-16' for p in sprites]
            else:raise ValueError(f'unaudited instruction {op}')
            self.cursor=following
            if stop:break
        else:raise ValueError('non-yielding script')
        if self.remaining:
            self.deviation=short(self.deviation+(self.delta>>8))
            if self.remaining<0:
                if (self.delta>0 and self.deviation>=self.destination) or (self.delta<0 and self.deviation<=self.destination):
                    self.deviation=self.destination;self.delta=self.remaining=0
            else:
                self.remaining=short(self.remaining-1)
                if self.remaining==0:self.delta=0
        for slot,(callback,condition,kind,called) in sorted(self.callbacks.items()):
            if kind!=1 and called==3:continue
            if condition==0 and not hit:continue
            if callback==2:
                if no_display:continue
                self.no_fade=fade is None or (fade[0]<=matrix[9]<=fade[1] and fade[2]<=matrix[11]<=fade[3])
                if self.no_fade:
                    red,green,blue=128-self.deviation,128+(-self.deviation>>1),127+self.deviation
                    packed=(blue<<16)+(green<<8)+red
                    self.colours=[(packed>>shift)&255 for shift in (0,8,16)]
                    self.ambient=[64,64,192]
                drown=carry and self.deviation>=128
            else:
                ids={0:[13],1:[19],8:[14,15]}[callback];sounds.extend(ids)
                self.requests += [f'sound:{i}:0:0:0' for i in ids]
        self.timer=(self.timer+1)&65535
        return seed,sounds,sprites,drown

    def advance_animation(self):
        if self.actions:self.cel=(self.cel+1)%self.actions[self.action]

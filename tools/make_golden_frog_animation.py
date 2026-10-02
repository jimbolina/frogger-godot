#!/usr/bin/env python3
"""Extract named frozen animation facts and independently execute source scripts."""
import argparse
import ast
import csv
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
sys.dont_write_bytecode=True

SOURCE=Path(__file__).resolve().parents[2]/'froggy/engine/vendor/frogger-psx-src/source'
FIELDS='scenario,tick,phase,type,flags,program,offset,queue_type,queue_flags,previous_type,previous_flags,script_timer,anim_timer,action,cel,total,env_flags,update_count,no_input_timer,if_counter,rng_seed,loop_start_program,loop_start_offset,loop_end_program,loop_end_offset,queue_program,queue_offset,previous_program,previous_offset'.split(',')


def clean(text): return re.sub(r'/\*.*?\*/|//[^\n]*','',text,flags=re.S)
def value(expression,names):
    node=ast.parse(expression.strip(),mode='eval').body
    def visit(n):
        if isinstance(n,ast.Constant) and isinstance(n.value,int): return n.value
        if isinstance(n,ast.Name): return names[n.id]
        if isinstance(n,ast.BinOp):
            a,b=visit(n.left),visit(n.right)
            if isinstance(n.op,ast.BitOr): return a|b
            if isinstance(n.op,ast.LShift): return a<<b
        raise ValueError('Unsupported source constant '+expression)
    return visit(node)


def catalog():
    names={}
    for file in ('froganim.h','FROG.H','gen_frog.h','gnm_frog.h'):
        text=clean((SOURCE/file).read_text())
        for group in re.findall(r'enum(?:\s+\w+)?\s*\{(.*?)\}\s*;',text,re.S):
            count=0
            for item in group.split(','):
                item=item.strip()
                if not item: continue
                parts=item.split('=',1);key=parts[0].strip()
                if len(parts)>1: count=value(parts[1],names)
                names[key]=count;count+=1
        for key,expression in re.findall(r'#define\s+(FROG_ANIM_\w+)\s+([^\n]+)',text):
            try: names[key]=value(expression,names)
            except (SyntaxError,ValueError,KeyError): pass
    source=clean((SOURCE/'froganim.c').read_text())
    programs={name:[value(token,names) for token in body.split(',') if token.strip()]
              for name,body in re.findall(r'MR_LONG\s+(froganim(?:_m)?_scr_\w+)\[\]\s*=\s*\{(.*?)\};',source,re.S)}
    table=re.search(r'FROG_ANIM\s+FrogAnimScripts\[\]\s*=\s*\{(.*?)\};',source,re.S).group(1)
    entries=[]
    for body in re.findall(r'\{([^{}]+)\}',table):
        parts=[p.strip() for p in body.split(',') if p.strip()]
        program=re.search(r'&(\w+)\[0\]',parts[0]).group(1)
        entries.append(dict(flags=value(parts[2],names),program=program,words=programs[program]))
    ids=sorted((v,k.removeprefix('FROG_ANIMATION_')) for k,v in names.items() if k.startswith('FROG_ANIMATION_') and k!='FROG_ANIMATION_MAX')
    actions=sorted((v,k) for k,v in names.items() if k.startswith('GEN_FROG_') and k not in ('GEN_FROG_KEYFRAME_SET',))
    # Only the source action enum, not generated transform-set enum names.
    action_body=re.search(r'enum GEN_FROG_KEYFRAME_SET_ACTION\s*\{(.*?)\}',clean((SOURCE/'gen_frog.h').read_text()),re.S).group(1)
    action_names=[p.strip() for p in action_body.split(',') if p.strip()]
    if len(entries)!=35 or len(ids)!=35 or len(action_names)!=34: raise ValueError('Source animation census changed')
    for i,entry in enumerate(entries): entry['name']=ids[i][1]
    return dict(entries=entries,actions=action_names,action_lengths=[3+i%3 for i in range(34)])


def runtime_catalog(data,path):
    lines=['class_name FrogAnimationCatalog','extends RefCounted','## Named action/script facts transcribed independently from frozen froganim.c and gen_frog.h.','## Regenerate with tools/make_golden_frog_animation.py --runtime-catalog; no retail bytes.','']
    lines += ['const %s: int = %d' % (e['name'],i) for i,e in enumerate(data['entries'])]
    lines += ['', 'const NAMES: Array[StringName] = ['+', '.join('&"'+e['name']+'"' for e in data['entries'])+']',
              'const ACTION_NAMES: Array[StringName] = ['+', '.join('&"'+n+'"' for n in data['actions'])+']',
              'const FLAGS: Array[int] = '+str([e['flags'] for e in data['entries']]),
              'const PROGRAMS: Array[Array] = [']
    lines += ['\t'+str(e['words'])+',' for e in data['entries']]
    lines += [']','','## Returns a detached source command program for the named animation ID.',
              'static func program(animation_id: int) -> PackedInt32Array:', '\treturn PackedInt32Array(PROGRAMS[animation_id])','']
    path.parent.mkdir(parents=True,exist_ok=True);path.write_text('\n'.join(lines))


class State:
    def __init__(self,data,jungle=False):
        self.data=data;self.type=14;self.flags=data['entries'][14]['flags'];self.program=14;self.offset=0
        self.queue_type=self.previous_type=-1;self.queue_flags=self.previous_flags=0
        self.queue_cursor=self.previous_cursor=(-1,-1)
        self.loop_start=self.loop_end=(-1,-1);self.timer=self.anim_timer=0
        self.action=0;self.cel=0;self.total=data['action_lengths'][0];self.env_flags=7168;self.update_count=0
        self.no_input_timer=self.if_counter=0;self.seed=1;self.jungle=jungle
    def initialise(self,anim):
        self.type=self.program=anim;self.offset=0;self.flags=self.data['entries'][anim]['flags']
        self.queue_type=self.previous_type=-1;self.queue_flags=self.previous_flags=0
        self.queue_cursor=self.previous_cursor=(-1,-1)
    def request(self,anim):
        flags=self.data['entries'][anim]['flags']
        if self.flags&32: return
        if self.flags&16: self.previous_type=self.type;self.previous_flags=self.flags;self.previous_cursor=(self.program,self.offset)
        if flags&2:
            if self.anim_timer: self.type=self.program=anim;self.offset=0;self.flags=flags
            else: self.queue_type=anim;self.queue_flags=flags;self.queue_cursor=(anim,0)
            self.anim_timer=0
        elif flags&4:
            if self.type==14: self.queue_type=anim;self.queue_flags=flags;self.anim_timer=0;self.queue_cursor=(anim,0)
        elif flags&8:
            self.type=self.program=anim;self.offset=0;self.flags=flags;self.queue_type=-1;self.queue_flags=0;self.anim_timer=0
            self.queue_cursor=(-1,-1)
    def scripts(self):
        old_cel,old_total=self.cel,self.total
        for _ in range(128):
            result=0
            while result==0:
                program,at=self.program,self.offset;words=self.data['entries'][program]['words'];token=words[at]
                if token==0:
                    playback,delay,action=words[at+1:at+4]
                    if delay and not self.anim_timer: self.anim_timer=delay;result=1;continue
                    if delay:
                        self.anim_timer-=1
                        if self.anim_timer: result=1;continue
                    self.action=action;self.cel=-1;self.total=self.data['action_lengths'][action]
                    self.env_flags|=7168
                    if playback==0: self.env_flags|=256
                    else: self.env_flags&=~256
                    self.anim_timer=0;self.offset=at+4
                elif token==1:
                    self.loop_start=(program,at+1);end=at+1
                    lengths=[4,1,1,1,1,1,8,2,2]
                    while words[end]!=2: end+=lengths[words[end]]
                    self.loop_end=(program,end);self.offset=at+1
                elif token==2: self.program,self.offset=self.loop_start;result=1
                elif token==3: result=2
                elif token==4: result=1
                elif token==5:
                    if self.cel>=self.total-1: self.offset=at+1
                    else: result=1
                elif token==6:
                    if self.no_input_timer>=words[at+2]:
                        self.seed=(self.seed*0x41c64e6d+0x3039)&0xffffffff;draw=(self.seed>>16)&32767
                        anim=words[at+4+(draw&3)]
                        if self.jungle:
                            previous=self.if_counter;self.if_counter+=1
                            if previous==4: anim=27;self.if_counter=0
                        self.request(anim);self.no_input_timer=0
                    self.program=program;self.offset=at+8
                elif token==7: self.timer=words[at+1];self.offset=at+2
                elif token==8:
                    if self.timer>=words[at+1]: self.offset=at+2
                    else: result=1
                else: raise ValueError('Invalid token')
            if self.queue_type!=-1 and old_cel>=old_total-1:
                self.type=self.program=self.queue_type;self.offset=0;self.flags=self.queue_flags
                self.queue_type=-1;self.queue_flags=0;self.queue_cursor=(-1,-1);continue
            if result==2 and self.previous_type!=-1:
                self.type=self.program=self.previous_type;self.offset=0;self.flags=self.previous_flags
                self.previous_type=-1;self.previous_flags=0;self.previous_cursor=(-1,-1);continue
            self.timer+=1;return
        raise ValueError('Script runaway')
    def pose(self):
        if self.env_flags&1024:
            self.update_count+=1
            if self.update_count>=1 or self.cel==-1:
                self.update_count=0;self.cel+=1
                if self.cel>=self.total: self.cel=self.total-1 if self.env_flags&256 else 0
    def row(self,s,t,phase):
        return [s,t,phase,self.type,self.flags,self.program,self.offset,self.queue_type,self.queue_flags,self.previous_type,self.previous_flags,
                self.timer,self.anim_timer,self.action,self.cel,self.total,self.env_flags,self.update_count,self.no_input_timer,self.if_counter,self.seed]+list(self.loop_start)+list(self.loop_end)+list(self.queue_cursor)+list(self.previous_cursor)


def expected(data):
    rows=[]
    for scenario in range(5):
        state=State(data,scenario==3)
        for tick in range(64 if scenario==3 else 24):
            requests={0:{0:16,1:14,7:16,8:14},1:{0:11,2:14,6:16,7:14},2:{0:8,3:16},4:{0:25,2:24}}.get(scenario,{})
            if tick in requests: state.request(requests[tick])
            if scenario==2 and tick==8: state.initialise(14)
            state.no_input_timer=30 if scenario==3 else 0
            state.scripts();rows.append(state.row(scenario,tick,'scripts'))
            state.pose();rows.append(state.row(scenario,tick,'pose'))
    return rows


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--c-oracle',required=True)
    parser.add_argument('--out-dir',default='tests/golden/synthetic')
    parser.add_argument('--verify',action='store_true')
    parser.add_argument('--runtime-catalog',action='store_true')
    args=parser.parse_args();data=catalog()
    run=lambda *extra: subprocess.run([args.c_oracle,*extra],text=True,capture_output=True,check=True,creationflags=0x08000000 if os.name=='nt' else 0).stdout
    actual=[list(map(int,row.split(',')[1:])) for row in run('--catalog').splitlines() if row.startswith('T,')]
    want=[[i,e['flags'],len(e['words'])]+e['words'] for i,e in enumerate(data['entries'])]
    if actual!=want: raise ValueError('Compiled C animation catalog differs from source extraction')
    stdout=run();actual=list(csv.reader(io.StringIO(stdout[stdout.index('scenario,tick,phase,'):])));header=actual.pop(0)
    if header!=FIELDS: raise ValueError('Animation C schema differs')
    want=expected(data)
    if len(actual)!=len(want): raise ValueError('Animation C count differs')
    for i,(a,b) in enumerate(zip(actual,want)):
        for field,got,value in zip(FIELDS,a,b):
            if got!=str(value): raise ValueError('Animation C disagreement row %d %s Python=%s C=%s' % (i+2,field,value,got))
    out=Path(args.out_dir);out.mkdir(parents=True,exist_ok=True)
    content=io.StringIO(newline='');writer=csv.writer(content,lineterminator='\n');writer.writerow(FIELDS);writer.writerows(want)
    products={'frog_animation_catalog.json':json.dumps(data,indent=2)+'\n','frog_animation_components.csv':content.getvalue()}
    for file,text in products.items():
        path=out/file
        if args.verify:
            if path.read_text()!=text: raise ValueError('Frog animation golden differs: '+file)
        else: path.write_text(text)
    if args.runtime_catalog: runtime_catalog(data,Path('src/game/animation/frog_animation_catalog.gd'))
    print('Independent source catalog35 and Python/C animation320 component records match.')


if __name__=='__main__': main()

#!/usr/bin/env python3
"""Invented bounded script fixtures; Python expectations checked against frozen C."""
import argparse,csv,io,json,os,subprocess
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT
from tools.golden.org1_script_state import Script

ROOT=REPO_ROOT
IDENTITY=[4096,0,0,0,4096,0,0,0,4096,0,0,0]


def fixtures():
    def case(name,words,ticks,**kw):
        c=dict(name=name,root=1,programs={'1':words},names={'1':'SCRIPT_TURTLE'},registers=[],payload_offset=0,
               actions=[3,4],form_id=21,timer=0,deviation=0,seed=1,
               inputs=[[0,0,0,0,1,0] for _ in range(ticks)])
        c.update(kw);return c
    stop=case('stop_once_wrap',[34,0,1,0,0,38],5,timer=65534)
    for row in stop['inputs'][1:]:row[0]=1
    slots=case('callback_slots',[34,1,1,0,0,34,0,8,0,0,38],4)
    for row in slots['inputs']:row[0]=1
    dive=case('dive_rise',[34,1,2,7,1,8,0,1,128,2048,-1,9,7,0,0,0,0,3,8,0,1,0,-2048,-1,9,38],40)
    for row in dive['inputs']:row[1]=1
    fade=case('fade_display',[34,1,2,7,1,38],4,deviation=128)
    fade['inputs']=[[0,1,1,0,1,0],[0,1,0,1,1,0],[0,1,0,0,1,0],[0,0,0,0,1,0]]
    action=case('action_loop',[11,3,1,7,0,0,0,0,5,12,5],15)
    sound=case('sound_sprite_owner',[11,37,11,0,512,1024,44,0,12,5],6)
    sound['inputs'][0][4]=0;sound['inputs'][3][5]=1
    narrow=case('source_narrowing',[7,0,-1,8,0,1,0,65535,1,38],4)
    register=case('register_timer_sound',[31,12,3,35,0,7,1,0,0,1,1,36,0,2,11,0,0,38],7,registers=[2,4,0],payload_offset=12)
    branch=case('random_restart',[11,13,0,6,2,3,12,5],40)
    branch['programs']['2']=[36,0,2,11,0,0,5];branch['names']['2']='SCRIPT_ORG_TRUCK_SFX'
    return [stop,slots,dive,fade,action,sound,narrow,register,branch]


def expected(c):
    s=Script({int(k):v for k,v in c['programs'].items()},c['root'],c['registers'],c['actions'])
    s.timer=c['timer'];s.deviation=c['deviation'];seed=c['seed'];rows=[]
    for tick,(hit,carry,hidden,outside,allocation,clear) in enumerate(c['inputs']):
        if clear:s.moving_sound=False
        seed,_,_,drown=s.update(seed,IDENTITY,[0,0,0],hit,carry,c['form_id'],[1,32767,-32767,32767] if outside else None,bool(hidden),bool(allocation))
        s.advance_animation()
        row=dict(tick=tick,program=s.program,cursor=s.cursor,loop_start=s.start,loop_end=s.end,timer=s.timer,
                 deviation=s.deviation,delta=s.delta,destination=s.destination,remaining=s.remaining,action=s.action,cel=s.cel,rng=seed)
        row.update(zip(('red','green','blue'),s.colours));row.update(zip(('ambient_red','ambient_green','ambient_blue'),s.ambient))
        row.update(no_fade=int(s.no_fade),drown=int(drown),requests=';'.join(s.requests) or '-')
        for cb in range(2):row['callback'+str(cb)]=':'.join(map(str,s.callbacks.get(cb,(-1,0,0,0))))
        row.update(zip(('sound_id','sound_min','sound_max'),s.moving_sound or [-1,-1,-1]))
        rows.append(row)
    return rows


def transport(c):
    values=[len(c['inputs']),c['root'],c['seed'],len(c['programs'])]
    for k,v in c['programs'].items():values += [int(k),len(v),*v]
    values += [c['form_id'],c['payload_offset'],len(c['registers']),*c['registers'],len(c['actions']),*c['actions'],c['timer'],c['deviation']]
    for row in c['inputs']:values+=row
    return ' '.join(map(str,values))+'\n'


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--oracle',type=Path,required=True);parser.add_argument('--acos-table',type=Path,required=True)
    parser.add_argument('--output-directory',type=Path,required=True);parser.add_argument('--write',action='store_true');args=parser.parse_args()
    out=args.output_directory.resolve()
    if any(out.is_relative_to(p.resolve()) for p in (ROOT,ROOT.parent/'froggy')):raise ValueError('External output required')
    out.mkdir(parents=True,exist_ok=True);all_rows=[];cases=fixtures()
    for c in cases:
        path=out/(c['name']+'.txt');path.write_text(transport(c),encoding='ascii')
        process=subprocess.run([str(args.oracle.resolve()),str(args.acos_table.resolve()),'--entity-script',str(path)],capture_output=True,text=True,timeout=30,
                               creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        (out/(c['name']+'.csv')).write_text(process.stdout,encoding='utf-8')
        if process.returncode:raise ValueError(f'{c["name"]}: C exit {process.returncode}: {process.stderr}')
        lines=process.stdout.splitlines();at=next(i for i,line in enumerate(lines) if line.startswith('tick,program,'))
        actual=list(csv.DictReader(io.StringIO('\n'.join(lines[at:]))));wanted=expected(c)
        if len(actual)!=len(wanted):raise ValueError('Incomplete C script trace')
        for a,w in zip(actual,wanted):
            for key,value in w.items():
                if a[key]!=str(value):raise ValueError(f'{c["name"]} tick {w["tick"]} {key}: C={a[key]}, Python={value}')
            all_rows.append(dict(case=c['name'],**w))
    output=io.StringIO(newline='');writer=csv.DictWriter(output,fieldnames=list(all_rows[0]),delimiter='\t',lineterminator='\n');writer.writeheader();writer.writerows(all_rows)
    for path,text in [(ROOT/'tests/golden/synthetic/entity_scripts.tsv',output.getvalue()),(ROOT/'tests/golden/fixtures/entity_scripts.json',json.dumps(cases,indent=2)+'\n')]:
        if args.write:path.write_text(text,encoding='utf-8',newline='\n')
        elif path.read_text(encoding='utf-8')!=text:raise ValueError(f'Golden mismatch: {path.name}')
    print(f'{len(cases)} synthetic cases, {len(all_rows)} complete script updates match frozen C.')


if __name__=='__main__':main()

"""Streaming complete ORG1 schedule comparison against independent source facts."""
import csv
import hashlib
import itertools
import json
import os
from pathlib import Path
import subprocess
import uuid


def phase_facts(record):
    s=record['state'];c=s['camera'];d=s['entities']['entities'][0]
    result=dict(tick=record['tick'],phase='pose' if record['phase']=='final' else record['phase'])
    result.update(zip(('x16','y16','z16'),s['position_16']))
    for target,source in [('flags','flags'),('mode','mode'),('attached','current_entity_index'),('count','remaining_ticks'),('old_y','old_y'),('direction','direction'),('rng','rng_state'),('sounds','sound_requests')]:result[target]=s[source]
    for prefix,key in [('camera','tracked_world'),('source','source_world'),('target','target_world')]:result.update(zip((prefix+'_'+axis for axis in 'xyz'),c[key]))
    result.update((f'controller_{i}',v) for i,v in enumerate(c['controller_directions']))
    result.update((f'camera_mod{i//3}{i%3}',v) for i,v in enumerate(c['mod_matrix12'][:9]))
    result.update(action=s['animation']['action'],cel=s['animation']['cel'],diver_y=d['script_state']['deviation'],diver_timer=d['script_state']['timer'],diver_action=d['animation']['action'])
    return result


def entity_facts(visit,fly,tick):
    p=visit['entity'];s=p['script_state'];a=p['animation']
    result=dict(tick=tick,index=p['entity_index'],root=s['root_id'] if s else -1,program=s['program_id'] if s else -1,
                action=a['action'],cel=a['cel'],rng=visit['rng_state'],sounds=visit['sound_requests'],moving_sound=int(bool(s and s['moving_sound'])),
                requests=';'.join(p['requests']) or '-',previous_flags=visit['previous_flags'],live_flags=p['live_flags'],
                fly_mode=fly['mode'],fly_timer=fly['timer'],fly_checkpoint=fly['checkpoint_index'],covered=visit['environment']['covered'])
    for key in ('cursor','loop_start','loop_end','timer','deviation','delta','destination','remaining'):result[key]=s[key] if s else (-1 if key in ('cursor','loop_start','loop_end') else 0)
    result.update(zip(('red','green','blue'),p['colour_scale']));result.update(zip(('ambient_red','ambient_green','ambient_blue'),p['ambient']))
    result.update(zip('xyz',p['matrix12'][9:]))
    for slot in range(2):result[f'callback{slot}']=':'.join(map(str,s['callbacks'][slot])) if s else '-1:0:0:0'
    result.update(zip(('sound_id','sound_min','sound_max'),s['moving_sound'] if s and s['moving_sound'] else (-1,-1,-1)))
    return result


def check_source(path,repo,name,ticks):
    directory=repo/'tests/golden/pc-retail-v3.0e'
    with (directory/(name+'.tsv')).open(newline='') as stream:expected=list(csv.DictReader(stream,delimiter='\t'))
    with (directory/(name+'_entities.tsv')).open(newline='') as stream:digests=list(csv.DictReader(stream,delimiter='\t'))
    fields=json.loads((directory/'org1_entity_update_fields.json').read_text())
    fly=dict(mode=0,timer=60,checkpoint_index=-1);count=0
    with path.open() as stream:
        metadata=json.loads(next(stream))
        if metadata['exploration']!='org1-turtle-log-bank' or metadata['tick_limit']!=ticks:raise ValueError('wrong ORG1 metadata')
        if metadata['exploration_guard']['world_bounds']!=[-512,-128,1024,608]:raise ValueError('admission bounds changed')
        for record,source in itertools.zip_longest((json.loads(line) for line in stream),expected):
            if record is None or source is None:raise ValueError('incomplete ORG1 trace')
            for key,value in phase_facts(record).items():
                if str(value)!=source[key]:raise ValueError(f'{record["tick"]}/{record["phase"]}: {key} runtime={value}, source={source[key]}')
            if record['phase']=='control':
                visits=record['state']['entities']['updates']
                if [v['entity']['entity_index'] for v in visits]!=list(range(63,-1,-1)):raise ValueError('ordered visits incomplete')
                canonical='\t'.join(fields)+'\n'
                for visit in visits:
                    if visit['entity']['entity_index']==55:fly=visit['entity']['background']
                    facts=entity_facts(visit,fly,record['tick'])
                    canonical+='\t'.join(str(facts[k]) for k in fields)+'\n'
                digest=hashlib.sha256(canonical.encode('ascii')).hexdigest()
                if digest!=digests[record['tick']]['ordered_entity_updates_sha256']:raise ValueError(f'tick {record["tick"]} ordered source updates differ')
            count+=1
    if count!=ticks*6:raise ValueError('wrong complete phase count')
    return count


def run(args):
    repo=Path(__file__).resolve().parents[1];output=args.output_directory.resolve()
    for protected in (repo,(repo.parent/'froggy').resolve()):
        if output==protected or protected in output.parents:raise ValueError('Evidence must be external')
    fixture=json.loads(args.scenario_file.read_text());ticks=fixture['tick_limit']
    name='org1_round_trip' if ticks==730 else 'org1_attached_diver' if ticks==1255 else None
    if name is None or args.tick_limit is not None:raise ValueError('Select the complete frozen ORG1 route fixture')
    evidence=output/('org1-schedules-'+uuid.uuid4().hex);profile=evidence/'profile';profile.mkdir(parents=True)
    env=os.environ.copy();env.pop('FROGGER_DATA_DIR',None);env.update(APPDATA=str(profile),TEMP=str(profile),TMP=str(profile),XDG_DATA_HOME=str(profile))
    startup=None
    if os.name=='nt':
        startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    def identities():
        paths=[p for directory in ('src','tools','scenes') for p in (repo/directory).rglob('*') if p.suffix in ('.gd','.gdshader','.json','.py','.tscn')]
        paths += [args.scenario_file,repo/'project.godot']
        paths += list((repo/'tests/golden/pc-retail-v3.0e').glob('org1*'))
        return {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    before=identities();(evidence/'provenance.json').write_text(json.dumps(before,indent=2))
    print('ORG1 schedule evidence: '+str(evidence),flush=True)
    def stage(label,arguments,headless=True):
        command=[args.godot,'--disable-crash-handler','--path',str(repo),'--log-file',str(evidence/(label+'.log')),'--resolution','640x480']
        if headless:command.append('--headless')
        with (evidence/(label+'-process.log')).open('w') as stream:
            result=subprocess.run(command+arguments,cwd=repo,env=env,startupinfo=startup,stdout=stream,stderr=subprocess.STDOUT,timeout=1800)
        log=(evidence/(label+'.log')).read_text()
        if result.returncode or any(x in log for x in ('SCRIPT ERROR','Parse Error','CHECK FAILED','ERROR:')):raise RuntimeError(f'{label} failed; see {evidence}')
    selected=['--level=ORG1','--exploration=org1-turtle-log-bank','--scenario-file='+str(args.scenario_file.resolve()),'--data-dir='+str(args.data_dir.resolve())]
    stage('import',['--import']);stage('check',['-s','res://tools/check_scripts.gd'])
    baseline=evidence/'headless.jsonl'
    stage('headless',['-s','res://tools/run_terrain_scenario.gd','--','--trace-jsonl='+str(baseline),*selected])
    count=check_source(baseline,repo,name,ticks);print(f'Headless source agreement: {count} phases and {ticks*64} ordered updates',flush=True)
    for rate in (30,60,144):
        rendered=evidence/f'rendered-{rate}.jsonl';captures=evidence/f'captures-{rate}'
        stage(f'rendered-{rate}',['res://scenes/tools/terrain_viewer.tscn','--','--run-scenario',f'--render-rate={rate}','--trace-jsonl='+str(rendered),'--screenshot-dir='+str(captures),*selected],False)
        with baseline.open() as a,rendered.open() as b:
            for index,(left,right) in enumerate(itertools.zip_longest(a,b)):
                if left is None or right is None or json.loads(left)!=json.loads(right):raise ValueError(f'{rate} FPS full trace mismatch at record {index}')
        from verify_platform_schedules import check_png
        required=('org1-turtle-out','org1-log','org1-turtle-return','org1-bank-return') if ticks==730 else ('org1-diver-attachment','org1-diver-drowning')
        for label in (*required, 'org1-diving', 'org1-rising'):check_png(captures/f'entity-{label}.png')
        print(f'{rate} FPS complete trace and captures match',flush=True)
    if identities()!=before:raise ValueError('Source or proof changed during verification')
    (evidence/'comparison.json').write_text(json.dumps(dict(passed=True,phases=count,ordered_updates=ticks*64,rates=[30,60,144],scope='Full represented state and ordered outcomes; scheduled frame deltas, not measured host FPS'),indent=2))
    print('ORG1 schedule verification passed: '+str(evidence),flush=True)

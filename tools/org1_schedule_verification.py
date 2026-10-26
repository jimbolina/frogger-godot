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
    result.update(action=s['animation']['action'],cel=s['animation']['cel'],diver_y=d['script_state']['deviation'] if d['script_state'] else 0,diver_timer=d['script_state']['timer'] if d['script_state'] else 0,diver_action=d['animation']['action'] if d['animation'] else 0)
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
    if p['background'] and p['background']['moving_sound']:
        result['moving_sound']=1
        result.update(zip(('sound_id','sound_min','sound_max'),p['background']['moving_sound']))
    return result


def check_source(path,repo,name,ticks,preset='org1-turtle-log-bank'):
    directory=repo/'tests/golden/pc-retail-v3.0e'
    with (directory/(name+'.tsv')).open(newline='') as stream:expected=list(csv.DictReader(stream,delimiter='\t'))
    with (directory/(name+'_entities.tsv')).open(newline='') as stream:digests=list(csv.DictReader(stream,delimiter='\t'))
    fields=json.loads((directory/'org1_entity_update_fields.json').read_text())
    fly=dict(mode=0,timer=60,checkpoint_index=-1);count=0;updates=0
    with path.open() as stream:
        metadata=json.loads(next(stream))
        if metadata['exploration']!=preset or metadata['tick_limit']!=ticks:raise ValueError('wrong ORG1 metadata')
        manifest='org1_visibility_admission.json' if preset.endswith('-visibility') else 'org1_road_river_admission.json' if preset=='org1-road-river' else 'org1_exploration_admission.json'
        admission=json.loads((repo/'src/presentation/setup'/manifest).read_text())
        x,z=admission['admitted_x'],admission['admitted_z']
        if metadata['exploration_guard']['world_bounds']!=[x[0],z[0],x[1]-x[0],z[1]-z[0]]:raise ValueError('admission bounds changed')
        for record,source in itertools.zip_longest((json.loads(line) for line in stream),expected):
            if record is None or source is None:raise ValueError('incomplete ORG1 trace')
            observed=phase_facts(record)
            if 'first_killer' in source:
                s=record['state'];pose=s['frog_collision_pose']
                observed.update(zip(('vx16','vy16','vz16'),s['velocity_16']))
                observed.update(death_equate=s['death_equate'],lives=s['fixture_lives']-int(s['life_decrement_requested']),first_killer=s['death_entity_index'],stored_action=pose['action'],stored_actual_cel=pose['actual_cel'])
                observed['primitive_hit_indices']=';'.join(str(p['entity_index']) for p in s['entities']['entities'] if 24<=p['entity_index']<=47 and p['live_flags']&64) or '-'
                if 'primitive_contacts' in source and record['phase']=='final':
                    observed['primitive_contacts']=';'.join(f'{p["entity_index"]}:{p["frog_part_index"]}:{p["hilite_index"]}:{p["primitive_index"]}' for p in record.get('primitive_contacts',[]) if p['status']=='contact') or '-'
            for key,value in observed.items():
                if str(value)!=source[key]:raise ValueError(f'{record["tick"]}/{record["phase"]}: {key} runtime={value}, source={source[key]}')
            if record['phase']=='control':
                visits=record['state']['entities']['updates']
                updates+=len(visits)
                if not preset.endswith('-visibility') and [v['entity']['entity_index'] for v in visits]!=list(range(63,-1,-1)):raise ValueError('ordered visits incomplete')
                canonical='\t'.join(fields)+'\n'
                for visit in visits:
                    if visit['entity']['entity_index']==55:fly=visit['entity']['background']
                    facts=entity_facts(visit,fly,record['tick'])
                    canonical+='\t'.join(str(facts[k]) for k in fields)+'\n'
                digest=hashlib.sha256(canonical.encode('ascii')).hexdigest()
                if digest!=digests[record['tick']]['ordered_entity_updates_sha256']:raise ValueError(f'tick {record["tick"]} ordered source updates differ')
            count+=1
    if count!=ticks*6:raise ValueError('wrong complete phase count')
    return count,updates


def run(args):
    repo=Path(__file__).resolve().parents[1];output=args.output_directory.resolve()
    for protected in (repo,(repo.parent/'froggy').resolve()):
        if output==protected or protected in output.parents:raise ValueError('Evidence must be external')
    fixture=json.loads(args.scenario_file.read_text());ticks=fixture['tick_limit']
    if args.exploration.endswith('-visibility'):
        names=('org1_visibility_round_trip','org1_visibility_diver','org1_visibility_pickup','org1_visibility_pickup_death')
        name=next((candidate for candidate in names if fixture==json.loads((repo/'tests/golden/fixtures'/(candidate+'.json')).read_text())),None)
    elif args.exploration=='org1-road-river':
        names=('org1_road_river','org1_road_vehicle_death')
        name=next((candidate for candidate in names if fixture==json.loads((repo/'tests/golden/fixtures'/(candidate+'.json')).read_text())),None)
    else:
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
    selected=['--level=ORG1','--exploration='+args.exploration,'--scenario-file='+str(args.scenario_file.resolve()),'--data-dir='+str(args.data_dir.resolve())]
    stage('import',['--import']);stage('check',['-s','res://tools/check_scripts.gd'])
    baseline=evidence/'headless.jsonl'
    stage('headless',['-s','res://tools/run_terrain_scenario.gd','--','--trace-jsonl='+str(baseline),*selected])
    count,updates=check_source(baseline,repo,name,ticks,args.exploration);print(f'Headless source agreement: {count} phases and {updates} ordered updates',flush=True)
    rates = (30,60,144) if args.exploration.endswith('-visibility') else (30,60,144,200,240,'irregular')
    for rate in rates:
        rendered=evidence/f'rendered-{rate}.jsonl';captures=evidence/f'captures-{rate}'
        schedule = ['--render-rate=240', '--frame-schedule=irregular'] if rate == 'irregular' else [f'--render-rate={rate}']
        stage(f'rendered-{rate}',['res://scenes/tools/terrain_viewer.tscn','--','--run-scenario','--smoothing=false',*schedule,'--trace-jsonl='+str(rendered),'--screenshot-dir='+str(captures),*selected],False)
        with baseline.open() as a,rendered.open() as b:
            for index,(left,right) in enumerate(itertools.zip_longest(a,b)):
                if left is None or right is None or json.loads(left)!=json.loads(right):raise ValueError(f'{rate} FPS full trace mismatch at record {index}')
        from verify_platform_schedules import check_png
        if args.exploration=='org1-road-river':
            required=('org1-road-start','org1-road-traffic','org1-road-bank','org1-road-river') if name=='org1_road_river' else ('org1-road-start','org1-road-traffic','org1-road-vehicle-death')
        elif name.startswith('org1_visibility_pickup'):
            required=('org1-pink-contact','org1-pink-pickup','org1-pink-riding')
            if name.endswith('_death'):required+=('org1-pink-death',)
        else:
            required=('org1-turtle-out','org1-log','org1-turtle-return','org1-bank-return') if ticks==730 else ('org1-diver-attachment','org1-diver-drowning')
            required=(*required,'org1-diving','org1-rising')
        for label in required:check_png(captures/f'entity-{label}.png')
        print(f'{rate} FPS complete trace and captures match',flush=True)
    if identities()!=before:raise ValueError('Source or proof changed during verification')
    (evidence/'comparison.json').write_text(json.dumps(dict(passed=True,phases=count,ordered_updates=updates,rates=rates,scope='Full represented state and ordered outcomes; scheduled frame deltas, not measured host FPS'),indent=2))
    print('ORG1 schedule verification passed: '+str(evidence),flush=True)

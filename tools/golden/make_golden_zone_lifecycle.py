"""Independent combined zone/path/visibility facts, checked against unchanged frozen C."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT
from tools.golden import make_golden_camera_zones as camera
from tools.golden import make_golden_entity_lifecycle as visibility
from tools.golden import make_golden_retail_platform as retail
from tools.golden import make_lifecycle_integrated_fixture as fixture

ROOT = REPO_ROOT


def synthetic():
    authored = fixture.build()
    authored['name'] = 'zone_visibility_departure_return'
    zone = dict(zone_index=0, bounds=[5, 0, 12, 3], regions=[], camera_flags=0,
                camera_direction=-1, camera_offsets=[[0,-768,-768],[0,0,0]]*4)
    authored['level']['camera_zones'] = [zone]
    frames = []
    x = -128 << 16
    remaining = 0
    y = 0
    for tick in range(336):
        key = 2 if tick in range(16,144,8) else 8 if tick in range(176,304,8) else 0
        if key:
            target = x + (256 << 16) * (1 if key == 2 else -1)
            velocity = visibility.div(target-x,6)
            vertical = -56 << 16
            remaining = 6
        if remaining:
            remaining -= 1
            if remaining:
                vertical += 16 << 16
                x += velocity
                y += vertical
            else:
                x, y = target, 0
        frames.append(dict(cell=[(x >> 16)+512 >> 8,1], world=[x >> 16,y >> 16,-128],
                           freeze=0,turn=0,fixed=0,start_timer=0,key=key))
    case = dict(name=authored['name'], zones=[dict(bounds=zone['bounds'],regions=[],flags=0,
                direction=-1,offsets=zone['camera_offsets'])], frames=frames,
                startup=False,yaw=0,source=[0,-512,-512],target=[0,0,0],initial=[-128,0,-128],grounded_hops=True)
    entities = []
    for item in authored['level']['entity_collision']['entities']:
        record = dict(index=item['entity_index'],kind=item['entity_name'],flags=item['flags'])
        if record['kind']=='STATIC': record['position']=item['matrix12'][9:]
        else:
            record['segments']=item['path_definition']['segments']
            record['start']=dict(item['path_start'],flags=item['path_start']['flags']|1)
        entities.append(record)
    groups=dict(base=[-8192,0,-8192],dimensions=[32,32],size=[512,512],counts=[1]*1024)
    return authored, dict(case=case,entities=entities,groups=groups,gameplay=True)


def retail_inputs(data_dir):
    exe=retail.exe_tables
    cfg=exe.parse_cfg(str(Path(exe.CFG_ROOT)/'versions/pc-retail-v3.0e.cfg'))
    image=exe.Exe((data_dir/'FROGGER.EXE').read_bytes(),exe.java_int(cfg.values['ramOffset']))
    _,entries,wads,files=retail.mof.load_archive(str(data_dir),exe.java_int(cfg.values['mwiOffset']),exe.java_int(cfg.values['mwiLength']))
    archive=(data_dir/'FROGPSX.MWD').read_bytes()
    levels,_=exe.read_map_book(image,exe.java_int(cfg.values['mapBook']),exe.java_int(cfg.values['themeBook']))
    level=levels[exe.LEVEL_CODES.index('JUN1')]
    if level['high_map']!=656: raise ValueError('JUN1 high map changed')
    blob=retail.resource(files,entries,archive,656)
    names,sections,_=exe.name_list('forms',cfg.values.get('formList','1997-09-12-psx-build57'))
    entity_names,_,entity_cfg=exe.name_list('entities',cfg.values.get('entityList','1997-09-12-psx-build57'))
    overrides=entity_cfg.child('Override')
    forms=exe.read_forms(image,exe.read_theme_book(image,exe.java_int(cfg.values['themeBook'])),sections,[])
    gene,grap,_,emtp,_,path=struct.unpack_from('<6I',blob,76)
    theme=struct.unpack_from('<H',blob,gene+10)[0]
    group=struct.unpack_from('<I',blob,grap+8)[0]
    groups=dict(base=list(struct.unpack_from('<3h',blob,group+4)),dimensions=list(struct.unpack_from('<2H',blob,group+12)),size=list(struct.unpack_from('<2H',blob,group+16)))
    groups['counts']=[sum(blob[group+20+i*72:group+28+i*72]) for i in range(groups['dimensions'][0]*groups['dimensions'][1])]
    entities=[]; bindings=[]
    for index in range(struct.unpack_from('<H',blob,emtp+8)[0]):
        at=struct.unpack_from('<I',blob,emtp+12+index*4)[0]
        grid,uid,fid,flags=struct.unpack_from('<4H',blob,at)
        form=forms[0 if fid&32768 else theme][fid&32767]
        name=names[form['global']]
        if name!='JUN_LOG': continue
        kind=overrides.values.get(name,entity_names[form['entity_type']])
        if kind!='MOVING' or form['script'] or form['collision'] or form['bonus'] or flags:
            raise ValueError('JUN_LOG behavior changed')
        model_id=wads[level['high_wad']][form['id']][0]
        bindings.append([index,fid,uid,name,kind,form['script'],form['collision'],form['bonus'],flags,model_id])
        pid,segment,distance,motion,speed,padding=struct.unpack_from('<6H',blob,at+24)
        if padding or motion & ~14: raise ValueError('Unsupported log path start')
        ptr=struct.unpack_from('<I',blob,path+8+pid*4)[0]
        segments=[]
        for si in range(struct.unpack_from('<I',blob,ptr+4)[0]):
            offset=struct.unpack_from('<I',blob,ptr+8+si*4)[0]
            kind_id,length=struct.unpack_from('<2i',blob,offset)
            item=dict(segment_type=kind_id,length=length)
            if kind_id==2:
                item.update(start=list(struct.unpack_from('<3h',blob,offset+8)),end=list(struct.unpack_from('<3h',blob,offset+16)))
            elif kind_id==0:
                words=list(struct.unpack_from('<28i',blob,offset+8))
                item.update(matrix=words[:12],smooth_t=words[12:16],smooth_c=words[16:])
            else: raise ValueError('Unverified log path kind')
            segments.append(item)
        entities.append(dict(index=index,kind='MOVING',flags=flags,segments=segments,
                             start=dict(segment_index=segment,distance=distance,speed=speed,flags=motion|1)))
    if len(entities)!=11: raise ValueError('Expected eleven JUN_LOG records')
    proof=dict(schema='jun1-zone-lifecycle-preset-v1',build='pc-retail-v3.0e',
               exe_sha256=hashlib.sha256((data_dir/'FROGGER.EXE').read_bytes()).hexdigest(),
               mwd_sha256=hashlib.sha256(archive).hexdigest(),map_resource_id=656,bindings=bindings)
    return proof,[dict(case=dict(case,initial=[0,0,0]),entities=entities,groups=groups,gameplay=False) for case in camera.retail_cases(data_dir)]


def expected(workload):
    case=workload['case'];groups=workload['groups'];entities=workload['entities']
    cams=camera.model(case)
    paths={e['index']:retail.paths.python_trace(dict(segments=e['segments'],start=e['start'],tick_limit=len(cams))) for e in entities if e['kind']=='MOVING'}
    live=[];pending=set();generations={e['index']:0 for e in entities};result=[]
    for tick,cam in enumerate(cams):
        events=[]
        for identity in list(live):
            if identity in pending:
                live.remove(identity);pending.remove(identity)
                events.append(f'destroy:{identity}:{generations[identity]}')
            else: pending.add(identity)
        selected=visibility.select(groups,dict(source=cam['source_world'],axes=[cam['axis_x_12'],cam['axis_y_12'],cam['axis_z_12']]))
        polygons=sum(groups['counts'][i] for i in selected)
        if polygons>=2500: raise ValueError(f'Visibility budget exceeded at {tick}')
        poses={e['index']:(paths[e['index']][tick+1][9:12] if e['kind']=='MOVING' else e['position']) for e in entities}
        membership={}
        for e in entities:
            v=poses[e['index']]
            gx,gz=[max(0,min(groups['dimensions'][axis]-1,visibility.div(v[world]-groups['base'][world],groups['size'][axis]))) for axis,world in enumerate((0,2))]
            membership[e['index']]=gz*groups['dimensions'][0]+gx
        for group in selected:
            for kind in ('MOVING','STATIC'):
                for e in reversed(entities):
                    identity=e['index']
                    if e['kind']!=kind or membership[identity]!=group: continue
                    if identity in live: pending.discard(identity)
                    else:
                        live.insert(0,identity);generations[identity]+=1
                        events.append(f'create:{identity}:{generations[identity]}')
        records=[]
        for e in entities:
            i=e['index'];path=paths[i][tick+1] if i in paths else None
            records.append(dict(entity_index=i,live=i in live,destroy_pending=i in pending,generation=generations[i],position=poses[i],
                                path=path))
        result.append(dict(tick=tick,world=case['frames'][tick]['world'],camera=cam,selected_groups=selected,
                           polygon_total=polygons,live_order=list(live),events=events,entities=records))
    if not any(r['events'] for r in result) or not any(e['generation']>1 for r in result for e in r['entities']):
        raise ValueError('Fixture must recreate entities')
    return result


def transport(workload):
    case=workload['case'];g=workload['groups']
    values=[int(workload['gameplay']),len(case['frames']),case['yaw'],*case['initial'],*case['source'],*case['target'],
            *g['base'],*g['dimensions'],*g['size'],len(workload['entities'])]
    for e in workload['entities']:
        values += [e['index'],int(e['kind']=='MOVING'),e['flags']]
        if e['kind']=='STATIC':values+=e['position']
        else:
            start=e['start'];values += [len(e['segments']),start['segment_index'],start['distance'],start['speed'],start['flags']]
            for s in e['segments']:
                values += [s['segment_type'],s['length']]
                values += s['start']+s['end'] if s['segment_type']==2 else s['matrix']+s['smooth_t']+s['smooth_c']
    values += [len(case['zones'])]
    for z in case['zones']:
        values += [*z['bounds'],len(z['regions'])]
        for region in z['regions']:values+=region
        values += [z['flags'],z['direction']]
        for offset in z['offsets']:values+=offset
    for f in case['frames']:values += [*f['cell'],*f['world'],f.get('key',0)]
    return '\n'.join(map(str,values))+'\n'


def verify_c(workload, rows, executable, evidence):
    name=workload['case']['name'];source=evidence/(name+'.txt');source.write_text(transport(workload))
    run=subprocess.run([str(executable),str(source)],capture_output=True,text=True,timeout=60)
    (evidence/(name+'.log')).write_text(run.stdout+run.stderr)
    if run.returncode: raise ValueError(f'Frozen transport failed: {name}, {run.returncode}')
    frozen=[json.loads(line) for line in run.stdout.splitlines() if line.startswith('{')]
    if len(frozen)!=len(rows):raise ValueError(f'Frozen row count differs: {name}')
    for tick,(actual,expected_row) in enumerate(zip(frozen,rows)):
        for key,value in actual.items():
            target=expected_row[key]
            if key=='camera':target={k:target[k] for k in value}
            if key=='entities':target=[{k:r[k] for k in value[i]} for i,r in enumerate(target)]
            if value!=target: raise ValueError(f'{name} tick {tick} {key}: frozen {value} != independent {target}')


def save(path, value, verify):
    text=json.dumps(value,indent=2)+'\n'
    if verify:
        if path.read_text(encoding='utf-8')!=text: raise ValueError(f'Golden differs: {path}')
    else:path.write_text(text,encoding='utf-8')


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--c-oracle',type=Path,required=True);ap.add_argument('--evidence',type=Path,required=True)
    ap.add_argument('--data-dir',type=Path,required=True);ap.add_argument('--verify',action='store_true')
    args=ap.parse_args();evidence=args.evidence.resolve()
    for protected in (ROOT,ROOT.parent/'froggy'):
        if evidence==protected or protected in evidence.parents:ap.error('Evidence must be outside repositories')
    evidence.mkdir(parents=True,exist_ok=True)
    authored,work=synthetic();proof,retail_work=retail_inputs(args.data_dir)
    for label,workloads in [('synthetic',[work]),('pc-retail-v3.0e',retail_work)]:
        cases=[]
        for workload in workloads:
            rows=expected(workload);verify_c(workload,rows,args.c_oracle,evidence)
            cases.append(dict(workload=workload,expected=rows))
        save(ROOT/f'tests/golden/{label}/zone_lifecycle.json',dict(schema='zone-lifecycle-facts-v1',cases=cases),args.verify)
    save(ROOT/'tests/golden/fixtures/lifecycle_zones.json',authored,args.verify)
    save(ROOT/'src/inspection/jun1_zone_lifecycle_preset.json',proof,args.verify)
    print('Synthetic and JUN1 zone/lifecycle facts agree with frozen C.')


if __name__=='__main__':main()

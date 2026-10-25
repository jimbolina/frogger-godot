#!/usr/bin/env python3
"""Independent retail transport for ORG1 route research, not an admission.

Only decimal decoded facts leave this reader. The C trace is evidence to be
compared with an independent simulation before any runtime preset is enabled.
"""
import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
import verify_org1_admission as admission
import org1_neighbor_admission as neighbor
import org1_hilite_admission as hilite


def admission_manifest(context,geometry,probes):
    """Pin independently decoded inputs and the state-space proof conditions."""
    if geometry['zone_count'] or geometry['included_FORM_indices']!=[0,1,2,3,12,13,14,15,16,23]:
        raise ValueError('ORG1 contact/zone closure changed')
    if geometry['unresolved_contact_indices']!=list(range(24,48)) or not probes['separated']:
        raise ValueError('ORG1 neighbor exclusion is incomplete')
    for r in geometry['neighbors']:
        if r['entity_index'] in geometry['included_FORM_indices']:
            form=geometry['form_grids'][r['form_grid_id']]
            if r['primitive_count'] or r['book_flags']&2 or set(form['flags'])!={3}:
                raise ValueError('supported contact no longer has a snapped primitive-free SAFE FORM')
        if r['entity_type'] in ('CHECKPOINT','ORG_FLY','ORG_BABY_FROG'):
            if r['minimum_candidate_xz_distance_squared']<=640**2:
                raise ValueError('a collectable or checkpoint can enter the tongue/croak radius')
    heights=[]
    for cell in geometry['terrain']:
        if len(cell['layers'])!=1:raise ValueError('terrain stack closure changed')
        layer=cell['layers'][0]
        if layer['flags'] not in (65539,9):raise ValueError('terrain reaction closure changed')
        heights.extend(p[1] for p in layer['vertices'])
    if min(heights)<-256 or max(heights)>0:raise ValueError('terrain fall-height closure changed')
    if any(not f['all_writers_agree'] for f in geometry['form_grids']):raise ValueError('shared FORM writer disagreement')
    books=[];models=[]
    for r in geometry['neighbors']:
        fid=r['form_id'];b=context['forms'][0 if fid&0x8000 else context['theme']][fid&0x7fff]
        books.append([r['entity_index'],r['unique_id'],r['form_grid_id'],fid,r['flags'],b['entity_type'],b['id'],
                      b['script'],b['flags'],b['collision'],b['radius2'],b['death'],b['bonus']])
        models.append(-1 if b['flags']&1 else r['model_resource_id'])
    model_facts=[{k:r[k] for k in ('resource_id','sha256','counterpart_resource_id')} for r in geometry['models']]
    model_facts.append(dict(resource_id=214,sha256=probes['animation_sha256'],counterpart_resource_id=-1))
    return dict(schema='org1-route-admission-v1',build='pc-retail-v3.0e',map_resource_id=658,
        map_sha256=geometry['map_sha256'],form_book_rows_sha256=admission.platform.route_numeric_digest(books),
        script_rows_sha256=admission.platform.route_numeric_digest([[i,len(s['stream']),*s['stream']] for i,s in enumerate(context['scripts'])]),
        model_resources=sorted(model_facts,key=lambda r:r['resource_id']),entity_model_resources=models,
        name_bindings=[dict(index=r['entity_index'],form=r['form_name'],entity=r['entity_type'],script=context['script_names'][r['script_id']]) for r in geometry['neighbors']],
        script_names=context['script_names'],callback_names=context['callbacks'],
        theme_index=context['theme'],theme_death_height=context['themes'][context['theme']]['death_height'],
        general_high_wad=geometry['general_high_wad'],admitted_x=[-512,512],admitted_z=[-128,480],
        frog_resource_id=214,live_frog_actions=probes['live_actions'],initial_action_cel=[0,0],frog_roots=probes['roots'],
        included_contact_indices=geometry['included_FORM_indices'],authored_count=64,
        contact_exclusions=[dict(index=r['entity_index'],unique_id=r['unique_id'],offset=r['source_offset'],
            reason='excluded_by_animated_frog_probe_closure' if 24<=r['entity_index']<48 else r['contact_status'])
            for r in geometry['neighbors'] if r['entity_index'] not in geometry['included_FORM_indices']],
        lifetime='all-attached',spawn_cell=[10,7],spawn_world=[128,-256,-128],spawn_direction=0,
        round_trip=dict(commands=[[0,1],[12,1],[34,4],[46,4]],observation_ticks=730,bank_return_tick=51),
        attached_diver=dict(commands=[[1230,1]],observation_ticks=1255,contact_tick=1233,death_tick=1254),
        traffic_probe_z_minimum=probes['minimum_probe_world_z'],traffic_point_z_maximum=probes['traffic_maximum_accepted_z'],
        conditions=['Single unpowered player; the selected high-detail frog resource and reset state are pinned.',
            'Every collision-bearing stored root origin remains in the half-open rectangle; rejected ticks roll back.',
            'SAFE bank/platforms and WATER only; maximum landing-height difference is below the 512-unit stun threshold.',
            'All support-path orientations, cardinal hops, snapping, centring and inherited up axes are included.',
            'Death/MUST_DIE skips primitive scans before death animation changes; croak imports affect no hilite-bearing part.',
            'No tongueable neighbor within 640 units, no collectable contact, no powerups or body scaling.',
            'All 64 authored identities retain their ordered logical updates; only ten require FORM contact.',
            'Checkpoint croak radius 512 is excluded; baby parent never retires; fly covered state and sound owners persist.'])


def golden_text(phases,entities):
    """Text phase facts and ordered 64-entity update digests, from Python only."""
    phase_output=io.StringIO(newline='');writer=csv.DictWriter(phase_output,fieldnames=list(phases[0]),delimiter='\t',lineterminator='\n')
    writer.writeheader();writer.writerows(phases)
    fields=list(entities[0]);lines=['tick\tordered_entity_updates_sha256']
    for tick in range(len(phases)//6):
        rows=[r for r in entities if r['tick']==tick]
        canonical='\t'.join(fields)+'\n'+''.join('\t'.join(str(row[field]) for field in fields)+'\n' for row in rows)
        lines.append(f'{tick}\t'+hashlib.sha256(canonical.encode('ascii')).hexdigest())
    return phase_output.getvalue(),'\n'.join(lines)+'\n',fields


def transport(root, ticks, commands, road=False, visibility=False):
    """Decode complete terrain, paths, script closure and all authored identities."""
    facts, c = admission.retail_counterexamples(root, True)
    data = c['data']; read = admission.contacts.read
    geometry = neighbor.neighbor_admission(facts, c,(-512,512,-1792,480)) if road else neighbor.neighbor_admission(facts,c)
    if road: geometry['road']=True
    grap = read(data,80,'<I'); grid = read(data,grap+20,'<I'); vertices = read(data,grap+16,'<I')
    width,depth = struct.unpack_from('<2H',data,grid+4)
    group = read(data,grap+8,'<I')
    gx,gy,gz,pad,nx,nz,sx,sz = struct.unpack_from('<4h4H',data,group+4)
    stacks = [struct.unpack_from('<BBH',data,grid+12+i*4) for i in range(width*depth)]
    total = max(first+count for count,avg,first in stacks)
    values = [ticks,*[commands.get(i,-1) for i in range(ticks)],width,depth,-width*128,-depth*128,
              128,-256,-1664 if road else -128,gx,gz,nx,nz,sx,sz,admission.exe_tables.LEVEL_CODES.index('ORG1'),256,total]
    for count,avg,first in stacks:
        values += [count,avg]
        for i in range(count):
            flags,poly = struct.unpack_from('<2I',data,grid+12+width*depth*4+(first+i)*8)
            values.append(flags)
            for vertex in struct.unpack_from('<4H',data,poly):
                values += struct.unpack_from('<3h',data,vertices+8+vertex*8)
    raw = admission.platform.resource(c['files'],c['entries'],c['mwd'],214)
    xar = hilite.animation.parse_xar(raw)
    values += [a['frames'] for a in hilite.discrete_actions(xar,16)]
    general = read(data,76,'<I')
    values += struct.unpack_from('<3h',data,general+24)
    values += struct.unpack_from('<3h',data,general+32)
    ids = {r['script_id'] for r in geometry['neighbors'] if r['script_id']}
    ids.add(c['script_names'].index('SCRIPT_TURTLE_NO_DIVE'))
    for script_id in list(ids):
        for op,args in admission.commands(c['scripts'][script_id]):
            if op == 'SCRIPT_IF': ids.add(args[2])
    values.append(len(ids))
    for script_id in sorted(ids):
        words = c['scripts'][script_id]['stream']
        values += [script_id,len(words),*words]
    definitions = neighbor.decode_paths(data)
    values.append(len(definitions))
    for path in definitions:
        values.append(len(path))
        for seg in path:
            values += [seg['segment_type'],seg['length']]
            values += (seg['matrix']+seg['smooth_t']+seg['smooth_c'] if seg['segment_type']==0 else seg['start']+seg['end'])
    forms = admission.contacts.parse_forms(data)
    model_cache = {}
    for r in geometry['neighbors']:
        index = r['entity_index']; at = r['source_offset']; fid = r['form_grid_id']; form = forms[fid]
        effective = c['script_names'].index(r['turtle']['effective_script']) if 'turtle' in r else r['script_id']
        values += [index,r['unique_id'],r['flags'],r['form_id'],c['entity_names'].index(r['entity_type']),r['script_id'],effective,
                   int(index in geometry['included_FORM_indices']),r['book_flags'],r['radius_squared']]
        if form[2]:
            values += [*form[4:8],form[8][0][2],geometry['form_grids'][fid]['final_max_y'],*form[8][0][5]]
        else: values += [0,0,0,0,0,0]
        if 'path' in r:
            p = r['path']; t = r.get('turtle',{})
            values += [p['index'],p['initial_segment'],p['initial_distance'],p['speed'],t.get('dive_delay',0),t.get('rise_delay',0),t.get('type',0)]
        else:
            matrix = struct.unpack_from('<10h3i',data,at+24)
            values += [-1,*matrix[:9],*matrix[10:]]
            values += (list(struct.unpack_from('<2i',data,at+56)) if r['entity_type']=='STATIC_NOISE'
                       else list(struct.unpack_from('<2h',data,at+56)) if index==53 else [0,0])
        model_id=r['model_resource_id'];model = neighbor.model_facts(c,model_id,model_cache)['_model']
        if model['incomplete']:
            model_id=model_cache[model_id]['counterpart_resource_id'];model=model_cache[model_id]['_model']
        parts = model['statics'][0]['parts']
        actions = parts[0]['flipbook_actions'] if not model['incomplete'] else 0
        values.append(actions)
        if actions:
            raw = admission.platform.resource(c['files'],c['entries'],c['mwd'],model_id)
            values += [read(raw,parts[0]['flipbook_ptr']+4+j*4,'<H') for j in range(actions)]
    if road:
        import org1_traffic
        values += org1_traffic.transport_footer(c,geometry)
    if visibility:
        from org1_visibility import groups_from_map
        values += groups_from_map(data)['counts'];geometry['visibility']=True
    return ' '.join(map(str,values))+'\n',geometry,c


def run(args):
    output=args.output_directory.resolve()
    project=Path(__file__).resolve().parent.parent
    if any(output.is_relative_to(p.resolve()) for p in (project,project.parent/'froggy')):
        raise ValueError('route evidence must be outside both repositories')
    output.mkdir(parents=True,exist_ok=True)
    if args.road and args.visibility:raise ValueError('road visibility is not admitted')
    commands={int(t):int(d) for t,d in (item.split(':') for item in args.commands.split(','))}
    fixture,geometry,context=transport(args.data_dir,args.ticks,commands,args.road,args.visibility)
    source=output/'org1-route-input.txt';source.write_text(fixture,encoding='ascii')
    result=subprocess.run([str(args.oracle.resolve()),str(args.acos_table.resolve()),'--org1-visibility' if args.visibility else '--org1-road' if args.road else '--org1-route',str(source)],
        capture_output=True,text=True,timeout=30,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
    (output/'org1-route.csv').write_text(result.stdout,encoding='utf-8')
    (output/'org1-route-stderr.txt').write_text(result.stderr,encoding='utf-8')
    if result.returncode: raise ValueError(f'C route process exited {result.returncode}: {result.stderr[-500:]}')
    lines=result.stdout.splitlines();at=next(i for i,line in enumerate(lines) if line.startswith('tick,phase,'))
    rows=list(csv.DictReader(io.StringIO('\n'.join(lines[at:]))))
    from org1_route_verification import verify
    side=list(csv.DictReader(Path(str(source)+'.entities.csv').open()))
    phases,entities=verify(context,geometry,args.ticks,commands,rows,side,args.expected_death_tick)
    outputs={}
    if args.golden_name:
        schedules={'org1_visibility_round_trip':(730,{0:0,12:0,34:2,46:2},None),
                   'org1_visibility_diver':(203,{170:0},202),
                   'org1_round_trip':(730,{0:0,12:0,34:2,46:2},None),
                   'org1_attached_diver':(1255,{1230:0},1254),
                   'org1_road_river':(180,{t:0 for t in (0,12,24,36,102,114,126,138)},None),
                   'org1_road_vehicle_death':(60,{t:0 for t in (0,12,24,36,48)},50)}
        if args.golden_name not in schedules:raise ValueError('unknown ORG1 golden family')
        if args.visibility!=args.golden_name.startswith('org1_visibility_'):raise ValueError('golden visibility mode differs from route')
        if args.road!=args.golden_name.startswith('org1_road_'):raise ValueError('golden mode differs from route')
        expected=schedules[args.golden_name]
        if (args.ticks,commands,args.expected_death_tick)!=expected:raise ValueError('golden schedule differs from frozen route')
        phase_text,entity_text,fields=golden_text(phases,entities)
        directory=project/'tests/golden/pc-retail-v3.0e'
        outputs={directory/(args.golden_name+'.tsv'):phase_text,directory/(args.golden_name+'_entities.tsv'):entity_text,
                 directory/'org1_entity_update_fields.json':json.dumps(fields,indent=2)+'\n'}
    if args.admission:
        if args.road:
            if args.golden_name!='org1_road_river':raise ValueError('road admission requires successful crossing')
            import org1_traffic
            proof=org1_traffic.admission_manifest(context,geometry,args.oracle.resolve(),args.acos_table.resolve(),output)
            roots={tuple(r) for r in proof['frog_roots']}
            for row in rows:
                if int(row['mode'])!=2 and not int(row['flags'])&8 and tuple(int(row[f'm{r}{c}']) for r in range(3) for c in range(3)) not in roots:
                    raise ValueError('road frog root escaped the independently closed pose set')
            (output/'org1-road-admission-proof.json').write_text(json.dumps(dict(admission=proof,neighbors=geometry),indent=2)+'\n',encoding='ascii')
            path=project/'src/presentation/setup/org1_road_river_admission.json';content=json.dumps(proof,indent=2)+'\n'
            outputs[path]=content
        elif args.golden_name!=('org1_visibility_round_trip' if args.visibility else 'org1_round_trip'):raise ValueError('admission requires the complete frozen round trip')
    if args.admission and not args.road:
        probes=hilite.check_reachable_probes(context,geometry,args.oracle.resolve(),args.acos_table.resolve(),output)
        roots={tuple(r) for r in probes['roots']}
        for row in rows:
            if int(row['mode'])!=2 and tuple(int(row[f'm{r}{c}']) for r in range(3) for c in range(3)) not in roots:
                raise ValueError('integrated frog root escaped the independently closed pose set')
        proof=admission_manifest(context,geometry,probes)
        if args.visibility:
            proof['schema']='org1-visibility-admission-v1';proof['lifetime']='visibility'
            proof['conditions']=[v for v in proof['conditions'] if not v.startswith(('All 64','Checkpoint croak'))]
            proof['conditions'] += ['All 64 authored identities retain paths and source-ordered applicable live updates, including immortal initialization.',
                'Dynamic baby sphere and tongue exclusion requires XZ distance greater than 640 from every integer point in the corridor at each entity phase; otherwise reject the entire tick.',
                'Selected groups contain fewer than 2500 polygons; visibility failure rejects atomically.']
            proof['attached_diver']=dict(commands=[[170,1]],observation_ticks=203,death_tick=202)
            for r in proof['contact_exclusions']:
                if r['index']==53:r['reason']='excluded_by_dynamic_collection_radius_guard'
            if any(max(-512-int(r['x']),0,int(r['x'])-511)**2+max(-128-int(r['z']),0,int(r['z'])-479)**2<=640**2 for r in entities if r['index']==53):raise ValueError('baby exclusion failed')
        path=project/'src/presentation/setup'/('org1_visibility_admission.json' if args.visibility else 'org1_exploration_admission.json');content=json.dumps(proof,indent=2)+'\n'
        outputs[path]=content
    if args.visibility:
        frozen=list(csv.DictReader(open(str(source)+'.lifecycle.csv')))
        expected=geometry['lifecycle_facts']
        if len(frozen)!=len(expected):raise ValueError('incomplete lifecycle trace')
        for a,b in zip(expected,frozen):
            for k in ('tick','polygons','baby_mode','baby_search','baby_parent'):
                if str(a[k])!=b[k]:raise ValueError(f"Lifecycle {a['tick']} {k}: {a[k]} != {b[k]}")
            for k in ('groups','order'):
                if ';'.join(map(str,a[k]))!=b[k]:raise ValueError(f"Lifecycle {a['tick']} {k} differs")
            for i in range(64):
                if not a['entities'][i][0]:continue
                if ':'.join(map(str,a['entities'][i]))!=b['entity'+str(i)]:raise ValueError(f"Lifecycle {a['tick']} entity {i} differs: {a['entities'][i]} {b['entity'+str(i)]}")
        content=json.dumps(expected,separators=(',',':'))+'\n'
        (output/'lifecycle-expected.json').write_text(content)
        if args.golden_name:
            path=project/'tests/golden/pc-retail-v3.0e'/f'{args.golden_name}_lifecycle.json'
            outputs[path]=content
    for path,content in outputs.items():
        if args.write_goldens:path.write_text(content,encoding='ascii')
        elif not path.exists() or path.read_text(encoding='ascii')!=content:raise ValueError(f'golden mismatch: {path.name}')
    changes=[];previous=None
    for row in rows:
        if row['phase']!='pose':continue
        state=(row['attached'],row['mode'])
        if state!=previous:
            changes.append({k:row[k] for k in ('tick','attached','mode','diver_y')} |
                           {'world':[int(row[k])>>16 for k in ('x16','y16','z16')]})
        previous=state
    print(json.dumps(dict(route_admitted=bool(args.admission),independent_agreement=True,rows=len(rows),entity_rows=len(side),transitions=changes),indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('data-dir','oracle','acos-table','output-directory'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--ticks',type=int,default=120)
    parser.add_argument('--commands',default='0:0,12:0,34:2,46:2')
    parser.add_argument('--expected-death-tick',type=int)
    parser.add_argument('--golden-name')
    parser.add_argument('--write-goldens',action='store_true')
    parser.add_argument('--admission',action='store_true')
    parser.add_argument('--road',action='store_true')
    parser.add_argument('--visibility',action='store_true')
    run(parser.parse_args())

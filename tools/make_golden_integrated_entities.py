#!/usr/bin/env python3
"""Independently compose frozen path, frog, camera and animation POP rules."""
import argparse
import csv
import io
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from make_golden_frog_animation import State, catalog
from make_golden_integrated_terrain import scenarios as terrain_scenarios
from make_golden_paths import python_trace

FIELDS = ('scenario tick phase x16 y16 z16 vx16 vy16 vz16 grid_x grid_z count flags mode input direction '
          'no_input_timer death_count camera_mode camera_move_timer camera_twist camera_x camera_y camera_z '
          'source_x source_y source_z controller_up shake_timer animation_type script_timer animation_flags '
          'env_flags rng_seed if_counter program offset action cel total update_count game_mode '
          'e0x e0y e0z e0segment e0total e0flags e1x e1y e1z e1segment e1total e1flags '
          'contact_order hit_indices killer pgen_requests sound_requests').split()


def signed(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def cdiv(value, denominator):
    return abs(value) // denominator * (-1 if value < 0 else 1)


def contact_scan(collision, poses, frog):
    """Compute C group linkage and primitive-free FORM results from authored facts."""
    base, size, dims = (collision[key] for key in ('group_base','group_size','group_dimensions'))
    group = lambda xyz: (max(0,min(dims[0]-1,cdiv(signed(xyz[0]-base[0],32),size[0]))),
                         max(0,min(dims[1]-1,cdiv(signed(xyz[2]-base[2],32),size[1]))))
    fgx = cdiv(signed(frog[0]-base[0],32),size[0])
    fgz = cdiv(signed(frog[2]-base[2],32),size[1])
    ordered = []
    entities = collision['entities']
    for z in range(max(0,fgz-1),min(dims[1]-1,fgz+1)+1):
        for x in range(max(0,fgx-1),min(dims[0]-1,fgx+1)+1):
            for kind in ('MOVING','STATIC'):
                for index in range(len(entities)-1,-1,-1):
                    entity = entities[index]
                    if entity['entity_name'] != kind or kind == 'MOVING' and entity['flags'] & 1:
                        continue
                    if group(poses[index][9:12]) == (x,z):
                        ordered.append(index)
    hits = []
    for index in ordered:
        entity,contact = entities[index],collision['contacts'][index]
        if entity['flags'] & 8:
            continue
        matrix = poses[index]
        delta = [signed(frog[axis]-matrix[9+axis],16) for axis in range(3)]
        radius = signed(sum(value*value for value in delta),32)
        if radius >= contact['radius_squared']:
            continue
        local = [signed(sum(matrix[row*3+col]*delta[row] for row in range(3)),32)>>12
                 for col in range(3)]
        ox,oz = contact['offsets'];nx,nz = contact['dimensions']
        if not (ox < local[0] < ox+(nx<<8) and oz < local[2] < oz+(nz<<8)
                and contact['height'] <= local[1] <= contact['max_y']):
            continue
        cell_x=(local[0]-ox)>>8;cell_z=(local[2]-oz)>>8
        flags=contact['grid_flags'][cell_z*nx+cell_x]
        if not flags & 1 or flags & (64|2):
            continue
        if flags & (4096|4) and not (flags & 4 and not flags & 4096 and contact['death_type'] != 5):
            hits.append(index)
        elif flags & 16 or not flags & (4|32):
            hits.append(index)
    return ordered,hits


def entity_case(scenario):
    def static(index, z=-128):
        return dict(entity_index=index, unique_id=40+index, form_grid_id=index, form_id=index,
                    form_name='SYNTHETIC_POP', entity_name='STATIC', flags=0,
                    matrix12=[4096,0,0,0,4096,0,0,0,4096,-128,0,z])
    if scenario == 0:
        entities = [static(0,-86)]
    elif scenario == 1:
        moving = static(0)
        moving.pop('matrix12')
        moving.update(entity_name='MOVING', flags=16,
            path_definition=dict(path_index=0,segments=[dict(segment_type=2,length=20,
                start=[-138,0,-128],end=[-118,0,-128])]),
            path_start=dict(segment_index=0,distance=0,speed=10,flags=8))
        entities = [moving]
    else:
        entities = [static(0),static(1)]
    contacts = []
    for entity in entities:
        contacts.append(dict(entity_index=entity['entity_index'],unique_id=entity['unique_id'],
            form_grid_id=entity['form_grid_id'],form_id=entity['form_id'],form_name=entity['form_name'],
            entity_flags=entity['flags'],height=-1000,max_y=1000,radius_squared=25 if scenario==1 else 1000000,
            death_type=5,dimensions=[1,1],offsets=[-128,-128],grid_flags=[4097]))
    return dict(group_base=[-512,0,-512],group_dimensions=[3,3],group_size=[768,768],
                entities=entities,contacts=contacts)


def authored_cases():
    base = terrain_scenarios()['integrated-0.json']
    result = []
    for scenario in range(3):
        item = json.loads(json.dumps(base))
        item['tick_limit'] = 80
        item['level']['theme'] = 9
        item['level']['theme_name'] = 'SUB'
        item['level']['entity_collision'] = entity_case(scenario)
        item['commands'] = [dict(tick=0,pressed=1,held=1)] if scenario==0 else []
        result.append(item)
    return dict(cases=result)


def expected():
    rows = []
    path = python_trace(dict(segments=[dict(segment_type=2,length=20,start=[-138,0,-128],end=[-118,0,-128])],
                             start=dict(segment_index=0,distance=0,speed=10,flags=9),tick_limit=80))
    for scenario in range(3):
        collision = entity_case(scenario)
        anim = State(catalog())
        pos = [-128<<16,0,-128<<16]
        vel = [0,0,0]
        grid = [1,1]
        count = 0
        flags = 2049
        mode = 0
        input_key = 0
        direction = 0
        no_input = 0
        death = 0
        camera_mode = camera_timer = 0
        game_mode = 10
        killer = -1
        pgens = sounds = 0
        camera_tracked = [-128,0,-128]
        camera_source = [camera_tracked[0],camera_tracked[1]-500,camera_tracked[2]-500]
        for tick in range(80):
            if scenario == 1:
                cursor = path[tick+1]
                entity0 = [*cursor[9:12],cursor[3],cursor[6],cursor[8]]
            else:
                entity0 = [-128,0,-86 if scenario==0 else -128,-1,-1,0]
            entity1 = [-128,0,-128,-1,-1,0] if scenario==2 else [-1,-1,-1,-1,-1,0]
            poses = []
            for entity_index,entity in enumerate(collision['entities']):
                if entity['entity_name'] == 'STATIC':
                    poses.append(entity['matrix12'])
                else:
                    pose = entity0 if entity_index==0 else entity1
                    poses.append([4096,0,0,0,4096,0,0,0,4096,*pose[:3]])
            hits = '-'

            def emit(phase):
                world = [value>>16 for value in pos]
                order,_ = contact_scan(collision,poses,world)
                rows.append([scenario,tick,phase,*pos,*vel,*grid,count,flags,mode,input_key,direction,
                    no_input,death,camera_mode,camera_timer,0,*camera_tracked,*camera_source,0,0,
                    anim.type,anim.timer,anim.flags,anim.env_flags,anim.seed,anim.if_counter,
                    anim.program,anim.offset,anim.action,anim.cel,anim.total,anim.update_count,game_mode,
                    *entity0,*entity1,';'.join(str(i) for i in order) if order else '-',hits,killer,pgens,sounds])

            if flags & 8:
                flags &= ~8
                if mode != 1 or not flags & 64:
                    count = 0
                mode = 2
                death = 70
                camera_timer = 45
            if flags & 2048 and mode == 0:
                no_input += 1
                input_key = 128
                if scenario == 0 and tick == 0:
                    input_key = 0
                    no_input = 0
                    mode = 1
                    grid = [1,2]
                    count = 6
                    flags |= 64
                    vel = [0,-3670016,2796202]
                    anim.request(16)
                    sounds += 1
            emit('control')
            if mode == 1:
                count -= 1
                vel[1] += 1048576
                pos = [a+b for a,b in zip(pos,vel)]
                grid = [(pos[0]>>16)+512>>8,(pos[2]>>16)+512>>8]
            elif mode == 2:
                death -= 1
                if death == 0:
                    game_mode = 3
                if count:
                    count -= 1
                    if count:
                        vel[1] += 1048576
                        pos = [a+b for a,b in zip(pos,vel)]
                        grid = [(pos[0]>>16)+512>>8,(pos[2]>>16)+512>>8]
                    else:
                        pos = [-128<<16,0,128<<16]
                        vel = [0,0,0]
                        grid = [1,2]
                        flags &= ~(2|4|16|32|64|128|256|65536|16384)
                        anim.request(14)
                else:
                    pos = [a+b for a,b in zip(pos,vel)]
            emit('move')
            world = [value>>16 for value in pos]
            _,accepted_hits = contact_scan(collision,poses,world) if mode != 2 and not flags & 8 else ([],[])
            if accepted_hits:
                flags = (flags & ~2048) | 8
                if scenario != 0:
                    vel = [0,0,0]
                anim.request(23)
                camera_mode = 4
                killer = accepted_hits[0]
                pgens = 1
                hits = ';'.join(str(i) for i in accepted_hits)
            emit('collision')
            emit('camera')
            anim.no_input_timer = no_input
            anim.scripts()
            no_input = anim.no_input_timer
            emit('scripts')
            anim.pose()
            emit('pose')
            if game_mode != 10:
                break
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--c-oracle', required=True)
    parser.add_argument('--output', type=Path, default=Path('tests/golden/synthetic/integrated_entities.tsv'))
    parser.add_argument('--fixture', type=Path, default=Path('tests/golden/fixtures/integrated_entities.json'))
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    process = subprocess.run([args.c_oracle],capture_output=True,text=True,check=True,
                             creationflags=0x08000000 if os.name=='nt' else 0)
    actual = list(csv.reader(io.StringIO(process.stdout[process.stdout.index('scenario,tick,phase,'):])))
    if actual.pop(0) != FIELDS:
        raise ValueError('Integrated entity C schema differs')
    wanted = expected()
    if len(actual) != len(wanted):
        raise ValueError(f'row count C={len(actual)} Python={len(wanted)}')
    for number,(got,row) in enumerate(zip(actual,wanted),2):
        for field,c_value,python_value in zip(FIELDS,got,row):
            if c_value != str(python_value):
                raise ValueError(f'row {number} {field}: C={c_value} Python={python_value}; {row[:3]}')
    output = io.StringIO(newline='')
    writer = csv.writer(output,delimiter='\t',lineterminator='\n')
    writer.writerow(FIELDS)
    writer.writerows(wanted)
    fixture = json.dumps(authored_cases(),indent=2)+'\n'
    if args.verify:
        if args.output.read_text() != output.getvalue() or args.fixture.read_text() != fixture:
            raise ValueError('Integrated entity golden or fixture differs')
    else:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(output.getvalue())
        args.fixture.parent.mkdir(parents=True,exist_ok=True)
        args.fixture.write_text(fixture)


if __name__ == '__main__':
    main()

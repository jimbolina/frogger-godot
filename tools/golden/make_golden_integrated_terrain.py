#!/usr/bin/env python3
"""Independent composition of frozen terrain, camera and animation rules."""
import argparse
import csv
import io
import json
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden.make_golden_terrain_collision import expected as terrain_expected, FIELDS as TERRAIN_FIELDS
from tools.golden import make_golden_terrain_collision as terrain_rules
from tools.golden.make_golden_frog_animation import State, catalog
from tools.golden.make_golden_camera import cdiv, damp, trig

FIELDS = 'scenario,tick,phase,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,input,direction,no_input_timer,death_count,camera_mode,camera_move_timer,camera_twist,camera_x,camera_y,camera_z,source_x,source_y,source_z,controller_up,shake_timer,animation_type,script_timer,animation_flags,env_flags,rng_seed,if_counter,program,offset,action,cel,total,update_count,game_mode'.split(',')


def scenarios():
    """Authored adapter stimuli, also usable by both actual game frontends."""
    products = {}
    for scenario in range(4):
        squares = []
        for index in range(16):
            x,z = -512+(index%4)*256,-512+(index//4)*256
            y = 513 if scenario==2 and index==9 else 0
            squares.append(dict(flags=9 if scenario==3 and index==9 else 3,
                vertices=[[x,y,z+256],[x+256,y,z+256],[x,y,z],[x+256,y,z]]))
        commands = [dict(tick=0,pressed=3 if scenario==0 else 32 if scenario==1 else 1,
            held=32 if scenario==1 else 1)]
        if scenario==1:
            commands += [dict(tick=tick,pressed=0,held=1) for tick in range(1,13)]
        products['integrated-%s.json' % scenario] = dict(builtin='normal',tick_limit=24 if scenario<2 else 120 if scenario==2 else 80,
            grid=dict(dimensions=[4,4],base=[-512,-512],stacks=[[i,1] for i in range(16)],squares=squares),
            level=dict(spawn_cell=[1,1],spawn_direction=0,collision_enabled=True,collision_bounds=[-32767,-32767,65534,65534],
                theme=4 if scenario==2 else 9,theme_name='JUN' if scenario==2 else 'SUB',theme_death_height=30000,
                camera=dict(source_offset=[0,-500,-500],target_offset=[0,0,0]),frog_action_lengths=[3+i%3 for i in range(34)]),
            start=dict(seed=1,camera_startup=False,start_timer=0),commands=commands)
    return products


def expected():
    saved_height = terrain_rules.HEIGHTS[0]
    terrain_rules.HEIGHTS[0] = 0
    try:
        terrain = {(r[0], r[1], r[2]): dict(zip(TERRAIN_FIELDS, r)) for r in terrain_expected(120)}
    finally:
        terrain_rules.HEIGHTS[0] = saved_height
    rows = []
    for scenario in range(4):
        animation = State(catalog(), scenario == 2)
        current = [-128, 0, -128]
        source = [-128, -500, -628]
        offsets = [0, -500, -500]
        camera_mode = camera_timer = twist = angle = controller = shake_timer = 0
        no_input = last_requests = 0
        amp_x = amp_y = freq_x = freq_y = 0
        waiting = 0
        for tick in range(24 if scenario < 2 else 120 if scenario == 2 else 80):
            for phase in ('control', 'move', 'collision', 'camera', 'scripts', 'pose'):
                if phase in ('control', 'move', 'collision'):
                    if scenario == 1:
                        movement = dict(x16=-128<<16, y16=0, z16=-128<<16, vx16=0, vy16=0, vz16=0,
                            grid_x=1, grid_z=1, count=0, flags=2049, mode=waiting, input=0 if tick<=8 else 128,
                            direction=0, death_count=0, game_mode=10, animation_requests=0, old_y=0, target_y=0)
                        if tick == 0 and phase == 'control':
                            waiting = movement['mode'] = 3
                            no_input += 1
                            camera_timer = 8
                            twist = 1
                        elif phase == 'control' and waiting == 0:
                            no_input += 1
                        if phase == 'move' and not camera_timer and not twist:
                            waiting = movement['mode'] = 0
                    else:
                        source_scenario = {0: 0, 2: 1, 3: 8}[scenario]
                        old_mode = movement['mode'] if tick or phase != 'control' else 0
                        movement = terrain[source_scenario, tick, phase].copy()
                        if phase == 'control' and movement['mode'] == 2 and old_mode != 2:
                            camera_timer = 45
                        if phase == 'control' and movement['mode'] == 0 and movement['flags'] & 2048:
                            no_input += 1
                        requests = movement['animation_requests']
                        if requests != last_requests:
                            if phase == 'control':
                                animation.request(16)
                                no_input = 0
                            elif movement['flags'] & 8:
                                animation.request(8)
                                camera_mode = 4
                            elif movement['mode'] == 6:
                                animation.request(26)
                                if not shake_timer:
                                    animation.seed = (animation.seed * 0x41c64e6d + 0x3039) & 0xffffffff
                                    first = (animation.seed >> 16) & 32767
                                    animation.seed = (animation.seed * 0x41c64e6d + 0x3039) & 0xffffffff
                                    second = (animation.seed >> 16) & 32767
                                    theta = (first & 511) - 256
                                    amp_x = (trig(theta) * 128) >> 8
                                    amp_y = (trig(theta, True) * 128) >> 8
                                    freq_x = 20480
                                    freq_y = freq_x + second % (freq_x >> 3)
                                    shake_timer = 45
                            elif movement['mode'] == 1 and movement['flags'] & 128:
                                animation.request(6)
                            else:
                                animation.request(14)
                            last_requests = requests
                elif phase == 'camera':
                    if camera_mode == 0:
                        if camera_timer:
                            camera_timer -= 1
                        if twist:
                            angle = cdiv(twist * 1024, 8)
                            twist += 1
                            if twist > 8:
                                twist = 0
                        origin = [movement[k] >> 16 for k in ('x16', 'y16', 'z16')]
                        dest_y = origin[1]
                        if movement['mode'] == 1 and not movement['flags'] & 128:
                            dest_y = movement['old_y'] + cdiv((6-movement['count'])*(movement['target_y']-movement['old_y']), 6)
                        current = [damp(current[0], origin[0]), damp(current[1], min(dest_y, 0), True), damp(current[2], origin[2])]
                        cos, sin = trig(angle, True), trig(angle)
                        rotated = [(cos*offsets[0]+sin*offsets[2]) >> 12, offsets[1], (-sin*offsets[0]+cos*offsets[2]) >> 12]
                        source = [a+b for a,b in zip(current, rotated)]
                        dx, dz = -rotated[0], -rotated[2]
                        controller = (0 if dz>0 else 2) if abs(dz)>abs(dx) else (1 if dx>0 else 3)
                    if shake_timer:
                        elapsed = 45-shake_timer
                        sx = cdiv(trig(cdiv(elapsed*freq_x,45))*amp_x*shake_timer,45) >> 16
                        sy = cdiv(trig(cdiv(elapsed*freq_y,45))*amp_y*shake_timer,45) >> 16
                        source = [source[0]+sx,source[1]+((2896*sy)>>12),source[2]+((-2896*sy)>>12)]
                        shake_timer -= 1
                elif phase == 'scripts':
                    animation.no_input_timer = no_input
                    animation.scripts()
                    no_input = animation.no_input_timer
                else:
                    animation.pose()
                rows.append([scenario,tick,phase]+[movement[k] for k in ('x16','y16','z16','vx16','vy16','vz16','grid_x','grid_z','count','flags','mode','input','direction')]+
                    [no_input,movement['death_count'],camera_mode,camera_timer,twist]+current+source+
                    [controller,shake_timer,animation.type,animation.timer,animation.flags,animation.env_flags,animation.seed,animation.if_counter,
                    animation.program,animation.offset,animation.action,animation.cel,animation.total,animation.update_count,movement['game_mode']])
            if movement['game_mode'] != 10:
                break
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--c-oracle', required=True)
    parser.add_argument('--output', default='tests/golden/synthetic/integrated_terrain.csv')
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--scenario-dir', type=Path, help='Write independent authored setup/command JSON for headless/rendered consumers')
    args = parser.parse_args()
    result = subprocess.run([args.c_oracle],capture_output=True,text=True,check=True,creationflags=0x08000000 if os.name=='nt' else 0)
    actual = list(csv.reader(io.StringIO(result.stdout[result.stdout.index('scenario,tick,phase,'):])))
    if actual.pop(0) != FIELDS:
        raise ValueError('Integrated C schema differs')
    want = expected()
    if len(actual) != len(want):
        raise ValueError('Integrated row counts differ C=%s Python=%s' % (len(actual),len(want)))
    for number,(got,row) in enumerate(zip(actual,want),2):
        if len(got) != len(FIELDS):
            raise ValueError('Integrated C field count differs at row %s' % number)
        for key,a,b in zip(FIELDS,got,row):
            if a != str(b):
                raise ValueError('Integrated row %s %s Python=%s C=%s context=%s' % (number,key,b,a,row[:3]))
    output = io.StringIO(newline='')
    writer = csv.writer(output,lineterminator='\n');writer.writerow(FIELDS);writer.writerows(want)
    path = Path(args.output)
    if args.verify:
        if path.read_text() != output.getvalue(): raise ValueError('Integrated golden differs')
    else:
        path.parent.mkdir(parents=True,exist_ok=True);path.write_text(output.getvalue())
    if args.scenario_dir:
        args.scenario_dir.mkdir(parents=True,exist_ok=True)
        for name,scenario in scenarios().items():
            (args.scenario_dir/name).write_text(json.dumps(scenario,indent=2)+'\n')
    print('Independent Python/C integrated records match: %s rows, %s fields.' % (len(want),len(FIELDS)))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Independent ZONE.C/FROG.C/CAMERA.C model, checked against unchanged frozen objects."""
import argparse
import copy
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
sys.dont_write_bytecode = True
from make_golden_camera import cdiv, damp, trig
from make_golden_paths import normalised

SCALARS = ['frog_zone', 'frog_region', 'zone_index', 'mode', 'move_timer',
           'twist_counter', 'twist_quadrants', 'entity_angle']
VECTORS = ['tracked_world', 'source_offset', 'target_offset', 'next_source_offset',
           'next_target_offset', 'source_world', 'axis_x_12', 'axis_y_12', 'axis_z_12',
           'controller_directions', 'mod_rotation']
IDENTITY = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096]


def yaw(a):
    c, s = trig(a, True), trig(a)
    return [c, 0, s, 0, 4096, 0, -s, 0, c]


def apply(m, v):
    return [sum(m[r*3+i]*v[i] for i in range(3)) >> 12 for r in range(3)]


def multiply(a, b):
    return [sum(a[r*3+k]*b[k*3+c] for k in range(3)) >> 12
            for r in range(3) for c in range(3)]


def cross(a, b):
    return [(a[1]*b[2]-a[2]*b[1]) >> 12, (a[2]*b[0]-a[0]*b[2]) >> 12,
            (a[0]*b[1]-a[1]*b[0]) >> 12]


def quadrant(m):
    return (0 if m[8] > 0 else 2) if abs(m[8]) > abs(m[2]) else (1 if m[2] > 0 else 3)


def contains(bounds, cell, unsigned=False):
    b = [v & 65535 for v in bounds] if unsigned else bounds
    return b[0] <= cell[0] <= b[2] and b[1] <= cell[1] <= b[3]


def in_zone(z, cell):
    if not contains(z['bounds'], cell, True): return -2
    if not z['regions']: return -1
    return next((i for i, b in enumerate(z['regions']) if contains(b, cell)), -2)


def select(zones, cell, current, frozen=False):
    if frozen: return current
    zi, ri = current
    if zi >= 0:
        z = zones[zi]
        if contains(z['regions'][ri] if ri >= 0 else z['bounds'], cell): return current
        ri = in_zone(z, cell)
        if ri != -2: return [zi, ri]
    for i, z in enumerate(zones):
        ri = in_zone(z, cell)
        if ri != -2: return [i, ri]
    return [-1, -1]


def zone(bounds=(1, 1, 3, 3), direction=-1, flags=0, regions=()):
    return dict(bounds=list(bounds), regions=list(regions), direction=direction, flags=flags,
                offsets=[[10*i, -800-20*i, -700-30*i] if i % 2 == 0 else
                         [5*i, -100-10*i, 20*i] for i in range(8)])


def frame(cell, world=None, **kw):
    return dict(cell=list(cell), world=world or [cell[0]*256, -100, cell[1]*256],
                freeze=kw.get('freeze', 0), turn=kw.get('turn', 0), fixed=kw.get('fixed', 0),
                start_timer=kw.get('start_timer', 0))


def held(cells, ticks=40):
    return [frame(c) for c in cells for _ in range(ticks)]


def cases():
    result = []
    def add(name, zones, frames, startup=False, angle=0):
        result.append(dict(name=name, zones=zones, frames=frames, startup=startup, yaw=angle,
                           source=[0, -500, -500], target=[0, 0, 0]))
    add('entry-region-overlap-exit', [zone((2, 1, 4, 3)), zone((1, 1, 4, 3),
        regions=[[1, 1, 2, 2], [3, 2, 4, 3]])], held([(1, 1), (2, 1), (3, 2), (4, 1), (0, 0)]))
    add('absolute-transfer', [zone((1, 1, 1, 1), flags=8), zone((2, 1, 2, 1), flags=8),
        zone((3, 1, 3, 1))], held([(0, 0), (1, 1), (2, 1), (3, 1), (1, 1), (0, 0)], 17))
    for d in range(4):
        add('forced-'+str(d), [zone(direction=d)], held([(1, 1), (0, 0)]))
    add('startup-north-offset', [zone(direction=2, flags=8)],
        [frame((1, 1), start_timer=max(0, 40-t)) for t in range(90)], startup=True)
    add('frozen-selection-fixed-camera', [zone()],
        held([(1, 1)], 40)+[frame((0, 0), freeze=1) for _ in range(12)]+
        [frame((0, 0), fixed=1) for _ in range(12)])
    add('signed-and-inverted', [zone((-1, -1, -1, -1)), zone((4, 4, 2, 2)),
        zone((0, 0, 5, 5), regions=[[1, 1, 1, 1], [4, 4, 4, 4]])],
        held([(65535, 65535), (-1, -1), (1, 1), (2, 2), (4, 4)], 2))
    for name, flags, direction in [('manual', 0, -1), ('semiforced', 4, 0), ('blocked', 0, 0)]:
        frames = held([(1, 1)], 80)
        frames[35]['turn'] = 1
        frames[55]['turn'] = -1
        add(name, [zone(flags=flags, direction=direction)], frames)
    for angle in (1024, 2048, 3072):
        add('manual-from-'+str(angle), [zone()], held([(1, 1)], 35)+[frame((1, 1), turn=1)]+
            held([(1, 1)], 12), angle=angle)
    return result


def retail_cases(data_dir):
    import make_golden_retail_platform as reader
    exe = reader.exe_tables
    cfg = exe.parse_cfg(str(Path(exe.CFG_ROOT)/'versions/pc-retail-v3.0e.cfg'))
    _, entries, _, files = reader.mof.load_archive(str(data_dir),
        exe.java_int(cfg.values['mwiOffset']), exe.java_int(cfg.values['mwiLength']))
    blob = reader.resource(files, entries, (data_dir/'FROGPSX.MWD').read_bytes(), 656)
    general = struct.unpack_from('<I', blob, 76)[0]
    source = list(struct.unpack_from('<3h', blob, general+24))
    target = list(struct.unpack_from('<3h', blob, general+32))
    packet = struct.unpack_from('<I', blob, 92)[0]
    count = struct.unpack_from('<I', blob, packet+4)[0]
    if count != 18: raise ValueError('Expected 18 JUN1 zones')
    zones = []
    for i in range(count):
        at = struct.unpack_from('<I', blob, packet+8+i*4)[0]
        kind, n, *bounds, region_at = struct.unpack_from('<6HI', blob, at)
        if kind: raise ValueError('Unknown zone type')
        flags, direction = struct.unpack_from('<Hh', blob, at+16)
        zones.append(dict(bounds=[v if v < 32768 else v-65536 for v in bounds],
            regions=[list(struct.unpack_from('<4h', blob, region_at+j*8)) for j in range(n)],
            flags=flags, direction=direction,
            offsets=[list(struct.unpack_from('<3h', blob, at+20+j*8)) for j in range(8)]))
    result = []
    for name, cells, angle in [('jun1-zone15', [(10,3),(11,3),(11,4),(11,5)], 0),
                              ('jun1-zone0', [(14,22),(15,22),(14,23),(14,24)], 2048)]:
        frames = [frame(c, [(c[0]-14)*256+128, 0, (c[1]-30)*256+128]) for c in cells for _ in range(40)]
        result.append(dict(name=name, zones=zones, frames=frames, startup=False, yaw=angle,
                           source=source, target=target))
    return result


def model(case):
    zones = case['zones']; selected = [-1, -1]; consumed = -1
    mode = 3 if case['startup'] else 0; timer = 30 if case['startup'] else 0
    src = [200,-400,400] if case['startup'] else case['source'].copy()
    dst = [0,100,0] if case['startup'] else case['target'].copy()
    ns, nt = case['source'].copy(), case['target'].copy()
    current = case.get('initial', [0,0,0]).copy(); world_source = [a+b for a,b in zip(current,src)]; mod = yaw(case['yaw'])
    twist = 0; quadrants = 1; entity_angle = 0; controls = [0]*4 if case['startup'] else [0,1,2,3]
    axes = [[4096,0,0],[0,4096,0],[0,0,4096]]
    rows = []
    for f in case['frames']:
        selected = select(zones, f['cell'], selected, f['freeze'])
        active = zones[consumed] if consumed >= 0 else None
        if f['turn'] and (active is None or active['direction'] < 0 or active['flags'] & 4):
            if selected[0] >= 0:
                q = (quadrant(mod)+f['turn']) & 3
                if active is None: raise ValueError('Undefined manual payload lookup')
                ns, nt = copy.deepcopy(active['offsets'][q*2:q*2+2])
            else: ns, nt = case['source'].copy(), case['target'].copy()
            twist = f['turn']; quadrants = 1; timer = 8
        if f['fixed']: mode = 4
        before_mode = mode
        if mode == 3:
            if f['start_timer'] <= timer:
                mode = 2
                if selected[0] >= 0:
                    consumed = selected[0]; ns, nt = copy.deepcopy(zones[consumed]['offsets'][:2])
                else: ns, nt = case['source'].copy(), case['target'].copy()
        elif mode == 2:
            timer -= 1
            if timer == 0: mode = 0; current = f['world'].copy()
            else:
                src = [a+cdiv(b-a,timer) for a,b in zip(src,ns)]
                dst = [a+cdiv(b-a,timer) for a,b in zip(dst,nt)]
        elif mode == 0:
            if selected[0] != consumed:
                timer = 30
                old_absolute = active is not None and active['flags'] & 8
                if selected[0] < 0:
                    if old_absolute: current[1] = f['world'][1]; src=case['source'].copy(); dst=case['target'].copy()
                    ns, nt = case['source'].copy(), case['target'].copy()
                else:
                    if old_absolute: current[1] = 0
                    active = zones[selected[0]]
                    if active['flags'] & 8: current[1] = world_source[1]
                    q = quadrant(mod)
                    if active['direction'] >= 0:
                        diff = (active['direction']-q)&3
                        if diff: twist = -1 if diff == 3 else 1; quadrants = 2 if diff == 2 else 1
                        q = active['direction']
                    ns, nt = copy.deepcopy(active['offsets'][2*q:2*q+2])
                consumed = selected[0]
            active = zones[consumed] if consumed >= 0 else None
            if timer:
                src = [a+cdiv(b-a,timer) for a,b in zip(src,ns)]
                dst = [a+cdiv(b-a,timer) for a,b in zip(dst,nt)]; timer -= 1
            composed = mod
            if twist:
                composed = multiply(yaw(cdiv(twist*1024,8)), mod)
                direction = 1 if twist > 0 else -1; twist += direction
                if abs(twist) > 8*quadrants:
                    twist=0; mod=composed; entity_angle=(entity_angle+direction*quadrants)&3
            desired = f['world'].copy(); desired[1] = ns[1] if active and active['flags'] & 8 else (0 if case.get('grounded_hops') else min(desired[1],0))
            current = [damp(a,b,24 if i==1 else None) for i,(a,b) in enumerate(zip(current,desired))]
            world_source = [a+b for a,b in zip(current,apply(composed,src))]
            world_target = [a+b for a,b in zip(current,apply(composed,dst))]
            if active and active['flags'] & 8: world_source[1]=current[1]; world_target[1]=dst[1]
        if before_mode in (2,3):
            world_source = [a+b for a,b in zip(f['world'],src)]
            world_target = [a+b for a,b in zip(f['world'],dst)]
        if before_mode != 4:
            z = list(normalised([b-a for a,b in zip(world_source,world_target)]))
            x = list(normalised(cross([0,4096,0],z))); y = cross(z,x); axes=[x,y,z]
            if before_mode == 0:
                north = normalised([-y[0],0,-y[2]])
                d = (0 if north[2]>0 else 2) if abs(north[2])>abs(north[0]) else (1 if north[0]>0 else 3)
                controls=[(d+i)&3 for i in range(4)]
        row = dict(zip(SCALARS, [*selected,consumed,mode,timer,twist,quadrants,entity_angle]))
        row.update(zip(VECTORS, [current,src,dst,ns,nt,world_source,*axes,controls,mod]))
        rows.append(copy.deepcopy(row))
    return rows


def transport(case):
    values = [int(case['startup']),case['yaw'],len(case['zones']),len(case['frames']),*case['source'],*case['target']]
    for z in case['zones']:
        values += [*z['bounds'],len(z['regions'])]
        values += [v for r in z['regions'] for v in r]
        values += [z['flags'],z['direction'],*[v for offset in z['offsets'] for v in offset]]
    for f in case['frames']:
        values += [*f['cell'],*f['world'],f['freeze'],f['turn'],f['fixed'],f['start_timer']]
    return ' '.join(map(str,values))+'\n'


def generate(cases_to_run, executable, evidence):
    for case in cases_to_run:
        expected = model(case)
        fixture = evidence/(case['name']+'.txt'); fixture.write_text(transport(case))
        process = subprocess.run([str(executable),'--camera-zones',str(fixture)],capture_output=True,text=True,
            creationflags=0x08000000 if os.name == 'nt' else 0, timeout=60)
        (evidence/(case['name']+'.log')).write_text(process.stdout+process.stderr)
        if process.returncode: raise ValueError(f"C oracle failed {case['name']}: {process.returncode}")
        rows = [[int(v) for v in line.split(',')[1:]] for line in process.stdout.splitlines() if line.startswith('zone,')]
        if len(rows)!=len(expected): raise ValueError('C row count differs')
        for tick,(actual,want) in enumerate(zip(rows,expected)):
            flat = [want[k] for k in SCALARS]+[v for k in VECTORS for v in want[k]]
            if actual != flat:
                names = SCALARS+[k+str(i) for k in VECTORS for i in range(len(want[k]))]
                difference = [(n,a,b) for n,a,b in zip(names,actual,flat) if a!=b]
                raise ValueError(f"{case['name']} tick {tick}: (field,C,Python) {difference}")
        case['expected'] = expected
    return {'schema':'camera-zones-v1','cases':cases_to_run}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--c-oracle',type=Path,required=True)
    parser.add_argument('--evidence',type=Path,required=True)
    parser.add_argument('--data-dir',type=Path)
    parser.add_argument('--output',type=Path,default=Path('tests/golden/synthetic/camera_zones.json'))
    parser.add_argument('--verify',action='store_true')
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1]
    for protected in (repo,(repo.parent/'froggy').resolve()):
        if args.evidence.resolve()==protected or protected in args.evidence.resolve().parents:
            parser.error('Evidence must be outside both repositories')
    args.evidence.mkdir(parents=True,exist_ok=True)
    selected = retail_cases(args.data_dir) if args.data_dir else cases()
    result=generate(selected,args.c_oracle.resolve(),args.evidence.resolve())
    text=json.dumps(result,separators=(',',':')).replace('},{','},\n{')+'\n'
    if args.verify:
        if args.output.read_text()!=text: raise ValueError('Camera zone golden differs')
    else: args.output.write_text(text)
    print(f"Independent Python/frozen C camera zones: {len(selected)} cases, {sum(len(c['frames']) for c in selected)} ticks match")


if __name__ == '__main__': main()

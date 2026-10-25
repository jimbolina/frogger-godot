"""Independent frozen MAPVIEW selector and bounded lifecycle text facts.

The optional C transport calls the unchanged frozen selector. No Godot output is
used to derive expected facts. Run with --verify to compare existing fixtures.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import math
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'tests/golden/fixtures/lifecycle_visibility.json'
GOLDEN = ROOT / 'tests/golden/synthetic/lifecycle_visibility.tsv'
LINE_GOLDEN = ROOT / 'tests/golden/synthetic/lifecycle_mapview_lines.tsv'
INTEGRATED_FIXTURE = ROOT / 'tests/golden/fixtures/lifecycle_integrated.json'
INTEGRATED_GOLDEN = ROOT / 'tests/golden/synthetic/lifecycle_integrated.tsv'


def div(a: int, b: int) -> int:
    """C signed integer division, including negative coordinates."""
    return abs(a) // abs(b) * (-1 if (a < 0) != (b < 0) else 1)


def s32(value: int) -> int:
    """Frozen MR_LONG arithmetic wraps at signed 32 bits."""
    return (value + 2**31) % 2**32 - 2**31


def normal(x: int, z: int, y: int = 0) -> tuple[int, int]:
    length = math.sqrt(x*x + y*y + z*z)
    if not length:
        return 0, 0
    def lround(value: float) -> int:
        return math.floor(value + .5) if value >= 0 else math.ceil(value - .5)
    return lround(x * 4096 / length), lround(z * 4096 / length)


def draw_line(rows: list[list[int]], x0: int, z0: int, x1: int, z1: int,
              xlen: int, zlen: int) -> None:
    """The six-edge source rasterizer, including its short-edge midpoint branch."""
    minx = maxx = div(x0, xlen)
    mz, mz1 = div(z0, zlen), div(z1, zlen)
    tz = z0
    if z1 > z0:
        tz = div(tz, zlen) * zlen + zlen
    elif z1 < z0:
        tz = div(tz, zlen) * zlen
    while mz != mz1:
        if 0 <= mz < len(rows):
            if z1 > z0 and tz >= z1 or z1 < z0 and tz <= z1:
                break
            if abs(z1-z0) >= 16:
                tx = div(s32(((tz-z0) >> 2) * ((x1-x0) >> 2)), (z1-z0) >> 4) + x0
            else:
                tx = (z0 + z1) >> 1
            if x1 >= x0:
                maxx = div(tx, xlen)
                rows[mz][0] = min(minx, rows[mz][0])
                rows[mz][1] = max(maxx, rows[mz][1])
                minx = maxx
            else:
                minx = div(tx, xlen)
                rows[mz][0] = min(minx, rows[mz][0])
                rows[mz][1] = max(maxx, rows[mz][1])
                maxx = minx
        elif mz < 0 and z1 <= z0 or mz >= len(rows) and z1 >= z0:
            return
        if z1 > z0:
            mz += 1
            tz += zlen
        else:
            mz -= 1
            tz -= zlen
    if 0 <= mz < len(rows):
        if x1 >= x0:
            maxx = div(x1, xlen)
            rows[mz][0] = min(minx, rows[mz][0])
            rows[mz][1] = max(maxx, rows[mz][1])
        else:
            minx = div(x1, xlen)
            rows[mz][0] = min(minx, rows[mz][0])
            rows[mz][1] = max(maxx, rows[mz][1])


def select(geometry: dict, camera: dict) -> list[int]:
    base = geometry['base']
    xnum, znum = geometry['dimensions']
    xlen, zlen = geometry['size']
    source = camera['source']
    matrix = camera['axes']
    points = []
    last_ray_y = 0
    for px, py in ((-160,120),(-160,-120),(160,-120),(160,120)):
        view = (px, py, 256)
        vx, vy, vz = (sum(matrix[col][row] * view[col] for col in range(3)) >> 12
                      for row in range(3))
        if vy <= 0:
            last_ray_y = 0
            nx, nz = normal(vx, vz)
            points.append((source[0] + (nx << 2), source[2] + (nz << 2)))
        else:
            last_ray_y = vy
            distance = div((-source[1] << 8), vy)
            points.append((source[0] + ((distance * vx) >> 8),
                           source[2] + ((distance * vz) >> 8)))
    centre_x = sum(p[0] for p in points) >> 2
    centre_z = sum(p[1] for p in points) >> 2
    expanded = []
    for x,z in points:
        nx,nz = normal(x-centre_x,z-centre_z,-last_ray_y)
        expanded.append((x+((nx*768)>>12),z+((nz*768)>>12)))
    expanded.append((source[0],source[2]))
    rows = [[0x7fffffff,-0x7fffffff] for _ in range(znum)]
    shifted = [(x-base[0],z-base[2]) for x,z in expanded]
    for left,right in ((0,1),(1,2),(2,3),(3,4),(4,0),(3,0)):
        draw_line(rows,*shifted[left],*shifted[right],xlen,zlen)
    grid = [(div(x,xlen),div(z,zlen)) for x,z in shifted]
    groups = []
    for z in range(max(0,min(v[1] for v in grid)),min(znum-1,max(v[1] for v in grid))+1):
        for x in range(max(0,rows[z][0]),min(xnum-1,rows[z][1])+1):
            groups.append(z*xnum+x)
            if len(groups) == 128:
                return groups
    return groups


def c_select(executable: Path, geometry: dict, camera: dict) -> list[int]:
    axes = camera['axes']
    args = [*geometry['base'][::2], *geometry['dimensions'], *geometry['size'],
            *camera['source'], *(axes[col][row] for row in range(3) for col in range(3))]
    completed = subprocess.run([str(executable), *(str(x) for x in args)],
                               check=True, capture_output=True, text=True, timeout=20)
    selected = completed.stdout.splitlines()[-1].strip()
    return [int(x) for x in selected.split(',') if x]


def generate_lines(mapview_oracle: Path) -> str:
    fixture = json.loads(FIXTURE.read_text(encoding='utf-8'))
    out = io.StringIO(newline='')
    writer = csv.writer(out,delimiter='\t',lineterminator='\n')
    writer.writerow(('case','row_extents'))
    for name,case in fixture['line_cases'].items():
        xnum,znum,xlen,zlen,x0,z0,x1,z1 = case
        rows = [[0x7fffffff,-0x7fffffff] for _ in range(znum)]
        draw_line(rows,x0,z0,x1,z1,xlen,zlen)
        facts = [f'{z}:{minimum}:{maximum}' for z,(minimum,maximum) in enumerate(rows)
                 if minimum != 0x7fffffff]
        frozen = [line for line in subprocess.run(
            [str(mapview_oracle),'--line',*(str(v) for v in case)],
            check=True,capture_output=True,text=True,timeout=20).stdout.splitlines()
                  if line.count(':') == 2 and line.split(':',1)[0].isdigit()]
        if frozen != facts:
            raise ValueError(f'{name}: independent line raster {facts} != frozen {frozen}')
        writer.writerow((name,';'.join(facts) or '-'))
    return out.getvalue()


def generate_integrated(integrated_oracle: Path, mapview_oracle: Path) -> str:
    authored = json.loads(INTEGRATED_FIXTURE.read_text(encoding='utf-8'))
    geometry = authored['level']['entity_collision']
    groups = {'base': geometry['group_base'], 'dimensions': geometry['group_dimensions'],
              'size': geometry['group_size']}
    fixture_axes = json.loads(FIXTURE.read_text(encoding='utf-8'))['cameras']['A']['axes']
    run = subprocess.run([str(integrated_oracle)],check=True,capture_output=True,
                         text=True,timeout=20).stdout.splitlines()
    header = next((index for index,line in enumerate(run) if line.startswith('tick,frog_x,')),None)
    if header is None:
        raise ValueError('Frozen integrated transport emitted no table')
    frozen = list(csv.DictReader(run[header:]))
    if len(frozen) != 336:
        raise ValueError('Frozen integrated transport requires exactly 336 ticks')
    out = io.StringIO(newline='')
    writer = csv.writer(out,delimiter='\t',lineterminator='\n')
    writer.writerow(('tick','frog_x','frog_y','camera_x','camera_y','camera_z',
                     'selected_groups','polygon_total','static_live','static_pending',
                     'static_generation','moving_live','moving_pending',
                     'moving_generation','live_order','events','moving_distance'))
    x16 = -128 << 16
    y16 = 0
    target16 = x16
    velocity16 = 0
    vertical16 = 0
    remaining = 0
    camera_x = -128
    alive = {2:False,9:False}
    pending = {2:False,9:False}
    generations = {2:0,9:0}
    live_order = []
    distance = 256
    for tick,row in enumerate(frozen):
        if tick in range(16,144,8) or tick in range(176,304,8):
            if remaining:
                raise ValueError(f'Independent hop schedule overlaps at {tick}')
            direction = 1 if tick < 144 else -1
            target16 = x16 + direction * (256 << 16)
            velocity16 = div(target16-x16,6)
            vertical16 = -56 << 16
            remaining = 6
        if remaining:
            remaining -= 1
            if remaining:
                vertical16 += 16 << 16
                x16 += velocity16
                y16 += vertical16
            else:
                x16 = target16
                y16 = velocity16 = vertical16 = 0
        frog_x = x16 >> 16
        frog_y = y16 >> 16
        delta = frog_x-camera_x
        camera_x = frog_x if abs(delta)<5 else camera_x+(abs(delta)>>1)*(1 if delta>=0 else -1)
        source = [camera_x,-512,-640]
        frozen_axes = [[int(row[f'r{r}{c}']) for r in range(3)] for c in range(3)]
        frozen_fact = [int(row[key]) for key in ('frog_x','frog_y','frog_z','source_x','source_y','source_z')]
        python_fact = [frog_x,frog_y,-128,*source]
        if frozen_fact != python_fact or frozen_axes != fixture_axes:
            raise ValueError(f'tick {tick}: Python frog/camera {python_fact,fixture_axes} != frozen {frozen_fact,frozen_axes}')
        camera = {'source':source,'axes':fixture_axes}
        selected = select(groups,camera)
        if selected != (frozen_selected := c_select(mapview_oracle,groups,camera)):
            raise ValueError(f'tick {tick}: Python selector {selected} != frozen {frozen_selected}')
        distance = (distance+16)%512
        events = []
        for entity in list(live_order):
            if pending[entity]:
                alive[entity] = pending[entity] = False
                live_order.remove(entity)
                events.append(f'destroy:{entity}:{generations[entity]}')
            else:
                pending[entity] = True
        for selected_group in selected:
            for entity in (9,2):
                entity_x = -256+distance if entity==9 else 0
                gx = min(31,max(0,div(entity_x+8192,512)))
                gz = 16
                if selected_group != gz*32+gx:
                    continue
                if alive[entity]:
                    pending[entity] = False
                else:
                    alive[entity] = True
                    generations[entity] += 1
                    live_order.insert(0,entity)
                    events.append(f'create:{entity}:{generations[entity]}')
        writer.writerow((tick,frog_x,frog_y,*source,
                         ','.join(map(str,selected)) or '-',len(selected),
                         int(alive[2]),int(pending[2]),generations[2],
                         int(alive[9]),int(pending[9]),generations[9],
                         ','.join(map(str,live_order)) or '-',','.join(events) or '-',distance))
    return out.getvalue()


def generate(mapview_oracle: Path, entity_oracle: Path) -> str:
    fixture = json.loads(FIXTURE.read_text(encoding='utf-8'))
    geometry = fixture['groups']
    out = io.StringIO(newline='')
    writer = csv.writer(out, delimiter='\t', lineterminator='\n')
    writer.writerow(('case','tick','camera','selected_groups','polygon_total',
                     'entity_2_live','entity_2_pending','entity_2_generation',
                     'entity_9_live','entity_9_pending','entity_9_generation',
                     'live_order','events','moving_distance'))
    live = {2:False,9:False}
    pending = {2:False,9:False}
    generation = {2:0,9:0}
    live_order = []
    distance = 256
    frozen_rows = subprocess.run([str(entity_oracle)],check=True,capture_output=True,
                                 text=True,timeout=20).stdout.splitlines()
    frozen_header = next((index for index,line in enumerate(frozen_rows)
                          if line.startswith('tick,static_live,')),None)
    if frozen_header is None:
        raise ValueError('Frozen lifecycle transport emitted no table')
    frozen_states = list(csv.DictReader(frozen_rows[frozen_header:]))
    if len(frozen_states) != len(fixture['component_schedule']):
        raise ValueError('Frozen lifecycle transport row count differs')
    for tick,camera_name,attached in fixture['component_schedule']:
        camera = fixture['cameras'][camera_name]
        groups = select(geometry,camera)
        frozen = c_select(mapview_oracle,geometry,camera)
        if groups != frozen:
            raise ValueError(f'{camera_name}: independent selector {groups} != frozen {frozen}')
        events = []
        if tick:
            distance = (distance+16)%512
            for entity in list(live_order):
                if pending[entity] and entity != attached:
                    live[entity] = pending[entity] = False
                    live_order.remove(entity)
                    events.append(f'destroy:{entity}:{generation[entity]}')
                else:
                    pending[entity] = True
            for selected_group in groups:
                for entity in (9,2):
                    x = 0 if entity == 2 else -256+distance
                    group_x = div(x-geometry['base'][0],geometry['size'][0])
                    group_z = div(-geometry['base'][2],geometry['size'][1])
                    group_index = group_z*geometry['dimensions'][0]+group_x
                    if group_index != selected_group:
                        continue
                    if live[entity]:
                        pending[entity] = False
                    else:
                        live[entity] = True
                        generation[entity] += 1
                        live_order.insert(0,entity)
                        events.append(f'create:{entity}:{generation[entity]}')
        frozen_state = frozen_states[tick]
        frozen_fact = (int(frozen_state['static_live']),int(frozen_state['static_pending']),
                       int(frozen_state['static_generation']),int(frozen_state['moving_live']),
                       int(frozen_state['moving_pending']),int(frozen_state['moving_generation']),
                       frozen_state['live_order'].replace(';',',') or '-',
                       int(frozen_state['moving_distance']))
        python_fact = (int(live[2]),int(pending[2]),generation[2],int(live[9]),
                       int(pending[9]),generation[9],','.join(map(str,live_order)) or '-',distance)
        if python_fact != frozen_fact:
            raise ValueError(f'tick {tick}: independent lifecycle {python_fact} != frozen {frozen_fact}')
        writer.writerow(('component',tick,camera_name,','.join(map(str,groups)) or '-',
                         len(groups),int(live[2]),int(pending[2]),generation[2],
                         int(live[9]),int(pending[9]),generation[9],
                         ','.join(map(str,live_order)) or '-',','.join(events) or '-',distance))
    for name,camera in fixture['selector_cases'].items():
        groups = select(geometry,camera)
        if (frozen := c_select(mapview_oracle,geometry,camera)) != groups:
            raise ValueError(f'{name}: independent selector {groups} != frozen {frozen}')
        writer.writerow((name,-1,name,','.join(map(str,groups)) or '-',len(groups),
                         '-','-','-','-','-','-','-','-','-', '-'))
    return out.getvalue()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mapview-oracle', type=Path, required=True)
    parser.add_argument('--entity-oracle', type=Path, required=True)
    parser.add_argument('--integrated-oracle', type=Path, required=True)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    if not all(path.is_file() for path in (args.mapview_oracle,args.entity_oracle,args.integrated_oracle)):
        parser.error('All three frozen C oracle executables must exist')
    content = generate(args.mapview_oracle,args.entity_oracle)
    line_content = generate_lines(args.mapview_oracle)
    integrated_content = generate_integrated(args.integrated_oracle,args.mapview_oracle)
    if args.verify:
        if GOLDEN.read_text(encoding='utf-8') != content:
            raise SystemExit(f'{GOLDEN}: facts differ')
        if LINE_GOLDEN.read_text(encoding='utf-8') != line_content:
            raise SystemExit(f'{LINE_GOLDEN}: facts differ')
        if INTEGRATED_GOLDEN.read_text(encoding='utf-8') != integrated_content:
            raise SystemExit(f'{INTEGRATED_GOLDEN}: facts differ')
        print(f'Verified {GOLDEN}, {LINE_GOLDEN} and {INTEGRATED_GOLDEN}')
    else:
        GOLDEN.write_text(content,encoding='utf-8',newline='')
        LINE_GOLDEN.write_text(line_content,encoding='utf-8',newline='')
        INTEGRATED_GOLDEN.write_text(integrated_content,encoding='utf-8',newline='')
        print(f'Wrote {GOLDEN}, {LINE_GOLDEN} and {INTEGRATED_GOLDEN}')


if __name__ == '__main__':
    main()

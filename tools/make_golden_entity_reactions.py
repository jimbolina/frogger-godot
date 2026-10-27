#!/usr/bin/env python3
"""Independent synthetic FORM reaction facts checked against frozen CollideFrog.

All fixtures are invented integer inputs.  The offline C program calls the
unchanged collision/kill path; this module computes its expectations from the
source rules, never from game output.
"""
import argparse
import csv
import io
import json
import os
from pathlib import Path
import subprocess
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_golden_exe_tables as exe_tables
import make_golden_form_contacts as form_contacts
import make_golden_mof as mof

HEADER = ('case', 'mode', 'flags', 'death_animation', 'vx16', 'vy16', 'vz16',
          'camera_mode', 'pgen_requests', 'sound_requests', 'hit_indices',
          'contact_indices', 'reaction_statuses', 'death_entity_index')
IDENTITY = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096]
DES2_PROBE = (4, 46, (-683, -1576, 2176), (47, -21, 5), 2675)


def terrain_grid():
    squares = []
    for i in range(16):
        x, z = -512 + (i % 4) * 256, -512 + (i // 4) * 256
        squares.append({'flags': 3, 'vertices': [[x, 0, z + 256],
            [x + 256, 0, z + 256], [x, 0, z], [x + 256, 0, z]]})
    return {'dimensions': [4, 4], 'base': [-512, -512],
            'stacks': [[i, 1] for i in range(16)], 'squares': squares}


def authored_entity(index, flags=4097, entity_flags=0, translation=(-128, 0, -128),
                    death_type=5, radius=1000000):
    identity = dict(entity_index=index, unique_id=40 + index, form_grid_id=0,
                    form_id=3, form_name='SYNTHETIC_CACTUS')
    entity = dict(identity, entity_name='STATIC', flags=entity_flags,
                  matrix12=IDENTITY + list(translation))
    contact = dict(identity, entity_flags=entity_flags, dimensions=[1, 1],
                   offsets=[-128, -128], height=-128, max_y=128,
                   radius_squared=radius, grid_flags=[flags], death_type=death_type,
                   reaction_unsupported_reason='')
    return entity, contact


def authored_moving(index, flags=4097, entity_flags=16, speed=10):
    entity, contact = authored_entity(index, flags, entity_flags)
    entity['entity_name'] = 'MOVING'
    entity['path_definition'] = dict(path_index=0, segments=[dict(segment_type=2,
        length=20, start=[-138, 0, -128], end=[-118, 0, -128])])
    entity['path_start'] = dict(segment_index=0, distance=0, speed=speed, flags=8)
    entity['matrix12'] = IDENTITY + [-128 if speed == 10 else -138, 0, -128]
    return entity, contact


def cases():
    items = []
    def add(name, pairs, frozen_c=True, **changes):
        collision = dict(group_base=[-1024, 0, -1024], group_dimensions=[4, 4],
                         group_size=[512, 512], entities=[p[0] for p in pairs],
                         contacts=[p[1] for p in pairs])
        item = dict(name=name, frozen_c=frozen_c, builtin='normal', tick_limit=1, grid=terrain_grid(),
            level=dict(spawn_cell=[1, 1], spawn_direction=0, collision_enabled=True,
                collision_bounds=[-32767, -32767, 65534, 65534], theme=9,
                theme_name='SUB', theme_death_height=30000, map_index=0,
                camera=dict(source_offset=[0, -500, -500], target_offset=[0, 0, 0]),
                frog_action_lengths=[3 + i % 3 for i in range(34)], entity_collision=collision),
            start=dict(seed=1, camera_startup=False), commands=[])
        item.update(changes)
        items.append(item)
    add('popdeath', [authored_entity(0)])
    add('deadly_pop', [authored_entity(0, 5)])
    add('unusable_pop', [authored_entity(0, 4096)])
    add('usable_plain', [authored_entity(0, 1)])
    add('slippy_hit', [authored_entity(0, 17)])
    add('hidden_pop', [authored_entity(0, 4097, entity_flags=1)])
    add('no_display_pop', [authored_entity(0, 4097, entity_flags=2)])
    add('no_collision', [authored_entity(0, 4097, entity_flags=8)])
    add('sphere_edge', [authored_entity(0, 4097, radius=0)])
    add('outside_form', [authored_entity(0, 4097, translation=(-400, 0, -128))])
    add('two_overlapping_pop', [authored_entity(0), authored_entity(1)])
    add('reverse_authored_first_kill', [authored_entity(0, 5, death_type=0), authored_entity(1)])
    add('unusable_then_pop', [authored_entity(0, 4096), authored_entity(1)])
    add('death_type_squished', [authored_entity(0, 5, death_type=0)])
    add('pop_over_deadly', [authored_entity(0, 4101, death_type=0)])
    add('moving_before_static', [authored_moving(0), authored_entity(1)])
    add('hidden_moving_unlinked', [authored_moving(0, entity_flags=17)])
    add('shared_path_pair', [authored_moving(0), authored_moving(1)])
    first, second = authored_entity(2), authored_entity(7)
    second[0]['unique_id'] = first[0]['unique_id']
    second[1]['unique_id'] = first[1]['unique_id']
    add('index_gaps_duplicate_unique_id', [first, second])
    add('negative_group_truncation', [authored_entity(0)])
    items[-1]['level']['entity_collision'].update(group_base=[-27, 0, -27],
        group_dimensions=[3, 3], group_size=[100, 100])
    add('frog_group_out_of_bounds', [authored_entity(0)])
    items[-1]['level']['entity_collision'].update(group_base=[-10000, 0, -10000],
        group_dimensions=[4, 4], group_size=[512, 512])
    add('safe_precedes_pop_diagnostic', [authored_entity(0, 4099)], frozen_c=False)
    add('checkpoint_precedes_pop_diagnostic', [authored_entity(0, 4161)], frozen_c=False)
    items[-1]['level']['entity_collision']['contacts'][0]['reaction_unsupported_reason'] = 'Checkpoint requires a shared environment outside this bounded fixture'
    return items


def c_input(items):
    lines = [str(len(items))]
    for case in items:
        collision = case['level']['entity_collision']
        entities, contacts = collision['entities'], collision['contacts']
        header = [len(entities), collision['group_base'][0], collision['group_base'][2],
                  *collision['group_dimensions'], *collision['group_size'],
                  0, 2049, case['level']['theme_death_height'], -128, 0, -128,
                  0, 0, 0]
        lines.append(' '.join(map(str, header)))
        for entity, contact in zip(entities, contacts):
            row = [entity['entity_index'], 1 if entity['entity_name'] == 'MOVING' else 0,
                   entity['flags'], *entity['matrix12'],
                   *contact['offsets'], *contact['dimensions'], contact['height'],
                   contact['max_y'], contact['radius_squared'], contact['death_type'],
                   *contact['grid_flags']]
            lines.append(' '.join(map(str, row)))
    return '\n'.join(lines) + '\n'


def div_zero(a, b):
    return abs(a) // b * (-1 if a < 0 else 1)


def signed(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def python_row(case):
    collision = case['level']['entity_collision']
    entities, contacts = collision['entities'], collision['contacts']
    base = collision['group_base']; dims = collision['group_dimensions']; size = collision['group_size']
    frog = (-128, 0, -128)
    fx, fz = div_zero(frog[0] - base[0], size[0]), div_zero(frog[2] - base[2], size[1])
    first_kill = -1
    death_entity = -1
    hits = []
    contacts_seen = []
    statuses = []
    for gz in range(max(0, fz - 1), min(dims[1] - 1, fz + 1) + 1):
        for gx in range(max(0, fx - 1), min(dims[0] - 1, fx + 1) + 1):
            pairs = list(zip(entities, contacts))
            linked = list(reversed([p for p in pairs if p[0]['entity_name'] == 'MOVING' and not p[0]['flags'] & 1]))
            linked.extend(reversed([p for p in pairs if p[0]['entity_name'] == 'STATIC']))
            for entity, contact in linked:
                matrix = entity['matrix12']
                entity_gx = max(0, min(dims[0] - 1, div_zero(matrix[9] - base[0], size[0])))
                entity_gz = max(0, min(dims[1] - 1, div_zero(matrix[11] - base[2], size[1])))
                if (entity_gx, entity_gz) != (gx, gz):
                    continue
                if entity['flags'] & 8:
                    continue
                delta = [signed(frog[j] - matrix[9 + j], 16) for j in range(3)]
                distance = signed(sum(v * v for v in delta), 32)
                if distance >= contact['radius_squared']:
                    continue
                local = [signed(sum(matrix[row * 3 + col] * delta[row]
                                   for row in range(3)), 32) >> 12 for col in range(3)]
                xofs, zofs = contact['offsets']; nx, nz = contact['dimensions']
                if not (xofs < local[0] < xofs + (nx << 8) and
                        zofs < local[2] < zofs + (nz << 8) and
                        contact['height'] <= local[1] <= contact['max_y']):
                    continue
                cell_x = (local[0] - xofs) >> 8; cell_z = (local[2] - zofs) >> 8
                flags = contact['grid_flags'][cell_z * nx + cell_x]
                contacts_seen.append(entity['entity_index'])
                if not flags & 1:
                    statuses.append('none')
                    continue
                if flags & (64 | 2):
                    statuses.append('unsupported')
                    continue
                hits.append(entity['entity_index'])
                statuses.append('pop' if flags & 4096 or flags & 4 and contact['death_type'] == 5
                                else 'squish' if flags & 4 and contact['death_type'] == 0
                                else 'unsupported' if flags & 4 else 'hit')
                if first_kill < 0:
                    if flags & 4096:
                        first_kill = 23
                        death_entity = entity['entity_index']
                    elif flags & 4:
                        first_kill = {0: 2, 2: 8, 3: 10, 4: 12,
                                      5: 23, 6: 26, 7: 33}.get(contact['death_type'], 2)
                        death_entity = entity['entity_index']
    killed = first_kill >= 0
    return [case['name'], 0, 9 if killed else 2049, first_kill if killed else 0,
            0, 0, 0, 4 if killed else 0, 1 if killed else 0, 0,
            ','.join(map(str, hits)) if hits else '-',
            ','.join(map(str, contacts_seen)) if contacts_seen else '-',
            ','.join(statuses) if statuses else '-', death_entity]


def generate(args):
    items = cases()
    frozen_items = [case for case in items if case['frozen_c']]
    result = subprocess.run([args.oracle], input=c_input(frozen_items), text=True,
        capture_output=True, check=True, timeout=30,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    c_header = HEADER[:11]
    marker = '\t'.join(c_header) + '\n'
    if marker not in result.stdout:
        raise ValueError('Frozen C oracle did not emit its schema')
    rows = list(csv.reader(io.StringIO(result.stdout[result.stdout.index(marker):]), delimiter='\t'))
    if rows[0] != list(c_header) or len(rows) != len(frozen_items) + 1:
        raise ValueError('Frozen C oracle output schema/count differs: ' + repr(result.stdout[:300]))
    expected = [python_row(case) for case in items]
    for i, (case, actual) in enumerate(zip(frozen_items, rows[1:])):
        want = python_row(case)
        if actual[0] != str(i) or actual[1:] != list(map(str, want[1:11])):
            raise ValueError(f"Python/frozen C disagreement {want[0]}: Python={want[1:]} C={actual}")
    target = Path(args.output)
    out = io.StringIO(newline=''); writer = csv.writer(out, delimiter='\t', lineterminator='\n')
    writer.writerow(HEADER); writer.writerows(expected)
    fixture = Path(args.fixture)
    fixture_text = json.dumps({'cases': items}, indent=2) + '\n'
    if args.verify:
        if target.read_bytes() != out.getvalue().encode('utf-8') or fixture.read_bytes() != fixture_text.encode('utf-8'):
            raise ValueError('Entity reaction fixture or golden differs')
    else:
        target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(out.getvalue().encode('utf-8'))
        fixture.parent.mkdir(parents=True, exist_ok=True); fixture.write_bytes(fixture_text.encode('utf-8'))
    print(f'Independent Python/frozen C entity reaction facts match: {len(items)} cases')


def retail(args):
    cfg = exe_tables.parse_cfg(str(Path(exe_tables.CFG_ROOT) / 'versions' / (args.version + '.cfg')))
    with open(Path(args.data_dir) / 'FROGGER.EXE', 'rb') as source:
        image = exe_tables.Exe(source.read(), exe_tables.java_int(cfg.values['ramOffset']))
    levels, _ = exe_tables.read_map_book(image, exe_tables.java_int(cfg.values['mapBook']),
                                          exe_tables.java_int(cfg.values['themeBook']))
    level = levels[exe_tables.LEVEL_CODES.index('DES2')]
    resource_id = level['high_map']
    if resource_id != 650:
        raise ValueError(f'DES2 high map changed: {resource_id}')
    _, archive_entries, wads, files = mof.load_archive(args.data_dir,
        exe_tables.java_int(cfg.values['mwiOffset']), exe_tables.java_int(cfg.values['mwiLength']))
    with open(Path(args.data_dir) / 'FROGPSX.MWD', 'rb') as source:
        mwd = source.read()
    for entry in archive_entries:
        if entry['index'] != resource_id:
            continue
        start = entry['sector'] * mof.SECTOR_SIZE
        packed = mof.is_compressed(entry['flags'])
        raw = mwd[start:start + (entry['packed'] if packed else entry['unpacked'])]
        data = mof.pp20_unpack(raw)[0] if packed else raw
        break
    else:
        raise ValueError('DES2 map resource absent')
    form_names, sections, _ = exe_tables.name_list('forms', cfg.values.get('formList', '1997-09-12-psx-build57'))
    themes = exe_tables.read_theme_book(image, exe_tables.java_int(cfg.values['themeBook']))
    problems = []
    library = exe_tables.read_forms(image, themes, sections, problems)
    if problems:
        raise ValueError('; '.join(problems))
    forms = form_contacts.parse_forms(data)
    grap = form_contacts.read(data, 80, '<I')
    group = form_contacts.read(data, grap + 8, '<I')
    group_base = struct.unpack_from('<3h', data, group + 4)
    group_dimensions = struct.unpack_from('<2H', data, group + 12)
    group_size = struct.unpack_from('<2H', data, group + 16)
    grid = form_contacts.read(data, grap + 20, '<I')
    grid_dimensions = struct.unpack_from('<2H', data, grid + 4)
    grid_size = struct.unpack_from('<2H', data, grid + 8)
    gene = form_contacts.read(data, 76, '<I')
    theme = form_contacts.read(data, gene + 10, '<H')
    if grid_dimensions != (42, 44) or group_dimensions != (15, 15) or group_size != (768, 768):
        raise ValueError('DES2 grid/group geometry changed')
    def top_square_flags(cell_x, cell_z):
        stack = grid + 12 + (cell_z * grid_dimensions[0] + cell_x) * 4
        count, _cliff, first = struct.unpack_from('<BBH', data, stack)
        if count == 0:
            raise ValueError('DES2 probe stack is empty')
        square = grid + 12 + grid_dimensions[0] * grid_dimensions[1] * 4 + (first + count - 1) * 8
        return struct.unpack_from('<I', data, square)[0]
    if top_square_flags(17, 30) != 3 or top_square_flags(18, 30) != 4097:
        raise ValueError('DES2 probe ground flags changed')
    emtp = form_contacts.read(data, 88, '<I')
    count = form_contacts.read(data, emtp + 8, '<H')
    all_headers = []
    for index in range(count):
        pointer = form_contacts.read(data, emtp + 12 + 4 * index, '<I')
        all_headers.append(struct.unpack_from('<4H', data, pointer))
    grid_writers = {}
    for index, (grid_id, _uid, _form_id, _flags) in enumerate(all_headers):
        grid_writers.setdefault(grid_id, []).append(index)
    models = {}
    rows = []
    allowed = {'DES_STAT_CACTUS', 'DES_STAT_CACTUS2', 'DES_STAT_BALLCACTUS', 'DES_STAT_BALLCACTUS2'}
    for index in range(count):
        at = form_contacts.read(data, emtp + 12 + 4 * index, '<I')
        grid_id, unique_id, form_id, entity_flags = all_headers[index]
        owner = 0 if form_id & 0x8000 else theme
        local_id = form_id & 0x7fff
        if local_id >= len(library.get(owner, [])):
            continue
        book = library[owner][local_id]
        name = form_names[book['global']]
        if name not in allowed:
            continue
        if {all_headers[writer][2] for writer in grid_writers[grid_id]} != {form_id}:
            raise ValueError(f'Cactus FORM grid {grid_id} has a different last writer')
        if grid_id >= len(forms):
            raise ValueError(f'cactus entity {index} FORM grid absent')
        form = forms[grid_id]
        _, form_at, form_count, stored_max, nx, nz, xofs, zofs, form_items = form
        if form_count != 1 or form_items[0][1] != 0:
            raise ValueError(f'cactus entity {index} does not use one GRID form')
        _, _, height, _, _, square_flags = form_items[0]
        model_resource = wads[level['high_wad']][book['id']][0]
        if model_resource not in models:
            models[model_resource] = mof.parse_model(files[model_resource], name, None, [])
        model = models[model_resource]
        if model['kind'] != 'static' or not model['statics']:
            raise ValueError('cactus has non-static model')
        radius = book['radius2']
        parts = model['statics'][0]['parts']
        if radius == 0:
            for part in parts:
                if part['collprims']:
                    raise ValueError('cactus collprims need another oracle')
                for cel in part['partcel_list']:
                    box = cel['box']
                    for i in range(0, len(box), 3):
                        radius = max(radius, sum(v * v for v in box[i:i + 3]))
            radius = form_contacts.s32(radius + 100)
        first_box = parts[0]['partcel_list'][0]['box']
        max_y = 32767 if book['flags'] & 32 else (256 if book['flags'] & 512 else first_box[22])
        matrix = struct.unpack_from('<10h3i', data, at + 24)
        matrix12 = (*matrix[:9], *matrix[10:])
        rows.append([resource_id, 'DES2.MAP', index, at, unique_id, grid_id,
                     form_id, name, entity_flags, book['entity_type'], book['script'],
                     book['collision'], book['bonus'], book['death'], book['flags'],
                     level['high_wad'], model_resource, form_at, nx, nz, xofs, zofs,
                     height, stored_max, max_y, radius, ','.join(map(str, square_flags)),
                     ','.join(map(str, grid_writers[grid_id])),
                     *matrix12])
    names = [row[7] for row in rows]
    if len(rows) != 23 or names.count('DES_STAT_CACTUS') != 9 or names.count('DES_STAT_CACTUS2') != 5 or names.count('DES_STAT_BALLCACTUS') != 3 or names.count('DES_STAT_BALLCACTUS2') != 6:
        raise ValueError(f'Expected DES2 cactus family counts changed: {len(rows)} {names}')
    vertices_packet = form_contacts.read(data, grap + 16, '<I')
    def square_y(cell_x, cell_z):
        stack = grid + 12 + (cell_z * grid_dimensions[0] + cell_x) * 4
        count, _cliff, first = struct.unpack_from('<BBH', data, stack)
        square = grid + 12 + grid_dimensions[0] * grid_dimensions[1] * 4 + (first + count - 1) * 8
        polygon = struct.unpack_from('<I', data, square + 4)[0]
        vertex_ids = struct.unpack_from('<4H', data, polygon)
        heights = [struct.unpack_from('<h', data, vertices_packet + 8 + vertex * 8 + 2)[0]
                   for vertex in vertex_ids]
        return sum(heights) >> 2
    grid_base = (-grid_dimensions[0] * 128, -grid_dimensions[1] * 128)
    start_world = (grid_base[0] + 17 * 256 + 128, square_y(17, 30),
                   grid_base[1] + 30 * 256 + 128)
    target_world = (grid_base[0] + 18 * 256 + 128, square_y(18, 30), start_world[2])
    position = [value << 16 for value in start_world]
    duration = 6
    velocity = [div_zero((target_world[0] - start_world[0]) << 16, duration),
                div_zero((target_world[1] - start_world[1]) << 16, duration + 1) - ((0x100000 * (duration + 1)) >> 1),
                0]
    observed_probe = None
    for tick in range(duration):
        velocity[1] += 0x100000
        position = [a + b for a, b in zip(position, velocity)]
        world = tuple(value >> 16 for value in position)
        frog_group = (div_zero(world[0] - group_base[0], group_size[0]),
                      div_zero(world[2] - group_base[2], group_size[1]))
        for gz in range(max(0, frog_group[1] - 1), min(group_dimensions[1] - 1, frog_group[1] + 1) + 1):
            for gx in range(max(0, frog_group[0] - 1), min(group_dimensions[0] - 1, frog_group[0] + 1) + 1):
                for row in reversed(rows):
                    matrix = row[-12:]
                    entity_group = (max(0, min(group_dimensions[0] - 1, div_zero(matrix[9] - group_base[0], group_size[0]))),
                                    max(0, min(group_dimensions[1] - 1, div_zero(matrix[11] - group_base[2], group_size[1]))))
                    if entity_group != (gx, gz):
                        continue
                    delta = [signed(world[i] - matrix[9 + i], 16) for i in range(3)]
                    distance = signed(sum(value * value for value in delta), 32)
                    if distance >= row[25]:
                        continue
                    local = tuple(signed(sum(matrix[r * 3 + c] * delta[r] for r in range(3)), 32) >> 12
                                  for c in range(3))
                    xofs, zofs, height, max_y = row[20], row[21], row[22], row[24]
                    nx, nz = row[18], row[19]
                    if not (xofs < local[0] < xofs + nx * 256 and zofs < local[2] < zofs + nz * 256 and
                            height <= local[1] <= max_y):
                        continue
                    cell_x, cell_z = (local[0] - xofs) >> 8, (local[2] - zofs) >> 8
                    cell_flags = int(row[26].split(',')[cell_z * nx + cell_x])
                    if cell_flags & 1 and (cell_flags & 4096 or cell_flags & 4 and row[13] == 5):
                        observed_probe = (tick, row[2], world, local, distance)
                        break
                if observed_probe is not None:
                    break
            if observed_probe is not None:
                break
        if observed_probe is not None:
            break
    if observed_probe != DES2_PROBE:
        raise ValueError(f'DES2 independently derived first cactus POP changed: {observed_probe}')
    header = ['resource_id','map','entity_index','source_offset','unique_id','form_grid_id',
              'form_id','form_name','entity_flags','entity_type','script_id',
              'collision_callback','bonus_callback','death_type','book_flags',
              'wad_id','model_resource_id','form_source_offset','xnum','znum',
              'xofs','zofs','height','stored_max_y','runtime_max_y','radius_squared',
              'grid_flags','grid_writers'] + [f'matrix_{i}' for i in range(12)]
    out = io.StringIO(newline=''); writer = csv.writer(out, delimiter='\t', lineterminator='\n')
    writer.writerow(header); writer.writerows(rows)
    target = Path(args.retail_output)
    if args.verify:
        if target.read_bytes() != out.getvalue().encode('utf-8'):
            raise ValueError('DES2 cactus retail golden differs')
    else:
        target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(out.getvalue().encode('utf-8'))
    print(f'DES2 cactus setup: {len(rows)} source ordered instances, grid {grid_dimensions} at size {grid_size}, groups {group_base}/{group_dimensions}/{group_size}')


def death_policy(verify):
    """Independent COLLIDE.C FORM/primitive switch and FrogKill velocity facts."""
    rows = []
    for death_type in range(8):
        animation = {2: 8, 3: 10, 4: 12, 5: 23, 6: 26, 7: 33}.get(death_type, 2)
        for primitive in (False, True):
            for map_index in (2, 24):
                for jumping_to_land in (False, True):
                    velocity = [11, -22, 33] if jumping_to_land else [0, 0, 0]
                    if death_type == 2:
                        velocity = [0, 65536, 0]
                    if death_type == 4 and not primitive and map_index == 2:
                        velocity = [11, -22, 33]
                    rows.append(dict(death_type=death_type, primitive=primitive, map_index=map_index,
                                     jumping_to_land=jumping_to_land, animation=animation,
                                     shadow_hidden=death_type == 4, velocity=velocity))
    target = Path(__file__).resolve().parent.parent / 'tests/golden/synthetic/entity_deaths.json'
    text = json.dumps(rows, indent=2) + '\n'
    if verify:
        if target.read_text(encoding='utf-8') != text:
            raise ValueError('Independent entity death policy facts differ')
    else:
        target.write_text(text, encoding='utf-8')
    print('Entity death policy facts verified against independent Python source model.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--death-policy', action='store_true')
    parser.add_argument('--oracle')
    parser.add_argument('--data-dir')
    parser.add_argument('--version', default='pc-retail-v3.0e')
    parser.add_argument('--retail-output', default='tests/golden/pc-retail-v3.0e/entity_reactions_retail.tsv')
    parser.add_argument('--output', default='tests/golden/synthetic/entity_reactions.tsv')
    parser.add_argument('--fixture', default='tests/golden/fixtures/entity_reactions.json')
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    if not args.oracle and not args.data_dir and not args.death_policy:
        parser.error('Specify --oracle, --data-dir or --death-policy')
    if args.oracle:
        generate(args)
    if args.data_dir:
        retail(args)

    if args.death_policy:
        death_policy(args.verify)

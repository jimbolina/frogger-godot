#!/usr/bin/env python3
"""Decode the selected JUN1 SAFE log and its first source-arithmetic contact.

Reads the owner's retail EXE/MWI/MWD/MOF/MAP; emits decimal text facts only.
"""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_golden_exe_tables as exe_tables
import make_golden_form_contacts as contacts
import make_golden_mof as mof
import make_golden_entities as entities
import make_golden_paths as paths

HEADER = (
    'resource_id', 'map', 'map_index', 'entity_index', 'source_offset',
    'unique_id', 'form_grid_id', 'form_id', 'form_name', 'entity_name',
    'entity_flags', 'entity_type', 'script_id', 'collision_callback',
    'bonus_callback', 'book_flags', 'wad_id', 'model_resource_id',
    'model_kind', 'primitive_count',
    'form_source_offset', 'xnum', 'znum', 'xofs', 'zofs', 'height',
    'stored_max_y', 'runtime_max_y', 'radius_squared', 'grid_flags',
    'path_index', 'segment_index', 'segment_distance', 'motion_flags',
    'speed', 'path_padding', 'segment_type', 'segment_length',
    'line_start_x', 'line_start_y', 'line_start_z',
    'line_end_x', 'line_end_y', 'line_end_z',
    'initial_x', 'initial_y', 'initial_z',
    'initial_tangent_x', 'initial_tangent_y', 'initial_tangent_z',
    *(f'initial_matrix_{i}' for i in range(12)),
    'spawn_x', 'spawn_z', 'spawn_direction', 'spawn_y',
    'command_tick', 'entity_tick', 'frog_x', 'frog_y', 'frog_z',
    'entity_x', 'entity_y', 'entity_z', 'local_x', 'local_y', 'local_z',
    'cell_x', 'cell_z', 'contact_flags', 'distance_squared',
)


def div_zero(value, denominator):
    return (abs(value) // denominator) * (-1 if value < 0 else 1)


def route_numeric_digest(rows):
    """Hash ASCII decimal rows with commas between values and LF after every row."""
    return hashlib.sha256(''.join(','.join(map(str, row)) + '\n' for row in rows).encode('ascii')).hexdigest()


def signed(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def resource(files, entries, mwd, resource_id):
    if resource_id in files:
        return files[resource_id]
    entry = entries[resource_id]
    at = entry['sector'] * mof.SECTOR_SIZE
    compressed = mof.is_compressed(entry['flags'])
    raw = mwd[at:at + (entry['packed'] if compressed else entry['unpacked'])]
    return mof.pp20_unpack(raw)[0] if compressed else raw


def first_contact(start, segment, form, radius, flags):
    """Frozen JumpFrog/MoveFrog plus PATH and CollideFrog fixed-width gates."""
    _, _, _, _, nx, nz, xofs, zofs, items = form
    height = items[0][2]
    max_y = start['max_y']
    frog = [start['x'] << 16, start['y'] << 16, start['z'] << 16]
    target_z = start['z'] + 256
    duration = 6
    gravity = 0x100000
    velocity = [0, div_zero((start['target_y'] - start['y']) << 16, duration + 1)
                - ((gravity * (duration + 1)) >> 1),
                div_zero((target_z - start['z']) << 16, duration)]
    for command_tick in range(duration):
        velocity[1] += gravity
        frog = [a + b for a, b in zip(frog, velocity)]
        world = [value >> 16 for value in frog]
        entity_tick = command_tick + 1
        distance = start['distance'] + entity_tick * start['speed']
        _, position, tangent = paths.sample(segment, distance, False)
        matrix = entities.moving_matrix([0] * 9 + position + tangent, flags)
        delta = [signed(world[axis] - matrix[9 + axis], 16) for axis in range(3)]
        distance_squared = signed(sum(v * v for v in delta), 32)
        if distance_squared >= radius:
            continue
        local = [signed(sum(matrix[row * 3 + col] * delta[row]
                            for row in range(3)), 32) >> 12 for col in range(3)]
        if not (xofs < local[0] < xofs + nx * 256
                and zofs < local[2] < zofs + nz * 256
                and height <= local[1] <= max_y):
            continue
        cell_x = (local[0] - xofs) >> 8
        cell_z = (local[2] - zofs) >> 8
        cell_flags = items[0][5][cell_z * nx + cell_x]
        if cell_flags & 1 and cell_flags & 2 and cell_flags & 256:
            return [command_tick, entity_tick, *world, *position,
                    *local, cell_x, cell_z, cell_flags, distance_squared]
    raise ValueError('JUN1 inspection hop has no SAFE contact')


def row(data_dir, version):
    cfg = exe_tables.parse_cfg(str(Path(exe_tables.CFG_ROOT) / 'versions' / (version + '.cfg')))
    image = exe_tables.Exe((data_dir / 'FROGGER.EXE').read_bytes(),
                           exe_tables.java_int(cfg.values['ramOffset']))
    levels, _ = exe_tables.read_map_book(image, exe_tables.java_int(cfg.values['mapBook']),
                                          exe_tables.java_int(cfg.values['themeBook']))
    map_index = exe_tables.LEVEL_CODES.index('JUN1')
    level = levels[map_index]
    resource_id = level['high_map']
    if resource_id != 656:
        raise ValueError(f'JUN1 high-detail map changed: {resource_id}')
    _, entries, wads, files = mof.load_archive(str(data_dir),
        exe_tables.java_int(cfg.values['mwiOffset']), exe_tables.java_int(cfg.values['mwiLength']))
    mwd = (data_dir / 'FROGPSX.MWD').read_bytes()
    data = resource(files, entries, mwd, resource_id)
    if data[:4] != b'FROG':
        raise ValueError('JUN1 map signature changed')
    theme = contacts.read(data, contacts.read(data, 76, '<I') + 10, '<H')
    names, sections, _ = exe_tables.name_list('forms',
        cfg.values.get('formList', '1997-09-12-psx-build57'))
    entity_names, _, _ = exe_tables.name_list('entities',
        cfg.values.get('entityList', '1997-09-12-psx-build57'))
    problems = []
    library = exe_tables.read_forms(image,
        exe_tables.read_theme_book(image, exe_tables.java_int(cfg.values['themeBook'])),
        sections, problems)
    if problems:
        raise ValueError('; '.join(problems))
    emtp = contacts.read(data, 88, '<I')
    index = 1
    at = contacts.read(data, emtp + 12 + 4 * index, '<I')
    grid_id, unique_id, form_id, entity_flags = struct.unpack_from('<4H', data, at)
    book = library[theme][form_id]
    name = names[book['global']]
    entity_name = entity_names[book['entity_type']]
    path_id, segment_index, distance, motion, speed, padding = struct.unpack_from('<6H', data, at + 24)
    form = contacts.parse_forms(data)[grid_id]
    _, form_at, count, stored_max, nx, nz, xofs, zofs, items = form
    if count != 1 or items[0][1] != 0:
        raise ValueError('JUN_LOG requires one GRID FORM_DATA')
    model_id = wads[level['high_wad']][book['id']][0]
    model = mof.parse_model(resource(files, entries, mwd, model_id), name, None, [])
    if model['kind'] != 'static' or not model['statics']:
        raise ValueError('JUN_LOG model is not static MOF')
    parts = model['statics'][0]['parts']
    primitive_count = sum(part['collprims'] for part in parts)
    if primitive_count:
        raise ValueError('JUN_LOG has model collision primitives')
    radius = book['radius2']
    if radius == 0:
        for part in parts:
            for cel in part['partcel_list']:
                box = cel['box']
                for i in range(0, len(box), 3):
                    radius = max(radius, sum(v * v for v in box[i:i + 3]))
        radius = signed(radius + 100, 32)
    first_box = parts[0]['partcel_list'][0]['box']
    max_y = 32767 if book['flags'] & 32 else (256 if book['flags'] & 512 else first_box[22])
    path_packet = contacts.read(data, 96, '<I')
    path = contacts.read(data, path_packet + 8 + path_id * 4, '<I')
    segment_offset = contacts.read(data, path + 8 + segment_index * 4, '<I')
    kind, length = struct.unpack_from('<Ii', data, segment_offset)
    line_start = struct.unpack_from('<3h', data, segment_offset + 8)
    line_end = struct.unpack_from('<3h', data, segment_offset + 16)
    segment = dict(segment_type=kind, length=length, start=line_start, end=line_end)
    _, initial_position, initial_tangent = paths.sample(segment, distance, False)
    initial_matrix = entities.moving_matrix([0] * 9 + initial_position + initial_tangent,
                                             entity_flags)
    # Explicit water-cell inspection start. GRID top square vertices supply
    # the actual source height; no invented terrain height enters the oracle.
    grap = contacts.read(data, 80, '<I')
    grid = contacts.read(data, grap + 20, '<I')
    grid_width, grid_depth = struct.unpack_from('<2H', data, grid + 4)
    vertex_packet = contacts.read(data, grap + 16, '<I')
    def square(cell_x, cell_z):
        stack = grid + 12 + (cell_z * grid_width + cell_x) * 4
        count, _, first = struct.unpack_from('<BBH', data, stack)
        if not count:
            raise ValueError('JUN1 inspection water stack empty')
        square_at = grid + 12 + grid_width * grid_depth * 4 + (first + count - 1) * 8
        square_flags, polygon = struct.unpack_from('<II', data, square_at)
        vertices = struct.unpack_from('<4H', data, polygon)
        heights = [struct.unpack_from('<h', data, vertex_packet + 8 + v * 8 + 2)[0]
                   for v in vertices]
        return square_flags, sum(heights) >> 2
    spawn_flags, spawn_y = square(18, 5)
    target_flags, target_y = square(18, 6)
    if not spawn_flags & 8 or not target_flags & 8:
        raise ValueError(f'JUN1 inspection route no longer uses water: {spawn_flags}, {target_flags}')
    spawn_x = -grid_width * 128 + 18 * 256 + 128
    spawn_z = -grid_depth * 128 + 5 * 256 + 128
    probe = first_contact(dict(x=spawn_x, y=spawn_y, z=spawn_z,
                               target_y=target_y, distance=distance,
                               speed=speed, max_y=max_y), segment, form,
                          radius, entity_flags)
    if (name, entity_name, grid_id, form_id, path_id, segment_index,
        distance, speed, kind, probe[0], probe[1], probe[8:11], probe[11:14]) != (
            'JUN_LOG', 'MOVING', 1, 45, 1, 2, 2197, 16, 2, 3, 4,
            [88, 46, 42], [0, 1, 259]):
        raise ValueError(f'JUN1 platform identity/contact changed: {probe}')
    return [resource_id, 'JUN1.MAP', map_index, index, at, unique_id,
            grid_id, form_id, name, entity_name, entity_flags,
            book['entity_type'], book['script'], book['collision'], book['bonus'],
            book['flags'], level['high_wad'], model_id, model['kind'],
            primitive_count, form_at,
            nx, nz, xofs, zofs, items[0][2], stored_max, max_y, radius,
            ','.join(map(str, items[0][5])), path_id, segment_index, distance,
            motion, speed, padding, kind, length, *line_start, *line_end,
            *initial_position, *initial_tangent, *initial_matrix,
            18, 5, 0, spawn_y, *probe]


def route_fixture(data_dir, version, return_context=False):
    """Transport decoded retail numbers to the unchanged frozen-C platform phases."""
    cfg = exe_tables.parse_cfg(str(Path(exe_tables.CFG_ROOT) / 'versions' / (version + '.cfg')))
    image = exe_tables.Exe((data_dir / 'FROGGER.EXE').read_bytes(),
                           exe_tables.java_int(cfg.values['ramOffset']))
    levels, _ = exe_tables.read_map_book(image, exe_tables.java_int(cfg.values['mapBook']),
                                         exe_tables.java_int(cfg.values['themeBook']))
    level = levels[exe_tables.LEVEL_CODES.index('JUN1')]
    if level['high_map'] != 656:
        raise ValueError('JUN1 high-detail resource changed')
    _, entries, wads, files = mof.load_archive(str(data_dir),
        exe_tables.java_int(cfg.values['mwiOffset']), exe_tables.java_int(cfg.values['mwiLength']))
    mwd = (data_dir / 'FROGPSX.MWD').read_bytes()
    data = resource(files, entries, mwd, level['high_map'])
    theme = contacts.read(data, contacts.read(data, 76, '<I') + 10, '<H')
    names, sections, _ = exe_tables.name_list('forms',
        cfg.values.get('formList', '1997-09-12-psx-build57'))
    library = exe_tables.read_forms(image,
        exe_tables.read_theme_book(image, exe_tables.java_int(cfg.values['themeBook'])), sections, [])
    emtp = contacts.read(data, 88, '<I')
    entity_at = contacts.read(data, emtp + 12 + 24 * 4, '<I')
    grid_id, uid, form_id, entity_flags = struct.unpack_from('<4H', data, entity_at)
    book = library[theme][form_id]
    if (grid_id, form_id, names[book['global']], book['script'], book['collision'], book['bonus']) != (
            1, 45, 'JUN_LOG', 0, 0, 0):
        raise ValueError('selected JUN_LOG source identity changed')
    path_id, segment_index, distance, motion, speed, padding = struct.unpack_from('<6H', data, entity_at + 24)
    if (path_id, segment_index, distance, motion, speed, padding) != (4, 10, 387, 8, 16, 0):
        raise ValueError('selected JUN_LOG path start changed')
    form = contacts.parse_forms(data)[grid_id]
    _, _, count, _, nx, nz, xofs, zofs, items = form
    if count != 1 or items[0][1] != 0:
        raise ValueError('selected JUN_LOG FORM changed')
    model_id = wads[level['high_wad']][book['id']][0]
    model = mof.parse_model(resource(files, entries, mwd, model_id), 'JUN_LOG', None, [])
    if model['kind'] != 'static' or not model['statics']:
        raise ValueError('selected JUN_LOG static model changed')
    parts = model['statics'][0]['parts']
    if sum(part['collprims'] for part in parts):
        raise ValueError('selected JUN_LOG gained collision primitives')
    radius = book['radius2']
    if radius == 0:
        for part in parts:
            for cel in part['partcel_list']:
                box = cel['box']
                for j in range(0, len(box), 3):
                    radius = max(radius, sum(v * v for v in box[j:j + 3]))
        radius = signed(radius + 100, 32)
    first_box = parts[0]['partcel_list'][0]['box']
    max_y = 32767 if book['flags'] & 32 else (256 if book['flags'] & 512 else first_box[22])
    grap = contacts.read(data, 80, '<I')
    grid = contacts.read(data, grap + 20, '<I')
    vertices = contacts.read(data, grap + 16, '<I')
    width, depth = struct.unpack_from('<2H', data, grid + 4)

    def square(cx, cz):
        count, _, first = struct.unpack_from('<BBH', data, grid + 12 + (cz * width + cx) * 4)
        if count < 1:
            left = -width * 128 + cx * 256
            top = -depth * 128 + cz * 256
            return -1, [(left, 0, top + 256), (left + 256, 0, top + 256),
                        (left, 0, top), (left + 256, 0, top)]
        at = grid + 12 + width * depth * 4 + (first + count - 1) * 8
        flags, polygon = struct.unpack_from('<II', data, at)
        indices = struct.unpack_from('<4H', data, polygon)
        points = [struct.unpack_from('<3h', data, vertices + 8 + i * 8) for i in indices]
        return flags, points

    spawn_flags, spawn_points = square(22, 10)
    spawn_y = sum(point[1] for point in spawn_points) >> 2
    if not spawn_flags & 3 == 3 or spawn_y != -324:
        raise ValueError('bank start changed')
    approach_flags, approach_points = square(21, 10)
    approach_y = sum(point[1] for point in approach_points) >> 2
    if approach_flags != 9 or approach_y != -103:
        raise ValueError('JUN1 approach square changed')
    group_at = contacts.read(data, grap + 8, '<I')
    gx, gy, gz, _pad, group_x, group_z, group_width, group_depth = struct.unpack_from(
        '<4h4H', data, group_at + 4)
    stacks = [struct.unpack_from('<BBH', data, grid + 12 + i * 4)
              for i in range(width * depth)]
    square_total = max((first + count for count, _average, first in stacks), default=0)
    facts = [width, depth, -width * 128, -depth * 128, 2176, spawn_y, -4992,
             gx, gz, group_x, group_z, group_width, group_depth,
             exe_tables.LEVEL_CODES.index('JUN1'), 0x100, square_total]
    for cz in range(depth):
        for cx in range(width):
            count, average, first = stacks[cz * width + cx]
            facts.extend((count, average))
            for layer in range(count):
                at = grid + 12 + width * depth * 4 + (first + layer) * 8
                flags, polygon = struct.unpack_from('<II', data, at)
                indices = struct.unpack_from('<4H', data, polygon)
                facts.append(flags)
                for vertex in indices:
                    facts.extend(struct.unpack_from('<3h', data, vertices + 8 + vertex * 8))
    path_packet = contacts.read(data, 96, '<I')
    path_at = contacts.read(data, path_packet + 8 + path_id * 4, '<I')
    segment_count = contacts.read(data, path_at + 4, '<I')
    facts.append(segment_count)
    for si in range(segment_count):
        at = contacts.read(data, path_at + 8 + si * 4, '<I')
        kind, length = struct.unpack_from('<Ii', data, at)
        facts.extend((kind, length))
        if kind == 0:
            facts.extend(struct.unpack_from('<28i', data, at + 8))
        elif kind == 2:
            facts.extend(struct.unpack_from('<3h', data, at + 8))
            facts.extend(struct.unpack_from('<3h', data, at + 16))
        else:
            raise ValueError(f'route path segment {si} has unsupported type {kind}')
    candidate_indices = (16, 24, 25, 26, 27, 31)
    facts.append(len(candidate_indices))
    for index in candidate_indices:
        candidate_at = contacts.read(data, emtp + 12 + index * 4, '<I')
        candidate_grid, candidate_uid, candidate_form, candidate_flags = struct.unpack_from(
            '<4H', data, candidate_at)
        candidate_book = library[theme][candidate_form]
        candidate_path = struct.unpack_from('<6H', data, candidate_at + 24)
        if (candidate_grid, candidate_form, names[candidate_book['global']],
                candidate_book['script'], candidate_book['collision'],
                candidate_book['bonus'], candidate_path[0], candidate_path[3:]) != (
                1, 45, 'JUN_LOG', 0, 0, 0, 4, (8, 16, 0)):
            raise ValueError(f'route candidate {index} changed behavior')
        facts.extend((index, candidate_uid, candidate_flags,
                      candidate_path[1], candidate_path[2], candidate_path[4]))
    facts.extend((nx, nz, xofs, zofs, items[0][2], max_y, radius, book['flags']))
    facts.extend(items[0][5])
    count = contacts.read(data, emtp + 8, '<H')
    if count != 115 or hashlib.sha256(data).hexdigest() != (
            '0feb59bbb595caaeb520bcfc978203893e0da81abf6bdf18e7a088f8d175f46c'):
        raise ValueError('JUN1 admission MAP proof inputs changed')
    records = []
    for index in range(count):
        at = contacts.read(data, emtp + 12 + index * 4, '<I')
        form_grid, unique_id, form_id, flags = struct.unpack_from('<4H', data, at)
        owner = 0 if form_id & 0x8000 else theme
        resolved = library[owner][form_id & 0x7fff]
        records.append((index, at, form_grid, unique_id, form_id, flags, resolved))
    book_facts = [(i, uid, grid_id, flags, names[b['global']],
                   tuple(b[k] for k in ('entity_type', 'id', 'script', 'flags',
                                         'collision', 'radius2', 'death', 'bonus')))
                  for i, _at, grid_id, uid, _fid, flags, b in records]
    book_digest = hashlib.sha256(json.dumps(book_facts, separators=(',', ':')).encode()).hexdigest()
    if book_digest != '0b24c1ba6c7b4fd7a0be9acb51cebca50071ec582796e79b4d815bf7e282827f':
        raise ValueError('JUN1 admission form-book proof inputs changed')
    themes = exe_tables.read_theme_book(image, exe_tables.java_int(cfg.values['themeBook']))
    if themes[theme]['death_height'] != 256 or themes[0]['high_wad'] != 205:
        raise ValueError('JUN1 admission theme or GENERAL WAD changed')
    script_names, _, _ = exe_tables.name_list('scripts',
        cfg.values.get('scriptList', '1997-09-18-psx-build63'), False)
    scripts = exe_tables.read_scripts(image, exe_tables.java_int(cfg.values['scripts']),
                                      len(script_names))
    # Conservatively pin every decoded instruction stream. This includes the
    # HIPPO and CROCODILE programs, their transitive targets and callback refs.
    script_facts = [(index, script['stream']) for index, script in enumerate(scripts)]
    script_digest = hashlib.sha256(json.dumps(script_facts, separators=(',', ':')).encode()).hexdigest()
    if script_digest != '0d084966e0ab96c67a3421f4ac26ff3068a7d23efad878dcadc6bee71bb1c512':
        raise ValueError('JUN1 admission script proof inputs changed')
    numeric_books = [(i, uid, grid_id, form_id, flags, b['entity_type'], b['id'],
                      b['script'], b['flags'], b['collision'], b['radius2'],
                      b['death'], b['bonus'])
                     for i, _at, grid_id, uid, form_id, flags, b in records]
    numeric_scripts = [(index, len(script['stream']), *script['stream'])
                       for index, script in enumerate(scripts)]
    numeric_book_digest = route_numeric_digest(numeric_books)
    numeric_script_digest = route_numeric_digest(numeric_scripts)
    if numeric_book_digest != 'a986a337df0ffa2c0fe564765c3dafe183ce1d2d4cadb5480a2466e1addf826a':
        raise ValueError('JUN1 canonical form-book proof digest changed')
    if numeric_script_digest != '4598300941b69843fad8770aeef8e747b59b8792f1989b61681171f25ba591a2':
        raise ValueError('JUN1 canonical script proof digest changed')
    resolved_models = [-1 if b['flags'] & 1 else
                       wads[themes[0]['high_wad']][b['id'] - 128][0] if b['id'] >= 128
                       else wads[level['high_wad']][b['id']][0]
                       for _i, _at, _grid, _uid, _fid, _flags, b in records]
    model_ids = set(resolved_models) - {-1}
    # GENERAL checkpoint models 207–210 are incomplete MOFs using 206 as their
    # preceding complete counterpart; it must stay in the proof input closure.
    if not {206, 207, 208, 209, 210}.issubset(model_ids):
        raise ValueError('JUN1 GENERAL model counterpart closure changed')
    model_facts = sorted((model_id, hashlib.sha256(resource(files, entries, mwd, model_id)).hexdigest())
                         for model_id in model_ids)
    all_model_ids = sorted({resource_id for children in wads.values()
                            for resource_id, type_id in children if type_id in (3, 4)})
    incomplete = {}
    for model_id in all_model_ids:
        raw = resource(files, entries, mwd, model_id)
        incomplete[model_id] = (len(raw) >= 32 and raw[:4] == b'\x02FOM' and
                                struct.unpack_from('<I', raw, 28)[0] == 0x40)
    counterpart_ids = {}
    for model_id in model_ids:
        earlier = [candidate for candidate in all_model_ids
                   if candidate < model_id and not incomplete[candidate]]
        counterpart_ids[model_id] = max(earlier) if incomplete[model_id] and earlier else -1
    if {model_id: counterpart_ids[model_id] for model_id in (207, 208, 209, 210)} != {
            207: 206, 208: 206, 209: 206, 210: 206}:
        raise ValueError('JUN1 incomplete model counterpart mapping changed')
    model_digest = hashlib.sha256(json.dumps(model_facts, separators=(',', ':')).encode()).hexdigest()
    if model_digest != '61c5f0fbaa6ec6767770cdaed0856f6338a20526fdc8c339412d847becd16a5f':
        raise ValueError('JUN1 admission model proof inputs changed')

    def decoded_path(path_index):
        path = contacts.read(data, path_packet + 8 + path_index * 4, '<I')
        result = []
        for segment_index in range(contacts.read(data, path + 4, '<I')):
            at = contacts.read(data, path + 8 + segment_index * 4, '<I')
            kind, length = struct.unpack_from('<Ii', data, at)
            item = {'segment_type': kind, 'length': length}
            if kind == 0:
                values = struct.unpack_from('<28i', data, at + 8)
                item.update(matrix=list(values[:12]), smooth_t=list(values[12:16]),
                            smooth_c=list(values[16:]))
            elif kind == 1:
                item.update(start=list(struct.unpack_from('<3h', data, at + 8)),
                            centre=list(struct.unpack_from('<3h', data, at + 16)),
                            normal=list(struct.unpack_from('<3h', data, at + 24)),
                            radius=contacts.read(data, at + 32, '<i'),
                            pitch=contacts.read(data, at + 36, '<i'))
            elif kind == 2:
                item.update(start=list(struct.unpack_from('<3h', data, at + 8)),
                            end=list(struct.unpack_from('<3h', data, at + 16)))
            else:
                raise ValueError(f'unsupported JUN1 path type {kind}')
            result.append(item)
        return result

    path_definitions = [decoded_path(i) for i in range(contacts.read(data, path_packet + 4, '<I'))]
    facts.append(count)
    selected_trace = None
    candidate_traces = {}
    for index, at, _grid, unique_id, _form_id, flags, resolved in records:
        if flags & 1:
            raise ValueError(f'JUN1 entity {index} gained HIDDEN flag')
        if index in candidate_indices:
            reason = 0
        elif resolved['flags'] & 1:
            if resolved['collision']:
                raise ValueError(f'NO_MODEL entity {index} gained a callback')
            reason = 1
        elif index == 0:
            reason = 3
        elif index in (18, 20, 21, 22, 23):
            reason = 4
        elif index in (109, 110):
            reason = 5
        else:
            reason = 2
        facts.extend((index, unique_id, flags, resolved['entity_type'], reason))
        if index < 37:
            path_index, segment, distance, motion, speed, padding = struct.unpack_from('<6H', data, at + 24)
            if padding or motion not in (0, 8):
                raise ValueError(f'JUN1 moving runner {index} changed start flags')
            trace = paths.python_trace({'segments': path_definitions[path_index],
                                        'start': {'segment_index': segment, 'distance': distance,
                                                  'speed': speed, 'flags': motion | 1},
                                        'tick_limit': 60})
            positions = [row[9:12] for row in trace[1:]]
            if index in candidate_indices:
                candidate_traces[index] = trace
            if index == 24:
                selected_trace = trace
        else:
            position = struct.unpack_from('<3i', data, at + 24 + 20)
            positions = [position] * 60
        for position in positions:
            facts.extend(position)
    text = '\n'.join(map(str, facts)) + '\n'
    if not return_context:
        return text
    return_flags, return_points = square(22, 9)
    return_y = sum(point[1] for point in return_points) >> 2
    if not return_flags & 3 == 3 or return_y != -180:
        raise ValueError('JUN1 return bank changed')
    zone_packet = contacts.read(data, 92, '<I')
    zone_count = contacts.read(data, zone_packet + 4, '<I')
    if zone_count != 18:
        raise ValueError('JUN1 zone count changed')
    zones = []
    zone_records = []
    for index in range(zone_count):
        at = contacts.read(data, zone_packet + 8 + index * 4, '<I')
        zone_type, region_count, xmin, zmin, xmax, zmax, regions_at = struct.unpack_from(
            '<6HI', data, at)
        regions = [struct.unpack_from('<4h', data, regions_at + 8 * ri)
                   for ri in range(region_count)]
        zones.append((zone_type, (xmin, zmin, xmax, zmax), regions))
        camera_flags, camera_direction = struct.unpack_from('<Hh', data, at + 16)
        camera_offsets = [struct.unpack_from('<3h', data, at + 20 + 8 * vi)
                          for vi in range(8)]
        zone_records.append((index, at, zone_type, region_count,
                             (xmin, zmin, xmax, zmax), regions_at, camera_flags,
                             camera_direction, camera_offsets, regions))
    admission = dict(schema='jun1-route-admission-v1', build=version, map_resource_id=656,
                     map_sha256=hashlib.sha256(data).hexdigest(),
                     form_book_rows_sha256=numeric_book_digest,
                     script_rows_sha256=numeric_script_digest,
                     model_resources=[{'resource_id': model_id, 'sha256': digest,
                                       'counterpart_resource_id': counterpart_ids[model_id]}
                                      for model_id, digest in model_facts],
                     entity_model_resources=resolved_models,
                     numeric_digest_encoding='ASCII decimal integers separated by commas, LF after each row',
                     theme_index=theme, theme_death_height=themes[theme]['death_height'],
                     general_high_wad=themes[0]['high_wad'],
                     candidate_indices=list(candidate_indices),
                     excluded_indices=[i for i in range(count) if i not in candidate_indices],
                     admitted_x=[1900, 2304], admitted_z=[-5376, -4864],
                     source_pad_masks={'world_west': 1, 'world_east': 2},
                     normalized_command_masks={'world_west': 8, 'world_east': 2})
    supported_indices = [index for index, _at, _grid, _uid, _fid, flags, b in records
                         if b['entity_type'] in (0, 1) and not flags & ~127 and
                         not flags & (32 | 64)]
    return text, dict(selected_trace=selected_trace, form=(nx, nz, xofs, zofs,
                       items[0][2], max_y, radius), approach_y=approach_y,
                       start_y=spawn_y, return_y=return_y,
                       candidate_traces=candidate_traces, zones=zones,
                       zone_records=zone_records,
                       admission=admission, supported_indices=supported_indices)


def verify_route_trace(context, trace_path):
    """Check the retail frog route using Python PATH/matrix and source arithmetic."""
    lines = trace_path.read_text(encoding='ascii').splitlines()
    header = next((i for i, line in enumerate(lines) if line.startswith('tick,phase,')), None)
    if header is None:
        raise ValueError('frozen route CSV header missing')
    decoded = list(csv.DictReader(lines[header:]))
    rows = {(int(row['tick']), row['phase']): row for row in decoded}
    if len(rows) != len(decoded):
        raise ValueError('frozen route contains duplicate phase rows')
    if len(rows) != 360:
        raise ValueError(f'frozen route has {len(rows)} rows, expected 360')

    def check(tick, phase, **expected):
        row = rows[tick, phase]
        for field, wanted in expected.items():
            actual = int(row[field])
            if actual != wanted:
                raise ValueError(f'route tick {tick} {phase} {field}: C {actual}, Python {wanted}')

    def apply(matrix, point):
        return [sum(matrix[axis * 3 + column] * point[column]
                    for column in range(3)) >> 12 for axis in range(3)]

    def local(matrix, delta):
        return [sum(matrix[axis * 3 + column] * delta[axis]
                    for axis in range(3)) >> 12 for column in range(3)]

    def entity_pose(tick):
        path = context['selected_trace'][tick + 1]
        return entities.moving_matrix(path, 0)

    gravity = 1048576
    pos = [2176 << 16, context['start_y'] << 16, -4992 << 16]
    target = [1920, context['approach_y'], -4992]
    velocity = [div_zero((target[0] << 16) - pos[0], 6),
                div_zero((target[1] - (pos[1] >> 16)) << 16, 7) - ((gravity * 7) >> 1), 0]
    check(0, 'control', input=3, pad_mask=1, direction=3, count=6, vx16=velocity[0],
          vy16=velocity[1], vz16=0, x16=pos[0], y16=pos[1], z16=pos[2])
    for tick in range(4):
        velocity[1] += gravity
        pos = [pos[axis] + velocity[axis] for axis in range(3)]
        check(tick, 'move', x16=pos[0], y16=pos[1], z16=pos[2],
              attached=-1, count=5 - tick)
        if tick < 3:
            check(tick, 'collision', x16=pos[0], y16=pos[1], z16=pos[2], attached=-1)

    matrix = entity_pose(3)
    delta = [(value >> 16) - matrix[9 + axis] for axis, value in enumerate(pos)]
    frog_local = local(matrix, delta)
    nx, nz, xofs, zofs, height, max_y, radius2 = context['form']
    if sum(value * value for value in delta) >= radius2:
        raise ValueError('independent landing sphere missed')
    if not (xofs < frog_local[0] < xofs + nx * 256 and
            zofs < frog_local[2] < zofs + nz * 256 and
            height <= frog_local[1] <= max_y):
        raise ValueError(f'independent landing FORM missed: {frog_local}')
    cell_x, cell_z = (frog_local[0] - xofs) >> 8, (frog_local[2] - zofs) >> 8
    centre = [xofs + cell_x * 256 + 128, height, zofs + cell_z * 256 + 128]
    distance = sum((centre[axis] - frog_local[axis]) ** 2 for axis in range(3))
    import math
    centring_ticks = math.isqrt(distance) // 15 + 1
    if centring_ticks != 8:
        raise ValueError(f'independent centring duration {centring_ticks}')
    offset = [frog_local[0] << 16, height << 16, frog_local[2] << 16]
    mounted = [value << 16 for value in
               [matrix[9 + axis] + apply(matrix, [offset[j] >> 16 for j in range(3)])[axis]
                for axis in range(3)]]
    if not (1900 <= mounted[0] >> 16 < 2304 and -5376 <= mounted[2] >> 16 < -4864):
        raise ValueError('independent correction escaped admission rectangle')
    check(3, 'collision', x16=mounted[0], y16=mounted[1], z16=mounted[2],
          attached=24, mode=5, count=8)
    landing_mounted = mounted[:]
    step = [div_zero((centre[axis] << 16) - offset[axis], centring_ticks)
            for axis in range(3)]
    for tick in range(4, 12):
        if tick == 11:
            offset = [value << 16 for value in centre]
        else:
            offset = [offset[axis] + step[axis] for axis in range(3)]
        matrix = entity_pose(tick)
        transformed = apply(matrix, [value >> 16 for value in offset])
        mounted = [(matrix[9 + axis] + transformed[axis]) << 16 for axis in range(3)]
        check(tick, 'move', x16=mounted[0], y16=mounted[1], z16=mounted[2],
              attached=24, count=11 - tick)
        check(tick, 'collision', x16=mounted[0], y16=mounted[1], z16=mounted[2], attached=24)

    departure_start = mounted[:]
    target = [2176, context['return_y'], -5248]
    velocity = [div_zero((target[0] << 16) - departure_start[0], 6),
                div_zero((target[1] - (departure_start[1] >> 16)) << 16, 7) - ((gravity * 7) >> 1),
                div_zero((target[2] << 16) - departure_start[2], 6)]
    check(12, 'control', input=1, pad_mask=2, direction=1, attached=24, count=6,
          vx16=velocity[0], vy16=velocity[1], vz16=velocity[2])
    pos = departure_start
    for tick in range(12, 18):
        if tick == 17:
            pos = [value << 16 for value in target]
        else:
            velocity[1] += gravity
            pos = [pos[axis] + velocity[axis] for axis in range(3)]
        check(tick, 'move', x16=pos[0], y16=pos[1], z16=pos[2])
        check(tick, 'collision', x16=pos[0], y16=pos[1], z16=pos[2],
              attached=24 if tick < 17 else -1)
    for tick in range(18, 60):
        for phase in ('control', 'move', 'collision', 'camera', 'scripts', 'pose'):
            check(tick, phase, x16=pos[0], y16=pos[1], z16=pos[2], attached=-1)
    hits = [(tick, row['hit_indices']) for (tick, phase), row in rows.items()
            if phase == 'collision' and row['hit_indices'] != '-']
    if hits != [(3, '24')]:
        raise ValueError(f'unexpected collision hits: {hits}')
    for tick in range(60):
        row = rows[tick, 'move']
        frog_point = [int(row[field]) >> 16 for field in ('x16', 'y16', 'z16')]
        attached = int(row['attached'])
        forbidden = int(row['forbidden'])
        order = [int(value) for value in rows[tick, 'collision']['contact_order'].split(';')]
        for index in order:
            if index not in context['candidate_traces'] or index in (attached, forbidden):
                continue
            matrix = entities.moving_matrix(context['candidate_traces'][index][tick + 1], 0)
            delta = [frog_point[axis] - matrix[9 + axis] for axis in range(3)]
            if sum(value * value for value in delta) >= radius2:
                continue
            candidate_local = local(matrix, delta)
            contact = (xofs < candidate_local[0] < xofs + nx * 256 and
                       zofs < candidate_local[2] < zofs + nz * 256 and
                       height <= candidate_local[1] <= max_y)
            if contact:
                if (tick, index) != (3, 24):
                    raise ValueError(f'unexpected eligible FORM query tick {tick} entity {index}')
                frog_point = [value >> 16 for value in landing_mounted]
                if not (1900 <= frog_point[0] < 2304 and -5376 <= frog_point[2] < -4864):
                    raise ValueError('intermediate FORM correction escaped admission rectangle')
        cell_x, cell_z = int(row['grid_x']), int(row['grid_z'])
        for zone_index, (_zone_type, (zx0, zz0, zx1, zz1), regions) in enumerate(context['zones']):
            if zx0 <= cell_x <= zx1 and zz0 <= cell_z <= zz1:
                if not regions or any(rx0 <= cell_x <= rx1 and rz0 <= cell_z <= rz1
                                      for rx0, rz0, rx1, rz1 in regions):
                    raise ValueError(f'route entered zone {zone_index} at tick {tick}')
    for (tick, phase), row in rows.items():
        check(tick, phase, controller_n=0, controller_e=1,
              controller_s=2, controller_w=3, game_mode=10)
    print('Independent Python/frozen C JUN1 route matches through 60 ticks.')


ROUTE_GOLDEN_FIELDS = (
    'tick', 'phase', 'command', 'x16', 'y16', 'z16', 'vx16', 'vy16', 'vz16',
    'grid_x', 'grid_z', 'flags', 'mode', 'attached', 'count', 'direction', 'input',
    'entity_x', 'entity_y', 'entity_z', 'segment', 'distance',
    'camera_x', 'camera_y', 'camera_z', 'controller_n', 'controller_e',
    'controller_s', 'controller_w', 'old_y', 'entity_cell_x', 'entity_cell_z',
    'forbidden', 'entity_flags', 'game_mode', 'pad_mask', 'contact_order',
    'candidate_order', 'supported_order',
    'hit_indices',
)


def route_golden_content(trace_path, context):
    """Keep validated movement, contact and camera facts from the C trace."""
    lines = trace_path.read_text(encoding='ascii').splitlines()
    header = next(i for i, line in enumerate(lines) if line.startswith('tick,phase,'))
    source = list(csv.DictReader(lines[header:]))
    by_phase = {(int(row['tick']), row['phase']): row for row in source}
    output = io.StringIO(newline='')
    writer = csv.writer(output, delimiter='\t', lineterminator='\n')
    writer.writerow(ROUTE_GOLDEN_FIELDS)
    candidates = {16, 24, 25, 26, 27, 31}
    supported = set(context['supported_indices'])
    for row in source:
        tick = int(row['tick'])
        candidate_order = ';'.join(value for value in row['contact_order'].split(';')
                                   if value != '-' and int(value) in candidates) or '-'
        movement = by_phase[tick, 'move']
        skipped = {int(movement['attached']), int(movement['forbidden'])}
        supported_order = ';'.join(value for value in row['contact_order'].split(';')
                                   if value != '-' and int(value) in supported and
                                   int(value) not in skipped) or '-'
        facts = dict(row, command=8 if tick == 0 else 2 if tick == 12 else 0,
                     candidate_order=candidate_order, supported_order=supported_order)
        writer.writerow([facts[field] for field in ROUTE_GOLDEN_FIELDS])
    return output.getvalue()


def zone_queries(context):
    """Exhaustively query both zone types over every JUN1 terrain cell."""
    if 'queries' in context:
        return context['queries']
    return [(x, z, zone_type) for zone_type in (0, 1)
            for z in range(60) for x in range(28)]


def zone_records_content(context):
    """Capture all 18 authored ZONE records, including unused camera payload."""
    output = io.StringIO(newline='')
    writer = csv.writer(output, delimiter='\t', lineterminator='\n')
    fields = ['zone_index', 'source_offset', 'zone_type', 'region_count',
              'xmin', 'zmin', 'xmax', 'zmax', 'region_pointer',
              'camera_flags', 'camera_direction']
    for index in range(8):
        fields.extend(f'camera_{index}_{axis}' for axis in ('x', 'y', 'z'))
    fields.extend(('region_offsets', 'region_bounds'))
    writer.writerow(fields)
    if len(context['zone_records']) != 18:
        raise ValueError('JUN1 authored ZONE record count changed')
    for (index, offset, kind, count, bounds, pointer, flags, direction,
         camera_offsets, regions) in context['zone_records']:
        writer.writerow([index, offset, kind, count, *bounds, pointer, flags, direction,
                         *(axis for vector in camera_offsets for axis in vector),
                         ';'.join(str(pointer + 8 * i) for i in range(count)) or '-',
                         ';'.join(','.join(map(str, region)) for region in regions) or '-'])
    return output.getvalue()


def synthetic_zone_context(path):
    data = json.loads(path.read_text(encoding='utf-8'))
    zones = [(int(item['type']), tuple(item['bounds']), [tuple(row) for row in item['regions']])
             for item in data['zones']]
    queries = [tuple(row) for row in data['queries']]
    if not zones or any(len(bounds) != 4 or any(len(region) != 4 for region in regions)
                        for _kind, bounds, regions in zones) or any(len(row) != 3 for row in queries):
        raise ValueError('synthetic zone fixture shape invalid')
    return {'zones': zones, 'queries': queries}


def zone_fixture_content(context):
    facts = [len(context['zones'])]
    for zone_type, bounds, regions in context['zones']:
        facts.extend((zone_type, len(regions), *bounds))
        for region in regions:
            facts.extend(region)
    queries = zone_queries(context)
    facts.append(len(queries))
    for query in queries:
        facts.extend(query)
    return '\n'.join(map(str, facts)) + '\n'


def zone_golden_content(context, trace_path):
    """Match unchanged CheckCoordsInZones against independent inclusive bounds."""
    lines = trace_path.read_text(encoding='ascii').splitlines()
    header = next(i for i, line in enumerate(lines) if line.startswith('query,x,z,type,'))
    rows = list(csv.DictReader(lines[header:]))
    queries = zone_queries(context)
    if len(rows) != len(queries):
        raise ValueError(f'zone oracle returned {len(rows)} rows, expected {len(queries)}')
    output = io.StringIO(newline='')
    writer = csv.writer(output, delimiter='\t', lineterminator='\n')
    fields = ('query', 'x', 'z', 'type', 'found', 'zone_index', 'region_index')
    writer.writerow(fields)
    for number, ((x, z, zone_type), row) in enumerate(zip(queries, rows)):
        expected = (number, x, z, zone_type, 0, -1, -1)
        for zone_index, (actual_type, (xmin, zmin, xmax, zmax), regions) in enumerate(context['zones']):
            if actual_type != zone_type or not (xmin <= x <= xmax and zmin <= z <= zmax):
                continue
            if not regions:
                expected = (number, x, z, zone_type, -1, zone_index, -1)
                break
            match = next((i for i, (rxmin, rzmin, rxmax, rzmax) in enumerate(regions)
                          if rxmin <= x <= rxmax and rzmin <= z <= rzmax), None)
            if match is not None:
                expected = (number, x, z, zone_type, -1, zone_index, match)
                break
        actual = tuple(int(row[field]) for field in fields)
        if actual != expected:
            raise ValueError(f'zone query {number} C {actual}, Python {expected}')
        writer.writerow(expected)
    return output.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', type=Path)
    parser.add_argument('--version', default='pc-retail-v3.0e')
    parser.add_argument('--output', type=Path,
        default=Path('tests/golden/pc-retail-v3.0e/platform_retail.tsv'))
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--route-fixture', type=Path,
                        help='Write decoded numeric JUN1 route input outside the repository')
    parser.add_argument('--route-trace', type=Path,
                        help='Compare a frozen-C JUN1 CSV trace with independent Python route arithmetic')
    parser.add_argument('--route-admission', type=Path,
                        help='Write compact proof-input fingerprint manifest')
    parser.add_argument('--route-golden', type=Path,
                        help='Write validated JUN1 movement/contact/camera TSV from --route-trace')
    parser.add_argument('--zones-fixture', type=Path,
                        help='Write numeric all-cell JUN1 zone queries outside the repositories')
    parser.add_argument('--zones-trace', type=Path,
                        help='Frozen CheckCoordsInZones CSV from --zones-fixture')
    parser.add_argument('--zones-golden', type=Path,
                        help='Write independently checked JUN1 zone TSV from --zones-trace')
    parser.add_argument('--zones-records-golden', type=Path,
                        help='Write all authored JUN1 ZONE record facts')
    parser.add_argument('--zones-synthetic-case', type=Path,
                        help='Use invented zone regions and queries instead of retail JUN1')
    args = parser.parse_args()
    if args.zones_fixture or args.zones_trace or args.zones_records_golden:
        if args.zones_synthetic_case:
            context = synthetic_zone_context(args.zones_synthetic_case)
        else:
            if args.data_dir is None:
                raise ValueError('retail zone generation requires --data-dir')
            _facts, context = route_fixture(args.data_dir, args.version, return_context=True)
        if args.zones_fixture:
            destination = args.zones_fixture.resolve()
            project = Path(__file__).resolve().parent.parent
            if destination.is_relative_to(project) or destination.is_relative_to(project.parent / 'froggy'):
                raise ValueError('zone fixture must be written outside both repositories')
            content = zone_fixture_content(context)
            if args.verify:
                if args.zones_fixture.read_text(encoding='ascii') != content:
                    raise ValueError('JUN1 zone input differs from retail data')
            else:
                args.zones_fixture.parent.mkdir(parents=True, exist_ok=True)
                args.zones_fixture.write_text(content, encoding='ascii')
        if args.zones_trace:
            content = zone_golden_content(context, args.zones_trace)
            if args.zones_golden:
                if args.verify:
                    if args.zones_golden.read_text(encoding='ascii') != content:
                        raise ValueError('JUN1 zone golden differs from C/Python')
                else:
                    args.zones_golden.parent.mkdir(parents=True, exist_ok=True)
                    args.zones_golden.write_text(content, encoding='ascii')
            print(('Synthetic' if args.zones_synthetic_case else 'JUN1 all-cell') +
                  ' zone queries match frozen C and Python.')
        if args.zones_records_golden:
            if args.zones_synthetic_case:
                raise ValueError('authored ZONE records require retail JUN1')
            content = zone_records_content(context)
            if args.verify:
                if args.zones_records_golden.read_text(encoding='ascii') != content:
                    raise ValueError('JUN1 authored ZONE record golden differs')
            else:
                args.zones_records_golden.parent.mkdir(parents=True, exist_ok=True)
                args.zones_records_golden.write_text(content, encoding='ascii')
            print('JUN1 authored ZONE records match independent decoder.')
        return
    if args.data_dir is None:
        raise ValueError('--data-dir is required outside synthetic zone cases')
    if args.route_admission:
        _facts, context = route_fixture(args.data_dir, args.version, return_context=True)
        content = json.dumps(context['admission'], indent=2) + '\n'
        if args.verify:
            if args.route_admission.read_text(encoding='ascii') != content:
                raise ValueError('JUN1 proof-input manifest differs from retail data')
            print('JUN1 proof-input manifest verified.')
        else:
            args.route_admission.parent.mkdir(parents=True, exist_ok=True)
            args.route_admission.write_text(content, encoding='ascii')
            print('Decoded JUN1 proof-input manifest written.')
        return
    if args.route_trace:
        _facts, context = route_fixture(args.data_dir, args.version, return_context=True)
        verify_route_trace(context, args.route_trace)
        if args.route_golden:
            content = route_golden_content(args.route_trace, context)
            if args.verify:
                if args.route_golden.read_text(encoding='ascii') != content:
                    raise ValueError('JUN1 route golden differs from frozen C/Python proof')
                print('JUN1 route golden verified.')
            else:
                args.route_golden.parent.mkdir(parents=True, exist_ok=True)
                args.route_golden.write_text(content, encoding='ascii')
                print('JUN1 route golden written.')
        return
    if args.route_golden:
        raise ValueError('--route-golden requires --route-trace')
    if args.route_fixture:
        destination = args.route_fixture.resolve()
        project = Path(__file__).resolve().parent.parent
        reference = project.parent / 'froggy'
        if destination.is_relative_to(project) or destination.is_relative_to(reference):
            raise ValueError('route fixture must be written outside both repositories')
        args.route_fixture.parent.mkdir(parents=True, exist_ok=True)
        args.route_fixture.write_text(route_fixture(args.data_dir, args.version), encoding='ascii')
        print('Decoded JUN1 bank-route facts written for frozen-C oracle.')
        return
    out = io.StringIO(newline='')
    writer = csv.writer(out, delimiter='\t', lineterminator='\n')
    writer.writerow(HEADER)
    writer.writerow(row(args.data_dir, args.version))
    content = out.getvalue().encode('utf-8')
    if args.verify:
        if args.output.read_bytes() != content:
            raise ValueError('JUN1 retail platform golden differs')
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(content)
    print('Independent JUN1 SAFE platform facts match; one selected entity and first contact.')


if __name__ == '__main__':
    main()

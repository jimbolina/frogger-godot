#!/usr/bin/env python3
"""Decode the selected JUN1 SAFE log and its first source-arithmetic contact.

Reads the owner's retail EXE/MWI/MWD/MOF/MAP; emits decimal text facts only.
"""
import argparse
import csv
import io
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', type=Path, required=True)
    parser.add_argument('--version', default='pc-retail-v3.0e')
    parser.add_argument('--output', type=Path,
        default=Path('tests/golden/pc-retail-v3.0e/platform_retail.tsv'))
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
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

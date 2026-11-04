#!/usr/bin/env python3
"""Decode SWP1–SWP5 custom-entity payloads, script registers, models, primitives, callbacks and FORM squares.

Reads FROGGER.EXE, its MWI and FROGPSX.MWD; emits decimal text facts only.
"""
import argparse
import collections
import csv
import io
import os
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT
from tools.golden import make_golden_cave_lights as cave_lights
from tools.golden import make_golden_collprims as collprims
from tools.golden import make_golden_desert_entities as desert_entities
from tools.golden import make_golden_entities as entities
from tools.golden import make_golden_exe_tables as exe_tables
from tools.golden import make_golden_form_contacts as form_contacts
from tools.golden import make_golden_jungle_entities as jungle_entities
from tools.golden import make_golden_mof as mof
from tools.golden import make_golden_swamp as swamp

OUTPUT = REPO_ROOT / 'tests/golden/pc-retail-v3.0e/swamp_entities.tsv'
LEVELS = ('SWP1', 'SWP2', 'SWP3', 'SWP4', 'SWP5')
SWAMP_THEME = 7
FORMS = ('SWP_SQUIRT', 'SWP_CRUSHER', 'SWP_CRUSHER2', 'SWP_PRESS', 'SWP_RAT', 'SWP_SLUG', 'SWP_NUCLEAR_BARREL',
         'SWP_STAT_WEIR', 'SWP_STAT_WASTE_BARREL')
PAYLOAD_SIZES = {'SWP_SQUIRT': 44, 'SWP_CRUSHER': 40, 'SWP_PRESS': 40, 'SWP_RAT': 68, 'SWP_SLUG': 16,
                 'NUCLEAR_BARREL': 20, 'SWP_STAT_WEIR': 32, 'DYNAMIC': 36}
PATH_KINDS = ('SWP_SLUG', 'NUCLEAR_BARREL')
ACTION_FORMS = ('SWP_RAT', 'SWP_SLUG')
PRIMITIVE_FORMS = ('SWP_CRUSHER', 'SWP_CRUSHER2', 'SWP_PRESS')
FORM_GRID_FORMS = ('SWP_CRUSHER', 'SWP_CRUSHER2', 'SWP_PRESS')
CALLBACK_FORMS = ('SWP_CRUSHER', 'SWP_CRUSHER2', 'SWP_PRESS')
CALLBACK_ADDRESS = jungle_entities.DOOR_CALLBACK
CALLBACK_NAME = jungle_entities.DOOR_CALLBACK_NAME
PROJECT_MAX_THEME_MOFS = 128
FORM_BOOK_THICK_FORM, FORM_BOOK_UNIT_FORM = 1 << 5, 1 << 9
HEADER = desert_entities.HEADER
fields = desert_entities.fields
SCRIPT_NAMES = exe_tables.name_list('scripts', swamp.SCRIPT_LIST, False)[0]


def instructions(stream):
    """Split a decoded script stream into (opcode, operands) by FrogLord's opcode widths."""
    at, out = 0, []
    while at < len(stream):
        opcode = stream[at]
        width = swamp.WIDTHS[opcode]
        out.append((opcode, stream[at + 1:at + width]))
        at += width
    return out


def prepared_registers(scripts, root):
    """The PREPARE_REGISTERS operands reachable from a root through SCRIPT_IF and START_SCRIPT targets."""
    seen, pending, prepared = set(), [root], []
    while pending:
        script = pending.pop()
        if script in seen or not 0 <= script < len(scripts):
            continue
        seen.add(script)
        for opcode, operands in instructions(scripts[script]['stream']):
            name = exe_tables.OPCODES[opcode][0]
            if name == 'PREPARE_REGISTERS':
                prepared.append(tuple(operands))
            elif name == 'SCRIPT_IF':
                pending.append(operands[2])
            elif name == 'START_SCRIPT':
                pending.append(operands[0])
    if len(set(prepared)) > 1:
        raise ValueError(f'script {root} prepares conflicting registers {prepared}')
    return prepared[0] if prepared else None


def payload(entity, data, start, end, name, index):
    """Kind-specific operands following the 24-byte entity header."""
    size = end - start
    if size < PAYLOAD_SIZES[entity]:
        raise ValueError(f'{name}: short {entity} payload at entity {index}')
    if entity in PATH_KINDS:
        path_id, segment, distance, motion, speed, pad = struct.unpack_from('<6H', data, start)
        out = dict(path_id=path_id, segment_id=segment, segment_dist=distance, motion=motion, speed=speed,
                   path_pad=pad)
        if entity == 'SWP_SLUG':
            out['motion_type'], = struct.unpack_from('<I', data, start + 12)
        return out
    rotation = list(struct.unpack_from('<9h', data, start))
    translation = list(struct.unpack_from('<3i', data, start + 20))
    matrix = rotation + translation
    out = dict(matrix=matrix)
    if entity == 'SWP_SQUIRT':
        delay, drop, x, y, z, pad = struct.unpack_from('<6h', data, start + 32)
        out.update(time_delay=delay, drop_time=drop, target=[x, y, z], target_pad=pad)
    elif entity in ('SWP_CRUSHER', 'SWP_PRESS'):
        out.update(zip(('speed', 'distance', 'direction', 'delay'), struct.unpack_from('<4h', data, start + 32)))
    elif entity == 'SWP_RAT':
        speed, pad = struct.unpack_from('<2h', data, start + 32)
        targets = [struct.unpack_from('<4h', data, start + 36 + 8 * i) for i in range(4)]
        out.update(speed=speed, speed_pad=pad, target_x=[t[0] for t in targets], target_y=[t[1] for t in targets],
                   target_z=[t[2] for t in targets], target_pad=[t[3] for t in targets])
        resolved = swamp.rat_timing(speed, [list(t[:3]) for t in targets])
        out.update((key, resolved[key]) for key in ('run_speed', 'jump1_time', 'jump1_velocity_4', 'jump1_sine_step',
                                                     'run_time', 'run_velocity_4', 'jump2_time', 'jump2_velocity_4',
                                                     'jump2_sine_step'))
    elif entity == 'SWP_STAT_WEIR':
        out['weir_matrix'] = swamp.weir_matrix(matrix)
    return out


def runtime_max_y(form, model):
    """mapload.C: FORM_BOOK_THICK_FORM gives 0x7fff, FORM_BOOK_UNIT_FORM 0x100, else the first part's bbox vertex 7 Y."""
    if form['flags'] & FORM_BOOK_THICK_FORM:
        return 0x7fff
    if form['flags'] & FORM_BOOK_UNIT_FORM:
        return 0x100
    if model['kind'] != 'static':
        raise ValueError(f'{form["name"]} needs the animated global bounding box')
    return model['statics'][0]['parts'][0]['partcel_list'][0]['box'][22]


def map_rows(resource_id, name, data, forms, scripts, model_for):
    packets = entities.packet_offsets(data)
    theme = entities.number(data, packets['GENE'] + 10, '<H')
    at = packets['EMTP']
    packet_end = at + entities.number(data, at + 4, '<I')
    count = entities.number(data, at + 8, '<H')
    pointers = [entities.number(data, at + 12 + 4 * i, '<I') for i in range(count)]
    map_forms = form_contacts.parse_forms(data)
    rows, census, grids, users = [], collections.Counter(), {}, collections.defaultdict(list)
    for index, start in enumerate(pointers):
        end = min((p for p in pointers if p > start), default=packet_end)
        grid_id, unique_id, form_id, entity_flags = struct.unpack_from('<4H', data, start)
        owner = 0 if form_id & 0x8000 else theme
        library = forms.get(owner, [])
        form = library[form_id & 0x7fff] if (form_id & 0x7fff) < len(library) else None
        if form is None:
            raise ValueError(f'{name}: entity {index} has an unknown form {form_id}')
        census[(form['entity'], form['name'], entity_flags)] += 1
        users[grid_id].append(form)
        if form['name'] not in FORMS:
            continue
        operands = payload(form['entity'], data, start + 24, end, name, index)
        prepared = prepared_registers(scripts, form['script'])
        registers = dict(root_script=SCRIPT_NAMES[form['script']], register_offset=-1, registers=[])
        if prepared is not None:
            offset, words = prepared
            if end - start - 24 < offset + 4 * words:
                raise ValueError(f'{name}: entity {index} payload is shorter than its prepared registers')
            registers.update(register_offset=offset,
                             registers=list(struct.unpack_from(f'<{words}i', data, start + 24 + offset)))
        rows.append(('entity', resource_id, name, index, unique_id, form['entity'],
                     fields(form=form['name'], form_id=form_id, mof_id=form['id'], form_grid_id=grid_id,
                            entity_flags=entity_flags, form_flags=form['flags'], death=form['death'],
                            death_name=exe_tables.DEATH_TYPES[form['death']], script=form['script'],
                            payload_bytes=end - start - 24, **desert_entities.form_grid(map_forms, grid_id),
                            **registers, **operands)))
        if form['name'] in FORM_GRID_FORMS and grid_id not in grids:
            grids[grid_id] = form['name']
    maxima = {}
    for grid_id in grids:
        values = {runtime_max_y(form, model_for(form)) for form in users[grid_id]}
        if len(values) != 1:
            raise ValueError(f'{name}: FORM {grid_id} receives runtime maxima {sorted(values)}')
        maxima[grid_id] = values.pop()
    for grid_id in sorted(grids):
        _, _, datas, max_y, nx, nz, xofs, zofs, items = map_forms[grid_id]
        flags = items[0][5] if items else []
        rows.append(('form_grid', resource_id, name, -1, -1, grids[grid_id],
                     fields(form_grid_id=grid_id, form_xnum=nx, form_znum=nz, form_xofs=xofs, form_zofs=zofs,
                            form_max_y=max_y, runtime_max_y=maxima[grid_id], form_datas=datas, height=items[0][2] if items else 0,
                            grid_flags=flags, deadly=sum(1 for f in flags if f & swamp.GRID_SQUARE_DEADLY),
                            usable=sum(1 for f in flags if f & swamp.GRID_SQUARE_USABLE))))
    for (entity, form_name, flags), total in sorted(census.items()):
        rows.append(('census', resource_id, name, -1, -1, entity, fields(form=form_name, entity_flags=flags, count=total)))
    return rows


def model_slot(form, level, themes, detail):
    if form['id'] >= PROJECT_MAX_THEME_MOFS:
        return themes[0][detail + '_wad'], form['id'] - PROJECT_MAX_THEME_MOFS
    return level[detail + '_wad'], form['id']


def model_rows(levels, themes, forms, entries, wads, files):
    rows, seen_actions, seen_prims = [], set(), set()
    swamp_forms = {form['name']: form for form in forms[SWAMP_THEME]}
    for code in LEVELS:
        level = levels[exe_tables.LEVEL_CODES.index(code)]
        for detail in ('high', 'low'):
            for form_name in ACTION_FORMS + PRIMITIVE_FORMS:
                form = swamp_forms[form_name]
                wad, slot = model_slot(form, level, themes, detail)
                rid = wads[wad][slot][0]
                if mof.file_name(entries, rid) == 'NULL':
                    continue
                if form_name in ACTION_FORMS and rid not in seen_actions:
                    seen_actions.add(rid)
                    kind, lengths = desert_entities.action_lengths(files[rid])
                    rows.append(('actions', rid, mof.file_name(entries, rid), -1, -1, form['entity'],
                                 fields(form=form_name, mof_id=form['id'], detail=detail, wad=wad, slot=slot,
                                        kind=kind, lengths=lengths)))
                if form_name in PRIMITIVE_FORMS and rid not in seen_prims:
                    seen_prims.add(rid)
                    rows.extend(primitive_rows(rid, mof.file_name(entries, rid), files[rid], form, detail))
    return rows


def primitive_rows(rid, name, blob, form, detail):
    model = mof.parse_model(blob, name, None, [])
    if model['incomplete'] or model['kind'] != 'static':
        raise ValueError(f'{name} is not a complete static model')
    rows = []
    for part_index, part in enumerate(model['statics'][0]['parts']):
        prims, _ = collprims.own_part(blob, 0, part)
        for index, (kind, flags, ox, oy, oz, radius2, sx, sy, sz, user, matrix_index) in enumerate(prims):
            rows.append(('collprim', rid, name, -1, -1, form['entity'],
                         fields(form=form['name'], detail=detail, part=part_index, primitive=index, type=kind,
                                flags=flags, offset=[ox, oy, oz], radius_squared=radius2, extents=[sx, sy, sz],
                                user=user, matrix_index=matrix_index)))
    return rows


def callback_rows(exe, forms):
    """The FORM collision callbacks of the Swamp hazards; 0x4241C0 must be exactly frozen formlib.C's users."""
    users = sorted(form['name'] for library in forms.values() for form in library
                   if form['collision'] == CALLBACK_ADDRESS)
    if users != sorted(jungle_entities.DOOR_CALLBACK_FORMS):
        raise ValueError(f'{CALLBACK_ADDRESS:#x} is used by {users}, not the formlib.C {CALLBACK_NAME} forms')
    rows = []
    for form in forms[SWAMP_THEME]:
        if form['name'] not in CALLBACK_FORMS:
            continue
        address = form['collision']
        rows.append(('callback', -1, 'FROGGER.EXE', -1, -1, form['entity'],
                     fields(form=form['name'], address=f'{address:#x}',
                            callback=CALLBACK_NAME if address == CALLBACK_ADDRESS else '-',
                            file_offset=jungle_entities.file_offset(exe, address) if address else -1)))
    return rows


def rows(data_dir, version):
    cfg = exe_tables.parse_cfg(os.path.join(exe_tables.CFG_ROOT, 'versions', version + '.cfg'))
    exe = (Path(data_dir) / 'FROGGER.EXE').read_bytes()
    image = exe_tables.Exe(exe, exe_tables.java_int(cfg.values['ramOffset']))
    levels, _ = exe_tables.read_map_book(image, exe_tables.java_int(cfg.values['mapBook']),
                                          exe_tables.java_int(cfg.values['themeBook']))
    themes = exe_tables.read_theme_book(image, exe_tables.java_int(cfg.values['themeBook']))
    forms = cave_lights.forms_by_theme(image, cfg)
    scripts = exe_tables.read_scripts(image, exe_tables.java_int(cfg.values['scripts']), len(SCRIPT_NAMES))
    _, entries, wads, models = mof.load_archive(str(data_dir), exe_tables.java_int(cfg.values['mwiOffset']),
                                                exe_tables.java_int(cfg.values['mwiLength']))
    wanted = []
    for code in LEVELS:
        level = levels[exe_tables.LEVEL_CODES.index(code)]
        wanted.extend((level['high_map'], level['low_map']))
    files = cave_lights.map_bytes(data_dir, cfg, set(wanted))
    parsed = {}

    def models_for(level, detail):
        def model_for(form):
            wad, slot = model_slot(form, level, themes, detail)
            if slot >= len(wads[wad]):
                return None
            rid = wads[wad][slot][0]
            if mof.file_name(entries, rid) == 'NULL' or rid not in models:
                return None
            if rid not in parsed:
                parsed[rid] = mof.parse_model(models[rid], mof.file_name(entries, rid), None, [])
            return parsed[rid]
        return model_for

    details = {}
    for code in LEVELS:
        level = levels[exe_tables.LEVEL_CODES.index(code)]
        details[level['high_map']] = models_for(level, 'high')
        details[level['low_map']] = models_for(level, 'low')
    out = []
    for resource_id in sorted(wanted):
        out.extend(map_rows(resource_id, *files[resource_id], forms, scripts, details[resource_id]))
    out.extend(model_rows(levels, themes, forms, entries, wads, models))
    out.extend(callback_rows(exe, forms))
    return out


def main():
    """Verify the committed facts by default; rewrite only with an explicit flag."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', required=True, type=Path)
    parser.add_argument('--version', default='pc-retail-v3.0e')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    buffer = io.StringIO()
    writer = csv.writer(buffer, delimiter='\t', lineterminator='\n')
    writer.writerow(HEADER)
    writer.writerows(rows(args.data_dir, args.version))
    if args.write:
        OUTPUT.write_text(buffer.getvalue(), encoding='utf-8')
    elif OUTPUT.read_text(encoding='utf-8') != buffer.getvalue():
        raise SystemExit('Swamp entity facts differ; use --write only to deliberately regenerate')
    print('Swamp entity facts verified')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Decode SKY1–SKY4 Sky-form entity payloads, script registers, FORM grids, models, primitives and callbacks.

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
from tools.golden import make_golden_animation as animation
from tools.golden import make_golden_cave_lights as cave_lights
from tools.golden import make_golden_desert_entities as desert_entities
from tools.golden import make_golden_entities as entities
from tools.golden import make_golden_exe_tables as exe_tables
from tools.golden import make_golden_form_contacts as form_contacts
from tools.golden import make_golden_jungle_entities as jungle_entities
from tools.golden import make_golden_mof as mof
from tools.golden import make_golden_sky as sky
from tools.golden import make_golden_swamp as swamp
from tools.golden import make_golden_swamp_entities as swamp_entities

OUTPUT = REPO_ROOT / 'tests/golden/pc-retail-v3.0e/sky_entities.tsv'
LEVELS = ('SKY1', 'SKY2', 'SKY3', 'SKY4')
SKY_THEME = sky.THEME_SKY
TRIGGER_CALLBACK = 0x42ba00
TRIGGER_CALLBACK_NAME = 'TriggerEntityCallback'
TRIGGER_FORMS = ('SKY_FROGGERS_MAGICAL_POPPING_BALLOON', 'VOL_SWITCH')
FROZEN_REGISTERS = {'SCRIPT_SKY_HELICOPTER': 2, 'SCRIPT_SKY_HELIUM_BALLOON_WAITING': 2,
                    'SCRIPT_SKY_RUBBER_BALLOON_WAITING': 3, 'SCRIPT_SKY_BIRD': 2}
PATH_ENTITIES = ('MOVING', 'MOVING_PLATFORM')
MATRIX_ENTITIES = ('STATIC', 'DYNAMIC', 'TRIGGER')
MR_ANIM_GLOBAL_BBOXES_INCLUDED = 1
FORM_BOOK_FLAG_NO_MODEL = 1
HEADER = desert_entities.HEADER
fields = desert_entities.fields
SCRIPT_NAMES = swamp_entities.SCRIPT_NAMES
model_slot = swamp_entities.model_slot
primitive_rows = swamp_entities.primitive_rows


def payload(entity, data, start, end, name, index):
    """Kind-specific operands following the 24-byte entity header."""
    size = end - start
    if entity in PATH_ENTITIES:
        if size < sky.PATH_INFO_SIZE:
            raise ValueError(f'{name}: short PATH_INFO at entity {index}')
        decoded = sky.platform_payload(dict(payload=list(data[start:end]), theme=SKY_THEME))
        out = dict(path_id=decoded['path_id'], segment_id=decoded['segment_id'], segment_dist=decoded['segment_dist'],
                   motion=decoded['motion_type'], speed=decoded['speed'], path_pad=struct.unpack_from('<H', data, start + 10)[0])
        if entity == 'MOVING_PLATFORM':
            out.update(initial_movement=decoded['initial_movement'], chain_sound=decoded['chain_sound'])
        return out
    if entity not in MATRIX_ENTITIES:
        raise ValueError(f'{name}: entity {index} has an unexpected Sky entity type {entity}')
    if size < sky.MATRIX_SIZE:
        raise ValueError(f'{name}: short matrix at entity {index}')
    rotation = list(struct.unpack_from('<9h', data, start))
    translation = list(struct.unpack_from('<3i', data, start + 20))
    out = dict(matrix=rotation + translation)
    if entity == 'TRIGGER':
        decoded = sky.trigger_payload(dict(payload=list(data[start:end])))
        if not decoded['source_defined']:
            raise ValueError(f'{name}: entity {index} trigger lies outside the source record')
        out.update(trigger_type=decoded['type'], trigger_ids=decoded['ids'])
    return out


def runtime_max_y(form, model, stored):
    """mapload.C: no model keeps the stored value; THICK 0x7fff; UNIT 0x100; else bounding-box vertex 7 Y."""
    if model is None:
        return stored
    if form['flags'] & swamp_entities.FORM_BOOK_THICK_FORM:
        return 0x7fff
    if form['flags'] & swamp_entities.FORM_BOOK_UNIT_FORM:
        return 0x100
    if model['kind'] == 'static':
        return model['statics'][0]['parts'][0]['partcel_list'][0]['box'][22]
    static_id, parts, model_flags, box = model['xar']['sets'][0][0][0]
    if not model_flags & MR_ANIM_GLOBAL_BBOXES_INCLUDED:
        raise ValueError(f'{form["name"]} animation lacks the global bounding box mapload.C asserts')
    return box[22]


def map_rows(resource_id, name, data, forms, scripts, model_for):
    packets = entities.packet_offsets(data)
    theme = entities.number(data, packets['GENE'] + 10, '<H')
    if theme != SKY_THEME:
        raise ValueError(f'{name} has theme {theme}')
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
        if owner != SKY_THEME:
            continue
        operands = payload(form['entity'], data, start + 24, end, name, index)
        registers = dict(root_script=SCRIPT_NAMES[form['script']] if form['script'] else '-', register_offset=-1,
                         registers=[])
        prepared = swamp_entities.prepared_registers(scripts, form['script']) if form['script'] else None
        if prepared is not None:
            offset, words = prepared
            if FROZEN_REGISTERS.get(SCRIPT_NAMES[form['script']]) != words or offset != sky.MATRIX_SIZE:
                raise ValueError(f'{name}: entity {index} prepares {prepared}, not the frozen ent_sky.c registers')
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
        if grid_id < len(map_forms) and grid_id not in grids:
            grids[grid_id] = form['name']
    for grid_id in sorted(grids):
        _, _, datas, max_y, nx, nz, xofs, zofs, items = map_forms[grid_id]
        values = {runtime_max_y(form, model_for(form), max_y) for form in users[grid_id]}
        if len(values) != 1:
            raise ValueError(f'{name}: FORM {grid_id} receives runtime maxima {sorted(values)}')
        flags = items[0][5] if items else []
        rows.append(('form_grid', resource_id, name, -1, -1, grids[grid_id],
                     fields(form_grid_id=grid_id, form_xnum=nx, form_znum=nz, form_xofs=xofs, form_zofs=zofs,
                            form_max_y=max_y, runtime_max_y=values.pop(), form_datas=datas,
                            height=items[0][2] if items else 0, grid_flags=flags,
                            deadly=sum(1 for f in flags if f & swamp.GRID_SQUARE_DEADLY),
                            usable=sum(1 for f in flags if f & swamp.GRID_SQUARE_USABLE))))
    for (entity, form_name, flags), total in sorted(census.items()):
        rows.append(('census', resource_id, name, -1, -1, entity, fields(form=form_name, entity_flags=flags, count=total)))
    return rows


def model_rows(levels, themes, forms, entries, wads, files):
    """Action lengths of every animated or flipbook Sky model and the primitives of every Sky model that has them."""
    rows, seen = [], set()
    for code in LEVELS:
        level = levels[exe_tables.LEVEL_CODES.index(code)]
        for detail in ('high', 'low'):
            for form in forms[SKY_THEME]:
                if form['flags'] & FORM_BOOK_FLAG_NO_MODEL:
                    continue
                wad, slot = model_slot(form, level, themes, detail)
                if slot >= len(wads[wad]):
                    continue
                rid = wads[wad][slot][0]
                name = mof.file_name(entries, rid)
                if name == 'NULL' or rid in seen or rid not in files:
                    continue
                seen.add(rid)
                kind, lengths = desert_entities.action_lengths(files[rid])
                if kind != 'static':
                    rows.append(('actions', rid, name, -1, -1, form['entity'],
                                 fields(form=form['name'], mof_id=form['id'], detail=detail, wad=wad, slot=slot,
                                        kind=kind, lengths=lengths)))
                model = mof.parse_model(files[rid], name, None, [])
                if model['kind'] == 'static' and not model['incomplete']:
                    rows.extend(primitive_rows(rid, name, files[rid], form, detail))
    return rows


def callback_rows(exe, forms):
    """Every Sky form's collision and bonus callbacks and root script; 0x42BA00 must be exactly formlib.C's two trigger forms."""
    users = sorted(form['name'] for library in forms.values() for form in library if form['collision'] == TRIGGER_CALLBACK)
    if users != sorted(TRIGGER_FORMS):
        raise ValueError(f'{TRIGGER_CALLBACK:#x} is used by {users}, not the formlib.C {TRIGGER_CALLBACK_NAME} forms')
    rows = []
    for index, form in enumerate(forms[SKY_THEME]):
        address = form['collision']
        rows.append(('callback', -1, 'FROGGER.EXE', index, -1, form['entity'],
                     fields(form=form['name'], address=f'{address:#x}',
                            callback=TRIGGER_CALLBACK_NAME if address == TRIGGER_CALLBACK else '-',
                            file_offset=jungle_entities.file_offset(exe, address) if address else -1,
                            bonus=f'{form["bonus"]:#x}', script=form['script'],
                            root_script=SCRIPT_NAMES[form['script']] if form['script'] else '-')))
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
            if form['flags'] & FORM_BOOK_FLAG_NO_MODEL:
                return None
            wad, slot = model_slot(form, level, themes, detail)
            if slot >= len(wads[wad]):
                return None
            rid = wads[wad][slot][0]
            if mof.file_name(entries, rid) == 'NULL' or rid not in models:
                return None
            if rid not in parsed:
                model = mof.parse_model(models[rid], mof.file_name(entries, rid), None, [])
                if model['kind'] != 'static':
                    model['xar'] = animation.parse_xar(models[rid])
                parsed[rid] = model
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
        raise SystemExit('Sky entity facts differ; use --write only to deliberately regenerate')
    print('Sky entity facts verified')


if __name__ == '__main__':
    main()

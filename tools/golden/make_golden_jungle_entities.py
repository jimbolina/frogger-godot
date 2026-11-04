#!/usr/bin/env python3
"""Decode JUN1/JUN2 custom-entity payloads, plinth models, action lengths and the door callback from retail files.

Reads FROGGER.EXE, its MWI and FROGPSX.MWD; emits decimal text facts only.
"""
import argparse
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
from tools.golden import make_golden_desert_entities as desert_entities
from tools.golden import make_golden_entities as entities
from tools.golden import make_golden_exe_tables as exe_tables
from tools.golden import make_golden_form_contacts as form_contacts
from tools.golden import make_golden_jungle as jungle
from tools.golden import make_golden_mof as mof

OUTPUT = REPO_ROOT / 'tests/golden/pc-retail-v3.0e/jungle_entities.tsv'
LEVELS = ('JUN1', 'JUN2')
JUNGLE_THEME, GENERAL_THEME = 4, 0
FORMS = ('JUN_PLANT', 'JUN_ROPEBRIDGE', 'JUN_ROPEBRIDGE2', 'JUN_HIPPO', 'JUN_SCORPION', 'JUN_BOUNCY_MUSH', 'JUN_OUTRO',
         'JUN_OUTRO_DOOR', 'JUN_OUTRO_GOLD_DOOR', 'JUN_OUTRO_PLINTH', 'JUN_OUTRO_GOLD_FROG', 'JUN_STONE_FROG')
PAYLOAD_SIZES = {'JUN_PLANT': 36, 'JUN_ROPE_BRIDGE': 36, 'JUN_HIPPO': 24, 'JUN_SCORPION': 12,
                 'JUN_BOUNCY_MUSHROOM': 32, 'JUN_OUTRO': 164, 'JUN_OUTRO_DOOR': 32, 'JUN_PLINTH': 36,
                 'JUN_GOLD_FROG': 36, 'JUN_STONE_FROG': 36}
ACTION_FORMS = ('JUN_PLANT', 'JUN_SCORPION', 'JUN_ROPEBRIDGE', 'JUN_BOUNCY_MUSH', 'JUN_OUTRO_DOOR', 'JUN_OUTRO_GOLD_FROG')
OUTRO_TARGETS = 11
PROJECT_MAX_THEME_MOFS = 128
PLINTH_TABLE = bytes([50 + 8, 0, 1, 2, 3, 4, 5, 6, 7])
DOOR_CALLBACK = 0x4241c0
DOOR_CALLBACK_NAME = 'SwpCrusherCallback'
DOOR_CALLBACK_FORMS = ('JUN_OUTRO_DOOR', 'JUN_OUTRO_GOLD_DOOR', 'SWP_CRUSHER', 'SWP_CRUSHER2')
HEADER = desert_entities.HEADER
fields = desert_entities.fields
SCRIPT_NAMES = exe_tables.name_list('scripts', jungle.SCRIPT_LIST, False)[0]


def sections(data):
    """PE section headers: (name, virtual address, file offset, raw size)."""
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError('Expected a PE executable')
    count, = struct.unpack_from('<H', data, pe + 6)
    optional, = struct.unpack_from('<H', data, pe + 20)
    base, = struct.unpack_from('<I', data, pe + 52)
    out = []
    for index in range(count):
        at = pe + 24 + optional + 40 * index
        _, rva, size, offset = struct.unpack_from('<IIII', data, at + 8)
        out.append((data[at:at + 8].rstrip(b'\0').decode('ascii'), base + rva, offset, size))
    return out


def file_offset(data, address):
    for _, virtual, offset, size in sections(data):
        if virtual <= address < virtual + size:
            return offset + address - virtual
    raise ValueError(f'{address:#x} is outside executable sections')


def plinth_table(data):
    """Locate jun_plinth_table by its frozen-C contents in .data; it must occur exactly once."""
    name, virtual, offset, size = next(s for s in sections(data) if s[0] == '.data')
    body = data[offset:offset + size]
    hits, at = [], body.find(PLINTH_TABLE)
    while at >= 0:
        hits.append(at)
        at = body.find(PLINTH_TABLE, at + 1)
    if len(hits) != 1:
        raise ValueError(f'jun_plinth_table occurs {len(hits)} times in {name}')
    return virtual + hits[0], list(body[hits[0]:hits[0] + len(PLINTH_TABLE)])


def payload(entity, data, start, end, name, index):
    """Kind-specific operands following the 24-byte entity header."""
    size = end - start
    if size < PAYLOAD_SIZES[entity]:
        raise ValueError(f'{name}: short {entity} payload at entity {index}')
    if entity in ('JUN_HIPPO', 'JUN_SCORPION'):
        path_id, segment, distance, motion, speed, pad = struct.unpack_from('<6H', data, start)
        out = dict(path_id=path_id, segment_id=segment, segment_dist=distance, motion=motion, speed=speed,
                   path_pad=pad)
        if entity == 'JUN_HIPPO':
            dive, rise, turtle = struct.unpack_from('<3I', data, start + 12)
            out.update(dive_delay=dive, rise_delay=rise, turtle_type=turtle,
                       root_script=jungle.hippo_no_dive(dict(turtle_type=turtle), SCRIPT_NAMES)['script'])
        return out
    rotation = list(struct.unpack_from('<9h', data, start))
    translation = list(struct.unpack_from('<3i', data, start + 20))
    out = dict(matrix=rotation + translation)
    if entity == 'JUN_PLANT':
        out.update(zip(('snap_time', 'snap_delay'), struct.unpack_from('<2h', data, start + 32)))
    elif entity == 'JUN_ROPE_BRIDGE':
        out.update(zip(('fall_delay', 'hops_before'), struct.unpack_from('<2H', data, start + 32)))
    elif entity in ('JUN_PLINTH', 'JUN_GOLD_FROG', 'JUN_STONE_FROG'):
        out['op_id'], = struct.unpack_from('<i', data, start + 32)
    elif entity == 'JUN_OUTRO':
        targets = [struct.unpack_from('<4hI', data, start + 32 + 12 * i) for i in range(OUTRO_TARGETS)]
        out.update(target_x=[t[0] for t in targets], target_y=[t[1] for t in targets],
                   target_z=[t[2] for t in targets], target_pad=[t[3] for t in targets],
                   target_time=[t[4] for t in targets])
    return out


def map_rows(resource_id, name, data, forms, wad, entries, wads, table):
    packets = entities.packet_offsets(data)
    theme = entities.number(data, packets['GENE'] + 10, '<H')
    at = packets['EMTP']
    packet_end = at + entities.number(data, at + 4, '<I')
    count = entities.number(data, at + 8, '<H')
    pointers = [entities.number(data, at + 12 + 4 * i, '<I') for i in range(count)]
    map_forms = form_contacts.parse_forms(data)
    rows = []
    for index, start in enumerate(pointers):
        end = min((p for p in pointers if p > start), default=packet_end)
        grid_id, unique_id, form_id, entity_flags = struct.unpack_from('<4H', data, start)
        owner = 0 if form_id & 0x8000 else theme
        library = forms.get(owner, [])
        form = library[form_id & 0x7fff] if (form_id & 0x7fff) < len(library) else None
        if form is None or form['name'] not in FORMS:
            continue
        operands = payload(form['entity'], data, start + 24, end, name, index)
        rows.append(('entity', resource_id, name, index, unique_id, form['entity'],
                     fields(form=form['name'], form_id=form_id, mof_id=form['id'], form_grid_id=grid_id,
                            entity_flags=entity_flags, form_flags=form['flags'], death=form['death'],
                            death_name=exe_tables.DEATH_TYPES[form['death']], script=form['script'],
                            payload_bytes=end - start - 24, **desert_entities.form_grid(map_forms, grid_id),
                            **operands)))
        if form['entity'] == 'JUN_PLINTH':
            op_id = operands['op_id']
            if not 0 <= op_id < len(table[1]):
                raise ValueError(f'{name}: plinth op_id {op_id} leaves jun_plinth_table')
            slot = table[1][op_id]
            model = wads[wad][slot][0]
            rows.append(('plinth', resource_id, name, index, unique_id, form['entity'],
                         fields(op_id=op_id, table_address=f'{table[0]:#x}', slot=slot, wad=wad,
                                model_resource=model, model=mof.file_name(entries, model))))
    return rows


def model_rows(levels, themes, forms, entries, wads, files):
    rows, seen = [], set()
    jungle_forms = {form['name']: form for form in forms[JUNGLE_THEME]}
    for code in LEVELS:
        level = levels[exe_tables.LEVEL_CODES.index(code)]
        for detail in ('high', 'low'):
            for form_name in ACTION_FORMS:
                form = jungle_forms[form_name]
                if form['id'] >= PROJECT_MAX_THEME_MOFS:
                    wad, slot = themes[GENERAL_THEME][detail + '_wad'], form['id'] - PROJECT_MAX_THEME_MOFS
                else:
                    wad, slot = level[detail + '_wad'], form['id']
                rid = wads[wad][slot][0]
                if rid in seen or mof.file_name(entries, rid) == 'NULL':
                    continue
                seen.add(rid)
                kind, lengths = desert_entities.action_lengths(files[rid])
                rows.append(('actions', rid, mof.file_name(entries, rid), -1, -1, form['entity'],
                             fields(form=form_name, mof_id=form['id'], detail=detail, wad=wad, slot=slot,
                                    kind=kind, lengths=lengths)))
    return rows


def callback_row(exe, forms):
    """The collision callback shared by the outro doors, named from frozen formlib.C's matching entries."""
    users = sorted(form['name'] for library in forms.values() for form in library
                   if form['collision'] == DOOR_CALLBACK)
    if users != sorted(DOOR_CALLBACK_FORMS):
        raise ValueError(f'{DOOR_CALLBACK:#x} is used by {users}, not the formlib.C {DOOR_CALLBACK_NAME} forms')
    return ('callback', -1, 'FROGGER.EXE', -1, -1, DOOR_CALLBACK_NAME,
            fields(address=f'{DOOR_CALLBACK:#x}', file_offset=file_offset(exe, DOOR_CALLBACK), forms=users))


def rows(data_dir, version):
    cfg = exe_tables.parse_cfg(os.path.join(exe_tables.CFG_ROOT, 'versions', version + '.cfg'))
    exe = (Path(data_dir) / 'FROGGER.EXE').read_bytes()
    image = exe_tables.Exe(exe, exe_tables.java_int(cfg.values['ramOffset']))
    levels, _ = exe_tables.read_map_book(image, exe_tables.java_int(cfg.values['mapBook']),
                                          exe_tables.java_int(cfg.values['themeBook']))
    themes = exe_tables.read_theme_book(image, exe_tables.java_int(cfg.values['themeBook']))
    forms = cave_lights.forms_by_theme(image, cfg)
    table = plinth_table(exe)
    _, entries, wads, models = mof.load_archive(str(data_dir), exe_tables.java_int(cfg.values['mwiOffset']),
                                                exe_tables.java_int(cfg.values['mwiLength']))
    level_wad = {}
    for code in LEVELS:
        level = levels[exe_tables.LEVEL_CODES.index(code)]
        level_wad[level['high_map']] = level['high_wad']
        level_wad[level['low_map']] = level['low_wad']
    files = cave_lights.map_bytes(data_dir, cfg, set(level_wad))
    out = []
    for resource_id in sorted(level_wad):
        out.extend(map_rows(resource_id, *files[resource_id], forms, level_wad[resource_id], entries, wads, table))
    out.extend(model_rows(levels, themes, forms, entries, wads, models))
    out.append(callback_row(exe, forms))
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
        raise SystemExit('Jungle entity facts differ; use --write only to deliberately regenerate')
    print('Jungle entity facts verified')


if __name__ == '__main__':
    main()

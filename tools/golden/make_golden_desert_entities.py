#!/usr/bin/env python3
"""Decode Desert custom-entity payloads, rock targets and model action lengths from retail files.

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
from tools.golden import make_golden_animation as animation
from tools.golden import make_golden_cave_lights as cave_lights
from tools.golden import make_golden_desert as desert
from tools.golden import make_golden_entities as entities
from tools.golden import make_golden_exe_tables as exe_tables
from tools.golden import make_golden_form_contacts as form_contacts
from tools.golden import make_golden_mof as mof

OUTPUT = REPO_ROOT / 'tests/golden/pc-retail-v3.0e/desert_entities.tsv'
LEVELS = ('DES1', 'DES2', 'DES3', 'DES4', 'DES5')
PATH_KINDS = ('DES_SNAKE', 'DES_VULTURE', 'DES_ROLLING_ROCK', 'DES_TUMBLE_WEED', 'DES_THERMAL')
CUSTOM = PATH_KINDS + ('DES_FALLING_ROCK', 'DES_CROC_HEAD', 'DES_CRACK', 'DES_EARTH_QUAKE')
ANIMATED_FORMS = ('DES_SNAKE', 'DES_VULTURE', 'DES_CROCHEAD', 'DES_CRACK')
EXPLOSION_SLOT = 1
HEADER = ('record', 'resource_id', 'map', 'entity_index', 'unique_id', 'name', 'fields')


def fields(**values):
    """Space-separated key=value pairs; lists become comma-separated decimals."""
    out = []
    for key, value in values.items():
        if isinstance(value, bool):
            value = int(value)
        if isinstance(value, (list, tuple)):
            value = ','.join(str(v) for v in value) if value else '-'
        out.append(f'{key}={value}')
    return ' '.join(out)


def read_grid(data):
    """GRID header, stacks and per-square map-poly corner heights in mp_vertices order."""
    grap = entities.number(data, 80, '<I')
    _, _, _, vertices, grid, _ = struct.unpack_from('<6I', data, grap + 4)
    xnum, znum, xlen, zlen = struct.unpack_from('<4H', data, grid + 4)
    stacks = [list(struct.unpack_from('<BBH', data, grid + 12 + 4 * i)) for i in range(xnum * znum)]
    count = sum(stack[0] for stack in stacks)
    squares = []
    for index in range(count):
        _, poly = struct.unpack_from('<2I', data, grid + 12 + 4 * len(stacks) + 8 * index)
        corners = struct.unpack_from('<4H', data, poly)
        squares.append([entities.number(data, vertices + 8 + 8 * v + 2, '<h') for v in corners])
    return dict(base_x=(-(xlen * xnum)) >> 1, base_z=(-(zlen * znum)) >> 1, xnum=xnum, znum=znum,
                stacks=[[s[0], s[2]] for s in stacks], squares=squares)


def form_grid(forms, grid_id):
    """FORM dimensions and the first FORM_DATA's square flags for an entity's grid id."""
    if grid_id >= len(forms):
        return dict(form_xnum=-1, form_znum=-1, form_datas=0, grid_flags=[])
    _, _, count, _, nx, nz, _, _, items = forms[grid_id]
    return dict(form_xnum=nx, form_znum=nz, form_datas=count, grid_flags=items[0][5] if items else [])


def payload_rows(resource_id, name, index, unique_id, entity, data, payload, end, grid):
    """Kind-specific operands following the 24-byte entity header."""
    size = end - payload
    if entity in PATH_KINDS:
        if size < 12:
            raise ValueError(f'{name}: short PATH_INFO at entity {index}')
        path_id, segment, distance, motion, speed, pad = struct.unpack_from('<6H', data, payload)
        return dict(path_id=path_id, segment_id=segment, segment_dist=distance, motion=motion, speed=speed,
                    path_pad=pad), []
    if size < 32:
        raise ValueError(f'{name}: short matrix at entity {index}')
    rotation = list(struct.unpack_from('<9h', data, payload))
    translation = list(struct.unpack_from('<3i', data, payload + 20))
    base = dict(matrix=rotation + translation)
    if entity == 'DES_CROC_HEAD':
        if size < 44:
            raise ValueError(f'{name}: short croc head at entity {index}')
        rise, speed, snap, pause, flag, submerged = struct.unpack_from('<6H', data, payload + 32)
        return dict(base, rise_height=rise, rise_speed=speed, snap_delay=snap, pause_delay=pause,
                    snap_flag=flag, submerged_delay=submerged, start_position=translation[1] & 0xffff), []
    if entity == 'DES_CRACK':
        if size < 36:
            raise ValueError(f'{name}: short crack at entity {index}')
        fall, hops = struct.unpack_from('<2H', data, payload + 32)
        return dict(base, fall_delay=fall, hops_before=hops), []
    if entity == 'DES_FALLING_ROCK':
        if size < 188:
            raise ValueError(f'{name}: short falling rock at entity {index}')
        targets = [list(struct.unpack_from('<3hhHH', data, payload + 32 + 12 * i)) for i in range(12)]
        delay, = struct.unpack_from('<H', data, payload + 176)
        bounces = data[payload + 178]
        flags, sound = struct.unpack_from('<2i', data, payload + 180)
        resolved = desert.rock_targets(dict(grid=grid, bounces=bounces, flags=flags,
                                            targets=[[t[0], t[1], t[2], t[4]] for t in targets]))
        rows = []
        for i in range(bounces):
            got = resolved['targets'][i]
            rows.append(('rock_target', resource_id, name, index, unique_id, entity,
                         fields(target=i, authored=targets[i][:3], svec_pad=targets[i][3], time=targets[i][4],
                                time_pad=targets[i][5], resolved=[got['x'], got['y'], got['z']], error=got['error'])))
        times = [targets[i][4] for i in range(bounces)]
        return dict(base, delay=delay, bounces=bounces, rock_flags=flags, sound=sound,
                    times=times, resolved_flags=resolved['flags']), rows
    return base, []


def map_rows(resource_id, name, data, forms):
    packets = entities.packet_offsets(data)
    theme = entities.number(data, packets['GENE'] + 10, '<H')
    at = packets['EMTP']
    packet_end = at + entities.number(data, at + 4, '<I')
    count = entities.number(data, at + 8, '<H')
    pointers = [entities.number(data, at + 12 + 4 * i, '<I') for i in range(count)]
    grid = read_grid(data)
    map_forms = form_contacts.parse_forms(data)
    rows = []
    for index, start in enumerate(pointers):
        end = min((p for p in pointers if p > start), default=packet_end)
        grid_id, unique_id, form_id, entity_flags = struct.unpack_from('<4H', data, start)
        owner = 0 if form_id & 0x8000 else theme
        library = forms.get(owner, [])
        form = library[form_id & 0x7fff] if (form_id & 0x7fff) < len(library) else None
        if form is None or form['entity'] not in CUSTOM:
            continue
        operands, extra = payload_rows(resource_id, name, index, unique_id, form['entity'], data, start + 24, end, grid)
        rows.append(('entity', resource_id, name, index, unique_id, form['entity'],
                     fields(form=form['name'], form_id=form_id, mof_id=form['id'], form_grid_id=grid_id,
                            entity_flags=entity_flags, form_flags=form['flags'], death=form['death'],
                            death_name=exe_tables.DEATH_TYPES[form['death']], script=form['script'],
                            **form_grid(map_forms, grid_id), **operands)))
        rows.extend(extra)
    return rows


def action_lengths(blob):
    """Flipbook part-0 numpartcels, or a single environment's virtual cels per action."""
    model = mof.parse_model(blob, 'desert model', None, [])
    if model['incomplete']:
        raise ValueError('incomplete desert model needs a counterpart')
    if model['kind'] == 'static':
        part = model['statics'][0]['parts'][0]
        if not part['flipbook_ptr']:
            return 'static', []
        _, count = struct.unpack_from('<HH', blob, part['flipbook_ptr'])
        return 'flipbook', [struct.unpack_from('<HH', blob, part['flipbook_ptr'] + 4 + 4 * i)[0] for i in range(count)]
    xar = animation.parse_xar(blob)
    return 'single', [action['frames'] for action in xar['sets'][0][1]]


def model_rows(levels, forms, entries, wads, files):
    rows, seen = [], set()
    desert_forms = {form['name']: form for form in forms[2]}
    for code in LEVELS:
        level = levels[exe_tables.LEVEL_CODES.index(code)]
        for detail in ('high_wad', 'low_wad'):
            children = wads[level[detail]]
            rid = children[EXPLOSION_SLOT][0]
            kind, lengths = action_lengths(files[rid])
            rows.append(('explosion', level[detail], mof.file_name(entries, level[detail]), -1, -1, code,
                         fields(detail=detail.split('_')[0], slot=EXPLOSION_SLOT, model_resource=rid,
                                model=mof.file_name(entries, rid), kind=kind,
                                cels=lengths[0] if lengths else -1)))
            for form_name in ANIMATED_FORMS:
                form = desert_forms[form_name]
                rid = children[form['id']][0]
                if rid in seen or mof.file_name(entries, rid) == 'NULL':
                    continue
                seen.add(rid)
                kind, lengths = action_lengths(files[rid])
                rows.append(('actions', rid, mof.file_name(entries, rid), -1, -1, form['entity'],
                             fields(form=form_name, mof_id=form['id'], kind=kind, lengths=lengths)))
    return rows


def rows(data_dir, version):
    cfg = exe_tables.parse_cfg(os.path.join(exe_tables.CFG_ROOT, 'versions', version + '.cfg'))
    image = exe_tables.Exe((Path(data_dir) / 'FROGGER.EXE').read_bytes(), exe_tables.java_int(cfg.values['ramOffset']))
    levels, _ = exe_tables.read_map_book(image, exe_tables.java_int(cfg.values['mapBook']),
                                          exe_tables.java_int(cfg.values['themeBook']))
    forms = cave_lights.forms_by_theme(image, cfg)
    wanted = []
    for code in LEVELS:
        level = levels[exe_tables.LEVEL_CODES.index(code)]
        wanted.extend((level['high_map'], level['low_map']))
    files = cave_lights.map_bytes(data_dir, cfg, set(wanted))
    out = []
    for resource_id in sorted(wanted):
        out.extend(map_rows(resource_id, *files[resource_id], forms))
    _, entries, wads, models = mof.load_archive(str(data_dir), exe_tables.java_int(cfg.values['mwiOffset']),
                                                exe_tables.java_int(cfg.values['mwiLength']))
    out.extend(model_rows(levels, forms, entries, wads, models))
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
        raise SystemExit('Desert entity facts differ; use --write only to deliberately regenerate')
    print('Desert entity facts verified')


if __name__ == '__main__':
    main()

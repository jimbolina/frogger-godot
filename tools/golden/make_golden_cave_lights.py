#!/usr/bin/env python3
"""Decode Cave frogger-light payloads and pickup counts from the owner's retail files.

Reads FROGGER.EXE, its MWI and FROGPSX.MWD; emits decimal text facts only.
"""
import argparse
import csv
import io
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT
from tools.golden import make_golden_cave as cave
from tools.golden import make_golden_entities as entities
from tools.golden import make_golden_exe_tables as exe_tables
from tools.golden import make_golden_paths as paths

OUTPUT = REPO_ROOT / 'tests/golden/pc-retail-v3.0e/cave_lights.tsv'
LEVELS = ('CAV1', 'CAV3', 'CAV4')
HEADER = ('resource_id', 'map', 'light_unique_id', 'min_radius', 'max_radius', 'die_speed',
          'min_r2', 'max_r2', 'die', 'map_min', 'map_max', 'firefly_count',
          'fat_fire_fly_count', 'glowworm_count', 'entity_count')


def forms_by_theme(image, cfg):
    """Resolve FrogLord form and entity names for every theme's form library."""
    form_names, sections, _ = exe_tables.name_list('forms', cfg.values.get('formList', '1997-09-12-psx-build57'))
    entity_names, _, entity_cfg = exe_tables.name_list('entities', cfg.values.get('entityList', '1997-09-12-psx-build57'))
    overrides = entity_cfg.child('Override')
    themes = exe_tables.read_theme_book(image, exe_tables.java_int(cfg.values['themeBook']))
    problems = []
    forms = exe_tables.read_forms(image, themes, sections, problems)
    if problems:
        raise ValueError('; '.join(problems))
    for entries in forms.values():
        for form in entries:
            form['name'] = form_names[form['global']]
            entity_type = form['entity_type']
            form['entity'] = entity_names[entity_type] if 0 <= entity_type < len(entity_names) else ''
            if overrides is not None and form['name'] in overrides.values:
                form['entity'] = overrides.values[form['name']]
    return forms


def map_bytes(data_dir, cfg, resource_ids):
    """Read the selected MWD resources, unpacking PowerPacker where flagged."""
    _, entries, _, files = paths.archive.load_archive(
        str(data_dir), exe_tables.java_int(cfg.values['mwiOffset']), exe_tables.java_int(cfg.values['mwiLength']))
    mwd = (Path(data_dir) / 'FROGPSX.MWD').read_bytes()
    result = {}
    for entry in entries:
        if entry['index'] not in resource_ids:
            continue
        start = entry['sector'] * paths.archive.SECTOR_SIZE
        compressed = paths.archive.is_compressed(entry['flags'])
        raw = mwd[start:start + (entry['packed'] if compressed else entry['unpacked'])]
        result[entry['index']] = (paths.archive.file_name(entries, entry['index']),
                                  paths.archive.pp20_unpack(raw)[0] if compressed else raw)
    return result


def map_row(resource_id, name, data, forms):
    """Walk EMTP entity spans; the light payload follows the 24-byte entity header."""
    packets = entities.packet_offsets(data)
    theme = entities.number(data, packets['GENE'] + 10, '<H')
    at = packets['EMTP']
    packet_end = at + entities.number(data, at + 4, '<I')
    count = entities.number(data, at + 8, '<H')
    pointers = [entities.number(data, at + 12 + 4 * index, '<I') for index in range(count)]
    lights, fireflies, fat, glowworms = [], 0, 0, 0
    for start in pointers:
        end = min((p for p in pointers if p > start), default=packet_end)
        unique_id = entities.number(data, start + 2, '<H')
        form_id = entities.number(data, start + 4, '<H')
        owner = 0 if form_id & 0x8000 else theme
        library = forms.get(owner, [])
        form = library[form_id & 0x7fff] if (form_id & 0x7fff) < len(library) else None
        entity = '' if form is None else form['entity']
        payload = start + 24
        if entity == 'CAV_FROGGER_LIGHT':
            if payload + 44 > end:
                raise ValueError(f'{name}: short frogger light payload')
            values = [entities.number(data, payload + offset, '<I') for offset in (32, 36, 40)]
            lights.append((unique_id, *values))
        elif entity == 'FIREFLY':
            fireflies += 1
        elif entity == 'CAV_FAT_FIRE_FLY':
            fat += 1
        elif entity == 'BONUS_FLY' and payload + 34 <= end and entities.number(data, payload + 32, '<H') == 8:
            glowworms += 1
    if len(lights) != 1:
        raise ValueError(f'{name}: expected one frogger light, found {len(lights)}')
    unique_id, low, high, die = lights[0]
    facts = cave.light_create(dict(min_radius=low, max_radius=high, die_speed=die))
    return (resource_id, name, unique_id, low, high, die, facts['min_r2'], facts['max_r2'], facts['die'],
            facts['map_min'], facts['map_max'], fireflies, fat, glowworms, count)


def rows(data_dir, version):
    cfg = exe_tables.parse_cfg(os.path.join(exe_tables.CFG_ROOT, 'versions', version + '.cfg'))
    image = exe_tables.Exe((Path(data_dir) / 'FROGGER.EXE').read_bytes(), exe_tables.java_int(cfg.values['ramOffset']))
    levels, _ = exe_tables.read_map_book(image, exe_tables.java_int(cfg.values['mapBook']),
                                          exe_tables.java_int(cfg.values['themeBook']))
    wanted = []
    for code in LEVELS:
        level = levels[exe_tables.LEVEL_CODES.index(code)]
        if not level['cave_lights']:
            raise ValueError(f'{code} lacks the map-book cave light flag')
        wanted.extend((level['high_map'], level['low_map']))
    forms = forms_by_theme(image, cfg)
    files = map_bytes(data_dir, cfg, set(wanted))
    return [map_row(resource_id, *files[resource_id], forms) for resource_id in sorted(wanted)]


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
        raise SystemExit('Cave light facts differ; use --write only to deliberately regenerate')
    print('Cave light facts verified')


if __name__ == '__main__':
    main()

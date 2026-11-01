#!/usr/bin/env python3
"""Independent game-language facts: locale detection, language banks and localized image names.

Retail PC picks Game_language from GetUserDefaultLCID() & 0x3FF through a
ten-byte map and a five-arm jump table (transcribed below; cross-checked
against froggy's pinned frogger_language_map.h when it is available). The
language banks come from FrogLord's VLO configuration, the localized image
names from FrogLord's retail image list, and which retail bank holds each
image from the committed vlo_images.tsv. The bank order is checked against
tempopt.c when the frozen C is available.
See tests/golden/specs/frontend.md#languages.
"""
import argparse
import difflib
import os
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_golden_frontend as frontend
import make_golden_stack as stack

ROOT = frontend.ROOT
GOLDEN = frontend.GOLDEN
LANGUAGE_JSON = GOLDEN / 'synthetic' / 'frontend_language.json'
LANGUAGE_TSV = GOLDEN / 'pc-retail-v3.0e' / 'frontend_language.tsv'
VLO_FILES_TSV = GOLDEN / 'pc-retail-v3.0e' / 'vlo_files.tsv'
VLO_IMAGES_TSV = GOLDEN / 'pc-retail-v3.0e' / 'vlo_images.tsv'
FROGLORD = ROOT / 'archive' / 'third_party' / 'froglord_cfg'
IMAGE_CFG = FROGLORD / 'images' / '1997-11-15-pc-retail.cfg'
VLO_CFG = FROGLORD / 'vlo' / '1997-11-15-pc-retail-1.0.cfg'
DEFAULT_MAP_HEADER = ROOT.parent / 'froggy' / 'engine' / 'asset_pipeline' / 'include' / 'frogger_language_map.h'

LANGUAGES = [
    ('ENGLISH', 'English', 'E', 'en'),
    ('ITALIAN', 'Italian', 'I', 'it'),
    ('GERMAN', 'German', 'G', 'de'),
    ('FRENCH', 'French', 'F', 'fr'),
    ('SPANISH', 'Spanish', 'S', 'es'),
]
AUTO = -1
LCID_MASK = 0x3FF
PRIMARY_BIAS = 0x07
PRIMARY_BOUND = 0x09
PRIMARY_MAP = [0x00, 0x04, 0x04, 0x01, 0x04, 0x02, 0x04, 0x04, 0x04, 0x03]
ARM_LANGUAGES = [2, 4, 3, 1, 0]
EXE = {
    'map_offset': 0x00044150,
    'routine_offset': 0x000440E0,
    'prologue': [0xFF, 0x15, 0xCC, 0xD3, 0x4A, 0x00, 0x25, 0xFF, 0x03, 0x00, 0x00,
                 0x83, 0xE8, 0x07, 0x83, 0xF8, 0x09],
    'store_opcode': [0xC7, 0x05, 0x9C, 0xA9, 0x48, 0x00],
    'arm_store_offsets': [0x0004410D, 0x00044118, 0x00044123, 0x0004412E, 0x00044102],
}
LOCALE_PRIMARY_IDS = {
    'de': 0x07, 'el': 0x08, 'en': 0x09, 'es': 0x0A, 'fi': 0x0B,
    'fr': 0x0C, 'he': 0x0D, 'hu': 0x0E, 'is': 0x0F, 'it': 0x10,
}
LCID_CASES = [0x0000, 0x0406, 0x0407, 0x0807, 0x0408, 0x0409, 0x0809, 0x040A, 0x0C0A, 0x080A,
              0x040B, 0x040C, 0x0C0C, 0x040D, 0x040E, 0x040F, 0x0410, 0x0810, 0x0411, 0x0419, 0x0816, 0x03FF]
LOCALE_CASES = ['de_DE', 'de-AT', 'DE', 'it_IT', 'it', 'fr_FR', 'FR_ca', 'es_ES', 'es-MX', 'en_US', 'en_GB',
                'el_GR', 'fi_FI', 'he', 'hu_HU', 'is', 'ja_JP', 'pt_BR', 'nl_NL', 'zh_Hans_CN', '', '_']
FRONT_END_BANKS = ['OPT_VRAM.VLO', 'STARTNTSC.VLO', 'FIXE_VRAM.VLO', 'OPTE_RAM.VLO', 'LS_ALL.VLO']
FRONT_END_NAMES = [
    'opt_start', 'opt_options', 'opt_exit', 'opt_race', 'select_level', 'zone_complete',
    'press_fire', 'sel_loading', 'opt_big_continue', 'opt_yes', 'opt_no', 'opt_paused',
    'froglogo', 'newfont', 'select1', 'select2', 'select5', 'ls_gold_frog',
    'opt_view_hs', 'opt_ctrl_config', 'opt_insert_pad', 'select7', 'opt_keyboard',
    'opt_arrow_small_left', 'opt_arrow_small_right', 'select3', 'skip_hi_score', 'opt_arrow',
    'next', 'total_time', 'total_score', 'select4', 'opt_sec',
]


def read_images():
    """FrogLord's retail texture names: name -> texture id."""
    names = {}
    for line in IMAGE_CFG.read_text(encoding='utf-8').splitlines():
        match = re.match(r'^(\d+)=(\S+)', line.split('#')[0].strip())
        if match:
            if match.group(2) in names:
                raise SystemExit('duplicate image name %s' % match.group(2))
            names[match.group(2)] = int(match.group(1))
    return names


def read_vlo_groups():
    """The bank names of each FrogLord VLO section, without bracket depth."""
    groups, current = {}, None
    for line in VLO_CFG.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        header = re.match(r'^\[+([^\]]+)\]+$', line)
        if header:
            current = header.group(1)
            groups[current] = []
        elif current and line.upper().endswith('.VLO'):
            groups[current].append(line)
    return groups


def lcid_language(lcid):
    index = (lcid & LCID_MASK) - PRIMARY_BIAS
    if index < 0 or index > PRIMARY_BOUND:
        return 0
    return ARM_LANGUAGES[PRIMARY_MAP[index]]


def locale_language(locale):
    code = locale.strip().lower().replace('-', '_').split('_')[0]
    return lcid_language(LOCALE_PRIMARY_IDS[code]) if code in LOCALE_PRIMARY_IDS else 0


def localized_families(images):
    """English name -> {letter: localized name}, each variant found in the image list.

    A variant either appends `_<letter>` to the English name or inserts the
    letter after the name's first word. Returns the families, the first words
    that take the prefix form, and the variants with no English name."""
    letters = [letter.lower() for _key, _name, letter, _code in LANGUAGES[1:]]
    families, prefixes, orphans = {}, set(), []
    for name in sorted(images):
        found = None
        if len(name) > 2 and name[-2] == '_' and name[-1] in letters and name[:-2] in images:
            found = (name[:-2], name[-1], 'suffix')
        word, sep, rest = name.partition('_')
        if sep and len(word) > 1 and word[-1] in letters and word[:-1] + '_' + rest in images:
            if found:
                raise SystemExit('%s matches both name forms' % name)
            found = (word[:-1] + '_' + rest, word[-1], 'prefix')
            prefixes.add(word[:-1])
        if found:
            families.setdefault(found[0], {})[found[1].upper()] = name
        elif (len(name) > 2 and name[-2] == '_' and name[-1] in letters):
            orphans.append(name)
    for english, variants in families.items():
        word = english.partition('_')[0]
        for letter, variant in variants.items():
            expected = word + letter.lower() + english[len(word):] if word in prefixes else english + '_' + letter.lower()
            if variant != expected:
                raise SystemExit('%s does not follow the rule for %s' % (variant, english))
    return families, sorted(prefixes), orphans


def language_banks(index):
    banks = list(FRONT_END_BANKS)
    if index == 0:
        return banks
    letter = LANGUAGES[index][2]
    at = banks.index('OPTE_RAM.VLO') + 1
    return banks[:at] + ['FIX%s_VRAM.VLO' % letter, 'OPT%s_RAM.VLO' % letter] + banks[at:]


def document(images, groups):
    families, prefixes, orphans = localized_families(images)
    languages = []
    for index, (key, name, letter, code) in enumerate(LANGUAGES):
        fixed, option = 'FIX%s_VRAM.VLO' % letter, 'OPT%s_RAM.VLO' % letter
        if fixed not in groups['Fixed'] or option not in groups['OptionsText']:
            raise SystemExit('FrogLord does not list the %s banks' % name)
        languages.append({'id': index, 'key': key, 'name': name, 'letter': letter, 'code': code,
                          'fixed_bank': fixed, 'option_bank': option, 'front_end_banks': language_banks(index)})
    front_end = []
    for english in FRONT_END_NAMES:
        if english not in images:
            raise SystemExit('front-end image %s is not named' % english)
        variants = families.get(english, {})
        front_end.append({'name': english,
                          'localized': [variants.get(letter) for _k, _n, letter, _c in LANGUAGES[1:]],
                          'shared': not variants})
    return {
        'source': 'Game_language enum (tempopt.h:169), LanguageSelectionStartup map, FrogLord vlo/images retail cfg',
        'auto': AUTO,
        'languages': languages,
        'lcid': {'mask': LCID_MASK, 'primary_bias': PRIMARY_BIAS, 'primary_bound': PRIMARY_BOUND,
                 'primary_map': PRIMARY_MAP, 'arm_languages': ARM_LANGUAGES},
        'exe': EXE,
        'locale_primary_ids': LOCALE_PRIMARY_IDS,
        'lcid_cases': [[lcid, lcid_language(lcid)] for lcid in LCID_CASES],
        'locale_cases': [[locale, locale_language(locale)] for locale in LOCALE_CASES],
        'name_rule': {'order': [letter for _k, _n, letter, _c in LANGUAGES[1:]], 'prefix_families': prefixes,
                      'suffix': '_<letter>', 'variants_without_english': orphans},
        'families': [[english] + [variants.get(letter) for _k, _n, letter, _c in LANGUAGES[1:]]
                     for english, variants in sorted(families.items())],
        'front_end_images': front_end,
    }


def read_bank_ids():
    files = {int(row[0]): row[1] for row in frontend.read_tsv(VLO_FILES_TSV)}
    ids = {}
    for row in frontend.read_tsv(VLO_IMAGES_TSV):
        ids.setdefault(files[int(row[0])], set()).add(int(row[2]))
    return ids


def retail_text(images, doc):
    ids = read_bank_ids()
    lines = ['# Front-end image of each language; schema in tests/golden/specs/frontend.md#languages.',
             '#language\tenglish_name\tsource_name\ttexture_id\tbank']
    for language in doc['languages']:
        for image in doc['front_end_images']:
            source = image['name'] if language['id'] == 0 else image['localized'][language['id'] - 1]
            source = source or image['name']
            texture = images[source]
            holders = [bank for bank in language['front_end_banks'] if texture in ids.get(bank, set())]
            if not holders:
                raise SystemExit('%s %s (texture %d) is in no front-end bank' % (language['name'], source, texture))
            lines.append('%d\t%s\t%s\t%d\t%s' % (language['id'], image['name'], source, texture, holders[-1]))
    return '\n'.join(lines) + '\n'


def check_map_header(path):
    text = path.read_text(encoding='latin-1')
    problems = []
    found = re.search(r'#define FROGGER_LANGUAGE_MAP\s*\\\s*([0-9A-Fa-fx,\s]+)', text)
    if not found or [int(v, 16) for v in found.group(1).replace(',', ' ').split()] != PRIMARY_MAP:
        problems.append('language map bytes differ')
    arms = re.findall(r'X\((\d), (0x[0-9A-Fa-f]+), (\d), "\w+"\)', text)
    if [int(v) for _a, _o, v in arms] != ARM_LANGUAGES or [int(o, 16) for _a, o, _v in arms] != EXE['arm_store_offsets']:
        problems.append('arm languages or store offsets differ')
    for name, value in (('MAP_OFF', EXE['map_offset']), ('ROUTINE_OFF', EXE['routine_offset']),
                        ('LCID_MASK', LCID_MASK), ('PRIMARY_BIAS', PRIMARY_BIAS), ('PRIMARY_BOUND', PRIMARY_BOUND)):
        match = re.search(r'#define FROGGER_LANGUAGE_%s\s+(0x[0-9A-Fa-f]+)' % name, text)
        if not match or int(match.group(1), 16) != value:
            problems.append('%s differs' % name)
    return problems


def check_c(c_root):
    problems = []
    header = stack.squash((c_root / 'tempopt.h').read_text(encoding='latin-1'))
    enum = ','.join('GAME_LANGUAGE_' + key for key, _n, _l, _c in LANGUAGES) + ','
    if enum not in header:
        problems.append('tempopt.h language enum order differs')
    source = stack.squash((c_root / 'tempopt.c').read_text(encoding='latin-1'))
    options = 'Opt_resource_files[]={' + ','.join('RES_OPT%s_RAM_VLO' % l for _k, _n, l, _c in LANGUAGES) + ',}'
    fixed = 'Language_res[]={' + ','.join('RES_FIX%s_VRAM_VLO' % l for _k, _n, l, _c in LANGUAGES) + ',}'
    for snippet in (options, fixed, 'MRLoadResource(Language_res[Game_language]);'):
        if snippet not in source:
            problems.append('tempopt.c no longer contains: %s' % snippet[:80])
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--c-reference', type=Path, default=frontend.DEFAULT_C,
                        help='frozen C source folder (default: ../froggy/engine/vendor/frogger-psx-src/source)')
    parser.add_argument('--map-header', type=Path, default=DEFAULT_MAP_HEADER,
                        help="froggy's pinned frogger_language_map.h (default: ../froggy/engine/asset_pipeline/include)")
    parser.add_argument('--check', action='store_true', help='compare with the committed files instead of writing')
    args = parser.parse_args()
    for label, path, checker in (('C', args.c_reference, check_c), ('Map header', args.map_header, check_map_header)):
        if path.exists():
            problems = checker(path)
            for problem in problems:
                print('%s cross-check: %s' % (label, problem))
            if problems:
                sys.exit(1)
            print('%s cross-check passed against %s' % (label, path))
        else:
            print('%s not found at %s; cross-checks skipped' % (label, path))
    images = read_images()
    doc = document(images, read_vlo_groups())
    outputs = [(LANGUAGE_JSON, stack.dump(doc) + '\n'), (LANGUAGE_TSV, retail_text(images, doc))]
    if args.check:
        differ = False
        for path, text in outputs:
            old = path.read_text(encoding='utf-8') if path.exists() else ''
            if old != text:
                differ = True
                sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                           str(path), 'generated', n=0))
        print('Committed facts differ from the generator' if differ else 'Committed facts match the generator')
        sys.exit(1 if differ else 0)
    for path, text in outputs:
        path.write_text(text, encoding='utf-8')
        print('Wrote %s' % path.relative_to(ROOT))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Decode the retail effect resources: MOF hilites, effect texture ids, particle generator records, the score library and pop colours.

Reads FROGGER.EXE, its MWI and FROGPSX.MWD; emits decimal text facts only (ids, counts, integers).
"""
import argparse
import collections
import os
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_golden_effects as effects
import make_golden_exe_tables as exe_tables
from make_golden_manifest import FLAG_GROUP_ACCESS, SECTOR_SIZE, is_compressed, pp20_unpack
import make_golden_mof as mof

OUTPUT = Path(__file__).resolve().parents[1] / 'tests/golden/pc-retail-v3.0e/effect_resources.tsv'
HILITE_TYPES = ('COLLISION', '3DSPRITE_SPLASH', '3DSPRITE_WAKE', 'PARTICLE_EXHAUST', 'PARTICLE_CLOUD',
                'PARTICLE_SMOKE', 'PARTICLE_FIRE', 'MESH', 'ANIM')
HILITE_SPRITE_TYPES = (1, 2)
FROG_PARTICLES = ('FROG_PARTICLE_SLIDE', 'FROG_PARTICLE_WATER_BUBBLE', 'FROG_PARTICLE_ON_FIRE')
FROG_PARTICLE_GENERATORS = (('PGIN_frog_slip_effect', 'PGIN_frog_slip_effect'), ('PGIN_frog_water_bubble', None),
                            ('PGIN_frog_on_fire', None))
FROG_PARTICLE_FLAGS = (0x300, 0x200, 0x200)
SPECIAL_GENERATORS = (None, None, None, 'PGIN_hilite_exhaust', 'PGIN_hilite_exhaust', 'PGIN_hilite_dust',
                      'PGIN_hilite_fire', None, None)
C_ORDER = ('PGIN_for_swarm', 'PGIN_for_swarm_multiplayer', 'PGIN_pickup', 'PGIN_pickup_explosion',
           'PGIN_frog_pop_explosion', 'PGIN_hilite_exhaust', 'PGIN_hilite_dust', 'PGIN_hilite_fire',
           'PGIN_frog_slip_effect', 'PGIN_frog_water_bubble', 'PGIN_frog_on_fire', 'PGIN_stone_to_gold_frog',
           'PGIN_gold_frog_glow')
POWERUPS = dict(SUPER_TONGUE=1, QUICK_JUMP=2, AUTO_HOP=4, TIMER_SPEED=8, SUPER_LIGHT=16)
SCORE_FLAG_SCORE, SCORE_FLAG_LIGHT, SCORE_FLAG_TIME, SCORE_FLAG_REDUCE, SCORE_FLAG_LIFE, SCORE_FLAG_POWERUP = \
    1, 2, 4, 8, 0x10, 0x20
SCORE_LIBRARY = (
    (5, None, SCORE_FLAG_SCORE), (10, 'im_score_10', SCORE_FLAG_SCORE), (25, 'im_score_25', SCORE_FLAG_SCORE),
    (50, 'im_score_50', SCORE_FLAG_SCORE), (75, 'im_score_75', SCORE_FLAG_SCORE),
    (100, 'im_score_100', SCORE_FLAG_SCORE), (150, 'im_score_150', SCORE_FLAG_SCORE),
    (200, 'im_score_200', SCORE_FLAG_SCORE), (250, 'im_score_250', SCORE_FLAG_SCORE),
    (500, 'im_score_500', SCORE_FLAG_SCORE), (1000, 'im_score_1000', SCORE_FLAG_SCORE),
    (5000, 'im_score_5000', SCORE_FLAG_SCORE), (5, None, SCORE_FLAG_LIGHT), (8, None, SCORE_FLAG_LIGHT),
    (POWERUPS['SUPER_LIGHT'], None, SCORE_FLAG_POWERUP), (60, 'im_time_plus2', SCORE_FLAG_TIME),
    (150, 'im_time_plus5', SCORE_FLAG_TIME), (300, 'im_time_plus10', SCORE_FLAG_TIME),
    (-500, 'im_score_minus500', SCORE_FLAG_REDUCE), (POWERUPS['TIMER_SPEED'], None, SCORE_FLAG_POWERUP),
    (1, 'im_1up1', SCORE_FLAG_LIFE), (POWERUPS['SUPER_TONGUE'], None, SCORE_FLAG_POWERUP),
    (POWERUPS['QUICK_JUMP'], None, SCORE_FLAG_POWERUP), (POWERUPS['AUTO_HOP'], None, SCORE_FLAG_POWERUP))
SCORE_IDS = ('SCORE_5', 'SCORE_10', 'SCORE_25', 'SCORE_50', 'SCORE_75', 'SCORE_100', 'SCORE_150', 'SCORE_200',
             'SCORE_250', 'SCORE_500', 'SCORE_1000', 'SCORE_5000', 'LIGHT_5', 'LIGHT_8', 'ADD_SUPER_LIGHT',
             'TIME_MIN', 'TIME_MED', 'TIME_MAX', 'REDUCE_SCORE_100', 'ADD_TIMER_SPEED', 'ADD_EXTRA_LIFE',
             'ADD_SUPER_TONGUE', 'ADD_QUICK_JUMP', 'ADD_AUTO_HOP')
MR_SPRT_NOP, MR_SPRT_SETIMAGE, MR_SPRT_SETSPEED, MR_SPRT_SETSCALE, MR_SPRT_SETCOLOUR, MR_SPRT_KILL = 0, 1, 3, 4, 5, 16
SPLASH_PREFIX = (MR_SPRT_NOP, MR_SPRT_NOP, MR_SPRT_NOP, MR_SPRT_NOP, MR_SPRT_SETSPEED, 2, MR_SPRT_SETSCALE, 8 << 16)
GLOW_TEXTURE = 1727
SYMBOLS = (['im_frog_smoke1', 'im_gen_shadow', 'im_frog_shadow0', 'im_frog_shadow1', 'im_frog_shadow2', 'im_wake2']
           + ['im_ripple_tim%d' % i for i in range(1, 7)] + ['im_bison%d' % i for i in range(1, 7)]
           + ['im_tongue_tip', 'im_for_swarm'] + [s for _, s, _ in SCORE_LIBRARY if s] + ['glow_1727'])
HEADERS = {
    'hilite': ('resource_id', 'file_name', 'static_index', 'part', 'hilite_index', 'type', 'type_name', 'attach',
               'index', 'special'),
    'hilite_borrowed': ('resource_id', 'file_name', 'static_index', 'part', 'declared', 'counterpart'),
    'hilite_census': ('type', 'type_name', 'count', 'files'),
    'hilite_generator': ('type', 'type_name', 'generator'),
    'pgen': ('name', 'address', 'flags', 'prim_size', 'max_particles', 'generator_life', 'particle_min_life',
             'particle_max_life', 'gravity_16', 'user_data_1', 'user_data_2', 'texture_ids', 'c_differences'),
    'frog_particle': ('index', 'name', 'flags', 'single', 'multi'),
    'image': ('symbol', 'texture_id', 'resolution', 'width', 'height', 'flags', 'blend_mode', 'banks', 'exe_refs'),
    'score_library': ('score_id', 'name', 'value', 'symbol', 'texture_id', 'flags'),
    'pop_colour': ('player', 'value', 'r', 'g', 'b'),
}


def words_at(data, offset, count):
    return list(struct.unpack_from('<%dI' % count, data, offset))


def find_words(exe, words):
    """Every program-image offset holding the little-endian words, in ascending order."""
    pattern = b''.join(struct.pack('<I', w & 0xffffffff) for w in words)
    found, at = [], 0
    while True:
        at = exe.data.find(pattern, at)
        if at < 0 or at >= exe.length:
            return found
        found.append(at)
        at += 1


def pgen_records(exe):
    """MR_PGEN_INIT-shaped records: 2D type, flags 0 or MR_PF_NO_GEOMETRY, four callback slots (the first may be NULL)."""
    records = []
    for off in range(0, exe.length - 48, 4):
        kind, flags, prim, geom, prim_init, move, disp, gravity, maxp, life, min_life, max_life, user1, user2 = \
            struct.unpack_from('<HHIIIIIiHHHHII', exe.data, off)
        if kind != 2 or flags not in (0, 0x10) or not 16 <= prim <= 80:
            continue
        if not all(exe_tables.looks_like_pointer(p) for p in (prim_init, move, disp)):
            continue
        if geom and not exe_tables.looks_like_pointer(geom):
            continue
        records.append(dict(address=off + exe.ram, flags=flags, prim_size=prim, callbacks=(prim_init, move, disp),
                            max_particles=maxp, generator_life=life - 0x10000 if life & 0x8000 else life,
                            particle_min_life=min_life, particle_max_life=max_life, gravity_16=gravity,
                            user_data_1=user1, user_data_2=user2))
    return records


def identify_pgens(exe, records):
    """Name the records: hilite and frog tables first, then C declaration order on (flags, maxp, life, user_data_1)."""
    by_address = {r['address']: r for r in records}
    names = {}
    special = None
    for off in range(0, exe.length - 36, 4):
        table = words_at(exe.data, off, 9)
        if table[:3] == [0, 0, 0] and table[7:] == [0, 0] and table[3] == table[4] and \
                all(t in by_address for t in table[3:7]) and len(set(table[4:7])) == 3:
            if special is not None:
                raise ValueError('more than one Entity_special_particle_generators table')
            special = (off + exe.ram, table)
    if special is None:
        raise ValueError('Entity_special_particle_generators not found')
    for address, name in zip(special[1], SPECIAL_GENERATORS):
        if name:
            names.setdefault(address, name)
    frog = None
    for off in range(0, exe.length - 36, 4):
        table = words_at(exe.data, off, 9)
        if list(table[0::3]) == list(FROG_PARTICLE_FLAGS) and table[1] == table[2] and table[5] == table[8] == 0 and \
                all(t in by_address for t in (table[1], table[4], table[7])):
            if frog is not None:
                raise ValueError('more than one Frog_particle_effects table')
            frog = (off + exe.ram, table)
    if frog is None:
        raise ValueError('Frog_particle_effects not found')
    for index, (single, _) in enumerate(FROG_PARTICLE_GENERATORS):
        names[frog[1][3 * index + 1]] = single
    c_records = {r['name']: r for r in effects.generator_records()}
    last = 0
    for name in C_ORDER:
        fixed = [a for a, n in names.items() if n == name]
        if fixed:
            last = fixed[0]
            continue
        c = c_records[name]
        key = (c['flags'], c['max_particles'], c['generator_life'], c['user_data_1'])
        candidates = [r['address'] for r in records if r['address'] not in names and r['address'] > last and
                      (r['flags'], r['max_particles'], r['generator_life'], r['user_data_1']) == key]
        if not candidates:
            raise ValueError(f'no record matches {name}')
        names[candidates[0]] = name
        last = candidates[0]
    if sorted(names.values()) != sorted(C_ORDER):
        raise ValueError('particle generator names are not assigned exactly once')
    return names, special, frog


def texture_index(bmp):
    return {pointer: index for index, pointer in enumerate(bmp)}


def texture_list(exe, address, tex):
    """A NULL-terminated MR_TEXTURE* list (Hilite_dust_textures)."""
    out, off = [], exe.file_offset(address)
    while True:
        value = exe.u32(off)
        if value == 0:
            return out
        out.append(tex[value])
        off += 4


def find_unique(exe, label, predicate, span):
    found = [off for off in range(0, exe.length - span, 4) if predicate(off)]
    if len(found) != 1:
        raise ValueError(f'{label}: {len(found)} matches')
    return found[0]


def exe_tables_of(exe, bmp, tex, names, records):
    """Locate the effect data tables by structure, cross-check them with the frozen C, and resolve their textures."""
    by_name = {names[r['address']]: r for r in records if r['address'] in names}
    sources = collections.defaultdict(list)
    for name, symbol in (('PGIN_hilite_fire', 'im_frog_smoke1'), ('PGIN_frog_slip_effect', 'im_frog_smoke1'),
                         ('PGIN_frog_on_fire', 'im_frog_smoke1'), ('PGIN_stone_to_gold_frog', 'im_frog_smoke1'),
                         ('PGIN_frog_water_bubble', 'im_wake2'), ('PGIN_for_swarm', 'im_for_swarm'),
                         ('PGIN_for_swarm_multiplayer', 'im_for_swarm')):
        sources[symbol].append((name, tex[by_name[name]['user_data_2']]))
    dust = texture_list(exe, by_name['PGIN_hilite_dust']['user_data_2'], tex)
    if len(dust) != 6:
        raise ValueError(f'Hilite_dust_textures has {len(dust)} images')
    for i, value in enumerate(dust):
        sources['im_bison%d' % (i + 1)].append(('Hilite_dust_textures[%d]' % i, value))
    bmp_set = set(bmp)

    def shadow_textures(off):
        w = words_at(exe.data, off, 6)
        return all(x in bmp_set for x in w) and w[2] == w[3] == w[4] and w[1] == w[5] and len({w[0], w[1], w[2]}) == 3
    shadow = find_unique(exe, 'Frog_jump_shadow_textures', shadow_textures, 24)
    for i, value in enumerate(words_at(exe.data, shadow, 3)):
        sources['im_frog_shadow%d' % i].append(('Frog_jump_shadow_textures[%d]' % i, tex[value]))
    offset_pointers = words_at(exe.data, shadow - 24, 6)
    tables = [[list(struct.unpack_from('<3h', exe.data, exe.file_offset(p) + 8 * k)) for k in range(4)]
              for p in offset_pointers]
    expected = [[list(v) for v in effects.FROG_SHADOW_OFFSETS[i]] for i in effects.FROG_JUMP_SHADOW_OFFSETS]
    if tables != expected:
        raise ValueError('Frog_jump_shadow_offsets differ from FROG.C')
    splash = [off for off in range(0, exe.length - 120, 4)
              if tuple(words_at(exe.data, off, len(SPLASH_PREFIX))) == SPLASH_PREFIX]
    lists = []
    for off in splash:
        w = words_at(exe.data, off + 4 * len(SPLASH_PREFIX), 21)
        ops = w[0::2]
        if ops[:6] != [MR_SPRT_SETIMAGE] * 6 or w[12:] != [MR_SPRT_SETCOLOUR, 0x606060, MR_SPRT_SETIMAGE, w[11],
                                                          MR_SPRT_SETCOLOUR, 0x404040, MR_SPRT_SETIMAGE, w[11],
                                                          MR_SPRT_SETCOLOUR] or \
                words_at(exe.data, off + 4 * (len(SPLASH_PREFIX) + 21), 3) != [0x202020, MR_SPRT_SETIMAGE, w[11]] or \
                exe.u32(off + 4 * (len(SPLASH_PREFIX) + 24)) != MR_SPRT_KILL:
            raise ValueError('splash animlist at 0x%X differs from COLLIDE.C' % (off + exe.ram))
        lists.append([tex[w[2 * i + 1]] for i in range(6)])
    if len(lists) != 2 or lists[0] != lists[1]:
        raise ValueError('expected FrogSplashAnimList and TurtleSplashAnimList with the same images')
    for i, value in enumerate(lists[0]):
        for label in ('FrogSplashAnimList', 'TurtleSplashAnimList'):
            sources['im_ripple_tim%d' % (i + 1)].append(('%s[%d]' % (label, i), value))

    def score_library(off):
        for k in range(12):
            value, _, flags = struct.unpack_from('<iII', exe.data, off + 12 * k)
            if value != SCORE_LIBRARY[k][0] or flags != SCORE_FLAG_SCORE:
                return False
        return True
    score = find_unique(exe, 'Score_library', score_library, 12 * len(SCORE_LIBRARY))
    score_rows = []
    for k, (value, symbol, flags) in enumerate(SCORE_LIBRARY):
        stored, pointer, stored_flags = struct.unpack_from('<iII', exe.data, score + 12 * k)
        if (stored, stored_flags) != (value, flags) or (pointer == 0) != (symbol is None):
            raise ValueError(f'Score_library[{k}] differs from score.C')
        texture_id = tex[pointer] if pointer else -1
        if symbol:
            sources[symbol].append(('Score_library[%d]' % k, texture_id))
        score_rows.append(('score_library', k, SCORE_IDS[k], stored, symbol or '-', texture_id, stored_flags))
    fire = by_name['PGIN_hilite_fire']['address']
    stride = min(b['address'] - a['address'] for a, b in zip(records, records[1:]))
    colours_at = exe.file_offset(fire + stride)
    colours = words_at(exe.data, colours_at, 5)
    if colours != list(effects.FROG_POP_EXPLOSION_COLOURS):
        raise ValueError('Frog_pop_explosion_colours differ from PARTICLE.C')
    octagon_at = (colours_at + 20 + 7) & ~7
    octagon = [list(struct.unpack_from('<2h', exe.data, octagon_at + 8 * k)) for k in range(16)]
    if octagon != [list(v) for v in effects.EXPLOSION_OUTER + effects.EXPLOSION_INNER]:
        raise ValueError('Explosion_offsets_octagon differs from PARTICLE.C')
    colour_rows = [('pop_colour', i, '0x%06X' % c, c & 0xff, (c >> 8) & 0xff, (c >> 16) & 0xff)
                   for i, c in enumerate(colours)]
    return sources, score_rows, colour_rows, dict(shadow=shadow, splash=splash, score=score)


def image_names(cfg):
    names = exe_tables.parse_cfg(os.path.join(exe_tables.CFG_ROOT, 'images', cfg.values['imageList'] + '.cfg')).values
    return {int(k): v.strip() for k, v in names.items() if k.isdigit()}


def vlo_banks(data_dir, entries, wad_files):
    """Header facts of every 2GRP image by texture id: (width, height, flags, blend mode) and bank count."""
    mwd = open(os.path.join(data_dir, 'FROGPSX.MWD'), 'rb').read()
    banks = {}
    for e in entries:
        if e['flags'] & FLAG_GROUP_ACCESS:
            continue
        start = e['sector'] * SECTOR_SIZE
        raw = mwd[start:start + (e['packed'] if is_compressed(e['flags']) else e['unpacked'])]
        data = pp20_unpack(raw)[0] if is_compressed(e['flags']) else raw
        if data[:4] == b'2GRP':
            banks[e['index']] = data
    for rid, data in wad_files.items():
        if data[:4] == b'2GRP':
            banks.setdefault(rid, data)
    images = collections.defaultdict(set)
    for rid, data in banks.items():
        count = struct.unpack_from('<i', data, 4)[0]
        for i in range(count):
            _, _, _, _, _, tid, tpage, flags, _, _, _, w, h = struct.unpack_from('<hhhhihHHhBBBB', data, 12 + 24 * i)
            images[tid].add((rid, w or 256, h or 256, flags, (tpage >> 8) & 3))
    return images


def word_census(exe, table_offset, count):
    """Aligned program-image words outside the bmp_pointers table, counted by value."""
    words = struct.unpack_from('<%dI' % (exe.length // 4), exe.data, 0)
    first, last = table_offset // 4, table_offset // 4 + count
    return collections.Counter(words[:first] + words[last:])


def exe_refs(census, bmp, index):
    """Words that address any byte of the 16-byte MR_TEXTURE (the code reads te_w, te_h and the UV fields directly)."""
    return sum(census[bmp[index] + k] for k in range(16))


def image_rows(exe, bmp, sources, names, images, table_offset):
    census = word_census(exe, table_offset, len(bmp))
    by_name = {v: k for k, v in names.items()}
    rows = []
    for symbol in SYMBOLS:
        tokens, ids = [], set()
        if symbol == 'glow_1727':
            ids.add(GLOW_TEXTURE)
            source = 'fixed:pc_glow'
        elif sources.get(symbol):
            ids.update(value for _, value in sources[symbol])
            source = 'exe:' + ','.join(label for label, _ in sources[symbol])
        elif symbol[3:] in by_name:
            ids.add(by_name[symbol[3:]])
            source = None
        else:
            rows.append(('image', symbol, -1, 'unresolved', -1, -1, -1, -1, 0, 0))
            continue
        if len(ids) != 1:
            raise ValueError(f'{symbol}: sources disagree {sorted(ids)}')
        index = ids.pop()
        if not 0 <= index < len(bmp):
            raise ValueError(f'{symbol}: texture {index} is outside bmp_pointers')
        tokens.append('pointer:%d' % index)
        if source:
            tokens.append(source)
        name = names.get(index)
        if name:
            if symbol.startswith('im_') and name != symbol[3:]:
                raise ValueError(f'{symbol}: FrogLord names texture {index} {name}')
            tokens.append('name:' + name)
        facts = {(w, h, b) for _, w, h, _, b in images.get(index, ())}
        if len(facts) != 1:
            raise ValueError(f'{symbol}: texture {index} has VLO headers {sorted(facts)}')
        w, h, blend = facts.pop()
        flags = ','.join(str(f) for f in sorted({f for _, _, _, f, _ in images[index]}))
        rows.append(('image', symbol, index, ';'.join(tokens), w, h, flags, blend, len(images[index]),
                     exe_refs(census, bmp, index)))
    return rows


def pgen_rows(records, names, tex, exe, image_ids):
    c_records = {r['name']: r for r in effects.generator_records()}
    rows = []
    for r in records:
        name = names.get(r['address'], '-')
        user2 = r['user_data_2']
        if user2 == 0:
            textures, user2_text = [], '0'
        elif user2 in tex:
            textures, user2_text = [tex[user2]], 'texture'
        else:
            textures, user2_text = texture_list(exe, user2, tex), 'texture_list'
        differences = []
        if name == '-':
            differences.append('absent_from_c')
        else:
            c = c_records[name]
            for field in ('flags', 'max_particles', 'generator_life', 'particle_min_life', 'particle_max_life',
                          'gravity_16', 'user_data_1'):
                if c[field] != r[field]:
                    differences.append(field)
            c_textures = c.get('textures') or ([c['texture']] if c['texture_source'] == 'user_data_2' else [])
            if [image_ids[s] for s in c_textures] != textures:
                differences.append('texture')
        rows.append(('pgen', name, '0x%X' % r['address'], '0x%X' % r['flags'], r['prim_size'], r['max_particles'],
                     r['generator_life'], r['particle_min_life'], r['particle_max_life'], r['gravity_16'],
                     '0x%X' % r['user_data_1'], user2_text, ','.join(str(t) for t in textures) or '-',
                     ','.join(differences) or '-'))
    return rows


def hilite_rows(entries, wads, files, special_table, names):
    model_ids = sorted({rid for children in wads.values() for rid, type_id in children
                        if type_id in (mof.TYPE_MOF, mof.TYPE_MAPMOF)})
    models, rows, borrowed = {}, [], []
    census, census_files = collections.Counter(), collections.defaultdict(set)
    generators = [names.get(address, '-') if address else '-' for address in special_table]
    for rid in model_ids:
        previous = next((o for o in range(rid - 1, -1, -1) if o in models and not models[o]['incomplete']), -1)
        model = mof.parse_model(files[rid], '%d' % rid, models.get(previous), [])
        models[rid] = model
        file_name = mof.file_name(entries, rid)
        for si, static in enumerate(model['statics']):
            for pi, part in enumerate(static['parts']):
                if static['incomplete'] and part['hilites']:
                    borrowed.append(('hilite_borrowed', rid, file_name, si, pi, part['hilites'], previous))
                for hi, (kind, attach, index) in enumerate(part['hilite_list']):
                    if si:
                        special = 'unused'
                    elif kind in HILITE_SPRITE_TYPES:
                        special = 'sprite'
                    elif kind < len(generators) and generators[kind] != '-':
                        special = generators[kind]
                    else:
                        special = 'none' if kind == 0 else 'assert'
                    rows.append(('hilite', rid, file_name, si, pi, hi, kind,
                                 HILITE_TYPES[kind] if kind < len(HILITE_TYPES) else '-', attach, index, special))
                    census[kind] += 1
                    census_files[kind].add(file_name)
    census_rows = [('hilite_census', kind, HILITE_TYPES[kind], census[kind], len(census_files[kind]))
                   for kind in range(len(HILITE_TYPES))]
    generator_rows = [('hilite_generator', kind, HILITE_TYPES[kind], generators[kind]) for kind in range(len(HILITE_TYPES))]
    return rows + borrowed + census_rows + generator_rows


def rows(data_dir, version):
    cfg = exe_tables.parse_cfg(os.path.join(exe_tables.CFG_ROOT, 'versions', version + '.cfg'))
    exe = exe_tables.Exe((Path(data_dir) / 'FROGGER.EXE').read_bytes(), exe_tables.java_int(cfg.values['ramOffset']))
    table_offset = exe_tables.java_int(cfg.values['bmpPointerAddress'])
    bmp, _ = exe_tables.read_bmp_pointers(exe, table_offset)
    tex = texture_index(bmp)
    records = pgen_records(exe)
    names, special, frog = identify_pgens(exe, records)
    sources, score_rows, colour_rows, _ = exe_tables_of(exe, bmp, tex, names, records)
    _, entries, wads, files = mof.load_archive(str(data_dir), exe_tables.java_int(cfg.values['mwiOffset']),
                                               exe_tables.java_int(cfg.values['mwiLength']))
    images = vlo_banks(data_dir, entries, files)
    picture_names = image_names(cfg)
    images_out = image_rows(exe, bmp, sources, picture_names, images, table_offset)
    image_ids = {row[1]: row[2] for row in images_out}
    out = hilite_rows(entries, wads, files, special[1], names)
    out += pgen_rows(records, names, tex, exe, image_ids)
    for index, name in enumerate(FROG_PARTICLES):
        single, multi = frog[1][3 * index + 1], frog[1][3 * index + 2]
        out.append(('frog_particle', index, name, '0x%X' % frog[1][3 * index], names.get(single, '-'),
                    names.get(multi, '-') if multi else '-'))
    return out + images_out + score_rows + colour_rows


def encode(table):
    lines = ['# ' + '\t'.join((kind,) + columns) for kind, columns in HEADERS.items()]
    lines += ['\t'.join(str(c) for c in row) for row in table]
    return '\n'.join(lines) + '\n'


def main():
    """Verify the committed facts by default; rewrite only with an explicit flag."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', type=Path, default=os.environ.get('FROGGER_DATA_DIR'))
    parser.add_argument('--version', default='pc-retail-v3.0e')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    if not args.data_dir:
        parser.error('--data-dir (or FROGGER_DATA_DIR) is required')
    text = encode(rows(args.data_dir, args.version))
    if args.write:
        OUTPUT.write_text(text, encoding='utf-8')
    elif OUTPUT.read_text(encoding='utf-8') != text:
        raise SystemExit('Effect resource facts differ; use --write only to deliberately regenerate')
    print('Effect resource facts verified')


if __name__ == '__main__':
    main()

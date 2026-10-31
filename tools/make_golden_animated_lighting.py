#!/usr/bin/env python3
"""Independent per-part model lighting facts from the frozen C light and GTE path.

Reuses the independent archive, model, animation and map readers in
make_golden_mof.py, make_golden_animation.py, make_golden_map.py and
make_golden_exe_tables.py, and shares no code with the Godot project.

Map lights follow mapdisp.c CreateMapLights (1818-1872): only static records
(category 1) of API type ambient (1) or parallel (2) become lights; a
parallel direction is normalised with MRNormaliseVEC into the frame's z
column. MR_VIEW.C MRAddObjectToViewport (843-876) prepends each light, so the
last records come first, and adds ambient bytes to byte-sized back-colour
fields. MR_LIGHT.C MRUpdateViewportColourMatrix (114-155) and
MRUpdateViewportLightMatrix (178-220) fill the first three parallel slots.
MR_LIGHT.C MRCalculateCustomInstanceLights (369-416) applies custom ambient
and colour scaling. MR_ANIM.C (904-907) multiplies the light matrix by each
part's world transform, itself MR_ANIM.C (829-830) root * part matrix.

Every product is 4.12 integer arithmetic with arithmetic right shifts, as the
GTE computes it. Only light inputs, polygon colours and lit colours are
written; no model or map bytes. Verifies the committed file unless --write.
Usage:
    python3 tools/make_golden_animated_lighting.py <retail-dir> <out-dir> [--write]
"""
import argparse
import os
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_golden_mof as mof
import make_golden_animation as anim
import make_golden_map as maps
import make_golden_paths as paths
from make_golden_exe_tables import LEVEL_CODES, Exe, read_map_book

FILE_NAME = 'animated_lighting.tsv'
LEVELS = ('ORG1', 'CAV1', 'SWP1')
FROG_NAME = 'GEN_FROG.XAR'
FLIPBOOK_NAME = 'ORG_TURTLE3.XMR'
LIGHT_STATIC = 1
API_AMBIENT, API_PARALLEL = 1, 2
CUSTOM_AMBIENT, SCALED_COLOURS = 1, 2
IDENTITY = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096]
ROOTS = (('identity', IDENTITY), ('y90', [0, 0, 4096, 0, 4096, 0, -4096, 0, 0]))
PLAIN = (0, (0, 0, 0), (0, 0, 0))
FROG_VARIANTS = (PLAIN, (CUSTOM_AMBIENT | SCALED_COLOURS, (0, 64, 192), (32, 64, 64)),
                 (SCALED_COLOURS, (64, 64, 64), (0, 0, 0)))
LIGHTS_HEADER = ['lights', 'resource_id', 'name', 'ambient_r', 'ambient_g', 'ambient_b', 'parallels']
SAMPLE_HEADER = ['sample', 'resource_id', 'name', 'map', 'action', 'frame', 'root_rotation', 'part', 'polygon',
                 'flags', 'scale_r', 'scale_g', 'scale_b', 'ambient_r', 'ambient_g', 'ambient_b',
                 'base_r', 'base_g', 'base_b', 'lit']


def map_lights(data):
    """Viewport back colour bytes and up to three (direction, colour bytes) parallel slots."""
    grap = maps.read(data, 80, '<I')[0]
    lite = maps.read(data, grap + 4, '<I')[0]
    maps.signature(data, lite, b'LITE')
    count = maps.read(data, lite + 4, '<I')[0]
    records = [maps.read(data, lite + 8 + 40 * i, '<BBHB3xI8h2H2I') for i in range(count)]
    ambient = [0, 0, 0]
    parallels = []
    for record in reversed(records):
        category, api, colour, direction = record[0], record[3], record[4], record[9:12]
        if category != LIGHT_STATIC:
            continue
        rgb = [colour & 255, (colour >> 8) & 255, (colour >> 16) & 255]
        if api == API_AMBIENT:
            ambient = [(a + c) & 255 for a, c in zip(ambient, rgb)]
        elif api == API_PARALLEL and len(parallels) < 3:
            parallels.append((paths.normalised(direction), rgb))
    return ambient, parallels


def multiply(a, b):
    """MRMulMatrixABC: 4.12 row-major 3x3 product, each sum shifted right by 12."""
    return [sum(a[r * 3 + k] * b[k * 3 + c] for k in range(3)) >> 12 for r in range(3) for c in range(3)]


def clamp(value, low, high):
    return max(low, min(high, value))


def gte_inputs(lights, flags, scale, custom):
    """Back colour and colour matrix in 4.12 units after MRCalculateCustomInstanceLights."""
    ambient, parallels = lights
    back = [b << 4 for b in ambient]
    columns = [[c << 4 for c in rgb] for _d, rgb in parallels]
    if flags & CUSTOM_AMBIENT and not flags & SCALED_COLOURS:
        back = [c << 4 for c in custom]
    if flags & SCALED_COLOURS:
        columns = [[((s << 5) * c) >> 12 for s, c in zip(scale, column)] for column in columns]
        source = custom if flags & CUSTOM_AMBIENT else ambient
        back = [((c * s) >> 7) << 4 for c, s in zip(source, scale)]
    return back, columns


def shade(base, normal, world, lights, back, columns):
    """GTE NCS/NCCS: light matrix (directions * world), colour matrix, back colour, polygon colour."""
    rows = [v for direction, _rgb in lights[1] for v in direction]
    rows += [0] * (9 - len(rows))
    llm = multiply(rows, world)
    intensities = [clamp(sum(llm[i * 3 + j] * normal[j] for j in range(3)) >> 12, 0, 0x7fff) for i in range(3)]
    lit = []
    for channel in range(3):
        total = back[channel] * 4096 + sum(column[channel] * intensities[i] for i, column in enumerate(columns))
        illumination = clamp(total >> 12, 0, 0x7fff)
        lit.append(clamp((base[channel] * illumination) >> 12, 0, 255))
    return lit


def sample_polygons(part):
    indices = [i for i, polygon in enumerate(part['polygon_list']) if polygon['normals']]
    if not indices:
        return []
    return sorted({indices[0], indices[len(indices) // 2], indices[-1]})


def model_rows(rid, name, map_name, lights, part_samples, variants):
    """part_samples: (action, frame, part index, part basis, partcel normals, part)."""
    rows = []
    for root_name, root in ROOTS:
        for action, frame, part_index, basis, normals, part in part_samples:
            world = multiply(root, basis)
            for polygon_index in sample_polygons(part):
                polygon = part['polygon_list'][polygon_index]
                base = polygon['colour'][:3]
                for flags, scale, custom in variants:
                    back, columns = gte_inputs(lights, flags, scale, custom)
                    corners = [shade(base, normals[3 * n:3 * n + 3], world, lights, back, columns)
                               for n in polygon['normals']]
                    rows.append(['sample', rid, name, map_name, action, frame, root_name, part_index,
                                 polygon_index, flags] + list(scale) + list(custom) + list(base) +
                                ['/'.join('%d:%d:%d' % tuple(c) for c in corners)])
    return rows


def frog_samples(data, model):
    xar = anim.parse_xar(data)
    models, actions = xar['sets'][0]
    static_index, part_count = models[0][0], models[0][1]
    parts = model['statics'][static_index]['parts']
    valid = [i for i, a in enumerate(actions) if a['valid'] and a['parts'] >= part_count]
    longest = max(valid, key=lambda i: (actions[i]['frames'], -i))
    poses = [(0, 0), (longest, actions[longest]['frames'] // 2)]
    samples = []
    for action, frame in poses:
        for index in range(part_count):
            basis = anim.sampled_matrix(xar, actions[action], frame, index)[:9]
            samples.append((action, frame, index, basis, parts[index]['partcel_list'][0]['normals'], parts[index]))
    return samples


def flipbook_samples(data, model):
    parts = model['statics'][0]['parts']
    pointer = parts[0]['flipbook_ptr']
    frames, start = struct.unpack_from('<HH', data, pointer + 4)
    samples = []
    for frame in (0, frames - 1):
        for index, part in enumerate(parts):
            normals = part['partcel_list'][start + frame]['normals']
            samples.append((0, frame, index, IDENTITY, normals, part))
    return samples


def resource(entries, name):
    found = [i for i in range(len(entries)) if mof.file_name(entries, i) == name]
    if len(found) != 1:
        raise ValueError('%s resolves to %d resources' % (name, len(found)))
    return found[0]


def unpack(data_dir, entry):
    with open(os.path.join(data_dir, 'FROGPSX.MWD'), 'rb') as f:
        f.seek(entry['sector'] * mof.SECTOR_SIZE)
        compressed = mof.is_compressed(entry['flags'])
        raw = f.read(entry['packed'] if compressed else entry['unpacked'])
    return mof.pp20_unpack(raw)[0] if compressed else raw


def generate(data_dir, version):
    cfg = mof.parse_cfg(os.path.join(mof.CFG_ROOT, 'versions', version + '.cfg'))
    values = {k: mof.java_int(cfg.values[k].strip()) for k in ('mwiOffset', 'mwiLength', 'mapBook', 'themeBook', 'ramOffset')}
    exe_bytes, entries, _wads, files = mof.load_archive(data_dir, values['mwiOffset'], values['mwiLength'])
    book, _end = read_map_book(Exe(exe_bytes, values['ramOffset']), values['mapBook'], values['themeBook'])
    rows = []
    level_lights = []
    for code in LEVELS:
        rid = book[LEVEL_CODES.index(code)]['high_map']
        name = mof.file_name(entries, rid)
        lights = map_lights(unpack(data_dir, entries[rid]))
        level_lights.append((name, lights))
        ambient, parallels = lights
        slots = '/'.join('%d:%d:%d:%d:%d:%d' % tuple(list(d) + list(c)) for d, c in parallels) or '-'
        rows.append(['lights', rid, name] + ambient + [slots])
    for model_name, sampler, variants in ((FROG_NAME, frog_samples, FROG_VARIANTS),
                                          (FLIPBOOK_NAME, flipbook_samples, (PLAIN,))):
        rid = resource(entries, model_name)
        data = files[rid]
        model = mof.parse_model(data, model_name, None, [])
        if model['incomplete']:
            raise ValueError('%s borrows its geometry' % model_name)
        samples = sampler(data, model)
        for map_name, lights in level_lights:
            rows.extend(model_rows(rid, model_name, map_name, lights, samples, variants))
    return rows


def render(rows):
    lines = ['# ' + '\t'.join(LIGHTS_HEADER), '# ' + '\t'.join(SAMPLE_HEADER)]
    lines.extend('\t'.join(str(v) for v in row) for row in rows)
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('data_dir')
    parser.add_argument('out_dir')
    parser.add_argument('--version', default='pc-retail-v3.0e')
    parser.add_argument('--write', action='store_true', help='regenerate instead of verifying')
    args = parser.parse_args()
    rows = generate(args.data_dir, args.version)
    text = render(rows)
    path = os.path.join(args.out_dir, FILE_NAME)
    if args.write:
        os.makedirs(args.out_dir, exist_ok=True)
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
    else:
        existing = open(path, encoding='utf-8').read() if os.path.exists(path) else ''
        if existing != text:
            raise SystemExit('%s differs from an independent regeneration; use --write only deliberately' % path)
    samples = [r for r in rows if r[0] == 'sample']
    corners = sum(len(r[-1].split('/')) for r in samples)
    print('maps=%d samples=%d corners=%d %s' % (len(rows) - len(samples), len(samples), corners,
                                                'written' if args.write else 'verified'))
    return 0


if __name__ == '__main__':
    sys.exit(main())

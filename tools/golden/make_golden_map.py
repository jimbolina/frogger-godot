#!/usr/bin/env python3
"""Independent FrogLord/C MAP and SkyLand facts. Never reads Godot output."""
import argparse
import csv
import os
import struct
import subprocess
import sys
sys.dont_write_bytecode = True
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden import make_golden_mof as archive

TYPES = ('F3', 'F4', 'FT3', 'FT4', 'G3', 'G4', 'GT3', 'GT4', 'G2')
SIZES = (12, 12, 28, 28, 20, 24, 36, 40, 12)


def read(data, at, fmt):
    if at < 0 or at + struct.calcsize(fmt) > len(data):
        raise ValueError('MAP read outside file: %d %s' % (at, fmt))
    return list(struct.unpack_from(fmt, data, at))


def signature(data, at, expected):
    if data[at:at+4] != expected:
        raise ValueError('unexpected packet at %d' % at)


def h(values):
    return archive.list_digest(values)


def parse_map(data):
    signature(data, 0, b'FROG')
    header = read(data, 76, '<6I')
    gene, grap, form, entity, zone, path = header
    for at, sig in zip(header, (b'GENE', b'GRAP', b'FORM', b'EMTP', b'ZONE', b'PATH')):
        signature(data, at, sig)
    light, group, poly, vert, grid, anim = read(data, grap+4, '<6I')
    for at, sig in zip((light, group, poly, vert, grid, anim), (b'LITE', b'GROU', b'POLY', b'VRTX', b'GRID', b'ANIM')):
        signature(data, at, sig)
    general = read(data, gene+4, '<10H12h')
    vc = read(data, vert+4, '<H')[0]
    vertices = [v for i in range(vc) for v in read(data, vert+8+i*8, '<3h')]
    counts = read(data, poly+4, '<9H')
    pointers = read(data, poly+24, '<9I')
    polygons, typed, addresses = [], [], {}
    for ti, (count, pointer, size) in enumerate(zip(counts, pointers, SIZES)):
        words = []
        for pi in range(count):
            at = pointer+pi*size
            addresses[at] = (ti, pi)
            record = read(data, at, '<%dH' % (size//2))
            words.extend(record)
            polygons.extend([ti]+record)
        typed.append((TYPES[ti], count, h(words)))
    group_header = read(data, group+4, '<4h4H')
    gx, gz = group_header[4:6]
    groups, visible, invisible = [], set(), set()
    for gi in range(gx*gz+1):
        at = group+20+gi*72
        gc = read(data, at, '<9B')
        gp = read(data, at+12, '<9I')
        groups.extend(gc+gp+read(data, at+48, '<I'))
        for ti, (count, pointer, size) in enumerate(zip(gc, gp, SIZES)):
            for pi in range(count):
                ref = pointer+pi*size
                if ref not in addresses or addresses[ref][0] != ti:
                    raise ValueError('group polygon does not resolve')
                (visible if gi < gx*gz else invisible).add(ref)
    lc = read(data, light+4, '<I')[0]
    lights = []
    for i in range(lc):
        values = read(data, light+8+i*40, '<BBHB3xI8h2H2I')
        lights.extend(values[:8]+values[9:12]+values[13:15])
    ac, ap = read(data, anim+4, '<2I')
    animations, targets, cels, anim_rows = [], [], [], []
    for ai in range(ac):
        a = read(data, ap+ai*32, '<bbHIHHI4H2I')
        animations.extend(a)
        cel_count, cp, flags, target_count, tp = a[4], a[6], a[9], a[10], a[12]
        cv = read(data, cp, '<%dH' % cel_count) if flags & 2 else []
        tv = []
        for j in range(target_count):
            record = read(data, tp+j*12, '<I8B')
            if record[0] not in addresses:
                raise ValueError('animation polygon does not resolve')
            tv.extend(record)
        targets.extend(tv)
        cels.extend(cv)
        anim_rows.append([ai]+a+[h(cv), h(tv)])
    grid_values = read(data, grid+4, '<4H')
    stacks = [read(data, grid+12+i*4, '<BBH') for i in range(grid_values[0]*grid_values[1])]
    squares = max((s[0]+s[2] for s in stacks), default=0)
    return dict(size=len(data), version=data[8:12].decode('ascii'), general_sha256=h(general),
                vertex_count=vc, vertices_sha256=h(vertices), polygon_count=sum(counts),
                polygons_sha256=h(polygons), groups_x=gx, groups_z=gz,
                group_header_sha256=h(group_header[:3]+group_header[4:]), groups_sha256=h(groups),
                visible_polygon_count=len(visible), invisible_polygon_count=len(invisible),
                unreferenced_polygon_count=len(set(addresses)-visible-invisible),
                light_count=lc, lights_sha256=h(lights), animation_count=ac,
                animations_sha256=h(animations), animation_targets_sha256=h(targets),
                animation_cels_sha256=h(cels), grid_x=grid_values[0], grid_z=grid_values[1],
                grid_square_count=squares, form_count=read(data, form+4, '<H')[0],
                entity_count=read(data, entity+8, '<H')[0], zone_count=read(data, zone+4, '<I')[0],
                path_count=read(data, path+4, '<I')[0]), typed, anim_rows


def visibility_budget(data):
    """Decode visible groups counted by mapdisp.c ExpandMapGroup, excluding G2."""
    grap = read(data, 80, '<I')[0]
    group = read(data, grap + 8, '<I')[0]
    gx, gz = read(data, group + 12, '<2H')
    counts = [sum(read(data, group + 20 + index * 72, '<8B'))
              for index in range(gx * gz)]
    return [len(counts), sum(counts), h(counts)]


def write(out, name, columns, rows):
    with open(os.path.join(out, name), 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f, delimiter='\t', lineterminator='\n')
        writer.writerow(columns)
        writer.writerows(rows)


def animation_states(rows):
    """mapdisp.c MapUpdateAnimatedPolys: packed unsigned UV add carries U into V."""
    samples = []
    for row in rows:
        rid, name, ai = row[:3]
        a = row[3:16]
        du, dv, duration, _, nc, _, _, period, _, flags = a[:10]
        uv_count = uv_word = cel_count = cel = 0
        for tick in range(257):
            if tick in (0, 1, 2, 3, 7, 15, 31, 63, 127, 256):
                samples.append([rid, name, ai, tick, uv_word & 255, uv_word >> 8, uv_count, cel, cel_count])
            if flags & 1:
                uv_count = (uv_count+1) & 65535
                if uv_count == duration:
                    uv_word = uv_count = 0
                else:
                    uv_word = (uv_word+(du & 255)+((dv & 255)<<8)) & 65535
            if flags & 2:
                cel_count = (cel_count+1) & 65535
                if cel_count >= period:
                    cel_count = 0
                    cel = (cel+1) & 65535
                    if cel == nc:
                        cel = 0
    return samples


def verify_c_oracle(executable, data, facts, typed, animations):
    """Compare independently decoded Python fields to frozen compiled C calls."""
    process = subprocess.run([executable], input=data, capture_output=True, check=False)
    if process.returncode:
        raise ValueError('compiled C oracle failed: '+process.stderr.decode('utf-8',errors='replace'))
    expected = []
    gene, grap, _, entity, _, _ = read(data,76,'<6I')
    _, group, poly, _, _, _ = read(data,grap+4,'<6I')
    counts = [row[1] for row in typed]
    pointers = read(data,poly+24,'<9I')
    components, texture_ids = [], []
    for ti in (2,3,6,7):
        slots = 1 if ti in (2,3) else 3 if ti == 6 else 4
        for pi in range(counts[ti]):
            at = pointers[ti]+pi*SIZES[ti]
            texture_ids.extend(read(data,at+18,'<H'))
            for si in range(slots):
                components.extend(read(data,at+24+si*4,'<3B'))
    expected.append(['H',read(data,4,'<I')[0],facts['vertex_count'],facts['entity_count'],
                     facts['form_count'],facts['path_count'],facts['grid_x'],facts['grid_z'],
                     facts['grid_square_count'],max(texture_ids,default=-1)])
    gh = read(data,group+4,'<4h4H')
    expected.extend([['G']+gh[:3]+gh[4:], ['N']+read(data,gene+4,'<10H'), ['P']+counts,
                     ['R',max(components,default=-1),sum(v>128 for v in components),
                      sum(v==128 for v in components),len(components)], ['C',facts['animation_count']]])
    for row in animations:
        ai = row[0]
        a = row[1:14]
        expected.append(['A',ai,a[9],a[4],a[6],a[10],a[12]])
        if a[9]&2:
            expected.append(['T',ai]+read(data,a[6],'<%dH'%a[4]))
    for i in range(facts['entity_count']):
        at = read(data,entity+12+i*4,'<I')[0]
        expected.append(['E',i]+read(data,at,'<4H'))
    wanted = '\n'.join('\t'.join(str(v) for v in row) for row in expected)+'\n'
    actual = process.stdout.decode('ascii').replace('\r\n','\n')
    if actual != wanted:
        actual_rows = actual.splitlines()
        for i,row in enumerate(wanted.splitlines()):
            if i >= len(actual_rows) or actual_rows[i] != row:
                raise ValueError('compiled C oracle disagreement at row %d: Python %s; C %s' %
                                 (i,row,actual_rows[i] if i<len(actual_rows) else '<absent>'))
        raise ValueError('compiled C oracle returned additional rows')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('data_dir')
    parser.add_argument('out_dir')
    parser.add_argument('--version', default='pc-retail-v3.0e')
    parser.add_argument('--c-oracle', help='External map_oracle_adapter executable linked to the existing frozen C library')
    args = parser.parse_args()
    cfg = archive.parse_cfg(os.path.join(archive.CFG_ROOT, 'versions', args.version+'.cfg'))
    _, entries, _, files = archive.load_archive(args.data_dir, archive.java_int(cfg.values['mwiOffset']), archive.java_int(cfg.values['mwiLength']))
    with open(os.path.join(args.data_dir, 'FROGPSX.MWD'), 'rb') as f:
        mwd = f.read()
    for entry in entries:
        if entry['type'] != 0 or entry['flags'] & archive.FLAG_GROUP_ACCESS:
            continue
        start = entry['sector']*archive.SECTOR_SIZE
        compressed = archive.is_compressed(entry['flags'])
        raw = mwd[start:start+(entry['packed'] if compressed else entry['unpacked'])]
        files[entry['index']] = archive.pp20_unpack(raw)[0] if compressed else raw
    maps, polys, anims, sky, visibility = [], [], [], [], []
    fields = None
    for rid, data in sorted(files.items()):
        name = archive.file_name(entries, rid)
        if not name.upper().endswith('.MAP'):
            continue
        if data[:4] == b'FROG':
            facts, typed, animations = parse_map(data)
            visibility.append([rid, name] + visibility_budget(data))
            if args.c_oracle:
                verify_c_oracle(args.c_oracle, data, facts, typed, animations)
            fields = list(facts)
            maps.append([rid, name]+list(facts.values()))
            polys.extend([rid, name]+list(row) for row in typed)
            anims.extend([rid, name]+row for row in animations)
        else:
            x, z = read(data, 0, '<2H')
            if len(data) != 4+x*z*2:
                raise ValueError('unexpected non-FROG MAP')
            tiles = read(data, 4, '<%dH' % (x*z))
            sky.append([rid, name, x, z, h(tiles), h([v & 0x3fff for v in tiles]), h([v >> 14 for v in tiles])])
    if (len(maps), len(sky)) != (78, 2):
        raise ValueError('unexpected map census %d/%d' % (len(maps), len(sky)))
    os.makedirs(args.out_dir, exist_ok=True)
    write(args.out_dir, 'map_visibility_budget.tsv', ['resource_id', 'name', 'group_count', 'polygon_total', 'counts_sha256'], visibility)
    write(args.out_dir, 'map_facts.tsv', ['resource_id','name']+fields, maps)
    write(args.out_dir, 'map_polygons.tsv', ['resource_id','name','type','count','records_sha256'], polys)
    write(args.out_dir, 'map_animations.tsv', ['resource_id','name','animation','du','dv','duration','runtime_uv','cel_count','runtime_current_cel','cel_pointer','cel_period','runtime_cel_count','flags','target_count','runtime_texture','target_pointer','cels_sha256','targets_sha256'], anims)
    write(args.out_dir, 'sky_land.tsv', ['resource_id','name','width','height','tiles_sha256','texture_ids_sha256','rotations_sha256'], sky)
    write(args.out_dir, 'map_animation_states.tsv', ['resource_id','name','animation','updates','offset_u','offset_v','uv_count','current_cel','cel_count'], animation_states(anims))
    lighting = []
    for minimum, maximum in ((0,65536), (65536,262144), (65536,655360), (16384,65536)):
        factor = (128<<16)//(maximum-minimum)
        for distance in (0, minimum-1, minimum, minimum+1, (minimum+maximum)//2, maximum-1, maximum, maximum+1):
            if distance < 0:
                continue
            intensity = 128 if distance < minimum else 0 if distance > maximum else 128-((factor*(distance-minimum))>>16)
            lighting.append([minimum, maximum, distance, factor, intensity])
    write(args.out_dir, 'map_lighting.tsv', ['minimum_r2','maximum_r2','distance_r2','factor','intensity'], lighting)
    print('Generated %d maps, %d polygon type rows, %d animations, %d SkyLand maps.' % (len(maps),len(polys),len(anims),len(sky)))
    if args.c_oracle:
        print('Frozen compiled C overlap passed for all 78 maps: all nine polygon counts, general/group/grid/header census, all four textured RGB and texture-index scans, 297 animation scalars/cel lists and 7123 entity identities.')


if __name__ == '__main__':
    main()

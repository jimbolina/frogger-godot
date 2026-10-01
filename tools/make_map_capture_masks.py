#!/usr/bin/env python3
"""Source-only terrain coverage for fixed 640x480 map_slice captures.

python tools/make_map_capture_masks.py RETAIL_DIR --level SUB1 --out EXTERNAL.json
No reference or candidate pixels are read. C's NCLIP selects eligible faces;
entity exclusions and measured reference landmarks must be declared separately.
"""
import argparse
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
import make_golden_map as maps
import make_golden_map_projection as projection


def clip(points):
    """Sutherland-Hodgman clipping to pixel-centre bounds, no image sampling."""
    for axis, bound, lower in ((0, 0, True), (0, 639, False), (1, 0, True), (1, 479, False)):
        output = []
        if not points:
            break
        previous = points[-1]
        previous_in = previous[axis] >= bound if lower else previous[axis] <= bound
        for current in points:
            current_in = current[axis] >= bound if lower else current[axis] <= bound
            if current_in != previous_in:
                fraction = (bound - previous[axis]) / (current[axis] - previous[axis])
                intersection = [previous[i] + fraction * (current[i] - previous[i]) for i in range(2)]
                intersection[axis] = bound
                output.append(intersection)
            if current_in:
                output.append(current)
            previous, previous_in = current, current_in
        points = output
    return [[round(x), round(y)] for x, y in points]


def signed_area(a, b, c):
    return a[0]*b[1] + b[0]*c[1] + c[0]*a[1] - a[0]*c[1] - b[0]*a[1] - c[0]*b[1]


def clip_segment(a, b):
    """Clip existing polygon edges, without inventing viewport-border edges."""
    low, high = 0.0, 1.0
    delta = [b[i] - a[i] for i in range(2)]
    for p, q in ((-delta[0], a[0]), (delta[0], 639-a[0]),
                 (-delta[1], a[1]), (delta[1], 479-a[1])):
        if p == 0:
            if q < 0:
                return None
        elif p < 0:
            low = max(low, q/p)
        else:
            high = min(high, q/p)
        if low > high:
            return None
    return [[round(a[i] + t*delta[i]) for i in range(2)] for t in (low, high)]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('retail_dir')
    parser.add_argument('--level', required=True, help='FrogLord level code, high-poly map')
    parser.add_argument('--out', required=True, help='External JSON; paths inside the repository are rejected')
    parser.add_argument('--version', default='pc-retail-v3.0e')
    args = parser.parse_args()
    output = Path(args.out).resolve()
    repository = Path(__file__).resolve().parent.parent
    if output.is_relative_to(repository):
        parser.error('--out must be outside the repository')
    archive = maps.archive
    code = args.level.upper()
    if code not in archive.LEVEL_CODES:
        parser.error('Unknown level code')
    cfg = archive.parse_cfg(str(Path(archive.CFG_ROOT) / 'versions' / (args.version + '.cfg')))
    get = lambda key: archive.java_int(cfg.values[key])
    exe_bytes, entries, _, _ = archive.load_archive(args.retail_dir, get('mwiOffset'), get('mwiLength'))
    books, _ = archive.read_map_book(archive.Exe(exe_bytes, get('ramOffset')), get('mapBook'), get('themeBook'))
    rid = books[archive.LEVEL_CODES.index(code)]['high_map']
    entry = entries[rid]
    with (Path(args.retail_dir) / 'FROGPSX.MWD').open('rb') as stream:
        stream.seek(entry['sector'] * archive.SECTOR_SIZE)
        data = stream.read(entry['packed'] if archive.is_compressed(entry['flags']) else entry['unpacked'])
    if archive.is_compressed(entry['flags']):
        data = archive.pp20_unpack(data)[0]
    maps.parse_map(data)  # Independent structural validation before projection.
    grap = maps.read(data, 80, '<I')[0]
    _, group, _, vert, _, _ = maps.read(data, grap + 4, '<6I')
    vertices = [maps.read(data, vert + 8 + i * 8, '<3h') for i in range(maps.read(data, vert + 4, '<H')[0])]
    target = [projection.divide(min(v[i] for v in vertices) + max(v[i] for v in vertices), 2) for i in range(3)]
    camera = [target[0], target[1] - 10000, target[2] - 10000]
    gh = maps.read(data, group + 4, '<4h4H')
    gx, gz, width, height = gh[4:]
    def distance(index):
        x = gh[0] + index % gx * width + width // 2
        z = gh[2] + index // gx * height + height // 2
        return (x - target[0]) ** 2 + (z - target[2]) ** 2, index
    candidates = sorted(range(gx * gz), key=distance)[:128] if gx*gz > 128 else list(range(gx*gz))
    selected, budget_skipped, remaining = [], [], 2500
    for index in candidates:
        if remaining <= 0:
            break
        group_count = sum(maps.read(data, group + 20 + index*72, '<8B'))
        if group_count > remaining:
            budget_skipped.append(index)
            continue
        selected.append(index)
        remaining -= group_count
    regions = []
    polygon_count = g2_count = depth_rejected = backface_rejected = 0
    for index in selected:
        at = group + 20 + index * 72
        counts = maps.read(data, at, '<9B')
        pointers = maps.read(data, at + 12, '<9I')
        for kind, (count, pointer, size) in enumerate(zip(counts, pointers, maps.SIZES)):
            if kind == 8:
                g2_count += count
                continue
            corners = 3 if kind in (0, 2, 4, 6) else 4
            for ordinal in range(count):
                record = maps.read(data, pointer + ordinal * size, '<%dH' % (size // 2))
                projected = [projection.project(vertices[vi], camera) for vi in record[:corners]]
                # MRStub NCLIP uses raw SXY FIFO coordinates before gte_stsxy
                # narrows them. mapdisp.c accepts positive first triangle;
                # a quad also accepts its negative (1,2,3) second triangle.
                raw_screen = [[p[7], p[8]] for p in projected]
                first_area = signed_area(*raw_screen[:3])
                if first_area <= 0 and (corners == 3 or signed_area(*raw_screen[1:]) >= 0):
                    backface_rejected += 1
                    continue
                depths = [p[6] for p in projected]
                average = (1365 * sum(depths)) >> 12 if corners == 3 else sum(depths) // 4
                flags = record[4] if kind in (2, 3, 6, 7) else 0
                if not flags & 6 and (average <= 16 or (average >> 2) + 64 >= 4096):
                    depth_rejected += 1
                    continue
                polygon_count += 1
                screen = [[p[9], p[10]] for p in projected]
                for indices in ((0, 1, 2),) if corners == 3 else ((0, 1, 2), (1, 3, 2)):
                    points = clip([screen[i] for i in indices])
                    if len(points) >= 3:
                        regions.append({'polygon': points})
    if code.startswith('SKY'):
        regions = [{'rect': [0, 0, 640, 480]}]
    result = {'eligible_terrain': regions, 'include': regions,
              'raster_edge_policy': 'eligible_union_silhouette',
              'exclude': [], 'landmarks': [],
              'source': {'level': code, 'resource_id': rid, 'camera': camera, 'target': target,
                         'selected_groups': selected, 'projected_polygons': polygon_count,
                         'group_candidates': candidates, 'budget_skipped_groups': budget_skipped,
                         'polygon_budget_remaining': remaining,
                         'depth_rejected_polygons': depth_rejected, 'ignored_g2': g2_count,
                         'backface_rejected_polygons': backface_rejected,
                         'coverage_policy': 'Source projected geometry and C NCLIP face selection; invisible and unreferenced excluded; no entities; SKY includes full backdrop. No candidate pixels or error-driven masks.'}}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('%s: %d regions, %d selected groups -> %s' % (code, len(regions), len(selected), output))


if __name__ == '__main__':
    main()

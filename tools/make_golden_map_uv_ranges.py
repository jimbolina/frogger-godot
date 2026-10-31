#!/usr/bin/env python3
"""Golden facts for the premise that map terrain can sample per-image textures.

The modern rendering profile draws each textured map polygon from its own
padded image with repeat wrapping instead of the reconstructed 256x256 pages
(docs/reference/rendering/modern-profile.md). That is only faithful while
every corner lands inside the image, or on the first padding column or row
(u == width, v == height), and while the environment-mapped polygons use
images that fill a whole page. This generator measures that on every map
in the archive with the banks and remap the game loads for it.

For each map: the map book row and detail that load it give the remap
(SCGameInstance.readTextureRemaps) and the two banks (the GENERAL theme's
bank, then the map's theme bank, by detail and multiplayer level). A local
texture id resolves through the remap to a global id, which is looked up in
the theme bank first, then the GENERAL bank. Each corner's pixel is
mapload.C ResolveMapPolys' `coordinate * size / 255`, stored in a byte, and
the page byte the PC samples is `(pixel + image u) & 255`; the corner sits
`((pixel + u) & 255) - u` from the image's left edge (rows likewise).

A static polygon is a textured polygon that no animation targets; an
animated instance is one (animation, target polygon) pair, stepped through
one whole period of mapdisp.c MapUpdateAnimatedPolys from the stored
counters: the 16-bit packed U/V offset add (U carries into V) and its reset
when the count reaches the duration, and the cel list (resolved through the
remap) advancing every cel period. The base pixels come from the polygon's
own image; each state is measured against the image the animation shows.
ENVMAP polygons (flag bit 1) get camera-driven UVs and are counted apart.

Rows (tests/golden/specs/imported-assets.md "Map UV ranges"):
    map      name, textured_polygons, static_polygons, outside_static, max_static_reach,
             animated_instances, outside_scroll, max_scroll_reach, scroll_textures,
             env_polygons, env_textures
    env      texture id, bank, u, v, width, height, padded_width, padded_height,
             vram_x, vram_y, vram_page for every image an ENVMAP polygon uses
    padding  the smallest padding on one side over every image a map polygon or
             cel resolves to

Independent of the Godot project: maps are read from the frozen C layouts
(mapdisp.H), banks from their 2GRP headers, the books and remaps by
make_golden_exe_tables.py.

Usage:
    python3 tools/make_golden_map_uv_ranges.py [RETAIL_DIR] [OUTPUT] [--write]

RETAIL_DIR defaults to FROGGER_DATA_DIR and OUTPUT to
tests/golden/imported/map_uv_ranges.tsv. Without --write the facts are
compared with OUTPUT and a difference exits 1.
"""

import argparse
import difflib
import math
import os
import struct
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from imported_assets_common import ROOT, Archive
from make_golden_exe_tables import read_map_book, read_remaps, read_theme_book

OUTPUT = os.path.join(ROOT, "tests", "golden", "imported", "map_uv_ranges.tsv")
TEXTURED = {2: (28, 3), 3: (28, 4), 6: (36, 3), 7: (40, 4)}
SIZES = (12, 12, 28, 28, 20, 24, 36, 40, 12)
UV_OFFSETS = (12, 16, 20, 22)
POLY_ENVMAP = 1 << 1
ANIM_UV = 1 << 0
ANIM_TEXTURE = 1 << 1
IMAGE_HEADER = struct.Struct("<hhhhihHHhBBBB")
ANIM_HEADER = struct.Struct("<BBHBBHHHIHHHHII")
MAX_PERIOD = 1 << 20
PADDING_RULE = ("# padding rule: a corner may reach u == width or v == height, the first padding column or row; "
                "every image a map polygon or cel uses has at least one padding pixel on each side")


def bank_images(data):
    """Image headers of a 2GRP bank in stored order, as dicts."""
    if data[:4] != b"2GRP":
        raise ValueError("not a PC texture bank")
    count = struct.unpack_from("<i", data, 4)[0]
    images = []
    for i in range(count):
        vx, vy, pw, ph, _off, tid, _tp, _flags, _clut, u, v, w, h = IMAGE_HEADER.unpack_from(data, 12 + 24 * i)
        images.append({"texture_id": tid, "vram_x": vx, "vram_y": vy, "padded_w": pw, "padded_h": ph,
                       "u": u, "v": v, "w": w or 256, "h": h or 256})
    return images


def bank_id(theme, multiplayer, low_poly):
    """The multiplayer bank of the chosen detail when the theme has one, else the ordinary bank."""
    chosen = theme[("low" if low_poly else "high") + ("_mp" if multiplayer else "") + "_vlo"]
    return chosen or theme["low_vlo" if low_poly else "high_vlo"]


class Lookup:
    """Global texture id to image: the theme bank first, then the GENERAL bank; a bank holds each id once."""

    def __init__(self, general, theme):
        self.order = []
        for images in (theme, general):
            table = {img["texture_id"]: img for img in images}
            if len(table) != len(images):
                raise ValueError("a bank holds a texture id twice")
            self.order.append(table)

    def image(self, texture_id):
        for table in self.order:
            if texture_id in table:
                return table[texture_id]
        return None


def read_polygons(data):
    """{record offset: (type, flags, local texture id, [(u byte, v byte)])} of the textured map polygons."""
    grap = struct.unpack_from("<I", data, 80)[0]
    poly = struct.unpack_from("<I", data, grap + 12)[0]
    counts = struct.unpack_from("<9H", data, poly + 4)
    pointers = struct.unpack_from("<9I", data, poly + 24)
    polygons = {}
    for kind, (size, corners) in TEXTURED.items():
        if size != SIZES[kind]:
            raise ValueError("polygon size mismatch")
        for i in range(counts[kind]):
            at = pointers[kind] + i * size
            flags = struct.unpack_from("<H", data, at + 8)[0]
            local = struct.unpack_from("<H", data, at + 18)[0]
            uvs = [(data[at + o], data[at + o + 1]) for o in UV_OFFSETS[:corners]]
            polygons[at] = (kind, flags, local, uvs)
    return polygons


def read_animations(data):
    """MAP_ANIM records: header fields, cel list and target polygon offsets."""
    grap = struct.unpack_from("<I", data, 80)[0]
    anim = struct.unpack_from("<I", data, grap + 24)[0]
    count, first = struct.unpack_from("<2I", data, anim + 4)
    result = []
    for i in range(count):
        (du, dv, duration, ofs_u, ofs_v, uv_count, cel_total, cel, cel_list, cel_period, cel_count, flags,
         target_count, _texture, targets) = ANIM_HEADER.unpack_from(data, first + 32 * i)
        cels = list(struct.unpack_from("<%dH" % cel_total, data, cel_list)) if flags & ANIM_TEXTURE else []
        result.append({"du": du, "dv": dv, "duration": duration, "offset": ofs_u | (ofs_v << 8), "uv_count": uv_count,
                       "cel": cel, "cel_count": cel_count, "cel_period": cel_period, "cels": cels, "flags": flags,
                       "targets": [struct.unpack_from("<I", data, targets + 12 * j)[0] for j in range(target_count)]})
    return result


def global_id(remap, local):
    return remap[local] if 0 <= local < len(remap) else -1


def pixels(uvs, img):
    """ResolveMapPolys: each corner's byte pixel inside its image."""
    return [((c_u * img["w"] // 255) & 255, (c_v * img["h"] // 255) & 255) for c_u, c_v in uvs]


def reach(base, img, offset_u=0, offset_v=0):
    """How far past the image (0 inside, u == width included) the corners land when img is shown."""
    bu = (img["u"] + offset_u) & 255
    bv = (img["v"] + offset_v) & 255
    worst = 0
    for p_u, p_v in base:
        x = ((p_u + bu) & 255) - img["u"]
        y = ((p_v + bv) & 255) - img["v"]
        worst = max(worst, -x, x - img["w"], -y, y - img["h"])
    return worst


def period(anim):
    """Ticks after which the animation's state repeats."""
    ticks = 1
    if anim["flags"] & ANIM_UV:
        ticks = anim["duration"] or 65536
    if anim["flags"] & ANIM_TEXTURE:
        ticks = ticks * max(1, anim["cel_period"]) * max(1, len(anim["cels"])) // math.gcd(
            ticks, max(1, anim["cel_period"]) * max(1, len(anim["cels"])))
    if ticks > MAX_PERIOD:
        raise ValueError("animation period %d too long" % ticks)
    return ticks


def states(anim, remap, initial):
    """(offset word, global image id) after each update over one period, from the stored counters."""
    offset, uv_count = anim["offset"], anim["uv_count"]
    cel, cel_count = anim["cel"], anim["cel_count"]
    image = initial
    cels = [global_id(remap, local) for local in anim["cels"]]
    seen = []
    for _tick in range(period(anim)):
        if anim["flags"] & ANIM_UV:
            uv_count = (uv_count + 1) & 0xFFFF
            if uv_count == anim["duration"]:
                offset = uv_count = 0
            else:
                offset = (offset + anim["du"] + (anim["dv"] << 8)) & 0xFFFF
        if anim["flags"] & ANIM_TEXTURE and cels:
            cel_count = (cel_count + 1) & 0xFFFF
            if cel_count >= anim["cel_period"]:
                cel_count = 0
                cel = (cel + 1) & 0xFFFF
                if cel == len(cels):
                    cel = 0
                image = cels[cel]
        seen.append((offset, image))
    return sorted(set(seen))


def map_facts(name, data, remap, lookup, used, env_images):
    """The map row; adds every image the map uses to used and its ENVMAP images to env_images."""
    polygons = read_polygons(data)
    animations = read_animations(data)
    targeted = set()
    for anim in animations:
        for at in anim["targets"]:
            if at not in polygons:
                raise ValueError("%s: animation target %d is not a textured polygon" % (name, at))
            targeted.add(at)
    static = outside_static = static_reach = environment = 0
    env = set()
    for at, (_kind, flags, local, uvs) in sorted(polygons.items()):
        texture_id = global_id(remap, local)
        img = lookup.image(texture_id)
        if img is None:
            raise ValueError("%s: polygon at %d has no image for texture %d" % (name, at, texture_id))
        used.add(id(img))
        if flags & POLY_ENVMAP:
            environment += 1
            env.add(texture_id)
            env_images.setdefault((texture_id, id(img)), img)
            continue
        if at in targeted:
            continue
        static += 1
        worst = reach(pixels(uvs, img), img)
        static_reach = max(static_reach, worst)
        if worst > 0:
            outside_static += 1
    animated = outside_scroll = scroll_reach = 0
    scroll_textures = set()
    for anim in animations:
        for at in anim["targets"]:
            _kind, flags, local, uvs = polygons[at]
            if flags & POLY_ENVMAP:
                continue
            animated += 1
            own = lookup.image(global_id(remap, local))
            base = pixels(uvs, own)
            worst = 0
            for offset, texture_id in states(anim, remap, global_id(remap, local)):
                img = lookup.image(texture_id)
                if img is None:
                    raise ValueError("%s: animation image %d is in no bank" % (name, texture_id))
                used.add(id(img))
                distance = reach(base, img, offset & 255, offset >> 8)
                if distance > 0:
                    scroll_textures.add(texture_id)
                worst = max(worst, distance)
            scroll_reach = max(scroll_reach, worst)
            if worst > 0:
                outside_scroll += 1
    return ("map", name, len(polygons), static, outside_static, static_reach, animated, outside_scroll, scroll_reach,
            ids(scroll_textures), environment, ids(env))


def ids(values):
    return ",".join(str(v) for v in sorted(values)) or "-"


def facts(data_dir):
    """The TSV text and a summary line."""
    archive = Archive(data_dir)
    exe, cfg = archive.exe, archive.cfg
    rows_book, _end = read_map_book(exe, cfg["mapBook"], cfg["themeBook"])
    themes = read_theme_book(exe, cfg["themeBook"])
    remaps = {r["resource"]: r["ids"] for r in read_remaps(exe, archive.entries, rows_book, cfg.get("txl_sky_land", 0))}
    banks = {}
    loads = {}
    for level, row in enumerate(rows_book):
        for low_poly in (False, True):
            map_id = row["low_map" if low_poly else "high_map"]
            if map_id > 0:
                loads.setdefault(map_id, []).append((level, low_poly))
    map_ids = sorted(e["index"] for e in archive.entries
                     if archive.name(e["index"]).upper().endswith(".MAP")
                     and not archive.name(e["index"]).upper().startswith("SKY_LAND"))
    rows, used, env_images, placements = [], set(), {}, {}
    for map_id in map_ids:
        name = archive.name(map_id).rsplit(".", 1)[0]
        if len(loads.get(map_id, [])) != 1:
            raise ValueError("%s is loaded by %d map book rows, not one" % (name, len(loads.get(map_id, []))))
        level, low_poly = loads[map_id][0]
        data = archive.resource(map_id)
        if data[:4] != b"FROG":
            raise ValueError("%s is not a map" % name)
        gene = struct.unpack_from("<I", data, 76)[0]
        theme = struct.unpack_from("<10H", data, gene + 4)[3]
        multiplayer = level % 6 == 5
        pair = [bank_id(themes[0], multiplayer, low_poly), bank_id(themes[theme], multiplayer, low_poly)]
        for rid in pair:
            if rid not in banks:
                banks[rid] = bank_images(archive.resource(rid))
                for img in banks[rid]:
                    placements[id(img)] = (img, archive.name(rid))
        lookup = Lookup(banks[pair[0]], banks[pair[1]])
        rows.append(map_facts(name, data, remaps[map_id], lookup, used, env_images))
    env_rows = set()
    for (texture_id, key), img in env_images.items():
        bank = placements[key][1].rsplit(".", 1)[0]
        env_rows.add(("env", texture_id, bank, img["u"], img["v"], img["w"], img["h"], img["padded_w"], img["padded_h"],
                      img["vram_x"], img["vram_y"], img["vram_y"] // 256))
    minimum = min(min((placements[key][0]["padded_w"] - placements[key][0]["w"]) // 2,
                      (placements[key][0]["padded_h"] - placements[key][0]["h"]) // 2) for key in used)
    text = "\n".join([
        "# Map UV ranges: tests/golden/specs/imported-assets.md#map-uv-ranges",
        PADDING_RULE,
        "# map\tname\ttextured_polygons\tstatic_polygons\toutside_static\tmax_static_reach\tanimated_instances"
        "\toutside_scroll\tmax_scroll_reach\tscroll_textures\tenv_polygons\tenv_textures",
        "# env\ttexture_id\tbank\tu\tv\twidth\theight\tpadded_width\tpadded_height\tvram_x\tvram_y\tvram_page",
        "# padding\tminimum\tvalue",
    ]) + "\n"
    body = [tuple(r) for r in rows] + sorted(env_rows) + [("padding", "minimum", minimum)]
    text += "".join("\t".join(str(c) for c in row) + "\n" for row in body)
    summary = "%d maps, %d env images, minimum padding %d, %d placements used" % (
        len(rows), len(env_rows), minimum, len(used))
    return text, summary


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("data_dir", nargs="?", default=os.environ.get("FROGGER_DATA_DIR", ""),
                        help="folder with FROGGER.EXE and FROGPSX.MWD (default: $FROGGER_DATA_DIR)")
    parser.add_argument("output", nargs="?", default=OUTPUT, help="the facts file (default: %(default)s)")
    parser.add_argument("--write", action="store_true", help="rewrite the facts file instead of comparing")
    args = parser.parse_args()
    if not args.data_dir:
        parser.error("no retail folder: pass RETAIL_DIR or set FROGGER_DATA_DIR")
    started = time.time()
    text, summary = facts(args.data_dir)
    summary += ", %.1f s" % (time.time() - started)
    if args.write:
        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        with open(args.output, "w", newline="\n", encoding="utf-8") as f:
            f.write(text)
        print("wrote %s (%s)" % (args.output, summary))
        return
    old = open(args.output, encoding="utf-8").read() if os.path.exists(args.output) else ""
    if old != text:
        diff = list(difflib.unified_diff(old.splitlines(True), text.splitlines(True), args.output, "generated", n=0))
        sys.stdout.writelines(diff[:80])
        print("%s: committed facts differ from the generator; rerun with --write only to regenerate deliberately"
              % args.output)
        sys.exit(1)
    print("%s: committed facts match the generator (%s)" % (args.output, summary))


if __name__ == "__main__":
    main()

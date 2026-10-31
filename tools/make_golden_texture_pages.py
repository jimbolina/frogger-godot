#!/usr/bin/env python3
"""Golden facts for the composed 256x256 PC texture pages the maps sample.

For every pair of texture banks a map loads (the GENERAL theme's bank, then
the map's own theme bank, chosen by multiplayer level and detail exactly as
the theme book says), the fourteen physical 256x256 pages are composed in
upload order and the PC colour key is applied page-wide. Sky levels also get
one row for the sky-land atlas built from those pages. Each row gives the
SHA-256 of the RGBA8 bytes and the number of opaque pixels; the composition
rule is in tests/golden/specs/imported-assets.md.

Independent of the Godot project: banks are decoded by make_golden_vlo.py's
FrogLord reading, the books by make_golden_exe_tables.py.

Usage:
    python3 tools/make_golden_texture_pages.py [--data-dir DIR] [--output FILE] [--check]
"""

import hashlib
import os
import struct
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from imported_assets_common import Archive, arguments, finish, tsv
from make_golden_exe_tables import read_map_book, read_remaps, read_theme_book
from make_golden_vlo import FLAG_BLACK_IS_TRANSPARENT, parse_vlo

PAGE = 256
PAGES = 14
SKY_THEME = 8
ZERO = bytes([1]) + bytes(255)
ALPHA_FROM_BLACK = bytes([255, 0]) + bytes(254)


def bank_id(theme, multiplayer, low_poly):
    """MapSceneData._load_bank: the multiplayer bank, else the ordinary one, of the chosen detail."""
    key = ("low" if low_poly else "high") + ("_mp" if multiplayer else "") + "_vlo"
    chosen = theme[key]
    if chosen == 0:
        chosen = theme["low_vlo" if low_poly else "high_vlo"]
    return chosen


def valid_upload(img):
    """MapTexturePages._valid_upload."""
    return (img["vram_x"] >= 0 and img["vram_y"] >= 0 and img["padded_w"] > 0 and img["padded_h"] > 0
            and img["vram_x"] + img["padded_w"] <= PAGE and img["vram_y"] + img["padded_h"] <= PAGES * PAGE
            and len(img["rgba"]) == img["padded_w"] * img["padded_h"] * 4)


def page_keyed(banks, page):
    """True when any valid upload on page carries the black-is-transparent flag, so the page gets the colour key."""
    return any(valid_upload(img) and img["page"] == page and img["flags"] & FLAG_BLACK_IS_TRANSPARENT
               for images in banks for img in images)


def blit_uploads(banks, page, scale=1, pixels_of=None):
    """RGBA8 bytes of one physical page at scale: black opaque, every valid upload blitted in order, no colour key.

    pixels_of(img) supplies an upload's RGBA bytes at scale (padded_w * scale wide); the retail pixels by default.
    """
    size = PAGE * scale
    out = bytearray(b"\0\0\0\xff" * (size * size))
    top = page * size
    for images in banks:
        for img in images:
            if not valid_upload(img):
                continue
            vram_y = img["vram_y"] * scale
            y0 = max(vram_y, top)
            y1 = min(vram_y + img["padded_h"] * scale, top + size)
            if y0 >= y1:
                continue
            pixels = img["rgba"] if pixels_of is None else pixels_of(img)
            width = img["padded_w"] * scale * 4
            for y in range(y0, y1):
                src = (y - vram_y) * width
                dst = ((y - top) * size + img["vram_x"] * scale) * 4
                out[dst:dst + width] = pixels[src:src + width]
    return out


def compose_page(banks, page):
    """RGBA8 bytes of one physical page: black opaque, every valid upload blitted in order, then the colour key."""
    out = blit_uploads(banks, page)
    count = PAGE * PAGE
    if page_keyed(banks, page):
        zr = int.from_bytes(bytes(out[0::4]).translate(ZERO), "big")
        zg = int.from_bytes(bytes(out[1::4]).translate(ZERO), "big")
        zb = int.from_bytes(bytes(out[2::4]).translate(ZERO), "big")
        out[3::4] = (zr & zg & zb).to_bytes(count, "big").translate(ALPHA_FROM_BLACK)
    else:
        out[3::4] = b"\xff" * count
    return bytes(out)


def sky_atlas(pages, order, scale=1):
    """MapMeshBuilder._build_sky's atlas at scale: 256 x 258 per page slot, magenta, each page between its first
    and last rows repeated scale times."""
    slots = max(1, len(order))
    size = PAGE * scale
    row = size * 4
    slot_rows = 258 * scale
    atlas = bytearray(b"\xff\x00\xff\xff" * (size * slot_rows * slots))
    for slot, page in enumerate(order):
        if not 0 <= page < PAGES:
            continue
        pixels = pages[page]
        base = slot * slot_rows * row
        atlas[base + scale * row:base + (scale + size) * row] = pixels
        atlas[base:base + scale * row] = pixels[:row] * scale
        atlas[base + (scale + size) * row:base + slot_rows * row] = pixels[(size - 1) * row:size * row] * scale
    return bytes(atlas)


def sky_tiles(data):
    """Local texture ids (the low 14 bits) of a sky-land file's tiles, row-major."""
    width, height = struct.unpack_from("<2H", data, 0)
    if len(data) != 4 + width * height * 2:
        raise ValueError("unexpected sky-land size")
    return [v & 0x3FFF for v in struct.unpack_from("<%dH" % (width * height), data, 4)]


def discover_sets(archive):
    """The bank pairs every map loads, keyed (general bank id, theme bank id), each with the sky-land files its
    sky levels use; and the sky-land remap."""
    exe, cfg = archive.exe, archive.cfg
    map_rows, _end = read_map_book(exe, cfg["mapBook"], cfg["themeBook"])
    themes = read_theme_book(exe, cfg["themeBook"])
    remaps = read_remaps(exe, archive.entries, map_rows, cfg.get("txl_sky_land", 0))
    sky_remap = [r["ids"] for r in remaps if r["name"] == "txl_sky_land"][0]

    sets = {}
    for level, row in enumerate(map_rows):
        if row["high_remap"] == 0 and row["low_remap"] == 0:
            continue
        for low_poly in (False, True):
            map_id = row["low_map" if low_poly else "high_map"]
            if map_id <= 0:
                continue
            data = archive.resource(map_id)
            if data[:4] != b"FROG":
                raise ValueError("level %d: resource %d is not a map" % (level, map_id))
            gene = struct.unpack_from("<I", data, 76)[0]
            theme = struct.unpack_from("<10H", data, gene + 4)[3]
            multiplayer = level % 6 == 5
            pair = (bank_id(themes[0], multiplayer, low_poly), bank_id(themes[theme], multiplayer, low_poly))
            entry = sets.setdefault(pair, {"sky": set()})
            if theme == SKY_THEME:
                entry["sky"].add("SKY_LAND_WIN95.MAP" if low_poly else "SKY_LAND.MAP")
    return sets, sky_remap


def sky_page_order(archive, banks, sky_name, sky_remap):
    """The atlas slot order of sky-land file sky_name: each tile's page (theme bank first), first seen first."""
    order = []
    for local in sky_tiles(archive.resource(archive.find(sky_name))):
        texture_id = sky_remap[local] if 0 <= local < len(sky_remap) else -1
        found = None
        for images in reversed(banks):
            for img in images:
                if img["texture_id"] == texture_id:
                    found = img
                    break
            if found is not None:
                break
        page = found["page"] if found is not None else -1
        if page not in order:
            order.append(page)
    return order


def main():
    args = arguments(__doc__, "texture_pages.tsv")
    started = time.time()
    archive = Archive(args.data_dir)
    sets, sky_remap = discover_sets(archive)

    rows = []
    for pair in sorted(sets):
        name = "+".join(archive.name(rid) for rid in pair)
        banks = [parse_vlo(archive.resource(rid))[0] for rid in pair]
        pages = [compose_page(banks, page) for page in range(PAGES)]
        for page, pixels in enumerate(pages):
            rows.append((name, page, hashlib.sha256(pixels).hexdigest(), pixels[3::4].count(255)))
        atlases = set()
        for sky_name in sorted(sets[pair]["sky"]):
            order = sky_page_order(archive, banks, sky_name, sky_remap)
            atlas = sky_atlas(pages, order)
            atlases.add(("sky:" + ",".join(str(p) for p in order), hashlib.sha256(atlas).hexdigest(), atlas[3::4].count(255)))
        if len(atlases) > 1:
            raise ValueError("%s: the two sky-land files give different atlases" % name)
        for label, digest, opaque in atlases:
            rows.append((name, label, digest, opaque))
    text = tsv(["set", "page", "rgba_sha256", "opaque_pixels"], rows)
    finish(args, text, "%d sets, %d rows, %.1f s" % (len(sets), len(rows), time.time() - started))


if __name__ == "__main__":
    main()

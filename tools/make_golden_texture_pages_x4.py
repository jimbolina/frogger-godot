#!/usr/bin/env python3
"""Golden facts for the upscaled texture pages baked under assets/textures/pages_x4/.

For every bank pair of texture_pages.tsv the fourteen pages are composed at
scale S (default 4) by the rule of tests/golden/specs/imported-assets.md:
placement, upload order, flags, set membership and sky order come from the
retail executable and banks exactly as make_golden_texture_pages.py reads
them; only the RGB of each upload comes from the S-times image of its texture
id under assets/textures/images_x4/. A keyed page's alpha is the nearest
S-times enlargement of the retail page's colour-key mask with zero RGB under
it; other pages are opaque. The sky atlas repeats each scaled page's first and
last rows S times around it. Each row gives the size, the SHA-256 of the RGBA8
bytes and the opaque pixel count that tests/golden/assets/test_asset_pages_x4.gd
compares with the local bake.

Pillow decodes the upscaled PNGs; nothing here reads Godot output or the
bake tool.

Usage:
    python3 tools/make_golden_texture_pages_x4.py [--data-dir DIR] [--images-dir DIR] [--scale S]
                                                  [--output FILE] [--check]
"""

import hashlib
import os
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
from imported_assets_common import ROOT, Archive, arguments, finish, tsv
from make_golden_texture_pages import (PAGE, PAGES, blit_uploads, compose_page, discover_sets, page_keyed,
                                       sky_atlas, sky_page_order)
from make_golden_vlo import parse_vlo

IMPORTED_DIR = os.path.join(ROOT, "tests", "golden", "imported")
IMAGES_DIR = os.path.join(ROOT, "assets", "textures", "images_x4")


def options(parser):
    """The generator's own options; the facts live beside the other imported-asset goldens."""
    parser.set_defaults(output=os.path.join(IMPORTED_DIR, "texture_pages_x4.tsv"))
    parser.add_argument("--images-dir", default=IMAGES_DIR, help="folder of the upscaled tNNNN.png files")
    parser.add_argument("--scale", type=int, default=4, help="integer scale of the upscaled images (default 4)")


class Upscaled:
    """The RGBA bytes of each texture id's upscaled PNG, decoded once and checked against the padded size."""

    def __init__(self, folder, scale):
        self.folder = folder
        self.scale = scale
        self._cache = {}

    def pixels_of(self, img):
        texture_id = img["texture_id"]
        if texture_id not in self._cache:
            path = os.path.join(self.folder, "t%04d.png" % texture_id)
            with Image.open(path) as image:
                if image.size != (img["padded_w"] * self.scale, img["padded_h"] * self.scale):
                    raise ValueError("%s is %dx%d, not %d times %dx%d" % (
                        path, image.size[0], image.size[1], self.scale, img["padded_w"], img["padded_h"]))
                self._cache[texture_id] = image.convert("RGBA").tobytes()
        return self._cache[texture_id]


def compose_scaled_page(banks, page, scale, upscaled):
    """RGBA8 bytes of one page at scale: the upscaled uploads, then the retail colour key enlarged."""
    out = blit_uploads(banks, page, scale, upscaled.pixels_of)
    size = PAGE * scale
    if not page_keyed(banks, page):
        out[3::4] = b"\xff" * (size * size)
        return bytes(out)
    retail = compose_page(banks, page)
    mask = Image.frombytes("L", (PAGE, PAGE), retail[3::4]).resize((size, size), Image.NEAREST)
    image = Image.frombytes("RGBA", (size, size), bytes(out))
    zero = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    image = Image.composite(image, zero, mask)
    image.putalpha(mask)
    return image.tobytes()


def main():
    args = arguments(__doc__, "texture_pages_x4.tsv", options)
    started = time.time()
    archive = Archive(args.data_dir)
    sets, sky_remap = discover_sets(archive)
    upscaled = Upscaled(args.images_dir, args.scale)
    size = PAGE * args.scale
    rows = []
    for pair in sorted(sets):
        name = "+".join(archive.name(rid) for rid in pair)
        banks = [parse_vlo(archive.resource(rid))[0] for rid in pair]
        pages = [compose_scaled_page(banks, page, args.scale, upscaled) for page in range(PAGES)]
        for page, pixels in enumerate(pages):
            rows.append((name, page, size, size, hashlib.sha256(pixels).hexdigest(), pixels[3::4].count(255)))
        atlases = set()
        for sky_name in sorted(sets[pair]["sky"]):
            order = sky_page_order(archive, banks, sky_name, sky_remap)
            atlas = sky_atlas(pages, order, args.scale)
            atlases.add(("sky:" + ",".join(str(p) for p in order), size, 258 * args.scale * max(1, len(order)),
                         hashlib.sha256(atlas).hexdigest(), atlas[3::4].count(255)))
        if len(atlases) > 1:
            raise ValueError("%s: the two sky-land files give different atlases" % name)
        rows.extend((name,) + atlas for atlas in sorted(atlases))
    text = tsv(["set", "page", "width", "height", "rgba_sha256", "opaque_pixels"], rows)
    finish(args, text, "%d sets, %d rows, scale %d, %.1f s" % (len(sets), len(rows), args.scale, time.time() - started))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Write the Godot bitmap font of the retail `newfont` glyph texture.

`newfont` is texture id 310: assets/textures/images/t0310.png holds the 96
glyphs of ASCII 32..127 in 8 x 8 cells, 32 to a row in three rows, with no
padding. This tool is the golden generator of the font the game builds at
runtime (NewfontPage and NewfontFont): it writes a BMFont v3 text file in
the layout Godot's font_data_bmfont importer reads, and the font's page
beside it, into the folder given with --out:

    <out>/newfont.fnt and <out>/newfont.png  (from --images/t0310.png)

Nothing is committed: the page holds the retail pixels. Every page is built
at 4 times the retail size so that linear filtering keeps the glyph pixels
even at any window scale: the retail PNG is enlarged 4 times by repeating
pixels. Each 32 x 32 glyph
cell is then surrounded by a 4-pixel transparent border, giving 40 x 40
cells on a 1280 x 120 page. The two rings of transparent pixels around the
glyph's opaque pixels, within its cell, take the per-channel maximum colour
of their filled neighbours, so filtering does not darken the edges. Glyph `id` sits at
x = ((id - 32) % 32) * 40, y = ((id - 32) // 32) * 40 with width and height
40, offsets -4 and advance 32; the size, line height and base are 32. The
colour channels carry the glyph (alphaChnl=0 keeps the RGBA pixels as they
are). The info line ends with page_sha256, the SHA-256 of the page's RGBA
rows, which Godot ignores.

--quiet prints nothing on success. The tool uses only the standard library.
"""

import argparse
import hashlib
import os
import struct
import sys
import zlib

sys.dont_write_bytecode = True
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT

ROOT = str(REPO_ROOT)
IMAGES = os.path.join(ROOT, "assets", "textures", "images")
NAME = "newfont"
TEXTURE = "t0310.png"
PAGE = NAME + ".png"
CELL = 8
COLUMNS = 32
ROWS = 3
FIRST = 32
COUNT = COLUMNS * ROWS
PAGE_SCALE = 4
GLYPH = CELL * PAGE_SCALE
BORDER = PAGE_SCALE
STRIDE = GLYPH + 2 * BORDER
FILL_RINGS = 2
SIGNATURE = b"\x89PNG\r\n\x1a\n"


def read_png(path):
    """Width, height and RGBA rows (bytes) of the 8-bit RGBA, non-interlaced PNG at path."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != SIGNATURE:
        raise SystemExit("%s is not a PNG" % path)
    at, header, compressed = 8, None, []
    while at < len(data):
        length, kind = struct.unpack(">I4s", data[at:at + 8])
        body = data[at + 8:at + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            compressed.append(body)
        elif kind == b"IEND":
            break
        at += 12 + length
    if header is None or header[2:] != (8, 6, 0, 0, 0):
        raise SystemExit("%s is not an 8-bit RGBA non-interlaced PNG" % path)
    width, height = header[0], header[1]
    raw = zlib.decompress(b"".join(compressed))
    stride = width * 4
    rows, previous = [], bytearray(stride)
    for y in range(height):
        kind = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            left = line[i - 4] if i >= 4 else 0
            up = previous[i]
            corner = previous[i - 4] if i >= 4 else 0
            if kind == 1:
                line[i] = (line[i] + left) & 255
            elif kind == 2:
                line[i] = (line[i] + up) & 255
            elif kind == 3:
                line[i] = (line[i] + ((left + up) >> 1)) & 255
            elif kind == 4:
                guess = left + up - corner
                pa, pb, pc = abs(guess - left), abs(guess - up), abs(guess - corner)
                pick = left if pa <= pb and pa <= pc else (up if pb <= pc else corner)
                line[i] = (line[i] + pick) & 255
            elif kind != 0:
                raise SystemExit("%s has an unknown PNG filter %d" % (path, kind))
        rows.append(bytes(line))
        previous = line
    return width, height, rows


def write_png(width, height, rows):
    """The bytes of an 8-bit RGBA PNG holding rows, unfiltered."""
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + row for row in rows)
    return (SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def scale_of(path, width, height):
    """The glyph scale of the newfont PNG at path, which must divide the page scale."""
    if width % (COLUMNS * CELL) != 0:
        raise SystemExit("%s is %dx%d; the width is not a multiple of %d" % (path, width, height, COLUMNS * CELL))
    scale = width // (COLUMNS * CELL)
    if scale < 1 or height != ROWS * CELL * scale:
        raise SystemExit("%s is %dx%d; expected %dx%d" % (path, width, height, width, ROWS * CELL * scale))
    if PAGE_SCALE % scale != 0:
        raise SystemExit("%s has scale %d, which does not divide %d" % (path, scale, PAGE_SCALE))
    return scale


def page_pixels(path):
    """The page's RGBA rows built from the newfont PNG at path."""
    width, height, rows = read_png(path)
    factor = PAGE_SCALE // scale_of(path, width, height)
    page_width, page_height = COLUMNS * STRIDE, ROWS * STRIDE
    page = [bytearray(page_width * 4) for _ in range(page_height)]
    filled = [bytearray(page_width) for _ in range(page_height)]
    for index in range(COUNT):
        column, row = index % COLUMNS, index // COLUMNS
        for y in range(GLYPH):
            source = rows[(row * GLYPH + y) // factor]
            target = page[row * STRIDE + BORDER + y]
            mask = filled[row * STRIDE + BORDER + y]
            for x in range(GLYPH):
                at = ((column * GLYPH + x) // factor) * 4
                to = column * STRIDE + BORDER + x
                target[to * 4:to * 4 + 4] = source[at:at + 4]
                mask[to] = 1 if source[at + 3] else 0
    for _ in range(FILL_RINGS):
        ring = []
        for y in range(page_height):
            for x in range(page_width):
                if filled[y][x]:
                    continue
                colour = None
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        same_cell = ny // STRIDE == y // STRIDE and nx // STRIDE == x // STRIDE
                        if (dy or dx) and 0 <= ny < page_height and 0 <= nx < page_width and same_cell and filled[ny][nx]:
                            rgb = page[ny][nx * 4:nx * 4 + 3]
                            colour = rgb if colour is None else bytes(max(a, b) for a, b in zip(colour, rgb))
                if colour is not None:
                    ring.append((y, x, colour))
        for y, x, colour in ring:
            page[y][x * 4:x * 4 + 3] = colour
            filled[y][x] = 1
    return page_width, page_height, [bytes(line) for line in page]


def font_text(page):
    """The BMFont v3 text of a font whose page beside it holds page, as page_pixels returns it."""
    digest = hashlib.sha256(b"".join(page[2])).hexdigest()
    lines = [
        'info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 '
        'padding=0,0,0,0 spacing=0,0 outline=0 page_sha256=%s' % (NAME, GLYPH, digest),
        "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=0 redChnl=4 "
        "greenChnl=4 blueChnl=4" % (GLYPH, GLYPH, COLUMNS * STRIDE, ROWS * STRIDE),
        'page id=0 file="%s"' % PAGE,
        "chars count=%d" % COUNT,
    ]
    for code in range(FIRST, FIRST + COUNT):
        index = code - FIRST
        lines.append("char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15"
                     % (code, (index % COLUMNS) * STRIDE, (index // COLUMNS) * STRIDE, STRIDE, STRIDE,
                        -BORDER, -BORDER, GLYPH))
    return "\n".join(lines) + "\n"


def outputs(images, out):
    """The path, kind and contents of the font file and its page."""
    png = os.path.join(images, TEXTURE)
    if not os.path.exists(png):
        raise SystemExit("%s is missing" % png)
    page = page_pixels(png)
    return [(os.path.join(out, NAME + ".fnt"), "fnt", font_text(page).encode("ascii")),
            (os.path.join(out, PAGE), "page", page)]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True, help="the folder the font and its page are written into")
    parser.add_argument("--images", default=IMAGES, help="the retail images folder holding %s" % TEXTURE)
    parser.add_argument("--quiet", action="store_true", help="print nothing on success")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for path, kind, contents in outputs(args.images, args.out):
        with open(path, "wb") as f:
            f.write(write_png(*contents) if kind == "page" else contents)
        if not args.quiet:
            print("wrote %s" % path)


if __name__ == "__main__":
    main()

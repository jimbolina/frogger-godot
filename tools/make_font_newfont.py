#!/usr/bin/env python3
"""Write the Godot bitmap fonts of the retail `newfont` glyph texture.

`newfont` is texture id 310: assets/textures/images/t0310.png holds the 96
glyphs of ASCII 32..127 in 8 x 8 cells, 32 to a row in three rows, with no
padding. assets/textures/images_x4/t0310.png is the same grid at four times
the size. For each texture set whose PNG exists this tool writes a BMFont v3
text file that Godot's font_data_bmfont importer turns into a FontFile, and
copies the PNG beside it as the font's page:

    assets/fonts/retail/newfont.fnt and newfont.png  (from textures/images/t0310.png)
    assets/fonts/x4/newfont.fnt and newfont.png      (from textures/images_x4/t0310.png)

The page is a copy because the importer marks every page image of a font as
not imported (importer "skip"), which would take t0310.png away from the
texture banks. The scale S is the PNG width divided by 256; the height must
be 24 * S. Glyph `id` sits at x = ((id - 32) % 32) * 8 * S,
y = ((id - 32) // 32) * 8 * S with width, height and advance 8 * S and no
offsets; the line height and base are 8 * S. The colour channels carry the
glyph (alphaChnl=0 keeps the RGBA pixels as they are).

--check writes nothing, prints a unified diff for each font file and names
each page that differs or is missing, and exits 1. --quiet prints nothing on
success. A missing x4 PNG skips the x4 font.
"""

import argparse
import difflib
import os
import struct
import sys

sys.dont_write_bytecode = True

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXTURES = os.path.join(ROOT, "assets", "textures")
FONTS = os.path.join(ROOT, "assets", "fonts")
NAME = "newfont"
TEXTURE = "t0310.png"
PAGE = NAME + ".png"
CELL = 8
COLUMNS = 32
ROWS = 3
FIRST = 32
COUNT = COLUMNS * ROWS
SETS = (("retail", "images", True), ("x4", "images_x4", False))


def png_size(path):
    """Width and height from a PNG's IHDR chunk."""
    with open(path, "rb") as f:
        header = f.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise SystemExit("%s is not a PNG" % path)
    return struct.unpack(">II", header[16:24])


def scale_of(path):
    """The glyph scale of the newfont PNG at path."""
    width, height = png_size(path)
    if width % (COLUMNS * CELL) != 0:
        raise SystemExit("%s is %dx%d; the width is not a multiple of %d" % (path, width, height, COLUMNS * CELL))
    scale = width // (COLUMNS * CELL)
    if scale < 1 or height != ROWS * CELL * scale:
        raise SystemExit("%s is %dx%d; expected %dx%d" % (path, width, height, width, ROWS * CELL * scale))
    return scale


def font_text(scale):
    """The BMFont v3 text of the font whose page beside it has glyphs at scale."""
    cell = CELL * scale
    lines = [
        'info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 '
        'padding=0,0,0,0 spacing=0,0 outline=0' % (NAME, cell),
        "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=0 redChnl=4 "
        "greenChnl=4 blueChnl=4" % (cell, cell, COLUMNS * cell, ROWS * cell),
        'page id=0 file="%s"' % PAGE,
        "chars count=%d" % COUNT,
    ]
    for code in range(FIRST, FIRST + COUNT):
        index = code - FIRST
        lines.append("char id=%d x=%d y=%d width=%d height=%d xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15"
                     % (code, (index % COLUMNS) * cell, (index // COLUMNS) * cell, cell, cell, cell))
    return "\n".join(lines) + "\n"


def outputs():
    """The path and bytes of every font file and page of the sets whose PNG exists."""
    result = []
    for set_name, images_dir, required in SETS:
        png = os.path.join(TEXTURES, images_dir, TEXTURE)
        if not os.path.exists(png):
            if required:
                raise SystemExit("%s is missing" % png)
            continue
        folder = os.path.join(FONTS, set_name)
        result.append((os.path.join(folder, NAME + ".fnt"), font_text(scale_of(png)).encode("ascii")))
        with open(png, "rb") as f:
            result.append((os.path.join(folder, PAGE), f.read()))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="compare with the committed fonts instead of writing")
    parser.add_argument("--quiet", action="store_true", help="print nothing on success")
    args = parser.parse_args()
    files = outputs()
    differing = 0
    for path, data in files:
        relative = os.path.relpath(path, ROOT)
        old = None
        if os.path.exists(path):
            with open(path, "rb") as f:
                old = f.read()
        if old == data:
            continue
        if args.check:
            differing += 1
            if path.endswith(".fnt"):
                old_lines = (old or b"").decode("utf-8", "replace").splitlines(True)
                diff = list(difflib.unified_diff(old_lines, data.decode("ascii").splitlines(True),
                                                 relative, "generated", n=0))
                sys.stdout.writelines(diff[:80])
            print("%s: %s" % (relative, "missing" if old is None else "differs from the generator"))
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
        if not args.quiet:
            print("wrote %s" % relative)
    if differing:
        print("%d of %d newfont font files differ from the generator" % (differing, len(files)))
        sys.exit(1)
    if not args.quiet:
        verb = "match" if args.check else "are up to date with"
        print("%d newfont font files %s the generator" % (len(files), verb))


if __name__ == "__main__":
    main()

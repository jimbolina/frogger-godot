#!/usr/bin/env python3
"""Write the TrueType font of the angular letter face.

Reads the glyph outlines through tools/content/angular_glyphs.py (the SVGs under
content/fonts/angular/svg/ and content/fonts/angular/derived.json) and writes

    content/fonts/angular/frogger_angular.ttf

with fontTools' FontBuilder. Run it through uv so the pinned fontTools builds
the bytes: `uv run tools/content/make_angular_font.py`.

The font has 1000 units per em and a cap height of 800, so font units equal
the source units. Each glyph sits angular_glyphs.SIDE_BEARING units after the
pen (its left side bearing equals its xMin) and advances by its ink width
plus both side bearings; the space advances by angular_glyphs.SPACE_ADVANCE.
The SVGs fill even-odd; every contour is oriented by its nesting depth (ink
clockwise, holes counter-clockwise) so TrueType's nonzero fill draws the same
shape, and contours that cross are refused. The ascent and descent are the
highest and lowest outline points (the accents and the cedilla), with no line
gap. The cmap holds A-Z, 0-9, the space and the derived characters; there is
no lowercase. The family is "Frogger Angular". The head timestamps are fixed
and nothing else depends on the time or the machine, so the bytes reproduce
with the pinned fontTools.

--check writes nothing; when the committed font differs it names each glyph,
metric or table that differs and exits 1. --quiet prints nothing on success.
"""

import argparse
import calendar
import io
import os
import sys

sys.dont_write_bytecode = True

from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.content import angular_glyphs
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

ROOT = angular_glyphs.ROOT
OUTPUT = os.path.join(angular_glyphs.FACE, "frogger_angular.ttf")
UNITS_PER_EM = 1000
FAMILY = "Frogger Angular"
STYLE = "Regular"
VERSION = "Version 1.000"
NOTDEF_ADVANCE = 500
MAC_EPOCH_OFFSET = 2082844800
TIMESTAMP = calendar.timegm((2026, 11, 1, 0, 0, 0)) + MAC_EPOCH_OFFSET


def glyph_name(char):
    """The glyph name of char."""
    return "space" if char == " " else "uni%04X" % ord(char)


def placed_contours(glyph):
    """glyph's nonzero-oriented contours in integer font units, shifted right by the side bearing."""
    return [[(round(x) + angular_glyphs.SIDE_BEARING, round(y)) for x, y in contour]
            for contour in angular_glyphs.nonzero_contours(glyph)]


def build():
    """The bytes of the font."""
    glyphs = angular_glyphs.glyphs()
    chars = [" "] + list(glyphs)
    order = [".notdef"] + [glyph_name(char) for char in chars]
    builder = FontBuilder(UNITS_PER_EM, isTTF=True)
    builder.setupGlyphOrder(order)
    builder.setupCharacterMap({ord(char): glyph_name(char) for char in chars})
    outlines = {".notdef": TTGlyphPen(None).glyph(), "space": TTGlyphPen(None).glyph()}
    metrics = {".notdef": (NOTDEF_ADVANCE, 0), "space": (angular_glyphs.SPACE_ADVANCE, 0)}
    y_min, y_max = 0, 0
    for char, glyph in glyphs.items():
        pen = TTGlyphPen(None)
        contours = placed_contours(glyph)
        for contour in contours:
            pen.moveTo(contour[0])
            for point in contour[1:]:
                pen.lineTo(point)
            pen.closePath()
        name = glyph_name(char)
        outlines[name] = pen.glyph()
        x_min = min(x for contour in contours for x, _ in contour)
        y_min = min(y_min, min(y for contour in contours for _, y in contour))
        y_max = max(y_max, max(y for contour in contours for _, y in contour))
        metrics[name] = (round(glyph.advance()), x_min)
    builder.setupGlyf(outlines)
    builder.setupHorizontalMetrics(metrics)
    builder.setupHorizontalHeader(ascent=y_max, descent=y_min, lineGap=0)
    builder.setupHead(unitsPerEm=UNITS_PER_EM, created=TIMESTAMP, modified=TIMESTAMP, fontRevision=1.0)
    builder.setupNameTable({
        "familyName": FAMILY,
        "styleName": STYLE,
        "uniqueFontIdentifier": "%s %s" % (FAMILY, STYLE),
        "fullName": FAMILY,
        "version": VERSION,
        "psName": FAMILY.replace(" ", "") + "-" + STYLE,
    })
    builder.setupOS2(
        sTypoAscender=y_max, sTypoDescender=y_min, sTypoLineGap=0,
        usWinAscent=y_max, usWinDescent=-y_min,
        sCapHeight=angular_glyphs.CAP_HEIGHT, sxHeight=angular_glyphs.CAP_HEIGHT,
        achVendID="NONE",
    )
    builder.setupPost(keepGlyphNames=True)
    builder.font.recalcTimestamp = False
    stream = io.BytesIO()
    builder.save(stream)
    return stream.getvalue(), glyphs


def outline(font, name):
    """The points and contour ends of glyph name in font."""
    coordinates, ends, _ = font["glyf"][name].getCoordinates(font["glyf"])
    return list(coordinates), list(ends)


def differences(old_bytes, new_bytes):
    """Lines naming each glyph, metric or table that differs between two builds."""
    old = TTFont(io.BytesIO(old_bytes))
    new = TTFont(io.BytesIO(new_bytes))
    lines = []
    old_cmap = old.getBestCmap() or {}
    new_cmap = new.getBestCmap()
    for code in sorted(set(old_cmap) | set(new_cmap)):
        label = "glyph %r (U+%04X)" % (chr(code), code)
        if code not in old_cmap:
            lines.append("%s is missing from the committed font" % label)
            continue
        if code not in new_cmap:
            lines.append("%s is not in the generated font" % label)
            continue
        old_name, new_name = old_cmap[code], new_cmap[code]
        if outline(old, old_name) != outline(new, new_name):
            lines.append("%s: outline differs" % label)
        if old["hmtx"][old_name] != new["hmtx"][new_name]:
            lines.append("%s: advance and side bearing %s, expected %s"
                         % (label, old["hmtx"][old_name], new["hmtx"][new_name]))
    if not lines:
        for tag in sorted(set(old.keys()) | set(new.keys())):
            if tag == "GlyphOrder":
                continue
            if tag not in old or tag not in new:
                lines.append("table %r is only in the %s font" % (tag, "generated" if tag in new else "committed"))
            elif old.getTableData(tag) != new.getTableData(tag):
                lines.append("table %r differs" % tag)
    if not lines:
        lines.append("the bytes differ")
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="compare with the committed font instead of writing")
    parser.add_argument("--quiet", action="store_true", help="print nothing on success")
    args = parser.parse_args()
    try:
        data, glyphs = build()
    except ValueError as error:
        print("make_angular_font: %s" % error)
        sys.exit(1)
    relative = os.path.relpath(OUTPUT, ROOT)
    old = None
    if os.path.exists(OUTPUT):
        with open(OUTPUT, "rb") as f:
            old = f.read()
    if old != data:
        if args.check:
            if old is None:
                print("%s: missing" % relative)
            else:
                for line in differences(old, data)[:40]:
                    print("%s: %s" % (relative, line))
                print("%s differs from the generator" % relative)
            sys.exit(1)
        os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
        with open(OUTPUT, "wb") as f:
            f.write(data)
        if not args.quiet:
            print("wrote %s" % relative)
    if not args.quiet:
        verb = "matches" if args.check else "is up to date with"
        print("%s (%d glyphs) %s the generator" % (relative, len(glyphs) + 1, verb))


if __name__ == "__main__":
    main()

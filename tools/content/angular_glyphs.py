"""Glyph outlines of the angular letter face, shared by its generators.

The face is the hand-cut capital alphabet the retail lettering textures and the
March 1997 alpha's letter models share. Its sources live under
content/fonts/angular/:

    svg/<char>.svg   A-Z and 0-9, third-party traces of the alpha's models
    derived.json     the punctuation, the arrow and the accented capitals

Every glyph comes out in font units: y up, baseline 0, cap height 800, x from
the left edge of the glyph's ink box, so the leftmost point has x 0 and the
ink width is the largest x. An SVG's viewBox is "0 0 W 800"; a point (x, y)
of the SVG becomes (x, 800 - y). A glyph is set SIDE_BEARING units after the
pen and advances the pen by its ink width plus twice SIDE_BEARING; a space
advances it by SPACE_ADVANCE.

Only <path> elements (M, L, H, V and Z, absolute and relative) and <polygon>
elements are read; a path that never draws a third point is a stray marker
and is skipped. The SVGs fill even-odd: each closed subpath toggles inside
and outside.

derived.json maps each derived character to an object with:

    base      a character defined before it whose outline the glyph starts from
    rotate    180 turns the base about the centre of its ink box
    polygons  extra contours (marks) as lists of [x, y] points, in the base's
              units (x from the left of the base's ink box)

A derived glyph's contours are the base's followed by its own polygons, all
filled even-odd like the SVGs; the result is then shifted so its leftmost
point has x 0. Keys starting with "_" are notes.

glyphs() returns {char: Glyph}; contours are lists of (x, y) floats with no
repeated closing point, in the order the sources give them.
"""

import json
import os
import re
import sys

sys.dont_write_bytecode = True
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT

ROOT = str(REPO_ROOT)
FACE = os.path.join(ROOT, "content", "fonts", "angular")
SVG_DIR = os.path.join(FACE, "svg")
DERIVED = os.path.join(FACE, "derived.json")
CAP_HEIGHT = 800
SVG_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
SIDE_BEARING = 40
SPACE_ADVANCE = 320

_NUMBER = r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"
_TOKEN = re.compile(r"[MLHVZmlhvz]|" + _NUMBER)
_PATH = re.compile(r"<path\b[^>]*?\sd=\"([^\"]*)\"")
_POLYGON = re.compile(r"<polygon\b[^>]*?\spoints=\"([^\"]*)\"")
_VIEWBOX = re.compile(r"viewBox=\"([^\"]*)\"")


class Glyph:
    """One character's outline: closed contours in font units and the ink width."""

    def __init__(self, char, width, contours):
        self.char = char
        self.width = width
        self.contours = contours

    def advance(self):
        """The pen advance of the glyph: its ink width plus both side bearings."""
        return self.width + 2 * SIDE_BEARING

    def bounds(self):
        """(x_min, y_min, x_max, y_max) of every contour point, or None when empty."""
        points = [p for contour in self.contours for p in contour]
        if not points:
            return None
        xs = [p[0] for p in points]
        ys = [p[1] for p in points]
        return min(xs), min(ys), max(xs), max(ys)


def _close(points):
    """points without consecutive repeats or a final point equal to the first."""
    result = []
    for point in points:
        if not result or point != result[-1]:
            result.append(point)
    if len(result) > 1 and result[0] == result[-1]:
        result.pop()
    return result


def path_subpaths(d):
    """The subpaths of an SVG path's d attribute (M L H V Z only), in SVG units."""
    tokens = _TOKEN.findall(d)
    subpaths = []
    current = []
    position = (0.0, 0.0)
    start = position
    command = None
    i = 0

    def finish():
        closed = _close(current)
        if len(closed) > 2:
            subpaths.append(closed)

    while i < len(tokens):
        token = tokens[i]
        if token.isalpha():
            command = token
            i += 1
            if command in "Zz":
                finish()
                current = []
                position = start
            continue
        if command is None:
            raise ValueError("path data starts with a number: %r" % d)
        if command in "Mm":
            x, y = float(tokens[i]), float(tokens[i + 1])
            i += 2
            position = (x, y) if command == "M" else (position[0] + x, position[1] + y)
            finish()
            current = [position]
            start = position
            command = "L" if command == "M" else "l"
        elif command in "Ll":
            x, y = float(tokens[i]), float(tokens[i + 1])
            i += 2
            position = (x, y) if command == "L" else (position[0] + x, position[1] + y)
            current.append(position)
        elif command in "Hh":
            x = float(tokens[i])
            i += 1
            position = (x if command == "H" else position[0] + x, position[1])
            current.append(position)
        elif command in "Vv":
            y = float(tokens[i])
            i += 1
            position = (position[0], y if command == "V" else position[1] + y)
            current.append(position)
        else:
            raise ValueError("unsupported path command %r" % command)
    finish()
    return subpaths


def svg_outline(text):
    """(width, contours) of one glyph SVG's text, in font units."""
    view_box = _VIEWBOX.search(text)
    if view_box is None:
        raise ValueError("no viewBox")
    left, top, width, height = (float(n) for n in re.findall(_NUMBER, view_box.group(1)))
    if left != 0 or top != 0 or height != CAP_HEIGHT:
        raise ValueError("viewBox %r is not 0 0 W %d" % (view_box.group(1), CAP_HEIGHT))
    subpaths = []
    for d in _PATH.findall(text):
        subpaths.extend(path_subpaths(d))
    for points in _POLYGON.findall(text):
        numbers = [float(n) for n in re.findall(_NUMBER, points)]
        if len(numbers) % 2:
            raise ValueError("odd number of polygon coordinates")
        polygon = _close(list(zip(numbers[0::2], numbers[1::2])))
        if len(polygon) > 2:
            subpaths.append(polygon)
    contours = [[(x, CAP_HEIGHT - y) for x, y in subpath] for subpath in subpaths]
    return width, contours


def svg_path(char):
    """The source SVG of an SVG character."""
    return os.path.join(SVG_DIR, char + ".svg")


def load_derived(path=DERIVED):
    """The derived glyph definitions of derived.json, in file order, without notes."""
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return {key: value for key, value in data.items() if not key.startswith("_")}


def _rotated(glyph):
    """glyph's contours turned 180 degrees about the centre of its ink box."""
    x_min, y_min, x_max, y_max = glyph.bounds()
    return [[(x_min + x_max - x, y_min + y_max - y) for x, y in contour] for contour in glyph.contours]


def glyphs():
    """Every glyph of the face: the SVG characters, then the derived ones."""
    result = {}
    for char in SVG_CHARS:
        with open(svg_path(char), "r", encoding="utf-8") as f:
            width, contours = svg_outline(f.read())
        if not contours:
            raise ValueError("%s.svg has no outline" % char)
        result[char] = Glyph(char, width, contours)
    for char, spec in load_derived().items():
        if len(char) != 1:
            raise ValueError("derived key %r is not one character" % char)
        if char in result:
            raise ValueError("derived character %r repeats a glyph" % char)
        contours = []
        if "base" in spec:
            base = result.get(spec["base"])
            if base is None:
                raise ValueError("%r: base %r is not defined before it" % (char, spec["base"]))
            rotate = spec.get("rotate", 0)
            if rotate == 180:
                contours = _rotated(base)
            elif rotate == 0:
                contours = [list(contour) for contour in base.contours]
            else:
                raise ValueError("%r: rotate must be 0 or 180" % char)
        elif "rotate" in spec:
            raise ValueError("%r: rotate needs a base" % char)
        for polygon in spec.get("polygons", []):
            points = _close([(float(x), float(y)) for x, y in polygon])
            if len(points) < 3:
                raise ValueError("%r: a polygon has fewer than three points" % char)
            contours.append(points)
        if not contours:
            raise ValueError("%r has no outline" % char)
        x_min = min(x for contour in contours for x, _ in contour)
        contours = [[(x - x_min, y) for x, y in contour] for contour in contours]
        width = max(x for contour in contours for x, _ in contour)
        result[char] = Glyph(char, width, contours)
    return result


def _signed_area(contour):
    """Twice the signed area of contour; positive when counter-clockwise (y up)."""
    total = 0.0
    for i, (x0, y0) in enumerate(contour):
        x1, y1 = contour[(i + 1) % len(contour)]
        total += x0 * y1 - x1 * y0
    return total


def _on_segment(point, a, b):
    """True when point lies on the segment a-b."""
    (px, py), (ax, ay), (bx, by) = point, a, b
    if abs((bx - ax) * (py - ay) - (by - ay) * (px - ax)) > 1e-9:
        return False
    return min(ax, bx) - 1e-9 <= px <= max(ax, bx) + 1e-9 and min(ay, by) - 1e-9 <= py <= max(ay, by) + 1e-9


def _inside(point, contour):
    """1 inside, 0 outside, None on the boundary of contour."""
    x, y = point
    inside = False
    for i, a in enumerate(contour):
        b = contour[(i + 1) % len(contour)]
        if _on_segment(point, a, b):
            return None
        if (a[1] > y) != (b[1] > y):
            crossing = a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
            if x < crossing:
                inside = not inside
    return 1 if inside else 0


def _segments_cross(a, b, c, d):
    """True when the open segments a-b and c-d cross at a single interior point."""
    def orient(p, q, r):
        value = (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
        return (value > 1e-9) - (value < -1e-9)
    o1, o2, o3, o4 = orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)
    return o1 * o2 < 0 and o3 * o4 < 0


def check_simple(glyph):
    """Raise ValueError if any contour of glyph crosses itself or another contour.

    Without crossings the even-odd fill equals the nonzero fill of the same
    contours oriented by their nesting depth (see nonzero_contours)."""
    edges = []
    for index, contour in enumerate(glyph.contours):
        for i, a in enumerate(contour):
            edges.append((index, i, a, contour[(i + 1) % len(contour)]))
    for k, (ci, i, a, b) in enumerate(edges):
        for cj, j, c, d in edges[k + 1:]:
            if _segments_cross(a, b, c, d):
                raise ValueError("%r: contour %d edge %d crosses contour %d edge %d" % (glyph.char, ci, i, cj, j))


def nonzero_contours(glyph):
    """glyph's contours oriented for a TrueType nonzero fill equal to the even-odd fill.

    A contour inside an even number of the others is ink and turns clockwise
    (y up); one inside an odd number is a hole and turns counter-clockwise."""
    check_simple(glyph)
    result = []
    for index, contour in enumerate(glyph.contours):
        depth = 0
        for other_index, other in enumerate(glyph.contours):
            if other_index == index:
                continue
            verdict = None
            for point in contour:
                verdict = _inside(point, other)
                if verdict is not None:
                    break
            if verdict is None:
                raise ValueError("%r: contour %d lies on the boundary of contour %d" % (glyph.char, index, other_index))
            depth += verdict
        clockwise = _signed_area(contour) < 0
        want_clockwise = depth % 2 == 0
        result.append(list(contour) if clockwise == want_clockwise else list(reversed(contour)))
    return result

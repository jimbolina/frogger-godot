#!/usr/bin/env python3
"""Write the lettering that replaces the retail angular-face textures.

Reads content/fonts/angular/lettering.tsv, one row per retail texture id,
content/fonts/angular/lettering_layout.tsv, the geometry of every row, and the
glyph outlines of tools/angular_glyphs.py, and writes

    content/lettering/tNNNN.png                   a transparent row's image
    content/lettering/masks/<background>/tNNNN.png  a tile row's fill coverage
    and a seed import sidecar beside each

(NNNN = the texture id). No retail image is read. Run it through uv so the
pinned Pillow draws the pixels: `uv run tools/make_lettering.py`, then
`godot --headless --path . --import` completes the seed sidecars.

lettering.tsv columns (tab separated; lines starting with "#" are notes):

    id          the retail texture id
    name        FrogLord's name of the texture, or "-"
    language    en, s, g, i, f, or "-" for no language
    text        the lettering; "|" breaks a line
    style       the colours (STYLES): fill and outline, or fill only
    background  transparent, green_pad, log or turtle
    layout      line, or components: each letter fitted to its own retail
                ink component, left to right

lettering_layout.tsv columns, one row per lettering.tsv row:

    id          the retail texture id
    width       the retail padded width
    height      the retail padded height
    boxes       the retail ink box of each line (line layout) or letter
                (components layout) as x0,y0,x1,y1 with exclusive ends,
                separated by ";"

--layout measures that geometry from the retail images once
(assets/textures/images/tNNNN.png, or --images) and writes the layout file;
it holds sizes and boxes only, never colours or pixels. The retail ink box is
the alpha box of a transparent image, or the box of the pixels whose
channels differ from the background by more than TILE_THRESHOLD. A text of N
lines splits that box into N row bands at its fully empty rows; when the
lines touch, each split is the row with the least ink within SPLIT_WINDOW
rows of the equal split, which starts the next band. Each line keeps the ink
extent of its band. A components layout splits the ink into one component per
letter (components()).

Each output is exactly SCALE times the retail padded size. A line is laid
out with the glyph advances (each glyph SIDE_BEARING after the pen, a space
SPACE_ADVANCE). Every line takes one uniform scale, the largest that fits
each line's laid-out ink (accents and the cedilla included) into its box less
one retail pixel of outline on every side, and is centred on that box. A
components layout fits and centres each letter on its own box instead.

Glyphs fill even-odd and are drawn with Pillow's ImageDraw at SUPERSAMPLE
times the output size, then box-reduced. The outline is the fill dilated by
one retail pixel (SCALE output pixels): the fill plus a rectangle along every
contour edge and a disc on every vertex, drawn under the fill in the outline
colour. Transparent images keep straight alpha (the dilated coverage); the
colour is the fill and outline coverage mix, and the outermost colour (the
outline, or the fill without one) under alpha 0, so filtering draws no dark
fringe. A tile row writes only its fill coverage as an 8-bit grey mask; the
game composites the opaque tile from it and the player's retail images
(LetteringTile).

--composite ASSETS --out DIR is the golden generator of those tiles: it
measures the geometry from ASSETS/textures/images itself and writes each
finished tile to DIR/tNNNN.png, the fill over the background, whose colour is
the most common colour of t0263 (green_pad) or t0566 (log), or for turtle the
shell of TURTLES: per pixel the most common shell colour (red channel at most
SHELL_RED) among the ten digit tiles, earlier tiles winning ties, and where
every tile shows a digit the mirrored pixel of the same row. A tile's fill is
the most common colour of its retail ink. The background is enlarged by
repeating pixels, the fill laid over it with Pillow's Image.composite, every
channel raised to at least MIN_CHANNEL and the alpha set to 255.

The image sidecar asks the texture importer for mipmaps and otherwise the
project defaults (SIDECAR_POLICY); a mask sidecar asks for the image importer,
which keeps the PNG's grey values exactly. An existing sidecar that already
holds its policy is kept. A file under content/lettering/ without a row is
removed.

Pillow's polygon rasteriser rounds edge crossings in floating point, and
Pillow's wheels fuse multiply-adds on some CPUs and not others, so the same
build may differ by one supersample on a few pixels between arm64 and x86_64.
A committed image or mask therefore counts as the generator's when no channel
of any pixel differs by more than one coverage step (RASTER_STEP) and at most
RASTER_PIXELS pixels differ at all; such a file is neither rewritten nor
reported. Any larger difference is a real change.

--check writes nothing; it names each id whose decoded pixels or sidecar
differ, or that is missing or extra (with --layout, whose measured geometry
differs from the layout file), and exits 1. --quiet prints nothing on
success.
"""

import argparse
import collections
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import angular_glyphs
from PIL import Image, ImageChops, ImageDraw, ImageMath

ROOT = angular_glyphs.ROOT
TABLE = os.path.join(angular_glyphs.FACE, "lettering.tsv")
LAYOUT = os.path.join(angular_glyphs.FACE, "lettering_layout.tsv")
IMAGES = os.path.join(ROOT, "assets", "textures", "images")
OUTPUT = os.path.join(ROOT, "content", "lettering")
MASKS = "masks"
LAYOUT_COLUMNS = ("id", "width", "height", "boxes")
SCALE = 8
SUPERSAMPLE = 4
PIXEL = SCALE * SUPERSAMPLE
OUTLINE = 1
TILE_THRESHOLD = 0x10
SPLIT_WINDOW = 2
SHELL_RED = 0x10
MIN_CHANNEL = 8
RASTER_STEP = -(-255 // (SUPERSAMPLE * SUPERSAMPLE))
RASTER_PIXELS = 16
PAD_SOURCE = 263
LOG_SOURCE = 566
TURTLES = tuple(range(638, 648))
COLUMNS = ("id", "name", "language", "text", "style", "background", "layout")
LANGUAGES = ("en", "s", "g", "i", "f", "-")
BACKGROUNDS = ("transparent", "green_pad", "log", "turtle")
LAYOUTS = ("line", "components")
STYLES = {
    "CK": ((0xF8, 0xF8, 0xD8), (0x10, 0x10, 0x10)),
    "C-": ((0xF8, 0xF8, 0xD8), None),
    "PK": ((0xE0, 0xE8, 0xC8), (0x10, 0x10, 0x10)),
    "EK": ((0xF8, 0xF8, 0xE8), (0x10, 0x10, 0x10)),
    "WK": ((0xF8, 0xF8, 0xF8), (0x10, 0x10, 0x10)),
    "W2": ((0xF8, 0xF8, 0xF8), (0x20, 0x20, 0x20)),
    "GO": ((0xF8, 0xF8, 0xC8), (0x38, 0x38, 0x30)),
    "PALE": ((0xE8, 0xE8, 0xA0), None),
    "TILE": (None, None),
}
SIDECAR_POLICY = {
    "compress/mode": "0",
    "detect_3d/compress_to": "0",
    "mipmaps/generate": "true",
    "process/fix_alpha_border": "false",
    "process/premult_alpha": "false",
    "process/size_limit": "0",
}
SIDECAR_SEED = '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n' + "".join(
    "%s=%s\n" % item for item in sorted(SIDECAR_POLICY.items()))
MASK_SIDECAR_SEED = '[remap]\n\nimporter="image"\ntype="Image"\n\n[params]\n\n'


class Row:
    """One row of lettering.tsv."""

    def __init__(self, fields, line_number):
        if len(fields) != len(COLUMNS):
            raise ValueError("lettering.tsv line %d has %d columns, not %d" % (line_number, len(fields), len(COLUMNS)))
        ident, self.name, self.language, self.text, self.style, self.background, self.layout = fields
        if not ident.isdigit():
            raise ValueError("lettering.tsv line %d: id %r is not a number" % (line_number, ident))
        self.id = int(ident)
        for value, allowed, column in ((self.language, LANGUAGES, "language"), (self.style, STYLES, "style"),
                                       (self.background, BACKGROUNDS, "background"), (self.layout, LAYOUTS, "layout")):
            if value not in allowed:
                raise ValueError("t%04d: unknown %s %r" % (self.id, column, value))
        if (self.style == "TILE") != (self.background != "transparent"):
            raise ValueError("t%04d: style TILE goes with a tile background and only there" % self.id)
        if not self.text.strip():
            raise ValueError("t%04d: empty text" % self.id)

    def lines(self):
        """The text's lines."""
        return self.text.split("|")


def read_table(path=TABLE):
    """The rows of lettering.tsv in file order; ids must be unique."""
    rows = []
    seen = set()
    with open(path, "r", encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            row = Row(line.split("\t"), number)
            if row.id in seen:
                raise ValueError("t%04d appears twice in lettering.tsv" % row.id)
            seen.add(row.id)
            rows.append(row)
    return rows


def file_name(ident):
    """The PNG file name of texture id ident."""
    return "t%04d.png" % ident


def retail_image(ident, images=IMAGES):
    """The retail RGBA image of texture id ident in the folder images."""
    with Image.open(os.path.join(images, file_name(ident))) as image:
        return image.convert("RGBA")


def most_common(colours):
    """The most common colour of colours; the first seen wins a tie."""
    counts = collections.Counter(colours)
    order = {}
    for index, colour in enumerate(colours):
        order.setdefault(colour, index)
    return max(counts, key=lambda colour: (counts[colour], -order[colour]))


def turtle_shell(images=IMAGES):
    """The turtle shell behind the rank digits, as an RGB image the size of the digit tiles."""
    tiles = [retail_image(ident, images).convert("RGB") for ident in TURTLES]
    width, height = tiles[0].size
    if any(tile.size != (width, height) for tile in tiles):
        raise ValueError("the turtle tiles differ in size")
    pixels = [tile.load() for tile in tiles]
    shell = Image.new("RGB", (width, height))
    out = shell.load()
    holes = []
    for y in range(height):
        for x in range(width):
            candidates = [p[x, y] for p in pixels if p[x, y][0] <= SHELL_RED]
            if candidates:
                out[x, y] = most_common(candidates)
            else:
                holes.append((x, y))
    hole_set = set(holes)
    for x, y in holes:
        mirror = (width - 1 - x, y)
        if mirror in hole_set:
            raise ValueError("every turtle digit covers %s and its mirror" % ((x, y),))
        out[x, y] = out[mirror]
    return shell


class Backgrounds:
    """The tile backgrounds, measured once from the retail images in the folder images."""

    def __init__(self, images=IMAGES):
        self.images = images
        self._flat = {}
        self._shell = None

    def image(self, name, size):
        """The retail-resolution RGB background called name, at size."""
        if name == "turtle":
            if self._shell is None:
                self._shell = turtle_shell(self.images)
            if self._shell.size != size:
                raise ValueError("a turtle tile is %s, the shell %s" % (size, self._shell.size))
            return self._shell
        if name not in self._flat:
            source = PAD_SOURCE if name == "green_pad" else LOG_SOURCE
            self._flat[name] = most_common(list(retail_image(source, self.images).convert("RGB").get_flattened_data()))
        return Image.new("RGB", size, self._flat[name])


def ink_mask(row, image, background):
    """A list of rows of booleans: True where the retail image shows ink."""
    width, height = image.size
    pixels = image.load()
    if background is None:
        return [[pixels[x, y][3] > 0 for x in range(width)] for y in range(height)]
    behind = background.load()
    return [[max(abs(a - b) for a, b in zip(pixels[x, y][:3], behind[x, y])) > TILE_THRESHOLD
             for x in range(width)] for y in range(height)]


def box_of(mask, rows):
    """(x0, y0, x1, y1) of the ink of mask within rows (a range), exclusive ends, or None."""
    xs = [x for y in rows for x, on in enumerate(mask[y]) if on]
    ys = [y for y in rows if any(mask[y])]
    if not xs:
        return None
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def line_boxes(row, mask):
    """The retail ink box of each line of row's text, top to bottom."""
    lines = len(row.lines())
    full = box_of(mask, range(len(mask)))
    if full is None:
        raise ValueError("t%04d has no ink" % row.id)
    if lines == 1:
        return [full]
    x0, y0, x1, y1 = full
    runs = []
    start = None
    for y in range(y0, y1):
        if any(mask[y]):
            if start is None:
                start = y
        elif start is not None:
            runs.append((start, y))
            start = None
    if start is not None:
        runs.append((start, y1))
    if len(runs) == lines:
        bands = runs
    elif len(runs) == 1:
        counts = [sum(mask[y]) for y in range(len(mask))]
        edges = [y0]
        for i in range(1, lines):
            middle = int(y0 + (y1 - y0) * i / lines)
            window = range(max(middle - SPLIT_WINDOW, edges[-1] + 1), min(middle + SPLIT_WINDOW + 1, y1))
            edges.append(min(window, key=lambda y: (counts[y], y)))
        edges.append(y1)
        bands = [(edges[i], edges[i + 1]) for i in range(lines)]
    else:
        raise ValueError("t%04d has %d ink bands for %d lines" % (row.id, len(runs), lines))
    boxes = []
    for top, bottom in bands:
        rows = range(top, bottom)
        box = box_of(mask, rows)
        if box is None:
            raise ValueError("t%04d: a line band has no ink" % row.id)
        boxes.append(box)
    return boxes


def _labels(mask):
    """The 8-connected components of mask as a list of pixel lists, in scan order."""
    height, width = len(mask), len(mask[0])
    seen = [[False] * width for _ in range(height)]
    found = []
    for y in range(height):
        for x in range(width):
            if not mask[y][x] or seen[y][x]:
                continue
            stack = [(x, y)]
            seen[y][x] = True
            pixels = []
            while stack:
                cx, cy = stack.pop()
                pixels.append((cx, cy))
                for ny in range(cy - 1, cy + 2):
                    for nx in range(cx - 1, cx + 2):
                        if 0 <= nx < width and 0 <= ny < height and mask[ny][nx] and not seen[ny][nx]:
                            seen[ny][nx] = True
                            stack.append((nx, ny))
            found.append(pixels)
    return found


def _eroded(mask):
    """mask without every ink pixel that has a 4-neighbour outside the ink."""
    height, width = len(mask), len(mask[0])

    def on(x, y):
        return 0 <= x < width and 0 <= y < height and mask[y][x]
    return [[mask[y][x] and on(x - 1, y) and on(x + 1, y) and on(x, y - 1) and on(x, y + 1)
             for x in range(width)] for y in range(height)]


def components(row, mask, count):
    """The ink boxes of count letters of mask, left to right.

    The letters are mask's 8-connected components. Letters that touch are
    split by eroding the mask until it falls into count components, then
    growing those seeds back over the ink, nearest seed first (4-connected
    breadth-first, earlier seeds winning ties)."""
    seeds = mask
    while True:
        labels = _labels(seeds)
        if len(labels) >= count or not labels:
            break
        seeds = _eroded(seeds)
    if len(labels) != count:
        raise ValueError("t%04d has %d ink components for %d letters" % (row.id, len(labels), count))
    height, width = len(mask), len(mask[0])
    owner = [[-1] * width for _ in range(height)]
    frontier = []
    for index, pixels in enumerate(labels):
        for x, y in pixels:
            owner[y][x] = index
            frontier.append((x, y))
    while frontier:
        grown = []
        for x, y in frontier:
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < width and 0 <= ny < height and mask[ny][nx] and owner[ny][nx] < 0:
                    owner[ny][nx] = owner[y][x]
                    grown.append((nx, ny))
        frontier = grown
    boxes = []
    for index in range(count):
        xs = [x for y in range(height) for x in range(width) if owner[y][x] == index]
        ys = [y for y in range(height) for x in range(width) if owner[y][x] == index]
        boxes.append((min(xs), min(ys), max(xs) + 1, max(ys) + 1))
    boxes.sort()
    return boxes


def layout(text, glyphs):
    """The placed glyphs of one line: a list of (glyph, x offset) in font units."""
    placed = []
    pen = 0.0
    for char in text:
        if char == " ":
            pen += angular_glyphs.SPACE_ADVANCE
            continue
        glyph = glyphs.get(char)
        if glyph is None:
            raise ValueError("no glyph for %r" % char)
        placed.append((glyph, pen + angular_glyphs.SIDE_BEARING))
        pen += glyph.advance()
    return placed


def extent(placed):
    """(x0, y0, x1, y1) in font units of the ink of placed glyphs."""
    xs = [x + dx for glyph, dx in placed for contour in glyph.contours for x, _ in contour]
    ys = [y for glyph, _ in placed for contour in glyph.contours for _, y in contour]
    return min(xs), min(ys), max(xs), max(ys)


class Fit:
    """Placed glyphs with the transform from font units to retail pixels."""

    def __init__(self, placed, scale, box):
        self.placed = placed
        self.scale = scale
        self.box = box
        x0, y0, x1, y1 = extent(placed)
        self.ink_width = (x1 - x0) * scale
        self.ink_height = (y1 - y0) * scale
        self.origin_x = (box[0] + box[2]) / 2 - (x0 + x1) / 2 * scale
        self.origin_y = (box[1] + box[3]) / 2 + (y0 + y1) / 2 * scale

    def fill_ratio(self):
        """(width, height) of the fitted ink as fractions of its box."""
        return self.ink_width / (self.box[2] - self.box[0]), self.ink_height / (self.box[3] - self.box[1])


def inset(box, margin):
    """box shrunk by margin on every side."""
    return box[0] + margin, box[1] + margin, box[2] - margin, box[3] - margin


def fit_scale(placed, box):
    """The largest scale that fits placed's ink into box."""
    x0, y0, x1, y1 = extent(placed)
    return min((box[2] - box[0]) / (x1 - x0), (box[3] - box[1]) / (y1 - y0))


def letters(row):
    """The letters of row's text, without spaces and line breaks."""
    return [char for char in row.text if char not in " |"]


def ink_boxes(row, mask):
    """The retail ink box of every line (or letter, for a components layout) of row."""
    if row.layout == "components":
        return components(row, mask, len(letters(row)))
    return line_boxes(row, mask)


def fits(row, boxes, glyphs, margin):
    """The Fit of every line (or letter, for a components layout) of row in its ink box of boxes."""
    if row.layout == "components":
        result = []
        for char, box in zip(letters(row), boxes):
            placed = layout(char, glyphs)
            target = inset(box, margin)
            result.append(Fit(placed, fit_scale(placed, target), target))
        return result
    boxes = [inset(box, margin) for box in boxes]
    lines = [layout(text, glyphs) for text in row.lines()]
    scale = min(fit_scale(placed, box) for placed, box in zip(lines, boxes))
    return [Fit(placed, scale, box) for placed, box in zip(lines, boxes)]


class Geometry:
    """A row's retail padded size and the ink box of each of its lines or letters."""

    def __init__(self, size, boxes):
        self.size = size
        self.boxes = [tuple(box) for box in boxes]

    def __eq__(self, other):
        return isinstance(other, Geometry) and self.size == other.size and self.boxes == other.boxes

    def text(self):
        """The layout file's columns after the id."""
        return "%d\t%d\t%s" % (self.size[0], self.size[1], ";".join(",".join(str(v) for v in box) for box in self.boxes))


def measure(row, backgrounds):
    """(geometry, source, background) of row measured from its retail image.

    background is the tile's retail-resolution RGB background, or None for a
    transparent row."""
    source = retail_image(row.id, backgrounds.images)
    background = None
    if row.background != "transparent":
        background = backgrounds.image(row.background, source.size)
    mask = ink_mask(row, source, background)
    return Geometry(source.size, ink_boxes(row, mask)), source, background


def read_layout(rows, path=LAYOUT):
    """{id: Geometry} of the layout file; every row of rows must have exactly one entry."""
    found = {}
    by_id = {row.id: row for row in rows}
    with open(path, "r", encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) != len(LAYOUT_COLUMNS) or not all(v.isdigit() for v in fields[:3]):
                raise ValueError("lettering_layout.tsv line %d is malformed" % number)
            ident = int(fields[0])
            if ident in found:
                raise ValueError("t%04d appears twice in lettering_layout.tsv" % ident)
            if ident not in by_id:
                raise ValueError("t%04d in lettering_layout.tsv has no row in lettering.tsv" % ident)
            boxes = []
            for text in fields[3].split(";"):
                box = text.split(",")
                if len(box) != 4 or not all(v.isdigit() for v in box):
                    raise ValueError("lettering_layout.tsv line %d has a malformed box %r" % (number, text))
                boxes.append(tuple(int(v) for v in box))
            row = by_id[ident]
            wanted = len(letters(row)) if row.layout == "components" else len(row.lines())
            if len(boxes) != wanted:
                raise ValueError("t%04d has %d boxes in lettering_layout.tsv, not %d" % (ident, len(boxes), wanted))
            found[ident] = Geometry((int(fields[1]), int(fields[2])), boxes)
    for row in rows:
        if row.id not in found:
            raise ValueError("t%04d has no row in lettering_layout.tsv" % row.id)
    return found


def layout_text(rows, geometries):
    """The contents of the layout file holding geometries (by id) in the order of rows."""
    lines = [
        "# The retail geometry the lettering is fitted to, measured from the retail",
        "# images by `uv run tools/make_lettering.py --layout`: the padded size and the",
        "# ink box x0,y0,x1,y1 (exclusive ends) of each line or letter. Sizes and boxes only.",
        "# " + "\t".join(LAYOUT_COLUMNS),
    ]
    for row in rows:
        lines.append("%d\t%s" % (row.id, geometries[row.id].text()))
    return "\n".join(lines) + "\n"


def _edge_quad(a, b, radius):
    """The rectangle swept by a disc of radius moving from a to b, or None for a point."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = (dx * dx + dy * dy) ** 0.5
    if length == 0:
        return None
    nx, ny = -dy / length * radius, dx / length * radius
    return [(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny), (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)]


def rasterise(fit_list, size, radius):
    """The fill and dilated masks ("1" images of size) of every glyph of fit_list.

    Coordinates are in pixels of size; radius is the dilation in those pixels
    (0 draws no outline and returns the fill twice)."""
    fill = Image.new("1", size, 0)
    dilated = Image.new("1", size, 0) if radius else fill
    for fit in fit_list:
        for glyph, dx in fit.placed:
            contours = [[(fit.origin_x * PIXEL + (x + dx) * fit.scale * PIXEL,
                          fit.origin_y * PIXEL - y * fit.scale * PIXEL) for x, y in contour]
                        for contour in glyph.contours]
            xs = [p[0] for c in contours for p in c]
            ys = [p[1] for c in contours for p in c]
            left = max(int(min(xs) - radius) - 2, 0)
            top = max(int(min(ys) - radius) - 2, 0)
            right = min(int(max(xs) + radius) + 3, size[0])
            bottom = min(int(max(ys) + radius) + 3, size[1])
            if right <= left or bottom <= top:
                continue
            local = [[(x - left, y - top) for x, y in contour] for contour in contours]
            box = (left, top, right, bottom)
            region = (right - left, bottom - top)
            glyph_fill = Image.new("1", region, 0)
            for contour in local:
                piece = Image.new("1", region, 0)
                ImageDraw.Draw(piece).polygon(contour, fill=1)
                glyph_fill = ImageChops.logical_xor(glyph_fill, piece)
            fill.paste(ImageChops.logical_or(fill.crop(box), glyph_fill), box)
            if not radius:
                continue
            glyph_dilated = glyph_fill.copy()
            draw = ImageDraw.Draw(glyph_dilated)
            for contour in local:
                for i, a in enumerate(contour):
                    quad = _edge_quad(a, contour[(i + 1) % len(contour)], radius)
                    if quad:
                        draw.polygon(quad, fill=1)
                    draw.ellipse((a[0] - radius, a[1] - radius, a[0] + radius, a[1] + radius), fill=1)
            dilated.paste(ImageChops.logical_or(dilated.crop(box), glyph_dilated), box)
    return fill, dilated



def coverage(mask):
    """The box-reduced coverage (an "L" image at output size) of a supersampled "1" mask."""
    return mask.convert("L").reduce(SUPERSAMPLE)


def lift(image):
    """image (RGB) with every channel at least MIN_CHANNEL."""
    return image.point(lambda value: max(value, MIN_CHANNEL))


def draw(row, geometry, glyphs):
    """(fill, alpha, fits) for row at geometry: the fill and dilated coverage ("L" images at output size)
    and the Fit of each line or letter. alpha is fill when the style has no outline."""
    width, height = geometry.size
    output = (width * SCALE, height * SCALE)
    canvas = (output[0] * SUPERSAMPLE, output[1] * SUPERSAMPLE)
    outline_colour = STYLES[row.style][1]
    margin = OUTLINE if outline_colour is not None else 0
    fit_list = fits(row, geometry.boxes, glyphs, margin)
    radius = OUTLINE * PIXEL if outline_colour is not None else 0
    fill_mask, dilated_mask = rasterise(fit_list, canvas, radius)
    fill = coverage(fill_mask)
    alpha = coverage(dilated_mask) if radius else fill
    return fill, alpha, fit_list


def lettering_image(row, fill, alpha):
    """The RGBA lettering image of the transparent row from its fill and dilated coverage."""
    fill_colour, outline_colour = STYLES[row.style]
    solid_fill = Image.new("RGB", fill.size, fill_colour)
    if outline_colour is None:
        rgb = solid_fill
    else:
        share = ImageMath.lambda_eval(
            lambda a: a["convert"](a["min"](a["f"] * 255 / a["max"](a["d"], 1), 255), "L"), f=fill, d=alpha)
        rgb = Image.composite(solid_fill, Image.new("RGB", fill.size, outline_colour), share)
    image = lift(rgb).convert("RGBA")
    image.putalpha(alpha)
    return image


def tile_image(row, fill, source, background):
    """The opaque RGBA tile of the tile row: its fill coverage over background in the colour of source's ink."""
    width, height = source.size
    mask = ink_mask(row, source, background)
    pixels = source.load()
    fill_colour = most_common([pixels[x, y][:3] for y in range(height) for x in range(width) if mask[y][x]])
    solid_fill = Image.new("RGB", fill.size, fill_colour)
    behind = background.resize(fill.size, Image.NEAREST)
    image = lift(Image.composite(solid_fill, behind, fill)).convert("RGBA")
    image.putalpha(255)
    return image


def content_files(rows, geometries, glyphs):
    """(path relative to OUTPUT, kind, image) for every row: an RGBA "image" or an "L" "mask"."""
    result = []
    for row in rows:
        for char in row.text:
            if char not in "| " and char not in glyphs:
                raise ValueError("t%04d: no glyph for %r" % (row.id, char))
        fill, alpha, _ = draw(row, geometries[row.id], glyphs)
        if row.background == "transparent":
            result.append((file_name(row.id), "image", lettering_image(row, fill, alpha)))
        else:
            result.append((os.path.join(MASKS, row.background, file_name(row.id)), "mask", fill))
    return result


def composite_tiles(rows, images, glyphs):
    """(id, image) of the finished tile of every tile row, measured and coloured from the retail images."""
    backgrounds = Backgrounds(images)
    result = []
    for row in rows:
        if row.background == "transparent":
            continue
        geometry, source, background = measure(row, backgrounds)
        fill, _, _ = draw(row, geometry, glyphs)
        result.append((row.id, tile_image(row, fill, source, background)))
    return result


def read_sidecar(path):
    """{section: {key: raw value}} of the one-line keys of the Godot import sidecar at path."""
    sections = {}
    current = sections.setdefault("", {})
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("[") and line.endswith("]"):
                current = sections.setdefault(line[1:-1], {})
            elif "=" in line and not line[:1].isspace():
                key, value = line.split("=", 1)
                current[key] = value
    return sections


def sidecar_problems(path, kind):
    """Why the sidecar at path does not hold the policy of kind (empty when it does)."""
    if not os.path.exists(path):
        return ["no sidecar"]
    sections = read_sidecar(path)
    problems = []
    importer = sections.get("remap", {}).get("importer")
    wanted = '"image"' if kind == "mask" else '"texture"'
    if importer != wanted:
        problems.append("sidecar importer is %s, not %s" % (importer, wanted))
    if kind == "mask":
        return problems
    params = sections.get("params", {})
    for key, value in SIDECAR_POLICY.items():
        got = params.get(key)
        if got != value:
            problems.append("sidecar %s is %s, not %s" % (key, got, value))
    return problems


def committed(path, mode):
    """The decoded image of the PNG at path in mode, or None."""
    if not os.path.exists(path):
        return None
    with Image.open(path) as image:
        return image.convert(mode)


def same_rasterisation(old, new):
    """Whether old and new (RGBA images of one size) differ at most by rasteriser rounding."""
    channels = ImageChops.difference(old, new).split()
    largest = max(channel.getextrema()[1] for channel in channels)
    if largest == 0:
        return True
    if largest > RASTER_STEP:
        return False
    changed = channels[0]
    for channel in channels[1:]:
        changed = ImageChops.lighter(changed, channel)
    return changed.point(lambda value: 255 if value else 0).histogram()[255] <= RASTER_PIXELS


def extra_files(wanted):
    """The files under the output folder, relative to it, that belong to no row."""
    extras = []
    for folder, _, names in os.walk(OUTPUT):
        for name in names:
            relative = os.path.relpath(os.path.join(folder, name), OUTPUT)
            base = relative[:-len(".import")] if relative.endswith(".import") else relative
            if base not in wanted:
                extras.append(relative)
    return sorted(extras)


def report(differing, relative):
    """Prints the differing lines and exits 1."""
    for line in differing[:60]:
        print("%s: %s" % (relative, line))
    if len(differing) > 60:
        print("%s: ... and %d more" % (relative, len(differing) - 60))
    print("%s differs from the generator in %d places" % (relative, len(differing)))
    sys.exit(1)


def run_layout(rows, images, check, quiet):
    """Measures the layout from the retail images and writes or checks the layout file."""
    backgrounds = Backgrounds(images)
    geometries = {row.id: measure(row, backgrounds)[0] for row in rows}
    text = layout_text(rows, geometries)
    relative = os.path.relpath(LAYOUT, ROOT)
    old = None
    if os.path.exists(LAYOUT):
        with open(LAYOUT, "r", encoding="utf-8") as f:
            old = f.read()
    if check:
        if old != text:
            differing = []
            stored = read_layout(rows) if old is not None else {}
            for row in rows:
                if stored.get(row.id) != geometries[row.id]:
                    differing.append("t%04d: measured %s" % (row.id, geometries[row.id].text().replace("\t", " ")))
            report(differing or ["the notes differ"], relative)
        if not quiet:
            print("%s (%d rows) matches the retail images" % (relative, len(rows)))
        return
    if old != text:
        with open(LAYOUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    if not quiet:
        print("%s %s (%d rows)" % ("wrote" if old != text else "kept", relative, len(rows)))


def run_composite(rows, assets, out, quiet):
    """Writes the finished tile of every tile row, from the retail images under assets, into out."""
    tiles = composite_tiles(rows, os.path.join(assets, "textures", "images"), angular_glyphs.glyphs())
    os.makedirs(out, exist_ok=True)
    for ident, image in tiles:
        image.save(os.path.join(out, file_name(ident)))
    if not quiet:
        print("wrote %d tiles to %s" % (len(tiles), out))


def run_content(rows, check, quiet):
    """Writes or checks the lettering images and tile masks under OUTPUT."""
    built = content_files(rows, read_layout(rows), angular_glyphs.glyphs())
    wanted = {path for path, _, _ in built}
    relative = os.path.relpath(OUTPUT, ROOT)
    differing = []
    written = 0
    seeded = 0
    for name, kind, image in built:
        path = os.path.join(OUTPUT, name)
        sidecar = path + ".import"
        old = committed(path, image.mode)
        problems = []
        if old is None:
            problems.append("missing")
        elif old.size != image.size:
            problems.append("is %dx%d, expected %dx%d" % (old.size + image.size))
        elif not same_rasterisation(old, image):
            problems.append("pixels differ")
        if check:
            problems.extend(sidecar_problems(sidecar, kind))
            if problems:
                differing.append("%s: %s" % (name, "; ".join(problems)))
            continue
        if problems:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            image.save(path)
            written += 1
        if sidecar_problems(sidecar, kind):
            with open(sidecar, "w", encoding="utf-8", newline="\n") as f:
                f.write(MASK_SIDECAR_SEED if kind == "mask" else SIDECAR_SEED)
            seeded += 1
    extras = extra_files(wanted)
    if check:
        for name in extras:
            differing.append("%s has no row in lettering.tsv" % name)
        if differing:
            report(differing, relative)
        if not quiet:
            print("%s (%d images and masks) matches the generator" % (relative, len(built)))
        return
    for name in extras:
        os.remove(os.path.join(OUTPUT, name))
    if not quiet:
        print("wrote %d images and masks and %d seed sidecars, removed %d extra files under %s"
              % (written, seeded, len(extras), relative))
        if seeded:
            print("run `godot --headless --path . --import` to complete the seed sidecars")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="compare with the committed files instead of writing")
    parser.add_argument("--quiet", action="store_true", help="print nothing on success")
    parser.add_argument("--layout", action="store_true", help="measure the layout file from the retail images")
    parser.add_argument("--images", default=IMAGES, help="the retail images folder --layout reads")
    parser.add_argument("--composite", metavar="ASSETS", help="write the finished tiles from this assets folder")
    parser.add_argument("--out", help="the folder --composite writes into")
    args = parser.parse_args()
    if args.composite is not None and (args.out is None or args.layout or args.check):
        parser.error("--composite needs --out and takes neither --layout nor --check")
    try:
        rows = read_table()
        if args.layout:
            run_layout(rows, args.images, args.check, args.quiet)
        elif args.composite is not None:
            run_composite(rows, args.composite, args.out, args.quiet)
        else:
            run_content(rows, args.check, args.quiet)
    except (ValueError, OSError) as error:
        print("make_lettering: %s" % error)
        sys.exit(1)


if __name__ == "__main__":
    main()

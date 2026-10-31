#!/usr/bin/env python3
"""Bake the upscaled texture pages and sky atlases from the committed assets.

Every page set under assets/textures/pages/<SET>/page_set.tres names its two
banks (the GENERAL bank, then the theme bank). Each bank's
assets/textures/banks/<BANK>.tres lists its images in upload order with their
padded VRAM placement, flags and PNG under assets/textures/images/. This tool
composes the set's fourteen 256 x 256 VRAM pages and, where the set has one,
its sky atlas at an integer scale S (default 4), taking RGB from the S-times
images (default assets/textures/images_x4/), and writes them to
assets/textures/pages_x4/<SET>/ with a page_set.tres pointing at them and a
.png.import sidecar per PNG that asks Godot for mipmaps. The output is
gitignored and baked on each machine.

Composition follows the importer's page bake:
  * A page starts opaque black. The GENERAL bank, then the theme bank, are
    copied in upload order, later uploads overwriting earlier pixels. An upload
    is valid when its padded rectangle lies inside the 256 x 3584 VRAM; it may
    run on into the next page, and each page takes the rows inside its band.
  * A page is colour keyed when a valid upload whose own page it is (vram_y
    // 256) has flag bit 5 (black is transparent). On a keyed page exact RGB
    0,0,0 anywhere is transparent and every other pixel opaque, whatever the
    image alpha; other pages are fully opaque.
  * The sky atlas is 256 wide with one 258-row slot per entry of sky_pages,
    magenta, holding the page in rows 1-256 with its first and last rows
    repeated above and below (clamp); a missing page leaves its slot magenta.
At scale S every coordinate and size is multiplied by S. The colour key is
page wide (it covers padding and unflagged neighbours), so a keyed page's
alpha is the nearest-neighbour S-times enlargement of the 1x page's alpha and
RGB under alpha 0 is zero, as at 1x. Each sky slot is 258*S rows: the scaled
page's first row repeated S times, the scaled page, then its last row repeated
S times.

Before writing anything the tool composes every selected set at 1x from
assets/textures/images/ and compares its RGBA with the committed pages, sky
atlas and colour_keyed list, and stops at the first mismatch. It warns (on
stderr) when an S-times image's alpha is not the enlargement of its 1x alpha.
Files are written only when their pixels or text change. --check composes
everything, writes nothing and exits 1 naming the first file that differs or
is missing. With --scale 1 the pages reproduce the committed ones. When the
S-times image folder does not exist the tool says so and exits 0, so a test
wrapper can call it unconditionally. --quiet prints only the total line.
"""

import argparse
import hashlib
import io
import os
import re
import sys
import time

from PIL import Image, ImageChops

sys.dont_write_bytecode = True

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE_SIZE = 256
PAGE_COUNT = 14
SKY_SLOT_HEIGHT = 258
FLAG_BLACK_IS_TRANSPARENT = 1 << 5
BLACK = (0, 0, 0, 255)
MAGENTA = (255, 0, 255, 255)
SET_FILE = "page_set.tres"
SKY_FILE = "sky.png"
IMAGE_KEYS = ("vram_x", "vram_y", "padded_width", "padded_height", "texture_id", "flags")

EXT_RESOURCE = re.compile(r'^\[ext_resource ([^\]]*)\]\s*$', re.M)
ATTRIBUTE = re.compile(r'(\w+)="([^"]*)"')
EXT_REFERENCE = re.compile(r'ExtResource\("([^"]+)"\)')
SUB_REFERENCE = re.compile(r'SubResource\("([^"]+)"\)')


class BakeError(Exception):
    """A problem that stops the bake: unreadable input or a failed self-check."""


class Upload:
    """One bank image: its padded VRAM rectangle, flags and PNG file name."""

    def __init__(self, values, file_name):
        self.vram_x, self.vram_y, self.padded_width, self.padded_height, self.texture_id, self.flags = values
        self.file_name = file_name

    def fits(self):
        """True when the padded upload lies inside the fourteen pages."""
        return (self.vram_x >= 0 and self.vram_y >= 0 and self.padded_width > 0 and self.padded_height > 0
                and self.vram_x + self.padded_width <= PAGE_SIZE
                and self.vram_y + self.padded_height <= PAGE_COUNT * PAGE_SIZE)

    def page(self):
        """The page the upload starts on."""
        return self.vram_y // PAGE_SIZE

    def keys_page(self):
        """True when the upload has the black-is-transparent flag."""
        return self.flags & FLAG_BLACK_IS_TRANSPARENT == FLAG_BLACK_IS_TRANSPARENT


class PageSet:
    """A committed page_set.tres: its text and the values the bake needs."""

    def __init__(self, name, text):
        self.name = name
        self.text = text
        self.bank_names = re.findall(r'"([^"]*)"', _property(text, "bank_names"))
        self.colour_keyed = [v.strip() == "true" for v in _list_body(_property(text, "colour_keyed")).split(",")]
        sky_pages = _list_body(_property(text, "sky_pages", "PackedInt32Array()"))
        self.sky_pages = [int(v) for v in sky_pages.split(",")] if sky_pages.strip() else []
        self.has_sky = _property(text, "sky_atlas", "") != ""
        if len(self.bank_names) != 2 or len(self.colour_keyed) != PAGE_COUNT:
            raise BakeError("%s: expected two banks and %d colour_keyed values" % (name, PAGE_COUNT))


def _property(text, key, default=None):
    """The raw value of resource property [key] in a .tres, or [default] when absent."""
    match = re.search(r'^%s = (.*)$' % re.escape(key), text, re.M)
    if match is None:
        if default is None:
            raise BakeError("no %s property" % key)
        return default
    return match.group(1).strip()


def _list_body(value):
    """The text between the innermost brackets or parentheses of a typed array literal."""
    match = re.search(r'[\[(]([^\[\]()]*)[\])]\)?$', value)
    return match.group(1) if match else ""


def ext_resources(text):
    """Each ext_resource of a .tres by id: a dict of its attributes."""
    result = {}
    for match in EXT_RESOURCE.finditer(text):
        attributes = dict(ATTRIBUTE.findall(match.group(1)))
        result[attributes["id"]] = attributes
    return result


def sub_resources(text):
    """Each sub_resource of a .tres by id: a dict of its raw property values."""
    result = {}
    current = None
    for line in text.splitlines():
        if line.startswith("["):
            current = None
            if line.startswith("[sub_resource "):
                current = {}
                result[dict(ATTRIBUTE.findall(line))["id"]] = current
        elif current is not None and " = " in line:
            key, value = line.split(" = ", 1)
            current[key] = value.strip()
    return result


def bank_file_name(bank_name):
    """The bank resource's file name for a display name with or without .VLO."""
    bare = bank_name[:-4] if bank_name.upper().endswith(".VLO") else bank_name
    return bare + ".tres"


def read_bank(assets, bank_name):
    """The uploads of bank [bank_name] in upload order."""
    path = os.path.join(assets, "textures", "banks", bank_file_name(bank_name))
    if not os.path.isfile(path):
        raise BakeError("missing bank %s" % path)
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    externals = ext_resources(text)
    images = sub_resources(text)
    order = SUB_REFERENCE.findall(_property(text[text.index("\n[resource]"):], "images"))
    uploads = []
    for image_id in order:
        values = images[image_id]
        numbers = tuple(int(values.get(key, "0")) for key in IMAGE_KEYS)
        texture = EXT_REFERENCE.search(values.get("texture", ""))
        file_name = os.path.basename(externals[texture.group(1)]["path"]) if texture else None
        uploads.append(Upload(numbers, file_name))
    return uploads


def read_page_sets(assets, names):
    """The committed page sets, by name, all of them or only [names]."""
    pages_dir = os.path.join(assets, "textures", "pages")
    available = sorted(n for n in os.listdir(pages_dir) if os.path.isfile(os.path.join(pages_dir, n, SET_FILE)))
    chosen = available if not names else names
    result = []
    for name in chosen:
        path = os.path.join(pages_dir, name, SET_FILE)
        if not os.path.isfile(path):
            raise BakeError("no page set %s" % path)
        with open(path, encoding="utf-8") as handle:
            result.append(PageSet(name, handle.read()))
    return result


class ImageSource:
    """Loads bank image PNGs from a folder at a known scale, warning once per problem."""

    def __init__(self, folder, scale, retail_folder=None):
        self.folder = folder
        self.scale = scale
        self.retail_folder = retail_folder
        self.checked = set()
        self.alpha_warnings = 0

    def load(self, upload):
        """The upload's RGBA image, checked to be its padded size times the scale."""
        path = os.path.join(self.folder, upload.file_name)
        if not os.path.isfile(path):
            raise BakeError("missing image %s" % path)
        image = Image.open(path)
        image.load()
        image = image.convert("RGBA") if image.mode != "RGBA" else image
        wanted = (upload.padded_width * self.scale, upload.padded_height * self.scale)
        if image.size != wanted:
            raise BakeError("%s is %dx%d, expected %dx%d" % (path, image.size[0], image.size[1], wanted[0], wanted[1]))
        if self.retail_folder is not None and upload.file_name not in self.checked:
            self.checked.add(upload.file_name)
            self._check_alpha(upload, image)
        return image

    def _check_alpha(self, upload, image):
        """Warns when the image's alpha is not the nearest enlargement of the 1x image's alpha."""
        retail = Image.open(os.path.join(self.retail_folder, upload.file_name)).convert("RGBA")
        expected = retail.getchannel("A").resize(image.size, Image.NEAREST)
        if ImageChops.difference(expected, image.getchannel("A")).getbbox() is not None:
            self.alpha_warnings += 1
            print("warning: %s alpha is not the nearest x%d of its 1x alpha" % (upload.file_name, self.scale),
                  file=sys.stderr)


def blank_pages(scale):
    """Fourteen opaque black pages at [scale]."""
    return [Image.new("RGBA", (PAGE_SIZE * scale, PAGE_SIZE * scale), BLACK) for _ in range(PAGE_COUNT)]


def upload_bank(pages, uploads, source, scale, diagnostics):
    """Copies each valid upload of a bank into [pages], in upload order, clipped to each page's band."""
    for upload in uploads:
        if not upload.fits() or upload.file_name is None:
            diagnostics.add("texture %d has an invalid physical VRAM upload" % upload.texture_id)
            continue
        image = source.load(upload)
        top = upload.vram_y * scale
        bottom = top + upload.padded_height * scale
        band = PAGE_SIZE * scale
        for page in range(top // band, (bottom - 1) // band + 1):
            first = max(top, page * band)
            last = min(bottom, (page + 1) * band)
            rows = image.crop((0, first - top, image.size[0], last - top))
            pages[page].paste(rows, (upload.vram_x * scale, first - page * band))


def keyed_pages(banks):
    """Per page, True when a valid upload whose own page it is has the colour-key flag."""
    keyed = [False] * PAGE_COUNT
    for uploads in banks:
        for upload in uploads:
            if upload.fits() and upload.keys_page():
                keyed[upload.page()] = True
    return keyed


def black_mask(page):
    """An L mask of [page]: 0 where RGB is exactly zero, 255 elsewhere."""
    red, green, blue, _ = page.split()
    lit = ImageChops.lighter(ImageChops.lighter(red, green), blue)
    return lit.point(lambda value: 255 if value else 0)


def finish_page(page, keyed, retail_mask, scale):
    """[page] with its final alpha: keyed by [retail_mask] enlarged to [scale], else opaque."""
    if not keyed:
        page.putalpha(255)
        return page
    mask = retail_mask if scale == 1 else retail_mask.resize(page.size, Image.NEAREST)
    result = Image.composite(page, Image.new("RGBA", page.size, BLACK), mask)
    result.putalpha(mask)
    return result


def sky_atlas(pages, order, scale):
    """The sky atlas of [order] at [scale]: each slot's page with its first and last rows repeated [scale] times."""
    size = PAGE_SIZE * scale
    slot_height = SKY_SLOT_HEIGHT * scale
    atlas = Image.new("RGBA", (size, slot_height * max(1, len(order))), MAGENTA)
    for slot, page in enumerate(order):
        if page < 0 or page >= len(pages) or pages[page] is None:
            continue
        top = slot * slot_height
        atlas.paste(pages[page], (0, top + scale))
        first = pages[page].crop((0, 0, size, 1)).resize((size, scale), Image.NEAREST)
        last = pages[page].crop((0, size - 1, size, size)).resize((size, scale), Image.NEAREST)
        atlas.paste(first, (0, top))
        atlas.paste(last, (0, top + scale + size))
    return atlas


class Composer:
    """Composes page sets at one scale, reusing the GENERAL bank's layer across consecutive sets."""

    def __init__(self, assets, source, scale):
        self.assets = assets
        self.source = source
        self.scale = scale
        self.banks = {}
        self.general = (None, None, None)

    def bank(self, name):
        """The uploads of bank [name], read once."""
        if name not in self.banks:
            self.banks[name] = read_bank(self.assets, name)
        return self.banks[name]

    def compose(self, page_set, retail_masks=None):
        """The set's final pages, keyed flags, black masks and diagnostics; masks default to its own."""
        general_name, theme_name = page_set.bank_names
        general, theme = self.bank(general_name), self.bank(theme_name)
        diagnostics = set()
        pages = [page.copy() for page in self._general_layer(general_name, general, diagnostics)]
        upload_bank(pages, theme, self.source, self.scale, diagnostics)
        keyed = keyed_pages([general, theme])
        masks = [black_mask(page) if keyed[i] else None for i, page in enumerate(pages)]
        use = masks if retail_masks is None else retail_masks
        final = [finish_page(page, keyed[i], use[i], self.scale) for i, page in enumerate(pages)]
        return final, keyed, masks, diagnostics

    def _general_layer(self, name, uploads, diagnostics):
        """The GENERAL bank's pages before keying, composed once per run of sets sharing it."""
        if self.general[0] != name:
            layer_diagnostics = set()
            layer = blank_pages(self.scale)
            upload_bank(layer, uploads, self.source, self.scale, layer_diagnostics)
            self.general = (name, layer, layer_diagnostics)
        diagnostics.update(self.general[2])
        return self.general[1]


def png_bytes(image):
    """[image] encoded as a non-interlaced RGBA PNG."""
    buffer = io.BytesIO()
    image.save(buffer, "PNG", compress_level=6)
    return buffer.getvalue()


def same_pixels(path, image):
    """True when the PNG at [path] exists and holds exactly [image]'s RGBA pixels."""
    if not os.path.isfile(path):
        return False
    existing = Image.open(path)
    if existing.size != image.size:
        return False
    return existing.convert("RGBA").tobytes() == image.tobytes()


def same_text(path, text):
    """True when the file at [path] exists and holds exactly [text]."""
    if not os.path.isfile(path):
        return False
    with open(path, "rb") as handle:
        return handle.read() == text.encode("utf-8")


def compare_retail(assets, page_set, pages, keyed):
    """Raises unless the 1x composition matches the committed pages, sky atlas and colour_keyed list."""
    folder = os.path.join(assets, "textures", "pages", page_set.name)
    if keyed != page_set.colour_keyed:
        raise BakeError("self-check: %s colour_keyed differs from the committed page set" % page_set.name)
    for page, image in enumerate(pages):
        path = os.path.join(folder, "page_%02d.png" % page)
        if not same_pixels(path, image):
            raise BakeError("self-check: composed 1x page differs from %s" % path)
    if page_set.has_sky:
        path = os.path.join(folder, SKY_FILE)
        if not same_pixels(path, sky_atlas(pages, page_set.sky_pages, 1)):
            raise BakeError("self-check: composed 1x sky atlas differs from %s" % path)


def res_path(path):
    """The res:// path of [path]; a folder outside the project keeps only its last three parts."""
    relative = os.path.relpath(os.path.abspath(path), ROOT).replace(os.sep, "/")
    if relative.startswith("../"):
        relative = "/".join(relative.split("/")[-3:])
    return "res://" + relative


def uid_text(seed):
    """A stable Godot uid:// text for [seed]: a 63-bit id in base 34, digits a-y then 0-8, as Godot writes it."""
    number = int.from_bytes(hashlib.sha256(seed.encode("utf-8")).digest()[:8], "big") & 0x7FFFFFFFFFFFFFFF
    digits = ""
    while True:
        number, digit = divmod(number, 34)
        digits = (chr(ord("a") + digit) if digit < 25 else chr(ord("0") + digit - 25)) + digits
        if number == 0:
            return "uid://" + digits


def import_sidecar(source):
    """The .png.import text for res:// path [source]: lossless, mipmapped, as Godot writes it."""
    imported = "res://.godot/imported/%s-%s.ctex" % (source.rsplit("/", 1)[-1], hashlib.md5(source.encode("utf-8")).hexdigest())
    return IMPORT_TEMPLATE % {"uid": uid_text(source), "imported": imported, "source": source}


IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="%(uid)s"
path="%(imported)s"
metadata={
"vram_texture": false
}

[deps]

source_file="%(source)s"
dest_files=["%(imported)s"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def page_set_text(page_set, folder):
    """The committed page_set.tres rewritten with fixed ids and texture paths into [folder]."""
    externals = ext_resources(page_set.text)
    renamed = {}
    lines = []
    for old_id, attributes in externals.items():
        name = os.path.basename(attributes["path"])
        if attributes["type"] == "Texture2D" and name.startswith("page_"):
            page = int(name[5:7])
            new_id, path = "%d_page%02d" % (page + 1, page), "%s/%s" % (folder, name)
        elif attributes["type"] == "Texture2D" and name == SKY_FILE:
            new_id, path = "%d_sky" % (PAGE_COUNT + 2), "%s/%s" % (folder, name)
        else:
            new_id, path = "%d_script" % (PAGE_COUNT + 1), attributes["path"]
        renamed[old_id] = new_id
        lines.append((new_id, '[ext_resource type="%s" path="%s" id="%s"]' % (attributes["type"], path, new_id)))
    lines.sort(key=lambda item: int(item[0].split("_")[0]))
    body = page_set.text[page_set.text.index("\n[resource]"):]
    body = EXT_REFERENCE.sub(lambda match: 'ExtResource("%s")' % renamed[match.group(1)], body)
    header = page_set.text[:page_set.text.index("\n")]
    return header + "\n\n" + "\n".join(line for _, line in lines) + "\n" + body


def set_outputs(page_set, pages, scale, folder):
    """Every file of a baked set as (file name, PIL image or text)."""
    outputs = [("page_%02d.png" % page, image) for page, image in enumerate(pages)]
    if page_set.has_sky:
        outputs.append((SKY_FILE, sky_atlas(pages, page_set.sky_pages, scale)))
    resource_folder = res_path(folder)
    files = []
    for name, image in outputs:
        files.append((name, image))
        files.append((name + ".import", import_sidecar(resource_folder + "/" + name)))
    files.append((SET_FILE, page_set_text(page_set, resource_folder)))
    return files


def write_set(files, folder, check):
    """Writes the changed files of a set; with [check] returns the first differing path instead."""
    written = 0
    for name, content in files:
        path = os.path.join(folder, name)
        same = same_text(path, content) if isinstance(content, str) else same_pixels(path, content)
        if same:
            continue
        if check:
            return path, written
        os.makedirs(folder, exist_ok=True)
        data = content.encode("utf-8") if isinstance(content, str) else png_bytes(content)
        with open(path, "wb") as handle:
            handle.write(data)
        written += 1
    return None, written


def report_diagnostics(name, diagnostics):
    """Prints a set's composition problems on stderr."""
    for message in sorted(diagnostics):
        print("warning: %s: %s" % (name, message), file=sys.stderr)


def self_check(assets, page_sets):
    """Composes every set at 1x, compares it with the committed pages and returns each set's black masks."""
    composer = Composer(assets, ImageSource(os.path.join(assets, "textures", "images"), 1), 1)
    masks = {}
    for page_set in page_sets:
        pages, keyed, set_masks, diagnostics = composer.compose(page_set)
        report_diagnostics(page_set.name, diagnostics)
        compare_retail(assets, page_set, pages, keyed)
        masks[page_set.name] = set_masks
    return masks


def arguments():
    """The parsed command line."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scale", type=int, default=4, help="integer scale of the images and pages (default 4)")
    parser.add_argument("--assets", default=os.path.join(ROOT, "assets"), help="assets folder (default: assets)")
    parser.add_argument("--images-dir", help="image folder under assets/textures (default: images_x<S>, or images at 1)")
    parser.add_argument("--output-dir", help="output folder (default: assets/textures/pages_x<S>)")
    parser.add_argument("--sets", nargs="+", metavar="NAME", help="bake only these sets")
    parser.add_argument("--check", action="store_true", help="write nothing; exit 1 when an output differs or is missing")
    parser.add_argument("--quiet", action="store_true", help="print only the total")
    args = parser.parse_args()
    if args.scale < 1:
        parser.error("--scale must be at least 1")
    if args.images_dir is None:
        args.images_dir = "images" if args.scale == 1 else "images_x%d" % args.scale
    if args.output_dir is None:
        args.output_dir = os.path.join(args.assets, "textures", "pages_x%d" % args.scale)
    return args


def bake(args):
    """Runs the self-check, then composes, writes or checks every set; returns the exit code."""
    started = time.monotonic()
    assets = os.path.abspath(args.assets)
    images = os.path.join(assets, "textures", args.images_dir)
    if not os.path.isdir(images):
        print("no %s; nothing to bake" % images)
        return 0
    page_sets = read_page_sets(assets, args.sets)
    retail_masks = self_check(assets, page_sets)
    retail_images = os.path.join(assets, "textures", "images")
    source = ImageSource(images, args.scale, retail_images if args.scale > 1 else None)
    composer = Composer(assets, source, args.scale)
    total_written = 0
    for page_set in page_sets:
        pages, keyed, _, diagnostics = composer.compose(page_set, retail_masks[page_set.name])
        folder = os.path.join(os.path.abspath(args.output_dir), page_set.name)
        differing, written = write_set(set_outputs(page_set, pages, args.scale, folder), folder, args.check)
        if differing is not None:
            print("differs or missing: %s" % differing, file=sys.stderr)
            return 1
        total_written += written
        if not args.quiet:
            print("%s: %d pages%s, %d keyed, %d files written" % (
                page_set.name, PAGE_COUNT, " + sky" if page_set.has_sky else "", sum(keyed), written))
    print("%d sets at x%d %s in %.1f s; %d files written; %d alpha warnings" % (
        len(page_sets), args.scale, "checked" if args.check else "baked", time.monotonic() - started,
        total_written, source.alpha_warnings))
    return 0


def main():
    """Entry point."""
    try:
        return bake(arguments())
    except BakeError as error:
        print("error: %s" % error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

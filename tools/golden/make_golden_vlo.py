#!/usr/bin/env python3
"""Build the golden texture-bank (VLO) facts for a retail Frogger PC install.

An independent, standard-library-only reading of the PC texture bank format
("2GRP"), written from FrogLord's Java sources (vlo2/VloFile, VloImage,
VloUtils, PSXClutColor). It shares no code with the Godot project; the Godot
tests compare their own decoding with the files written here. Every file in
the archive that starts with "2GRP" is read, whether it is stored on its own
in the MWD or inside a WAD (the retail build has none inside WADs).

No pixel data is written. Each image is described by its header fields and
two SHA-256 digests of decoded pixels, defined as follows (tests/golden/README.md):

  decoded pixel      bytes R, G, B, A (8 bits each), rows top to bottom,
                     pixels left to right; no row padding.
  source             4 bytes per pixel on disk in the order A, B, G, R.
  colour             R, G, B copied from the file.
  alpha              255, except 0 when the image's flag bit 5 ("black is
                     transparent") is set and R, G and B are all below 8
                     ((R | G | B) & 0xF8 == 0). The stored A byte is ignored:
                     the game never reads it.
  padded digest      over the whole stored image (padded width x height).
  unpadded digest    over the in-game region only: the unpadded width x
                     height starting at left = (padded w - unpadded w) / 2,
                     top = (padded h - unpadded h) / 2 (integer division).
                     This is what FrogLord's image export writes to PNG.

The script checks every header the way FrogLord does and fails on any
disagreement: header size, image data positions and zero alignment, the
texture page word (page = VRAM y / 256, blend mode in bits 8-9), the stored
U/V (page position plus padding) and horizontal padding equal to vertical.

Usage:
    python3 tools/golden/make_golden_vlo.py <dir with FROGGER.EXE and FROGPSX.MWD> <out dir>
"""

import argparse
import array
import hashlib
import os
import struct
import sys
import time

sys.dont_write_bytecode = True
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden.make_golden_manifest import FLAG_GROUP_ACCESS, SECTOR_SIZE, is_compressed, pp20_unpack, read_mwi

FLAG_BLACK_IS_TRANSPARENT = 1 << 5
PAGE_HEIGHT = 256
PAGE_WIDTH = 256
LOW_TABLE = bytes(1 if v < 8 else 0 for v in range(256))


class VloError(Exception):
    pass


def decode_rgba(raw, flags):
    """RGBA bytes for raw A,B,G,R pixels under the rule in the module docstring."""
    words = array.array("I")
    words.frombytes(raw)
    if sys.byteorder == "little":
        words.byteswap()
    else:
        words = array.array("I", [((w & 0xFF) << 24) | ((w >> 8 & 0xFF) << 16) | ((w >> 16 & 0xFF) << 8) | (w >> 24) for w in words])
    out = bytearray(words.tobytes())
    count = len(out) // 4
    alpha = bytearray(b"\xff" * count)
    if flags & FLAG_BLACK_IS_TRANSPARENT:
        low_r = int.from_bytes(bytes(out[0::4]).translate(LOW_TABLE), "big")
        low_g = int.from_bytes(bytes(out[1::4]).translate(LOW_TABLE), "big")
        low_b = int.from_bytes(bytes(out[2::4]).translate(LOW_TABLE), "big")
        transparent = (low_r & low_g & low_b).to_bytes(count, "big")
        alpha = bytearray(transparent.translate(bytes([255, 0]) + bytes(254)))
    out[3::4] = alpha
    return bytes(out)


def crop(rgba, width, left, top, w, h):
    rows = []
    for y in range(top, top + h):
        start = (y * width + left) * 4
        rows.append(rgba[start:start + w * 4])
    return b"".join(rows)


def parse_vlo(data):
    if data[:4] != b"2GRP":
        raise VloError("not a PC texture bank")
    count, header_end = struct.unpack_from("<ii", data, 4)
    if header_end != 12:
        raise VloError("image headers start at %d, not 12" % header_end)
    images = []
    for i in range(count):
        vx, vy, pw, ph, offset, tid, tpage, flags, clut, u, v, uw, uh = struct.unpack_from("<hhhhihHHhBBBB", data, 12 + 24 * i)
        uw = uw or 256
        uh = uh or 256
        pad_x, pad_y = pw - uw, ph - uh
        abr = (tpage >> 8) & 3
        page = vy // PAGE_HEIGHT
        if ((page & 0xFF) | (abr << 8)) != tpage:
            raise VloError("image %d: texture page word %d, expected %d" % (i, tpage, (page & 0xFF) | (abr << 8)))
        if pad_x != pad_y:
            raise VloError("image %d: padding %d x %d" % (i, pad_x, pad_y))
        if u != (vx % PAGE_WIDTH) + pad_x // 2 or v != (vy % PAGE_HEIGHT) + pad_y // 2:
            raise VloError("image %d: stored U/V do not match its position" % i)
        images.append({"vram_x": vx, "vram_y": vy, "padded_w": pw, "padded_h": ph, "offset": offset,
                       "texture_id": tid, "tpage": tpage, "flags": flags, "u": u, "v": v, "w": uw, "h": uh,
                       "abr": abr, "page": page})
    pos = 12 + 24 * count
    nonzero_alpha = 0
    for i, img in enumerate(images):
        aligned = (pos + 3) & ~3
        if data[pos:aligned] != b"\0" * (aligned - pos):
            raise VloError("image %d: non-zero alignment bytes" % i)
        if img["offset"] != aligned:
            raise VloError("image %d: data at %d, expected %d" % (i, img["offset"], aligned))
        size = img["padded_w"] * img["padded_h"] * 4
        raw = data[aligned:aligned + size]
        if len(raw) != size:
            raise VloError("image %d: pixel data runs past the end" % i)
        nonzero_alpha += len(raw[0::4]) - raw[0::4].count(0)
        img["rgba"] = decode_rgba(raw, img["flags"])
        near = img["rgba"][3::4].count(0)
        exact = 0
        if img["flags"] & FLAG_BLACK_IS_TRANSPARENT:
            words = array.array("I")
            words.frombytes(raw)
            exact = sum(1 for w in words if w & 0xFFFFFF00 == 0) if sys.byteorder == "little" else 0
        img["near_minus_exact"] = near - exact
        pos = aligned + size
    aligned = (pos + 3) & ~3
    names = {}
    if aligned < len(data):
        tail = data[aligned:]
        if tail[:8] != b"FROGLORD":
            raise VloError("unexpected %d bytes after the pixel data" % len(tail))
        count_names = struct.unpack_from("<H", tail, 9)[0]
        p = 11
        for _ in range(count_names):
            index, length = struct.unpack_from("<HB", tail, p)
            names[index] = tail[p + 3:p + 3 + length].split(b"\0")[0].decode("ascii")
            p += 3 + length
    return images, nonzero_alpha, names


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("data_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--mwi-offset", default="0x8AE20")
    ap.add_argument("--mwi-length", default="48840")
    args = ap.parse_args()
    exe = open(os.path.join(args.data_dir, "FROGGER.EXE"), "rb").read()
    mwd = open(os.path.join(args.data_dir, "FROGPSX.MWD"), "rb").read()
    mwi_offset, mwi_length = int(args.mwi_offset, 0), int(args.mwi_length, 0)
    entries = read_mwi(exe[mwi_offset:mwi_offset + mwi_length])
    started = time.time()

    banks = {}
    for e in entries:
        if e["flags"] & FLAG_GROUP_ACCESS:
            continue
        start = e["sector"] * SECTOR_SIZE
        raw = mwd[start:start + (e["packed"] if is_compressed(e["flags"]) else e["unpacked"])]
        data = pp20_unpack(raw)[0] if is_compressed(e["flags"]) else raw
        if data[:4] == b"2GRP":
            banks[e["index"]] = ("mwd", data)
        if e["type"] == -1:
            pos = 0
            while True:
                rid, _t, size, _c = struct.unpack_from("<iiii", data, pos)
                pos += 16
                if rid == -1:
                    break
                child = data[pos:pos + size]
                if child[:4] == b"PP20":
                    child = pp20_unpack(child)[0]
                if child[:4] == b"2GRP" and rid not in banks:
                    banks[rid] = ("wad %d" % e["index"], child)
                pos += size + (-(pos + size)) % 4
        print("\r%d/%d" % (e["index"] + 1, len(entries)), end="", file=sys.stderr, flush=True)
    print(file=sys.stderr)

    file_rows, image_rows = [], []
    totals = {"images": 0, "nonzero_alpha_bytes": 0, "black_is_transparent_images": 0,
              "transparent_texels": 0, "near_black_not_exact_black_texels": 0, "in_wads": 0, "custom_names": 0}
    for rid in sorted(banks):
        where, data = banks[rid]
        name = entries[rid]["path"].split("\\")[-1]
        images, nonzero_alpha, names = parse_vlo(data)
        file_rows.append((rid, name, where, len(images), len(names)))
        totals["images"] += len(images)
        totals["nonzero_alpha_bytes"] += nonzero_alpha
        totals["in_wads"] += where != "mwd"
        totals["custom_names"] += len(names)
        for i, img in enumerate(images):
            left = (img["padded_w"] - img["w"]) // 2
            top = (img["padded_h"] - img["h"]) // 2
            unpadded = crop(img["rgba"], img["padded_w"], left, top, img["w"], img["h"])
            if img["flags"] & FLAG_BLACK_IS_TRANSPARENT:
                totals["black_is_transparent_images"] += 1
            totals["transparent_texels"] += img["rgba"][3::4].count(0)
            totals["near_black_not_exact_black_texels"] += img["near_minus_exact"]
            image_rows.append((rid, i, img["texture_id"], img["vram_x"], img["vram_y"], img["padded_w"], img["padded_h"],
                               img["w"], img["h"], img["u"], img["v"], img["flags"], img["abr"], img["page"],
                               hashlib.sha256(img["rgba"]).hexdigest(), hashlib.sha256(unpadded).hexdigest()))
    elapsed = time.time() - started

    os.makedirs(args.out_dir, exist_ok=True)
    with open(os.path.join(args.out_dir, "vlo_files.tsv"), "w", newline="\n") as f:
        f.write("# resource_id\tname\tstored_in\timages\tcustom_names\n")
        for row in file_rows:
            f.write("\t".join(str(c) for c in row) + "\n")
    with open(os.path.join(args.out_dir, "vlo_images.tsv"), "w", newline="\n") as f:
        f.write("# resource_id\timage\ttexture_id\tvram_x\tvram_y\tpadded_width\tpadded_height\twidth\theight"
                "\tu\tv\tflags\tblend_mode\tpage\tpadded_rgba_sha256\trgba_sha256\n")
        for row in image_rows:
            f.write("\t".join(str(c) for c in row) + "\n")
    with open(os.path.join(args.out_dir, "vlo_summary.txt"), "w", newline="\n") as f:
        f.write("vlo_files=%d\n" % len(file_rows))
        for key in ("images", "black_is_transparent_images", "transparent_texels", "nonzero_alpha_bytes",
                    "near_black_not_exact_black_texels", "in_wads", "custom_names"):
            f.write("%s=%d\n" % (key, totals[key]))
    print("texture banks=%d images=%d in %.1f s" % (len(file_rows), totals["images"], elapsed))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Build the golden model (MOF) facts for a retail Frogger PC install.

An independent, standard-library-only reading of the game's model files,
written from FrogLord's Java sources (mof2/MRModel, MRBaseModelData,
mesh/MRStaticMof, MRMofPart, MRMofPartCel, MRMofPolygonBlock, MRMofPolygon,
MRMofPolygonType, animation/MRAnimatedMof, hilite/MRMofHilite,
collprim/MRCollprim, SCUtils.makeModel and FroggerFormEntry.getModel). It
shares no code with the Godot project; the Godot tests compare their own
reading with the files written here.

Every file inside a WAD whose type is 3 or 4 (FrogLord's model types) is
read. Rows describe what each file itself holds. Nothing FrogLord adds for
display is included (its extra zero vertex, its divide by 16, its flipped v).

No model data is written. Value lists are described by a "list digest":
    sha256(",".join(str(v) for v in values).encode("ascii")).hexdigest()
and "-" stands for an empty list. The lists are, per part:

  vertices     x,y,z of every vertex of the part's first partcel (signed 16 bit)
  normals      x,y,z of every normal of the part's first partcel
  bounding box x,y,z of the 8 corners of the first partcel's box
  indices      per polygon in file order: type, vertex indices, environment
               normal indices, normal indices, each in the order stored
  uvs          per textured polygon: u,v of each corner in the order stored
  image ids    per textured polygon: its image id
  colours      per polygon: red, green, blue, code

The script checks each file the way FrogLord does when loading, and refuses
to report success if a check fails: the signature, the stored length against
the bytes actually used, the flags against what the file holds, zero
run-time words, polygon types below 16, zero clut and texture page words,
zero padding, hilite and texture-animation targets that resolve, and vertex
blocks that lie inside the shared vector pool on 8-byte steps.

Usage:
    python3 tools/make_golden_mof.py <dir with FROGGER.EXE and FROGPSX.MWD> <out dir>
        [--version pc-retail-v3.0e]
"""

import argparse
import collections
import os
import struct
import sys
import time

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_golden_manifest import FLAG_GROUP_ACCESS, SECTOR_SIZE, is_compressed, pp20_unpack, read_mwi  # noqa: E402
from make_golden_exe_tables import (  # noqa: E402
    CFG_ROOT, LEVEL_CODES, THEMES, Exe, digest, java_int, name_list, parse_cfg, read_forms, read_map_book,
    read_theme_book)

TYPE_MOF, TYPE_MAPMOF = 3, 4
FLAG_ANIMATED = 1 << 3
FLAG_ANIMATED_TEXTURES = 1 << 4
FLAG_FLIPBOOK = 1 << 5
EXPECTED_ANIMATED_FLAGS = (1 << 20) | (1 << 16) | FLAG_ANIMATED
INCOMPLETE_TEST_ADDRESS, INCOMPLETE_TEST_VALUE = 0x1C, 0x40
COLLPRIM_LAST_IN_LIST = 1 << 1
FORM_FLAG_NO_MODEL = 1 << 0
FIRST_GENERAL_MODEL = 128

# MRMofPolygonType: name, vertices, environment normals, normals, textured.
POLYGON_TYPES = [
    ("F3", 3, 0, 1, False), ("F4", 4, 0, 1, False), ("FT3", 3, 0, 1, True), ("FT4", 4, 0, 1, True),
    ("G3", 3, 0, 3, False), ("G4", 4, 0, 4, False), ("GT3", 3, 0, 3, True), ("GT4", 4, 0, 4, True),
    ("E3", 3, 3, 1, False), ("E4", 4, 4, 1, False), ("LF2", 2, 0, 0, False), ("LF3", 3, 0, 0, False),
    ("HLF3", 3, 0, 0, False), ("HLF4", 4, 0, 0, False), ("GE3", 3, 3, 3, False), ("GE4", 4, 4, 4, False),
]
FT4 = 3


class MofError(Exception):
    pass


def list_digest(values):
    return digest(values) if values else "-"


class Cursor:
    """A little-endian reader that remembers how far it has read."""

    def __init__(self, data):
        self.data = data
        self.pos = 0

    def take(self, fmt):
        size = struct.calcsize(fmt)
        if self.pos + size > len(self.data):
            raise MofError("read of %d bytes at %d runs past the end (%d)" % (size, self.pos, len(self.data)))
        values = struct.unpack_from(fmt, self.data, self.pos)
        self.pos += size
        return values

    def zero(self, count, what):
        if any(self.take("<%dB" % count)):
            raise MofError("%s is not zero at %d" % (what, self.pos - count))

    def align_zero(self, step, what):
        self.zero((-self.pos) % step, what)


def read_vectors(data, pointer, count, pool_start, pool_end, what):
    if count == 0:
        return []
    if pointer < pool_start or pointer + 8 * count > pool_end:
        raise MofError("%s at %d (%d vectors) is outside the vector pool %d..%d" % (what, pointer, count, pool_start, pool_end))
    if (pointer - pool_start) % 8:
        raise MofError("%s at %d is not on an 8-byte step of the vector pool" % (what, pointer))
    out = []
    for i in range(count):
        x, y, z, _pad = struct.unpack_from("<hhhh", data, pointer + 8 * i)
        out.extend((x, y, z))
    return out


def read_polygon(cur, type_id):
    _name, vertices, env_normals, normals, textured = POLYGON_TYPES[type_id]
    poly = {"type": type_id, "vertices": list(cur.take("<%dH" % vertices)),
            "env_normals": list(cur.take("<%dH" % env_normals)) if env_normals else [],
            "normals": list(cur.take("<%dH" % normals)) if normals else [], "uvs": [], "image": -1}
    if textured:
        if type_id == FT4:
            poly["image"] = cur.take("<h")[0]
        poly["uvs"].extend(cur.take("<BB"))
        if cur.take("<h")[0] != 0:
            raise MofError("polygon clut word is not zero at %d" % (cur.pos - 2))
        poly["uvs"].extend(cur.take("<BB"))
        if cur.take("<h")[0] != 0:
            raise MofError("polygon texture page word is not zero at %d" % (cur.pos - 2))
        for _ in range(vertices - 2):
            poly["uvs"].extend(cur.take("<BB"))
        if type_id != FT4:
            poly["image"] = cur.take("<h")[0]
    cur.align_zero(4, "polygon padding")
    poly["colour"] = list(cur.take("<4B"))
    return poly


def read_part_body(data, header, incomplete, pool_start, warnings, label):
    part = dict(header)
    part.update({"partcel_list": [], "hilite_list": [], "collprims": 0, "matrices": 0, "anim_targets": 0,
                 "anims": 0, "anim_image_ids": [], "flipbook_actions": 0, "polygon_list": [], "bbox": [],
                 "boxes": 0, "vertex_values": [], "normal_values": []})
    sections_after = [p for p in (header["anim_ptr"], header["flipbook_ptr"], header["prim_ptr"])]

    if not incomplete and header["partcels"] > 0:
        cur = Cursor(data)
        cur.pos = header["partcel_ptr"]
        boxes = {}
        for i in range(header["partcels"]):
            vertex_ptr, normal_ptr, box_ptr, unused = cur.take("<4I")
            if unused:
                raise MofError("%s partcel %d: unused word is not zero" % (label, i))
            cel = {"vertices": read_vectors(data, vertex_ptr, header["vertices"], pool_start, header["pool_end"], "%s partcel %d vertices" % (label, i)),
                   "normals": read_vectors(data, normal_ptr, header["normals"], pool_start, header["pool_end"], "%s partcel %d normals" % (label, i)),
                   "box_ptr": box_ptr}
            part["partcel_list"].append(cel)
        for cel in part["partcel_list"]:
            ptr = cel["box_ptr"]
            if ptr == 0:
                cel["box"] = []
                continue
            if ptr not in boxes:
                if cur.pos != ptr:
                    warnings.append("%s: bounding box at %d, expected at %d" % (label, ptr, cur.pos))
                    cur.pos = ptr
                box = []
                for _ in range(8):
                    x, y, z, _pad = cur.take("<hhhh")
                    box.extend((x, y, z))
                boxes[ptr] = box
            cel["box"] = boxes[ptr]
        part["boxes"] = len(boxes)
        part["vertex_values"] = part["partcel_list"][0]["vertices"]
        part["normal_values"] = part["partcel_list"][0]["normals"]
        part["bbox"] = part["partcel_list"][0]["box"]

    if not incomplete and header["hilites"] > 0:
        cur = Cursor(data)
        cur.pos = header["hilite_ptr"]
        for i in range(header["hilites"]):
            hilite_type, attach, index, run0, run1 = cur.take("<BBHII")
            if run0 or run1:
                raise MofError("%s hilite %d: run-time words are not zero" % (label, i))
            if attach not in (1, 2):
                raise MofError("%s hilite %d: attach type %d" % (label, i, attach))
            part["hilite_list"].append((hilite_type, attach, index))

    if not incomplete and header["collprim_ptr"] > 0:
        cur = Cursor(data)
        cur.pos = header["collprim_ptr"]
        while True:
            kind, flags, run0, run1 = cur.take("<HHII")
            if run0 or run1:
                raise MofError("%s collision primitive: run-time words are not zero" % label)
            if kind > 4:
                raise MofError("%s collision primitive: type %d" % (label, kind))
            cur.take("<hhhh i HHHH i")
            part["collprims"] += 1
            if flags & COLLPRIM_LAST_IN_LIST:
                break

    if not incomplete and header["matrix_ptr"] > 0:
        after = [p for p in sections_after if p > header["matrix_ptr"]]
        if not after:
            raise MofError("%s: no section after the matrices" % label)
        span = min(after) - header["matrix_ptr"]
        if span % 32:
            raise MofError("%s: matrix block of %d bytes" % (label, span))
        part["matrices"] = span // 32

    anim_lists = {}
    targets = []
    if not incomplete and header["anim_ptr"] > 0:
        after = [p for p in (header["flipbook_ptr"], header["prim_ptr"]) if p > header["anim_ptr"]]
        if not after:
            raise MofError("%s: no section after the texture animations" % label)
        end = min(after)
        cur = Cursor(data)
        cur.pos = header["anim_ptr"]
        count = cur.take("<i")[0]
        for i in range(count):
            poly_type, poly_index, run0, list_ptr = cur.take("<iiIi")
            if run0:
                raise MofError("%s texture animation target %d: run-time word is not zero" % (label, i))
            targets.append((poly_type, poly_index, list_ptr))
        while end > cur.pos:
            start = cur.pos
            entries = cur.take("<i")[0]
            frames = []
            for _ in range(entries):
                frames.append(cur.take("<hH"))
            anim_lists[start] = frames
        if cur.pos != end:
            raise MofError("%s: texture animations end at %d, next section at %d" % (label, cur.pos, end))
        for i, (_t, _i, list_ptr) in enumerate(targets):
            if list_ptr not in anim_lists:
                raise MofError("%s texture animation target %d: no animation at %d" % (label, i, list_ptr))
        part["anim_targets"] = len(targets)
        part["anims"] = len(anim_lists)
        for start in sorted(anim_lists):
            part["anim_image_ids"].extend(image for image, _duration in anim_lists[start])

    if not incomplete and header["flipbook_ptr"] > 0:
        cur = Cursor(data)
        cur.pos = header["flipbook_ptr"]
        flags, actions = cur.take("<HH")
        if flags:
            raise MofError("%s: flipbook flags %d" % (label, flags))
        cur.take("<%dH" % (2 * actions))
        part["flipbook_actions"] = actions

    end = header["prim_ptr"]
    if header["polygons"] > 0 or header["prim_ptr"] > 0:
        cur = Cursor(data)
        cur.pos = header["prim_ptr"]
        left = header["polygons"]
        while left > 0:
            type_id, count = cur.take("<HH")
            if type_id >= len(POLYGON_TYPES):
                raise MofError("%s: polygon type %d" % (label, type_id))
            for _ in range(count):
                part["polygon_list"].append(read_polygon(cur, type_id))
            left -= count
        if left < 0:
            raise MofError("%s: polygon blocks hold %d more polygons than the part says" % (label, -left))
        end = cur.pos
    part["end"] = end

    if not incomplete:
        for i, (poly_type, poly_index, _ptr) in enumerate(targets):
            if not 0 <= poly_index < len(part["polygon_list"]):
                raise MofError("%s texture animation target %d: no polygon %d" % (label, i, poly_index))
            if part["polygon_list"][poly_index]["type"] != poly_type:
                raise MofError("%s texture animation target %d: polygon %d is not of type %d" % (label, i, poly_index, poly_type))
        for i, (_type, attach, index) in enumerate(part["hilite_list"]):
            limit = header["vertices"] if attach == 1 else len(part["polygon_list"])
            if index >= limit:
                raise MofError("%s hilite %d: index %d out of range" % (label, i, index))
    expected_flags = 1 if part["anim_targets"] > 0 else 0
    if header["flags"] != expected_flags:
        raise MofError("%s: part flags %d, expected %d" % (label, header["flags"], expected_flags))
    return part


def parse_static(data, label, counterpart, warnings):
    """One static model. counterpart is the parsed static model an incomplete one borrows from."""
    if len(data) < 16 or data[:4] != b"\x02FOM":
        raise MofError("%s: not a static model" % label)
    length, flags, part_count = struct.unpack_from("<III", data, 4)
    incomplete = len(data) >= INCOMPLETE_TEST_ADDRESS + 4 and \
        struct.unpack_from("<I", data, INCOMPLETE_TEST_ADDRESS)[0] == INCOMPLETE_TEST_VALUE
    headers = []
    cur = Cursor(data)
    cur.pos = 16
    for i in range(part_count):
        (part_flags, partcels, vertices, normals, polygons, hilites, partcel_ptr, prim_ptr, hilite_ptr, run_time,
         collprim_ptr, matrix_ptr, anim_ptr, flipbook_ptr) = cur.take("<hHHHHH8I")
        if run_time:
            raise MofError("%s part %d: run-time word is not zero" % (label, i))
        headers.append({"flags": part_flags, "partcels": partcels, "vertices": vertices, "normals": normals,
                        "polygons": polygons, "hilites": hilites, "partcel_ptr": partcel_ptr, "prim_ptr": prim_ptr,
                        "hilite_ptr": hilite_ptr, "collprim_ptr": collprim_ptr, "matrix_ptr": matrix_ptr,
                        "anim_ptr": anim_ptr, "flipbook_ptr": flipbook_ptr})
    unknown = cur.take("<I")[0]
    pool_start = cur.pos
    pool_end = headers[0]["partcel_ptr"] if headers else pool_start
    parts = []
    for i, header in enumerate(headers):
        header["pool_end"] = pool_end
        parts.append(read_part_body(data, header, incomplete, pool_start, warnings, "%s part %d" % (label, i)))
    end = parts[-1]["end"] if parts else cur.pos
    if end != length:
        raise MofError("%s: stored length %d, but the last polygon ends at %d" % (label, length, end))
    if length != len(data):
        raise MofError("%s: stored length %d, but %d bytes are present" % (label, length, len(data)))

    flag_parts = parts
    if incomplete:
        if counterpart is None:
            raise MofError("%s: incomplete, and no complete model to borrow from" % label)
        if len(counterpart["parts"]) != len(parts):
            raise MofError("%s: incomplete with %d parts, its counterpart has %d" % (label, len(parts), len(counterpart["parts"])))
        for mine, theirs in zip(parts, counterpart["parts"]):
            for key in ("partcels", "vertices", "normals", "hilites"):
                if mine[key] != theirs[key]:
                    warnings.append("%s: incomplete part has %d %s, its counterpart %d" % (label, mine[key], key, theirs[key]))
        flag_parts = counterpart["parts"]
    expected = 0
    if any(p["anim_targets"] > 0 for p in parts):
        expected |= FLAG_ANIMATED_TEXTURES
    if any(p["flipbook_actions"] > 0 for p in flag_parts):
        expected |= FLAG_FLIPBOOK
    if flags != expected:
        raise MofError("%s: flags 0x%X, expected 0x%X" % (label, flags, expected))
    return {"length": length, "flags": flags, "incomplete": incomplete, "unknown": unknown, "parts": parts}


def parse_model(data, label, counterpart, warnings):
    """counterpart: the parsed model an incomplete model borrows from, or None."""
    model = {"kind": "dummy", "signature": data[:4].hex(), "flags": 0, "incomplete": False, "statics": [],
             "model_sets": 0, "size": len(data)}
    if data[:4] == b"DUMY":
        return model
    if len(data) < 12:
        raise MofError("%s: %d bytes is too short for a model" % (label, len(data)))
    length, flags = struct.unpack_from("<II", data, 4)
    model["flags"] = flags
    if flags & FLAG_ANIMATED:
        sig = data[:4]
        if not (sig[0] in (0, 0x30, 0x31) and 0x30 <= sig[1] <= 0x39 and sig[2:4] == b"ax"):
            raise MofError("%s: animated flag set, but the signature is %r" % (label, sig))
        if flags != EXPECTED_ANIMATED_FLAGS:
            raise MofError("%s: animated model flags 0x%X" % (label, flags))
        model["kind"] = "animated"
        model_sets, static_count, sets_ptr, common_ptr, table_ptr = struct.unpack_from("<HHIII", data, 12)
        model["model_sets"] = model_sets
        if sets_ptr != 28:
            raise MofError("%s: model sets at %d, expected right after the header" % (label, sets_ptr))
        pointers = list(struct.unpack_from("<%dI" % static_count, data, table_ptr))
        if table_ptr + 4 * static_count != length or length != len(data):
            raise MofError("%s: stored length %d, table ends at %d, %d bytes present" % (label, length, table_ptr + 4 * static_count, len(data)))
        if not common_ptr < pointers[0]:
            raise MofError("%s: the shared animation data does not come before the models" % label)
        for i, start in enumerate(pointers):
            end = pointers[i + 1] if i + 1 < static_count else table_ptr
            other = counterpart["statics"][i] if counterpart is not None and i < len(counterpart["statics"]) else None
            static = parse_static(data[start:end], "%s model %d" % (label, i), other, warnings)
            # The reference engine takes the extent from the model's own length; parse_static
            # has just checked that this equals FrogLord's pointer-to-pointer extent.
            model["statics"].append(static)
    else:
        model["kind"] = "static"
        other = counterpart["statics"][0] if counterpart is not None and counterpart["statics"] else None
        model["statics"].append(parse_static(data, label, other, warnings))
    model["incomplete"] = any(s["incomplete"] for s in model["statics"])
    return model


def load_archive(data_dir, mwi_offset, mwi_length):
    exe = open(os.path.join(data_dir, "FROGGER.EXE"), "rb").read()
    mwd = open(os.path.join(data_dir, "FROGPSX.MWD"), "rb").read()
    entries = read_mwi(exe[mwi_offset:mwi_offset + mwi_length])
    wads = {}     # WAD resource id -> [(resource id, type id)]
    files = {}    # resource id -> bytes of the first copy
    for e in entries:
        if e["type"] != -1 or (e["flags"] & FLAG_GROUP_ACCESS):
            continue
        start = e["sector"] * SECTOR_SIZE
        raw = mwd[start:start + (e["packed"] if is_compressed(e["flags"]) else e["unpacked"])]
        data = pp20_unpack(raw)[0] if is_compressed(e["flags"]) else raw
        children = []
        pos = 0
        while True:
            rid, type_id, size, _count = struct.unpack_from("<iiii", data, pos)
            pos += 16
            if rid == -1:
                break
            child = data[pos:pos + size]
            if child[:4] == b"PP20" and len(child) > 11:
                child = pp20_unpack(child)[0]
            children.append((rid, type_id))
            files.setdefault(rid, child)
            pos += size + (-(pos + size)) % 4
        wads[e["index"]] = children
    return exe, entries, wads, files


def file_name(entries, rid):
    """MWIResourceEntry.getDisplayName: the path without its folders, whichever slash they use."""
    if not 0 <= rid < len(entries):
        return ""
    return entries[rid]["path"].split("\\")[-1].split("/")[-1]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("data_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--version", default="pc-retail-v3.0e")
    args = ap.parse_args()
    started = time.time()

    ver = parse_cfg(os.path.join(CFG_ROOT, "versions", args.version + ".cfg"))
    cfg = {k: java_int(v.strip()) for k, v in ver.values.items()
           if k in ("mwiOffset", "mwiLength", "mapBook", "themeBook", "ramOffset")}
    exe_bytes, entries, wads, files = load_archive(args.data_dir, cfg["mwiOffset"], cfg["mwiLength"])

    problems, warnings = [], []
    model_ids = sorted({rid for children in wads.values() for rid, type_id in children if type_id in (TYPE_MOF, TYPE_MAPMOF)})
    models = {}
    counterparts = {}
    for rid in model_ids:
        label = "%d %s" % (rid, file_name(entries, rid))
        data = files[rid]
        # SCUtils.makeModel: the nearest earlier model that is not incomplete.
        previous = -1
        for other in range(rid - 1, -1, -1):
            if other in models and not models[other]["incomplete"]:
                previous = other
                break
        try:
            model = parse_model(data, label, models.get(previous), warnings)
        except (MofError, struct.error) as err:
            problems.append("%s: %s" % (label, err))
            continue
        models[rid] = model
        counterparts[rid] = previous if model["incomplete"] else -1

    model_rows, part_rows = [], []
    totals = collections.Counter()
    type_totals = [0] * len(POLYGON_TYPES)
    for rid in sorted(models):
        m = models[rid]
        parts = [p for s in m["statics"] for p in s["parts"]]
        polygons = [poly for p in parts for poly in p["polygon_list"]]
        images = sorted({poly["image"] for poly in polygons if POLYGON_TYPES[poly["type"]][4]})
        textured = sum(1 for poly in polygons if POLYGON_TYPES[poly["type"]][4])
        model_rows.append((
            rid, file_name(entries, rid), entries[rid]["type"], m["size"], m["kind"], m["signature"], "0x%X" % m["flags"],
            int(m["incomplete"]), counterparts[rid], len(m["statics"]), m["model_sets"], len(parts),
            sum(p["partcels"] for p in parts), sum(p["vertices"] for p in parts), sum(p["normals"] for p in parts),
            len(polygons), textured, sum(p["hilites"] for p in parts), sum(p["collprims"] for p in parts),
            sum(p["matrices"] for p in parts), sum(p["flipbook_actions"] for p in parts),
            sum(p["anim_targets"] for p in parts), sum(p["anims"] for p in parts), len(images), list_digest(images)))
        totals[m["kind"]] += 1
        totals["incomplete"] += int(m["incomplete"])
        totals["static_models"] += len(m["statics"])
        totals["parts"] += len(parts)
        totals["partcels"] += sum(p["partcels"] for p in parts)
        totals["vertices"] += sum(p["vertices"] for p in parts)
        totals["normals"] += sum(p["normals"] for p in parts)
        totals["polygons"] += len(polygons)
        totals["textured_polygons"] += textured
        totals["hilites"] += sum(p["hilites"] for p in parts)
        totals["collprims"] += sum(p["collprims"] for p in parts)
        totals["matrices"] += sum(p["matrices"] for p in parts)
        totals["flipbook_actions"] += sum(p["flipbook_actions"] for p in parts)
        totals["texture_animation_targets"] += sum(p["anim_targets"] for p in parts)
        totals["models_with_textures"] += int(textured > 0)
        for static_index, s in enumerate(m["statics"]):
            totals["static_models_with_flipbook"] += int(bool(s["flags"] & FLAG_FLIPBOOK))
            totals["static_models_with_texture_animation"] += int(bool(s["flags"] & FLAG_ANIMATED_TEXTURES))
            for part_index, p in enumerate(s["parts"]):
                by_type = [0] * len(POLYGON_TYPES)
                indices, uvs, image_ids, colours = [], [], [], []
                for poly in p["polygon_list"]:
                    by_type[poly["type"]] += 1
                    type_totals[poly["type"]] += 1
                    indices.append(poly["type"])
                    indices.extend(poly["vertices"])
                    indices.extend(poly["env_normals"])
                    indices.extend(poly["normals"])
                    if POLYGON_TYPES[poly["type"]][4]:
                        uvs.extend(poly["uvs"])
                        image_ids.append(poly["image"])
                    colours.extend(poly["colour"])
                hilites = [v for h in p["hilite_list"] for v in h]
                part_rows.append((
                    rid, static_index, part_index, p["flags"], p["partcels"], p["vertices"], p["normals"], p["polygons"],
                    p["hilites"], p["collprims"], p["matrices"], p["flipbook_actions"], p["anim_targets"], p["anims"],
                    p["boxes"], ",".join(str(c) for c in by_type), list_digest(p["vertex_values"]),
                    list_digest(p["normal_values"]), list_digest(p["bbox"]), list_digest(indices), list_digest(uvs),
                    list_digest(image_ids), list_digest(colours), list_digest(hilites),
                    list_digest(p["anim_image_ids"])))

    child_kinds = collections.Counter()
    for children in wads.values():
        for rid, _type in children:
            if rid in models:
                child_kinds[models[rid]["kind"]] += 1

    # Which model each form of each level uses (FroggerFormEntry.getModel).
    exe = Exe(exe_bytes, cfg["ramOffset"])
    _names, form_sections, _cfg = name_list("forms", ver.values.get("formList", "1997-09-12-psx-build57"))
    map_rows, _end = read_map_book(exe, cfg["mapBook"], cfg["themeBook"])
    themes = read_theme_book(exe, cfg["themeBook"])
    forms = read_forms(exe, themes, form_sections, problems)
    general = themes[0]

    def lookup(wad_id, position):
        children = wads.get(wad_id, [])
        if not 0 <= position < len(children):
            return -1, "none"
        rid = children[position][0]
        return rid, models[rid]["kind"] if rid in models else "other"

    form_rows = []

    def add_forms(level, code, theme, multiplayer, high_wad, low_wad):
        general_high = general["high_mp_wad"] if multiplayer else general["high_wad"]
        general_low = general["low_mp_wad"] if multiplayer else general["low_wad"]
        for f in forms.get(theme, []):
            uses_general = theme == 0 or f["id"] >= FIRST_GENERAL_MODEL
            position = f["id"] - FIRST_GENERAL_MODEL if uses_general else f["id"]
            high = general_high if uses_general else high_wad
            low = general_low if uses_general else low_wad
            high_rid, high_kind = lookup(high, position)
            low_rid, low_kind = lookup(low, position)
            section = form_sections.get(THEMES[theme], [])
            form_rows.append((level, code, THEMES[theme], f["local"], section[f["local"]] if f["local"] < len(section) else "",
                              f["id"], int(bool(f["flags"] & FORM_FLAG_NO_MODEL)), int(uses_general), position,
                              high, high_rid, high_kind, low, low_rid, low_kind))

    add_forms(-1, "GENERAL", 0, False, 0, 0)
    add_forms(-1, "GENERAL_MULTIPLAYER", 0, True, 0, 0)
    for level, row in enumerate(map_rows):
        if (row["high_remap"] == 0 and row["low_remap"] == 0) or row["high_map"] <= 0:
            continue
        add_forms(level, LEVEL_CODES[level], 1 + level // 6, level % 6 == 5, row["high_wad"], row["low_wad"])

    elapsed = time.time() - started
    os.makedirs(args.out_dir, exist_ok=True)

    def write(name, header, rows):
        with open(os.path.join(args.out_dir, name), "w", newline="\n") as f:
            f.write("# " + "\t".join(header) + "\n")
            for row in rows:
                f.write("\t".join(str(c) for c in row) + "\n")

    write("mof_models.tsv", ["resource_id", "name", "type_id", "size", "kind", "signature", "flags", "incomplete",
                             "counterpart", "static_models", "model_sets", "parts", "partcels", "vertices", "normals",
                             "polygons", "textured_polygons", "hilites", "collprims", "matrices", "flipbook_actions",
                             "texture_animation_targets", "texture_animations", "distinct_image_ids",
                             "distinct_image_ids_sha256"], model_rows)
    write("mof_parts.tsv", ["resource_id", "static_model", "part", "flags", "partcels", "vertices", "normals",
                            "polygons", "hilites", "collprims", "matrices", "flipbook_actions",
                            "texture_animation_targets", "texture_animations", "bounding_boxes", "polygons_by_type",
                            "vertices_sha256", "normals_sha256", "bounding_box_sha256", "indices_sha256", "uvs_sha256",
                            "image_ids_sha256", "colours_sha256", "hilites_sha256",
                            "texture_animation_image_ids_sha256"], part_rows)
    write("mof_forms.tsv", ["level", "code", "theme", "form", "form_name", "model_id", "no_model", "general_wad",
                            "position", "high_wad", "high_resource", "high_kind", "low_wad", "low_resource",
                            "low_kind"], form_rows)
    with open(os.path.join(args.out_dir, "mof_summary.txt"), "w", newline="\n") as f:
        f.write("models=%d\n" % len(models))
        for key in ("dummy", "static", "animated", "incomplete", "static_models", "static_models_with_flipbook",
                    "static_models_with_texture_animation", "models_with_textures", "parts", "partcels", "vertices",
                    "normals", "polygons", "textured_polygons", "hilites", "collprims", "matrices", "flipbook_actions",
                    "texture_animation_targets"):
            f.write("%s=%d\n" % (key, totals[key]))
        for i, (name, _v, _e, _n, _t) in enumerate(POLYGON_TYPES):
            f.write("polygons_of_type[%s]=%d\n" % (name, type_totals[i]))
        for kind in ("dummy", "static", "animated"):
            f.write("wad_children_of_kind[%s]=%d\n" % (kind, child_kinds[kind]))
        f.write("form_rows=%d\n" % len(form_rows))

    print("models=%d (dummy %d, static %d, animated %d, incomplete %d) parts=%d polygons=%d in %.1f s" % (
        len(models), totals["dummy"], totals["static"], totals["animated"], totals["incomplete"], totals["parts"],
        totals["polygons"], elapsed))
    print("per WAD child: dummy %d, static %d, animated %d" % (child_kinds["dummy"], child_kinds["static"], child_kinds["animated"]))
    print("static models, counting those inside animated files: %d; with a textured polygon: see models_with_textures=%d"
          % (totals["static_models"], totals["models_with_textures"]))
    for w in warnings[:40]:
        print("note: " + w)
    if len(warnings) > 40:
        print("note: ... and %d more" % (len(warnings) - 40))
    if problems:
        print("CHECK FAILURES:\n  " + "\n  ".join(problems[:60]), file=sys.stderr)
        return 1
    print("checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

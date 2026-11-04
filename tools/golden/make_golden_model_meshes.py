#!/usr/bin/env python3
"""Golden facts for the triangle meshes built from every model part.

Each part of every model file (MOF) is turned into surfaces the way the
game's mesh builder does: one surface per resolved texture id, one for
untextured polygons (and textured ones whose image id is in no bank), and
one per polygon carrying a texture animation. Every corner is its own
vertex; a triangle keeps its stored corners, a quad gives corners (0, 1, 3)
and (1, 2, 3). Positions are the rest pose (partcel 0), borrowed from the
counterpart model when the model is incomplete. The digests and the reason
they ignore surface order are in tests/golden/specs/imported-assets.md.

Independent of the Godot project: models are read by make_golden_mof.py's
FrogLord parser, texture headers directly from the 2GRP banks.

Usage:
    python3 tools/golden/make_golden_model_meshes.py [--data-dir DIR] [--output FILE] [--check]
"""

import collections
import os
import struct
import sys
import time

sys.dont_write_bytecode = True
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden.imported_assets_common import Archive, arguments, finish, list_digest, multiset_digest, tsv
from tools.golden.make_golden_mof import FLAG_ANIMATED, POLYGON_TYPES, TYPE_MAPMOF, TYPE_MOF, parse_model

PART_HEADER = struct.Struct("<hHHHHH8I")


def texture_headers(archive):
    """{texture id: (width, height, padded width, padded height)} over every bank; fails if banks disagree."""
    found = {}
    for _rid, data in archive.texture_banks():
        count = struct.unpack_from("<i", data, 4)[0]
        for i in range(count):
            _vx, _vy, pw, ph, _off, tid, _tp, _flags, _clut, _u, _v, w, h = struct.unpack_from("<hhhhihHHhBBBB", data, 12 + 24 * i)
            value = (w or 256, h or 256, pw, ph)
            if found.setdefault(tid, value) != value:
                raise ValueError("texture %d has different sizes in different banks" % tid)
    return found


def static_slices(data):
    """The bytes of each static model in a model file, in stored order."""
    if data[:4] == b"DUMY":
        return []
    flags = struct.unpack_from("<I", data, 8)[0]
    if not flags & FLAG_ANIMATED:
        return [data]
    count, table = struct.unpack_from("<H", data, 14)[0], struct.unpack_from("<I", data, 24)[0]
    pointers = list(struct.unpack_from("<%dI" % count, data, table))
    return [data[p:(pointers[i + 1] if i + 1 < count else table)] for i, p in enumerate(pointers)]


def own_targets(data, part):
    """(polygon type, polygon index) of each stored texture-animation target, valid or None."""
    if part["anim_ptr"] <= 0:
        return []
    count = struct.unpack_from("<i", data, part["anim_ptr"])[0]
    result = []
    for i in range(count):
        poly_type, poly_index, _run, _list = struct.unpack_from("<iiIi", data, part["anim_ptr"] + 4 + 16 * i)
        polys = part["polygon_list"]
        ok = 0 <= poly_index < len(polys) and polys[poly_index]["type"] == poly_type and POLYGON_TYPES[poly_type][4]
        result.append((poly_type, poly_index) if ok else None)
    return result


def borrowed_targets(targets, polygons):
    """MofPart.borrow_from: the counterpart's targets, checked against this part's own polygons."""
    result = []
    for target in targets:
        ok = target is not None and 0 <= target[1] < len(polygons) and polygons[target[1]]["type"] == target[0]
        result.append(target if ok else None)
    return result


def build_part(polygons, cels, targets, images):
    """(surface count, triangles, positions digest, colours digest, uvs digest, unresolved textured polygons)."""
    cel = cels[0]["vertices"] if cels else None
    surfaces = collections.OrderedDict()
    unresolved = 0
    if cel is not None:
        for index, poly in enumerate(polygons):
            count = len(poly["vertices"])
            if count < 3:
                continue
            textured = POLYGON_TYPES[poly["type"]][4]
            image = images.get(poly["image"]) if textured else None
            if textured and image is None:
                unresolved += 1
            target = next((t for t, value in enumerate(targets) if value == (poly["type"], index)), -1)
            key = ("animated", target) if target >= 0 else ("plain",) if image is None else ("texture", poly["image"])
            surface = surfaces.setdefault(key, {"positions": [], "colours": [], "uvs": [], "textured": image is not None})
            r, g, b, _code = poly["colour"]
            for corner in ((0, 1, 3, 1, 2, 3) if count == 4 else (0, 1, 2)):
                at = poly["vertices"][corner] * 3
                surface["positions"].extend(cel[at:at + 3] if at + 2 < len(cel) else (0, 0, 0))
                surface["colours"].extend((r, g, b, 255))
                if image is not None:
                    w, h, pw, ph = image
                    u, v = poly["uvs"][corner * 2], poly["uvs"][corner * 2 + 1]
                    surface["uvs"].extend(((pw - w) // 2 + u * w // 255, (ph - h) // 2 + v * h // 255))
    triangles = sum(len(s["positions"]) // 9 for s in surfaces.values())
    return (len(surfaces), triangles,
            multiset_digest([list_digest(s["positions"]) for s in surfaces.values()]),
            multiset_digest([list_digest(s["colours"]) for s in surfaces.values()]),
            multiset_digest([list_digest(s["uvs"]) for s in surfaces.values() if s["textured"]]),
            unresolved)


def main():
    args = arguments(__doc__, "model_meshes.tsv")
    started = time.time()
    archive = Archive(args.data_dir)
    images = texture_headers(archive)
    children = archive.wad_children()
    model_ids = sorted({rid for kids in children.values() for rid, type_id in kids if type_id in (TYPE_MOF, TYPE_MAPMOF)})
    models, warnings = {}, []
    for rid in model_ids:
        previous = next((o for o in range(rid - 1, -1, -1) if o in models and not models[o]["incomplete"]), -1)
        model = parse_model(archive.resource(rid), "%d %s" % (rid, archive.name(rid)), models.get(previous), warnings)
        model["counterpart"] = previous if model["incomplete"] else -1
        model["slices"] = static_slices(archive.resource(rid))
        for s, data in zip(model["statics"], model["slices"]):
            for part in s["parts"]:
                part["targets"] = own_targets(data, part) if not s["incomplete"] else []
        models[rid] = model

    rows = []
    for rid in model_ids:
        model = models[rid]
        for static_index, s in enumerate(model["statics"]):
            for part_index, part in enumerate(s["parts"]):
                cels, targets = part["partcel_list"], part["targets"]
                if s["incomplete"]:
                    other = models[model["counterpart"]]
                    source = other["statics"][static_index] if model["kind"] == "animated" else other["statics"][0]
                    theirs = source["parts"][part_index]
                    cels = theirs["partcel_list"]
                    targets = borrowed_targets(theirs["targets"], part["polygon_list"])
                surfaces, triangles, positions, colours, uvs, unresolved = build_part(part["polygon_list"], cels, targets, images)
                rows.append((rid, archive.name(rid), static_index, part_index, surfaces, triangles, len(cels),
                             unresolved, positions, colours, uvs))
    text = tsv(["resource_id", "name", "static_model", "part", "surfaces", "triangles", "cels",
                "unresolved_textured_polygons", "positions_sha256", "colours_sha256", "uvs_sha256"], rows)
    finish(args, text, "%d models, %d parts, %.1f s" % (len(models), len(rows), time.time() - started))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Independent FrogLord FORM facts and frozen CollideFrog contact-gate traces."""
import argparse
import csv
import hashlib
import json
import os
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_golden_exe_tables as exe_tables
import make_golden_paths as paths
import make_golden_mof as mof


def s16(v):
    v &= 0xffff
    return v - 0x10000 if v & 0x8000 else v


def s32(v):
    v &= 0xffffffff
    return v - 0x100000000 if v & 0x80000000 else v


def read(data, at, fmt):
    if at < 0 or at + struct.calcsize(fmt) > len(data):
        raise ValueError("FORM read exceeds map")
    return struct.unpack_from(fmt, data, at)[0]


def digest(values):
    return hashlib.sha256(",".join(str(x) for x in values).encode("ascii")).hexdigest() if values else "-"


def evaluate(case):
    """The pre-reaction gate in COLLIDE.C, with source integer widths."""
    distance, local = source_math(case)
    if case["entity_flags"] & 8:
        return "disabled", [0, 0, 0], [-1, -1], 0, 0
    if distance >= case["radius_squared"]:
        return "miss", [0, 0, 0], [-1, -1], 0, 0
    xofs, zofs = case["offsets"]
    nx, nz = case["dimensions"]
    if not (xofs < local[0] < xofs + (nx << 8) and
            zofs < local[2] < zofs + (nz << 8) and
            case["height"] <= local[1] <= case["max_y"]):
        return "miss", local, [-1, -1], 0, 0
    cell = [(local[0] - xofs) >> 8, (local[2] - zofs) >> 8]
    flag = case["grid_flags"][cell[1] * nx + cell[0]]
    return "contact", local, cell, case["height"], flag


def source_math(case):
    m, p = case["matrix12"], case["frog"]
    delta = [s16(p[i] - m[9 + i]) for i in range(3)]
    distance = s32(sum(v * v for v in delta))
    # TransposeMatrix then ApplyMatrix: signed32 sum, arithmetic shift once.
    local = [s32(sum(m[row * 3 + axis] * delta[row] for row in range(3))) >> 12
             for axis in range(3)]
    return distance, local


def synthetic_cases(path):
    with open(path, encoding="utf-8") as source:
        fixture = json.load(source)
    defaults = fixture["defaults"]
    cases = []
    names = set()
    for change in fixture["cases"]:
        case = dict(defaults)
        case.update(change)
        if case["name"] in names:
            raise ValueError("duplicate contact case")
        names.add(case["name"])
        if len(case["matrix12"]) != 12 or len(case["frog"]) != 3 or len(case["grid_flags"]) != case["dimensions"][0] * case["dimensions"][1]:
            raise ValueError(f"invalid fixture shape: {case['name']}")
        cases.append(case)
    return cases


def frozen_contacts(cases, oracle):
    rows = [str(len(cases))]
    for c in cases:
        rows.append(" ".join(map(str, [*c["matrix12"], *c["frog"], *c["offsets"],
            *c["dimensions"], c["height"], c["max_y"], c["radius_squared"],
            c["entity_flags"], 1, 0, 0, 1])))
    result = subprocess.run([oracle], input="\n".join(rows) + "\n", text=True,
        capture_output=True, check=True, timeout=30,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    outputs = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) == 5 and fields[0] in ("0", "1") and all(v.lstrip("-").isdigit() for v in fields):
            outputs.append(tuple(map(int, fields)))
    if len(outputs) != len(cases):
        raise ValueError(f"Frozen CollideFrog returned {len(outputs)} contacts for {len(cases)} cases: {result.stdout[:500]!r}")
    return outputs


def write_synthetic(path, cases, oracle):
    if not oracle:
        raise ValueError("--oracle is required for synthetic contact goldens")
    frozen = frozen_contacts(cases, oracle)
    columns = ("case", "status", "local_x", "local_y", "local_z", "cell_x", "cell_z", "height", "cell_flags")
    with open(path, "w", newline="", encoding="utf-8") as target:
        writer = csv.writer(target, delimiter="\t", lineterminator="\n")
        writer.writerow(columns)
        for case, observed in zip(cases, frozen):
            status, local, cell, height, flags = evaluate(case)
            expected = int(status == "contact")
            distance, raw_local = source_math(case)
            if observed != (expected, distance, *raw_local):
                raise ValueError(f"Python/frozen CollideFrog disagreement: {case['name']} expected {(expected, distance, *raw_local)}, got {observed}")
            writer.writerow((case["name"], status, *local, *cell, height, flags))


def parse_forms(data):
    if data[:4] != b"FROG" or data[8:12] != b"2.00":
        raise ValueError("unsupported final PC map")
    packet = read(data, 84, "<I")  # FORM pointer in FROG header.
    if data[packet:packet + 4] != b"FORM":
        raise ValueError("missing FORM packet")
    count = read(data, packet + 4, "<H")
    pointers = [read(data, packet + 8 + i * 4, "<I") for i in range(count)]
    if len(set(pointers)) != count:
        raise ValueError("duplicate FORM pointers")
    forms = []
    for index, at in enumerate(pointers):
        if at < packet + 8 + count * 4:
            raise ValueError("FORM overlaps pointer table")
        n, max_y, nx, nz, xofs, zofs = struct.unpack_from("<Hhhhhh", data, at)
        if n > 1024 or (n > 0 and (nx < 0 or nz < 0 or nx * nz > 65536)):
            raise ValueError("invalid FORM dimensions/count")
        items = []
        for j in range(n):
            fd = read(data, at + 12 + j * 4, "<I")
            kind, height, flags_ptr, heights_ptr = struct.unpack_from("<HhII", data, fd)
            grid_flags = [read(data, flags_ptr + k * 2, "<H") for k in range(nx * nz)]
            items.append((fd, kind, height, flags_ptr, heights_ptr, grid_flags))
        forms.append((index, at, n, max_y, nx, nz, xofs, zofs, items))
    return forms


def retail_maps(data_dir, version):
    cfg = exe_tables.parse_cfg(os.path.join(exe_tables.CFG_ROOT, "versions", version + ".cfg"))
    _, entries, _, files = paths.archive.load_archive(data_dir,
        exe_tables.java_int(cfg.values["mwiOffset"]), exe_tables.java_int(cfg.values["mwiLength"]))
    with open(os.path.join(data_dir, "FROGPSX.MWD"), "rb") as source:
        mwd = source.read()
    for entry in entries:
        if entry["type"] != 0 or entry["flags"] & paths.archive.FLAG_GROUP_ACCESS:
            continue
        start = entry["sector"] * paths.archive.SECTOR_SIZE
        compressed = paths.archive.is_compressed(entry["flags"])
        raw = mwd[start:start + (entry["packed"] if compressed else entry["unpacked"])]
        files[entry["index"]] = paths.archive.pp20_unpack(raw)[0] if compressed else raw
    for resource_id, data in sorted(files.items()):
        name = paths.archive.file_name(entries, resource_id)
        if name.upper().endswith(".MAP") and data[:4] == b"FROG":
            yield resource_id, name, data


def write_retail_forms(path, data_dir, version):
    with open(path, "w", newline="", encoding="utf-8") as target:
        writer = csv.writer(target, delimiter="\t", lineterminator="\n")
        writer.writerow(("resource_id", "map", "form_count", "form_data_count", "form_digest", "form_data_digest", "flags_digest"))
        for resource_id, name, data in retail_maps(data_dir, version):
            forms = parse_forms(data)
            form_values, data_values, flags_values = [], [], []
            for index, at, count, max_y, nx, nz, xofs, zofs, items in forms:
                form_values.extend((index, at, count, max_y, nx, nz, xofs, zofs))
                for j, (fd, kind, height, flags_ptr, heights_ptr, flags) in enumerate(items):
                    data_values.extend((index, j, fd, kind, height, flags_ptr, heights_ptr))
                    flags_values.extend(flags)
            writer.writerow((resource_id, name, len(forms), len(data_values) // 7,
                             digest(form_values), digest(data_values), digest(flags_values)))


def write_retail_contacts(path, data_dir, version):
    """Six ORG1 small-log instances with independent EXE/MOF/map setup facts."""
    cfg = exe_tables.parse_cfg(os.path.join(exe_tables.CFG_ROOT, "versions", version + ".cfg"))
    with open(os.path.join(data_dir, "FROGGER.EXE"), "rb") as source:
        image = exe_tables.Exe(source.read(), exe_tables.java_int(cfg.values["ramOffset"]))
    levels, _ = exe_tables.read_map_book(image, exe_tables.java_int(cfg.values["mapBook"]),
                                         exe_tables.java_int(cfg.values["themeBook"]))
    org1 = levels[24]
    names, sections, _ = exe_tables.name_list("forms", cfg.values.get("formList", "1997-09-12-psx-build57"))
    library = exe_tables.read_forms(image,
        exe_tables.read_theme_book(image, exe_tables.java_int(cfg.values["themeBook"])), sections, [])
    book = library[5][3]
    if names[book["global"]] != "ORG_LOG_SMALL" or book["id"] != 3:
        raise ValueError("ORG1 small-log form mapping changed")
    _, entries, wads, files = mof.load_archive(data_dir,
        exe_tables.java_int(cfg.values["mwiOffset"]), exe_tables.java_int(cfg.values["mwiLength"]))
    model_rid = wads[org1["high_wad"]][book["id"]][0]
    model = mof.parse_model(files[model_rid], f"ORG1 small log {model_rid}", None, [])
    if model["kind"] != "static" or not model["statics"]:
        raise ValueError("ORG1 small-log model is not static")
    parts = model["statics"][0]["parts"]
    radius = book["radius2"]
    if radius == 0:
        for part in parts:
            if part["collprims"]:
                raise ValueError("ORG1 small-log collprims require radius implementation")
            for cel in part["partcel_list"]:
                box = cel["box"]
                for i in range(0, len(box), 3):
                    radius = max(radius, sum(v * v for v in box[i:i + 3]))
        radius = s32(radius + 100)  # MAPLOAD_MOF_RADIUS_EXTEND.
    first_box = parts[0]["partcel_list"][0]["box"]
    max_y = 32767 if book["flags"] & 32 else (256 if book["flags"] & 512 else first_box[22])
    data = next(content for rid, _name, content in retail_maps(data_dir, version)
                if rid == org1["high_map"])
    forms = parse_forms(data)
    form = forms[3]
    _, form_at, n, _stored_y, nx, nz, xofs, zofs, items = form
    if n < 1:
        raise ValueError("ORG1 small-log FORM has no grid")
    _, kind, height, _flag_ptr, _height_ptr, flags = items[0]
    if kind != 0:
        raise ValueError("ORG1 small-log height type is not GRID")
    packet = read(data, 88, "<I")  # EMTP pointer.
    if data[packet:packet + 4] != b"EMTP":
        raise ValueError("missing ORG1 EMTP")
    count = read(data, packet + 8, "<H")
    selected = []
    for index in range(count):
        at = read(data, packet + 12 + index * 4, "<I")
        grid_id, unique_id, form_id, entity_flags = struct.unpack_from("<4H", data, at)
        if grid_id == 3 and form_id == 3:
            selected.append((index, at, unique_id, entity_flags))
    if len(selected) != 6:
        raise ValueError(f"expected six ORG1 small logs, got {len(selected)}")
    with open(path, "w", newline="", encoding="utf-8") as target:
        writer = csv.writer(target, delimiter="\t", lineterminator="\n")
        writer.writerow(("resource_id", "map", "entity_index", "source_offset", "unique_id", "form_grid_id",
                         "form_id", "form_name", "entity_flags", "form_source_offset", "xnum", "znum",
                         "xofs", "zofs", "height", "max_y", "radius_squared", "flags_digest"))
        for index, at, unique_id, entity_flags in selected:
            writer.writerow((org1["high_map"], "ORG1.MAP", index, at, unique_id, 3, 3,
                             "ORG_LOG_SMALL", entity_flags, form_at, nx, nz, xofs, zofs,
                             height, max_y, radius, digest(flags)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir")
    parser.add_argument("--oracle")
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--version", default="pc-retail-v3.0e")
    args = parser.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    if args.oracle:
        cases = synthetic_cases("tests/golden/fixtures/form_contacts.json")
        write_synthetic(os.path.join(args.out_dir, "form_contacts.tsv"), cases, args.oracle)
    if args.data_dir:
        write_retail_forms(os.path.join(args.out_dir, "forms_retail.tsv"), args.data_dir, args.version)
        write_retail_contacts(os.path.join(args.out_dir, "form_contacts_retail.tsv"), args.data_dir, args.version)


if __name__ == "__main__":
    main()

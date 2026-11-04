#!/usr/bin/env python3
"""Independent final-PC entity facts and source entity/path component traces."""
import argparse
import csv
import hashlib
import json
import os
import struct
import sys

sys.dont_write_bytecode = True
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden import make_golden_exe_tables as exe_tables
from tools.golden import make_golden_paths as paths


def number(data, offset, fmt):
    if offset < 0 or offset + struct.calcsize(fmt) > len(data):
        raise ValueError("entity read exceeds map")
    return struct.unpack_from(fmt, data, offset)[0]


def digest(values):
    return hashlib.sha256(",".join(map(str, values)).encode("ascii")).hexdigest() if values else "-"


def packet_offsets(data):
    names = ("GENE", "GRAP", "FORM", "EMTP", "ZONE", "PATH")
    offsets = {name: number(data, 76 + 4 * index, "<I") for index, name in enumerate(names)}
    for name, offset in offsets.items():
        if data[offset:offset + 4] != name.encode("ascii"):
            raise ValueError(f"missing {name} packet")
    return offsets


def supported_paths(data, packet):
    count = number(data, packet + 4, "<I")
    result = {}
    for path_index in range(count):
        path = number(data, packet + 8 + 4 * path_index, "<I")
        segments = number(data, path + 4, "<I")
        lengths = []
        valid = segments > 0
        for segment_index in range(segments):
            at = number(data, path + 8 + 4 * segment_index, "<I")
            kind = number(data, at, "<I")
            length = number(data, at + 4, "<i")
            lengths.append(length)
            if kind not in (0, 1, 2) or length <= 0:
                valid = False
            if kind == 1:
                radius = number(data, at + 32, "<i")
                if radius <= 0 or radius * 0x6487 > 2147483647:
                    valid = False
        if sum(lengths) > 2147483647:
            valid = False
        if valid:
            result[path_index] = lengths
    return result


def decode_entity_map(data, forms, entity_names, overrides):
    packets = packet_offsets(data)
    theme = number(data, packets["GENE"] + 10, "<H")
    at = packets["EMTP"]
    packet_end = at + number(data, at + 4, "<I")
    paths_by_index = supported_paths(data, packets["PATH"])
    count = number(data, at + 8, "<H")
    pointers = [number(data, at + 12 + 4 * index, "<I") for index in range(count)]
    if len(set(pointers)) != len(pointers):
        raise ValueError("duplicate entity pointer")
    identity, records = [], []
    accepted = []
    static_count = moving_count = 0
    for index, start in enumerate(pointers):
        end = min((p for p in pointers if p > start), default=packet_end)
        if start < at + 12 + 4 * count or start + 24 > end:
            raise ValueError("invalid entity header span")
        grid_id, unique_id, form_id, flags = struct.unpack_from("<4H", data, start)
        owner = 0 if form_id & 0x8000 else theme
        local_id = form_id & 0x7fff
        form = forms.get(owner, [])[local_id] if local_id < len(forms.get(owner, [])) else None
        form_name = "" if form is None else form["name"]
        entity_name = "" if form is None else form["entity"]
        identity.extend((index, start, end, grid_id, unique_id, form_id, flags,
                         -1 if form is None else form["entity_type"],
                         -1 if form is None else form["script"],
                         -1 if form is None else form["collision"],
                         -1 if form is None else form["bonus"]))
        payload = start + 24
        butterfly_callback = form is not None and 0x4284e0 in (form['collision'], form['bonus'])
        callback_payload_valid = (not butterfly_callback or
                                  (payload + 14 <= end and number(data, payload + 12, '<H') < 19))
        if entity_name in ("STATIC", "DYNAMIC"):
            if payload + 32 > end:
                raise ValueError(f"short STATIC matrix at entity {index}")
            matrix = struct.unpack_from("<10h3i", data, payload)
            if entity_name == "STATIC":
                records.extend((index, 0, *matrix[:9], *matrix[10:]))
                static_count += 1
            if not flags & ~127 and not flags & (32 | 64) and callback_payload_valid:
                accepted.extend((index, unique_id))
        elif entity_name in ("MOVING", "MOVING_TONGUEABLE"):
            if payload + 12 > end:
                raise ValueError(f"short MOVING PATH_INFO at entity {index}")
            path_id, segment, distance, motion, speed, padding = struct.unpack_from("<6H", data, payload)
            if entity_name == "MOVING":
                records.extend((index, 1, path_id, segment, distance, motion, speed))
                moving_count += 1
            lengths = paths_by_index.get(path_id, [])
            if (not flags & ~127 and not flags & (32 | 64) and padding == 0 and
                    not motion & ~14 and segment < len(lengths) and distance <= lengths[segment] and callback_payload_valid):
                accepted.extend((index, unique_id))
        elif entity_name and entity_name not in entity_names:
            raise ValueError(f"unknown resolved entity name {entity_name} from {form_name}")
    return (count, static_count, moving_count, len(accepted) // 2,
            digest(identity), digest(records), digest(accepted))


def retail_rows(data_dir, version):
    cfg = exe_tables.parse_cfg(os.path.join(exe_tables.CFG_ROOT, "versions", version + ".cfg"))
    exe_bytes = open(os.path.join(data_dir, "FROGGER.EXE"), "rb").read()
    image = exe_tables.Exe(exe_bytes, exe_tables.java_int(cfg.values["ramOffset"]))
    form_names, sections, _ = exe_tables.name_list("forms", cfg.values.get("formList", "1997-09-12-psx-build57"))
    entity_names, _, entity_cfg = exe_tables.name_list("entities", cfg.values.get("entityList", "1997-09-12-psx-build57"))
    overrides = entity_cfg.child("Override")
    themes = exe_tables.read_theme_book(image, exe_tables.java_int(cfg.values["themeBook"]))
    problems = []
    forms = exe_tables.read_forms(image, themes, sections, problems)
    if problems:
        raise ValueError("; ".join(problems))
    for owner, entries in forms.items():
        for form in entries:
            form["name"] = form_names[form["global"]]
            entity_type = form["entity_type"]
            entity = entity_names[entity_type] if 0 <= entity_type < len(entity_names) else ""
            if overrides is not None and form["name"] in overrides.values:
                entity = overrides.values[form["name"]]
            form["entity"] = entity
    _, archive_entries, _, files = paths.archive.load_archive(
        data_dir, exe_tables.java_int(cfg.values["mwiOffset"]), exe_tables.java_int(cfg.values["mwiLength"]))
    with open(os.path.join(data_dir, "FROGPSX.MWD"), "rb") as source:
        mwd = source.read()
    for entry in archive_entries:
        if entry["type"] != 0 or entry["flags"] & paths.archive.FLAG_GROUP_ACCESS:
            continue
        start = entry["sector"] * paths.archive.SECTOR_SIZE
        compressed = paths.archive.is_compressed(entry["flags"])
        raw = mwd[start:start + (entry["packed"] if compressed else entry["unpacked"])]
        files[entry["index"]] = paths.archive.pp20_unpack(raw)[0] if compressed else raw
    for resource_id, data in sorted(files.items()):
        name = paths.archive.file_name(archive_entries, resource_id)
        if name.upper().endswith(".MAP") and data[:4] == b"FROG":
            try:
                facts = decode_entity_map(data, forms, entity_names, overrides)
            except ValueError as issue:
                raise ValueError(f"{name}: {issue}") from issue
            yield (resource_id, name, *facts)


def synthetic_rows(cases, path_cases):
    output = []
    for case in cases:
        path_traces = {}
        for entity in case["entities"]:
            if entity["entity_name"] == "MOVING":
                source = {"segments": entity["segments"]} if "segments" in entity else path_cases[entity["path_case"]].copy()
                source["start"] = entity["start"]
                source["tick_limit"] = case["tick_limit"]
                path_traces[entity["entity_index"]] = paths.python_trace(source)
        for tick in range(case["tick_limit"] + 1):
            for entity in case["entities"]:
                index = entity["entity_index"]
                if entity["entity_name"] == "STATIC":
                    matrix = entity["matrix12"]
                    path = [-1] * 15
                else:
                    path = path_traces[index][tick]
                    matrix = moving_matrix(path, entity["flags"])
                output.append((case["name"], tick, index, entity["unique_id"], *matrix, *path[1:]))
    return output


def moving_matrix(path, flags):
    position = path[9:12]
    if flags & 16:
        return [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, *position]
    z = path[12:15]
    x = paths.normalised([z[2], 0, -z[0]])
    y = [paths.signed(v >> 12, 16) for v in
         (paths.signed(z[1] * x[2] - z[2] * x[1]),
          paths.signed(z[2] * x[0] - z[0] * x[2]),
          paths.signed(z[0] * x[1] - z[1] * x[0]))]
    return [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2], *position]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data-dir")
    ap.add_argument("--oracle")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--version", default="pc-retail-v3.0e")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    if args.data_dir:
        with open(os.path.join(args.out_dir, "entities_retail.tsv"), "w", newline="", encoding="utf-8") as target:
            writer = csv.writer(target, delimiter="\t", lineterminator="\n")
            writer.writerow(("resource_id", "name", "entity_count", "generic_static", "generic_moving",
                             "setup_eligible", "identity_digest", "base_record_digest", "setup_digest"))
            writer.writerows(retail_rows(args.data_dir, args.version))
    if args.oracle:
        with open("tests/golden/fixtures/entities.json", encoding="utf-8") as source:
            cases = json.load(source)
        with open("tests/golden/fixtures/paths.json", encoding="utf-8") as source:
            path_cases = {case["name"]: case for case in json.load(source)}
        rows = synthetic_rows(cases, path_cases)
        import subprocess
        input_rows = []
        for case in cases:
            input_rows.append(f"{case['tick_limit']} {len(case['entities'])}")
            for entity in case["entities"]:
                if entity["entity_name"] == "STATIC":
                    input_rows.append("0 " + " ".join(map(str, [entity["entity_index"], entity["unique_id"], entity["flags"], *entity["matrix12"]])))
                else:
                    path_case = {"segments": entity["segments"]} if "segments" in entity else path_cases[entity["path_case"]]
                    start = entity["start"]
                    input_rows.append("1 " + " ".join(map(str, [entity["entity_index"], entity["unique_id"], entity["flags"], len(path_case["segments"]),
                        start["segment_index"], start["distance"], start["speed"], start["flags"]])))
                    for segment in path_case["segments"]:
                        kind = segment["segment_type"]
                        values = [kind, segment["length"]]
                        if kind == 0:
                            values += segment["matrix"] + segment["smooth_t"] + segment["smooth_c"]
                        elif kind == 1:
                            values += segment["start"] + segment["centre"] + segment["normal"] + [segment["radius"], segment["pitch"]]
                        else:
                            values += segment["start"] + segment["end"]
                        input_rows.append(" ".join(map(str, values)))
        result = subprocess.run([args.oracle], input="\n".join(input_rows) + "\n", text=True,
                                capture_output=True, check=True, timeout=30,
                                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        frozen = []
        for line in result.stdout.splitlines():
            values = line.split()
            if len(values) == 29 and all(value.lstrip("-").isdigit() for value in values):
                frozen.append(list(map(int, values)))
        wanted = [[int(value) for value in row[1:]] for row in rows]
        if frozen != wanted:
            mismatch = next((i for i, pair in enumerate(zip(frozen, wanted)) if pair[0] != pair[1]), min(len(frozen), len(wanted)))
            raise ValueError(f"Python/frozen entity mismatch row {mismatch}: {frozen[mismatch:mismatch+1]} != {wanted[mismatch:mismatch+1]}")
        with open(os.path.join(args.out_dir, "entities_trace.tsv"), "w", newline="", encoding="utf-8") as target:
            writer = csv.writer(target, delimiter="\t", lineterminator="\n")
            writer.writerow(("case", "tick", "entity_index", "unique_id", *[f"matrix_{i}" for i in range(12)],
                             "segment_index", "segment_type", "segment_distance", "segment_length", "segment_param",
                             "total_distance", "speed", "path_flags", "pos_x", "pos_y", "pos_z", "tan_x", "tan_y", "tan_z"))
            writer.writerows(rows)


if __name__ == "__main__":
    main()

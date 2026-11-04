#!/usr/bin/env python3
"""Independent FrogLord-layout PATH facts and frozen-C path trace transport."""
import argparse
import csv
import hashlib
import json
import math
import os
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden import make_golden_mof as archive


RECORD_SIZE = (120, 40, 24)


def signed(value, bits=32):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def divided(a, b):
    if not b:
        raise ValueError("reference division by zero")
    return (abs(a) // abs(b)) * (-1 if (a < 0) != (b < 0) else 1)


def rounded(value):
    return math.copysign(math.floor(abs(value) + 0.5), value)


def normalised(v):
    size = math.sqrt(sum(x * x for x in v))
    return [signed(int(rounded(x * 4096.0 / size))) for x in v] if size >= 1e-6 else [0, 0, 0]


def trig(angle):
    radians = 2.0 * math.pi * (angle & 4095) / 4096.0
    return int(rounded(math.cos(radians) * 4096.0)), int(rounded(math.sin(radians) * 4096.0))


def sample(segment, distance, backwards):
    kind, length = segment["segment_type"], segment["length"]
    if kind == 2:
        delta = [b - a for a, b in zip(segment["start"], segment["end"])]
        position = [signed(a + divided(signed(d * distance), length)) for a, d in zip(segment["start"], delta)]
        tangent = normalised(delta)
        param = divided(signed(distance * 4096), length)
    elif kind == 1:
        radius = segment["radius"]
        radial = normalised([a - b for a, b in zip(segment["start"], segment["centre"])])
        normal = segment["normal"]
        cross = [signed(normalised_value >> 12) for normalised_value in (
            signed(radial[1] * normal[2] - radial[2] * normal[1]),
            signed(radial[2] * normal[0] - radial[0] * normal[2]),
            signed(radial[0] * normal[1] - radial[1] * normal[0]))]
        columns = [list(map(lambda x: signed(x, 16), radial)),
                   [signed(-x, 16) for x in normal],
                   [signed(-x, 16) for x in cross]]
        param = divided(signed(distance * 4096), length)
        circumference = signed(radius * 0x6487)
        turns = divided(signed(distance << 12), circumference)
        angle = divided(signed(signed(distance << 18) - signed(turns * circumference)), signed(radius * 0x192))
        height = divided(signed(-segment["pitch"] * distance), length)
        cosine, sine = trig(angle)
        local = [signed(signed(cosine * radius) >> 12, 16), signed(height, 16),
                 signed(signed(sine * radius) >> 12, 16)]
        velocity = [signed(-sine, 16), 0, signed(cosine, 16)]
        def rotate(v):
            return [signed(sum(signed(columns[j][axis] * v[j]) for j in range(3)) >> 12)
                    for axis in range(3)]
        position = [signed(a + b) for a, b in zip(rotate(local), segment["centre"])]
        tangent = rotate(velocity)
    else:
        distance_scaled = signed(distance << 5)
        section, remainder = 0, distance_scaled
        for candidate in range(3, 0, -1):
            remainder = signed(distance_scaled - (segment["smooth_t"][candidate - 1] >> 3))
            if remainder >= 0:
                section = candidate
                break
        if section == 0:
            remainder = distance_scaled
        e = remainder
        coeff = segment["smooth_c"][section * 3:section * 3 + 3]
        value = 0
        for c in coeff:
            value = signed((signed(value + (c >> 11)) * e)) >> 13
        t = signed((value >> 5) + [0, 0, 512, 1024, 1536, 2048][section + 1])
        param = signed(t << 1)
        t2 = signed(t * t) >> 3
        t3 = signed(t2 * t) >> 11
        derivative_t2 = signed(3 * signed(t * t)) >> 3
        point, derivative = [], []
        for axis in range(3):
            m = segment["matrix"]
            point.append(signed(sum((signed(t3 * m[axis]) >> 16,
                signed(t2 * m[3 + axis]) >> 16, signed(t * m[6 + axis]) >> 8,
                signed(m[9 + axis] << 3))), 16))
            derivative.append(signed(sum((signed(derivative_t2 * m[axis]) >> 16,
                signed(t * m[3 + axis]) >> 7, signed(m[6 + axis] << 3))) >> 4))
        position = point
        tangent = normalised(derivative)
    if backwards:
        tangent = [-component for component in tangent]
    return signed(param), position, tangent


def python_trace(case):
    segments = case["segments"]
    state = dict(index=case["start"]["segment_index"], distance=case["start"]["distance"],
                 speed=case["start"]["speed"], flags=case["start"]["flags"])
    def total():
        return signed(sum(s["length"] for s in segments[:state["index"]]) + state["distance"])
    state["total"] = total()
    def row(tick):
        segment = segments[state["index"]]
        param, position, tangent = sample(segment, state["distance"], bool(state["flags"] & 2))
        return [tick, state["index"], segment["segment_type"], state["distance"],
                segment["length"], param, state["total"], state["speed"], state["flags"],
                *position, *tangent]
    result = [row(0)]
    for tick in range(case["tick_limit"]):
        state["flags"] &= ~0x3f0000
        if state["flags"] & 1:
            segment_length = segments[state["index"]]["length"]
            if state["flags"] & 2:
                state["distance"] = signed(state["distance"] - state["speed"])
                state["total"] = signed(state["total"] - state["speed"])
                if state["distance"] < 0:
                    state["index"] -= 1
                    if state["index"] < 0:
                        if state["flags"] & 4:
                            state["flags"] |= 16 | (1 << 20)
                            state["index"], state["distance"], state["total"] = 0, 0, 0
                        elif state["flags"] & 8:
                            state["index"] = len(segments) - 1
                            state["flags"] |= 1 << 18
                        else:
                            state["flags"] = (state["flags"] & ~2) | (1 << 16)
                            state["index"] = 0
                            state["distance"] = signed(-state["distance"])
                            state["total"] = state["distance"]
            else:
                state["distance"] = signed(state["distance"] + state["speed"])
                state["total"] = signed(state["total"] + state["speed"])
                if state["distance"] >= segment_length:
                    state["index"] += 1
                    if state["index"] == len(segments):
                        if state["flags"] & 4:
                            state["flags"] |= 16 | (1 << 21)
                            state["index"] -= 1
                            state["total"] = signed(state["total"] - (state["distance"] - segment_length))
                            state["distance"] = segment_length
                        elif state["flags"] & 8:
                            state["index"] = 0
                            state["distance"] = signed(state["distance"] - segment_length)
                            state["total"] = state["distance"]
                            state["flags"] |= 1 << 19
                        else:
                            state["flags"] |= 2 | (1 << 17)
                            state["index"] -= 1
                            overshoot = state["distance"] - segment_length
                            state["total"] = signed(state["total"] - (overshoot << 1))
                            state["distance"] = signed((segment_length << 1) - state["distance"])
                    else:
                        state["distance"] = signed(state["distance"] - segment_length)
            if state["distance"] < 0:
                state["distance"] = signed(state["distance"] + segments[state["index"]]["length"])
            if state["total"] < 0:
                state["total"] = total()
        result.append(row(tick + 1))
    return result


def number(data, offset, fmt):
    size = struct.calcsize(fmt)
    if offset < 0 or offset + size > len(data):
        raise ValueError("PATH record exceeds map")
    return struct.unpack_from(fmt, data, offset)[0]


def digest(values):
    return hashlib.sha256(",".join(map(str, values)).encode("ascii")).hexdigest() if values else "-"


def parse_paths(data):
    packet = number(data, 96, "<I")
    if data[packet:packet + 4] != b"PATH":
        raise ValueError("PATH signature missing")
    count = number(data, packet + 4, "<I")
    metadata, values, entity_lists = [], [], []
    types = [0, 0, 0]
    for path_index in range(count):
        path = number(data, packet + 8 + path_index * 4, "<I")
        entity_pointer = number(data, path, "<I")
        segments = number(data, path + 4, "<I")
        metadata.extend((path_index, path, entity_pointer, segments))
        members = []
        if entity_pointer:
            cursor = entity_pointer
            while True:
                member = number(data, cursor, "<h")
                cursor += 2
                if member == -1:
                    break
                if member < 0:
                    raise ValueError("negative PATH entity index")
                members.append(member)
        entity_lists.extend((path_index, len(members), *members))
        for segment_index in range(segments):
            offset = number(data, path + 8 + segment_index * 4, "<I")
            kind = number(data, offset, "<I")
            if kind > 2:
                raise ValueError("unknown PATH segment type")
            size = RECORD_SIZE[kind]
            if offset + size > len(data):
                raise ValueError("PATH segment exceeds map")
            length = number(data, offset + 4, "<i")
            types[kind] += 1
            values.extend((path_index, segment_index, offset, offset + size, kind, length))
            if kind == 0:
                values.extend(struct.unpack_from("<12i4i12i", data, offset + 8))
            elif kind == 1:
                for at in (8, 16, 24):
                    values.extend(struct.unpack_from("<3h", data, offset + at))
                values.extend(struct.unpack_from("<2i", data, offset + 32))
            else:
                for at in (8, 16):
                    values.extend(struct.unpack_from("<3h", data, offset + at))
    return count, types, digest(metadata), digest(values), digest(entity_lists)


def retail_rows(data_dir, version):
    cfg = archive.parse_cfg(os.path.join(archive.CFG_ROOT, "versions", version + ".cfg"))
    _, entries, _, files = archive.load_archive(
        data_dir, archive.java_int(cfg.values["mwiOffset"]), archive.java_int(cfg.values["mwiLength"]))
    with open(os.path.join(data_dir, "FROGPSX.MWD"), "rb") as source:
        mwd = source.read()
    for entry in entries:
        if entry["type"] != 0 or entry["flags"] & archive.FLAG_GROUP_ACCESS:
            continue
        start = entry["sector"] * archive.SECTOR_SIZE
        compressed = archive.is_compressed(entry["flags"])
        raw = mwd[start:start + (entry["packed"] if compressed else entry["unpacked"])]
        files[entry["index"]] = archive.pp20_unpack(raw)[0] if compressed else raw
    for resource_id, data in sorted(files.items()):
        name = archive.file_name(entries, resource_id)
        if name.upper().endswith(".MAP") and data[:4] == b"FROG":
            count, types, metadata_hash, segment_hash, entity_hash = parse_paths(data)
            yield (resource_id, name, count, *types, metadata_hash, segment_hash, entity_hash)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir")
    parser.add_argument("--oracle")
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--version", default="pc-retail-v3.0e")
    args = parser.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    if args.data_dir:
        with open(os.path.join(args.out_dir, "paths_retail.tsv"), "w", newline="", encoding="utf-8") as target:
            writer = csv.writer(target, delimiter="\t", lineterminator="\n")
            writer.writerow(("resource_id", "name", "path_count", "spline_count", "arc_count", "line_count", "metadata_digest", "segment_digest", "entity_list_digest"))
            writer.writerows(retail_rows(args.data_dir, args.version))
    if args.oracle:
        with open("tests/golden/fixtures/paths.json", encoding="utf-8") as source:
            cases = json.load(source)
        output = []
        for case in cases:
            lines = [f"{len(case['segments'])} {case['start']['segment_index']} {case['start']['distance']} {case['start']['speed']} {case['start']['flags']} {case['tick_limit']}"]
            for segment in case["segments"]:
                kind = segment["segment_type"]
                fields = [kind, segment["length"]]
                if kind == 0:
                    fields += segment["matrix"] + segment["smooth_t"] + segment["smooth_c"]
                elif kind == 1:
                    fields += segment["start"] + segment["centre"] + segment["normal"] + [segment["radius"], segment["pitch"]]
                else:
                    fields += segment["start"] + segment["end"]
                lines.append(" ".join(map(str, fields)))
            result = subprocess.run([args.oracle], input="\n".join(lines) + "\n", capture_output=True,
                                    text=True, check=True, timeout=30,
                                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            oracle_rows = []
            for row in result.stdout.splitlines():
                parts = row.split()
                if len(parts) == 15 and all(value.lstrip("-").isdigit() for value in parts):
                    oracle_rows.append([int(value) for value in parts])
            expected = python_trace(case)
            if len(oracle_rows) != len(expected):
                raise ValueError(f"frozen oracle returned {len(oracle_rows)} rows for {case['name']}; Python expected {len(expected)}")
            for index, (actual, wanted) in enumerate(zip(oracle_rows, expected)):
                if actual != wanted:
                    raise ValueError(f"Python/frozen path disagreement: {case['name']} tick {index}: {wanted} != {actual}")
                output.append(case["name"] + "\t" + "\t".join(map(str, wanted)))
        with open(os.path.join(args.out_dir, "paths_trace.tsv"), "w", newline="", encoding="utf-8") as target:
            target.write("case\ttick\tsegment_index\tsegment_type\tsegment_distance\tsegment_length\tsegment_param\ttotal_distance\tspeed\tflags\tpos_x\tpos_y\tpos_z\ttan_x\ttan_y\ttan_z\n")
            target.write("\n".join(output) + "\n")


if __name__ == "__main__":
    main()

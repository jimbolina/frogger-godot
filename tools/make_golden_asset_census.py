#!/usr/bin/env python3
"""Golden census of what the asset importer must reproduce from the retail files.

Counts the archive's index entries, maps, texture banks, images and texture
ids, models by kind, sound banks and samples, demos, the disc's audio tracks
and the rows of every executable table (by running make_golden_exe_tables.py
and make_golden_high_scores.py's readers into a scratch folder). Facts are
written one per line as key=value.

Usage:
    python3 tools/make_golden_asset_census.py [--data-dir DIR] [--disc FILE.mds] [--output FILE] [--check]
"""

import collections
import contextlib
import io
import os
import struct
import sys
import tempfile
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_golden_exe_tables
from imported_assets_common import Archive, arguments, finish
from make_golden_disc_tracks import extra_options, parse_mds
from make_golden_exe_tables import find_demo_table, read_demo_tables
from make_golden_high_scores import read_tables as read_high_scores
from make_golden_mof import TYPE_MAPMOF, TYPE_MOF, parse_model

TYPE_MAP = 0
SOUND_BANKS = 0x6E890


def exe_table_rows(data_dir):
    """{table file name: data rows} as make_golden_exe_tables.py writes them."""
    with tempfile.TemporaryDirectory() as folder:
        argv = sys.argv
        sys.argv = ["make_golden_exe_tables.py", data_dir, folder]
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                if make_golden_exe_tables.main() != 0:
                    raise ValueError("make_golden_exe_tables.py reported failed cross-checks")
        finally:
            sys.argv = argv
        rows = {}
        for name in sorted(os.listdir(folder)):
            if name.endswith(".tsv"):
                with open(os.path.join(folder, name), encoding="utf-8") as f:
                    rows[name[:-4]] = sum(1 for line in f if line.strip() and not line.startswith("#"))
        return rows


def main():
    args = arguments(__doc__, "asset_census.txt", extra_options)
    if not args.disc:
        sys.exit("no disc image: pass --disc or set FROGGER_DISC")
    started = time.time()
    archive = Archive(args.data_dir)
    facts = [("mwi_entries", len(archive.entries))]

    maps = sky = 0
    for e in archive.entries:
        if e["type"] == TYPE_MAP and archive.name(e["index"]).upper().endswith(".MAP"):
            if archive.resource(e["index"])[:4] == b"FROG":
                maps += 1
            else:
                sky += 1
    facts += [("maps", maps + sky), ("frog_maps", maps), ("sky_land_maps", sky)]

    banks = images = 0
    texture_ids = set()
    for _rid, data in archive.texture_banks():
        banks += 1
        count = struct.unpack_from("<i", data, 4)[0]
        images += count
        texture_ids.update(struct.unpack_from("<h", data, 12 + 24 * i + 12)[0] for i in range(count))
    facts += [("vlo_banks", banks), ("images", images), ("distinct_texture_ids", len(texture_ids))]

    children = archive.wad_children()
    model_ids = sorted({rid for kids in children.values() for rid, t in kids if t in (TYPE_MOF, TYPE_MAPMOF)})
    models, kinds, warnings = {}, collections.Counter(), []
    for rid in model_ids:
        previous = next((o for o in range(rid - 1, -1, -1) if o in models and not models[o]["incomplete"]), -1)
        model = parse_model(archive.resource(rid), str(rid), models.get(previous), warnings)
        models[rid] = model
        kinds[model["kind"]] += 1
        kinds["incomplete"] += int(model["incomplete"])
        kinds["parts"] += sum(len(s["parts"]) for s in model["statics"])
    facts += [("models", len(models))] + [("models_%s" % k, kinds[k]) for k in ("static", "animated", "dummy", "incomplete")]
    facts += [("model_parts", kinds["parts"])]

    sound_banks = samples = 0
    for i in range(12):
        header_id, _body_id = struct.unpack_from("<ii", archive.exe_bytes, SOUND_BANKS + 12 * i)
        if header_id < 0:
            continue
        sound_banks += 1
        header = archive.resource(header_id)
        count = struct.unpack_from("<i", header, 0)[0]
        samples += sum(1 for s in range(count) if struct.unpack_from("<i", header, 4 + 28 * s)[0] == 1)
    facts += [("sound_banks", sound_banks), ("sound_samples", samples)]

    offset, low_poly = find_demo_table(archive.exe, archive.entries)
    tables = read_demo_tables(archive.exe, offset, low_poly)
    demos = {rid for table in tables for _level, rid, _unlock in table if rid >= 0}
    facts += [("demo_tables", len(tables)), ("demo_table_rows", sum(len(t) for t in tables)), ("demos", len(demos))]

    mds = args.disc if args.disc.lower().endswith(".mds") else os.path.splitext(args.disc)[0] + ".mds"
    tracks, _end = parse_mds(open(mds, "rb").read())
    facts += [("disc_tracks", len(tracks)), ("disc_audio_tracks", len(tracks) - 1)]

    for name, count in exe_table_rows(args.data_dir).items():
        facts.append(("rows[%s]" % name, count))
    main_scores, level_scores, problems = read_high_scores(args.data_dir)
    if problems:
        raise ValueError("; ".join(problems))
    facts += [("rows[exe_high_scores_main]", len(main_scores)), ("rows[exe_high_scores_levels]", len(level_scores))]

    text = "".join("%s=%s\n" % fact for fact in facts)
    finish(args, text, "%d facts, %.1f s" % (len(facts), time.time() - started))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""FrogLord round-trip facts (tests/golden/specs/imported-assets.md#froglord-round-trip).

Reads the retail FROGGER.EXE and FROGPSX.MWD and the shared edit
specification tests/golden/synthetic/froglord_edits.tsv, applies every edit
to the decoded data in memory and writes the facts the edited files must
yield, in the schemas of the retail goldens:

  edit             each edit resolved: where it lands, the retail value, the new value
  exe_forms        the rows of the edited forms
  exe_scripts      the rows of the edited scripts
  exe_remaps       the rows of the edited remaps
  demos            the demo-table rows of the edited demos
  entities_retail  the rows of the high-detail maps of ORG1 and CAV3
  report           the unmapped or unplaced support-report rows the edits add for ORG1 and CAV3, by form

Form, script and remap edits patch the executable bytes, which are decoded
again with the readers of make_golden_exe_tables.py. Demo edits patch the
stored demo bytes and map edits the unpacked map bytes. Nothing here reads
the GDScript fixture or any Godot output. Before writing, the generator
checks that the same row formatting applied to the unedited retail data
reproduces the committed retail facts.
"""

import os
import struct
import sys

sys.dont_write_bytecode = True
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden import imported_assets_common as common
from tools.golden import make_golden_entities as entities
from tools.golden import make_golden_exe_tables as exe_tables
from tools.golden.make_golden_demos import demo_facts

SPEC = os.path.join(common.ROOT, "tests", "golden", "synthetic", "froglord_edits.tsv")
LEVELS = ("ORG1", "CAV3")
KINDS = ("form", "script", "remap", "demo", "map")
FORM_FIELDS = {"entity_type": (0, "<i"), "model_id": (4, "<i"), "script_id": (8, "<i"), "flags": (12, "<i"),
               "collision_callback": (16, "<I"), "radius_squared": (20, "<i"), "death_type": (24, "<i"),
               "bonus_callback": (28, "<I")}
CALLBACK_FIELDS = ("collision_callback", "bonus_callback")
MAP_FIELDS = {"form_grid_id": (0, "<H"), "unique_id": (2, "<H"), "form_id": (4, "<H"), "flags": (6, "<H")}
SECTIONS = {
    "edit": ["kind", "target", "subject", "field", "resource", "offset", "old", "new"],
    "exe_forms": ["theme", "local_id", "global_id", "form", "entity_type", "entity", "model_id", "script", "flags",
                  "collision_callback", "radius_squared", "death_type", "death", "bonus_callback"],
    "exe_scripts": ["index", "name", "pointer", "commands", "words", "words_sha256", "first_command", "last_command"],
    "exe_remaps": ["position", "name", "file_offset", "resource_id", "count", "ids_sha256", "first_id", "last_id"],
    "demos": ["detail", "level", "resource", "duration", "start_x", "start_z", "input_count", "input_digest", "skip",
              "up", "right", "down", "left", "unused", "super_hop", "tongue", "camera_ccw", "camera_cw"],
    "entities_retail": ["resource_id", "name", "entity_count", "generic_static", "generic_moving", "setup_eligible",
                        "identity_digest", "base_record_digest", "setup_digest"],
    "report": ["kind", "key", "levels", "form"],
}


def read_spec(path):
    """The edit rows: kind, target, subject, field, value (an integer) and note, in file order."""
    rows = []
    with open(path, encoding="utf-8") as f:
        for number, line in enumerate(f.read().split("\n"), 1):
            if not line.strip() or line.startswith("#"):
                continue
            cells = line.split("\t")
            if len(cells) != 6:
                raise ValueError("%s:%d has %d columns, not 6" % (path, number, len(cells)))
            kind, target, subject, field, value, note = cells
            if kind not in KINDS:
                raise ValueError("%s:%d: unknown kind %s" % (path, number, kind))
            rows.append({"kind": kind, "target": target, "subject": subject, "field": field,
                         "value": int(value, 0), "note": note, "line": number})
    return rows


class Retail:
    """The retail executable's decoded tables and name lists, with the archive behind them."""

    def __init__(self, data_dir):
        self.archive = common.Archive(data_dir)
        cfg = self.archive.version.values
        self.cfg = self.archive.cfg
        self.form_names, self.form_sections, _ = exe_tables.name_list("forms", cfg.get("formList", "1997-09-12-psx-build57"))
        self.entity_names, _, entity_cfg = exe_tables.name_list("entities", cfg.get("entityList", "1997-09-12-psx-build57"))
        self.script_names, _, _ = exe_tables.name_list("scripts", cfg.get("scriptList", "1997-09-18-psx-build63"), False)
        self.overrides = entity_cfg.child("Override")
        self.tables = self.decode(self.archive.exe_bytes)

    def decode(self, exe_bytes):
        """Every table this generator reports, decoded from exe_bytes."""
        exe = exe_tables.Exe(exe_bytes, self.cfg["ramOffset"])
        map_rows, _ = exe_tables.read_map_book(exe, self.cfg["mapBook"], self.cfg["themeBook"])
        themes = exe_tables.read_theme_book(exe, self.cfg["themeBook"])
        problems = []
        forms = exe_tables.read_forms(exe, themes, self.form_sections, problems)
        if problems:
            raise ValueError("; ".join(problems))
        for entries in forms.values():
            for form in entries:
                form["name"] = self.form_names[form["global"]]
                entity = self.entity_names[form["entity_type"]] if 0 <= form["entity_type"] < len(self.entity_names) else ""
                if self.overrides is not None and form["name"] in self.overrides.values:
                    entity = self.overrides.values[form["name"]]
                form["entity"] = entity
        remaps = exe_tables.read_remaps(exe, self.archive.entries, map_rows, self.cfg.get("txl_sky_land", 0))
        scripts = exe_tables.read_scripts(exe, self.cfg["scripts"], len(self.script_names))
        demo_offset, low_poly = exe_tables.find_demo_table(exe, self.archive.entries)
        demo_tables = exe_tables.read_demo_tables(exe, demo_offset, low_poly)
        return {"exe": exe, "map_rows": map_rows, "themes": themes, "forms": forms, "remaps": remaps,
                "scripts": scripts, "demo_tables": demo_tables, "low_poly": low_poly}


def resolve(retail, edit):
    """(resource, offset, struct format) of an edit: resource is 'exe' or an MWI index."""
    kind, target, subject, field = edit["kind"], edit["target"], edit["subject"], edit["field"]
    tables = retail.tables
    exe = tables["exe"]
    if kind == "form":
        if target not in exe_tables.THEMES or subject not in retail.form_sections.get(target, []):
            raise ValueError("line %d: no form %s in theme %s" % (edit["line"], subject, target))
        if field not in FORM_FIELDS:
            raise ValueError("line %d: unknown form field %s" % (edit["line"], field))
        library = tables["themes"][exe_tables.THEMES.index(target)]["form_library"]
        at, fmt = FORM_FIELDS[field]
        return "exe", exe.file_offset(library) + 32 * retail.form_sections[target].index(subject) + at, fmt
    if kind == "script":
        if target not in retail.script_names or field != "word":
            raise ValueError("line %d: no script %s word" % (edit["line"], target))
        script = tables["scripts"][retail.script_names.index(target)]
        word = int(subject)
        if not 0 <= word < len(script["stream"]):
            raise ValueError("line %d: %s has no word %d" % (edit["line"], target, word))
        return "exe", exe.file_offset(script["pointer"]) + 4 * word, "<i"
    if kind == "remap":
        found = [r for r in tables["remaps"] if r["name"] == target]
        slot = int(subject)
        if len(found) != 1 or field != "slot" or not 0 <= slot < len(found[0]["ids"]):
            raise ValueError("line %d: no remap %s slot %d" % (edit["line"], target, slot))
        return "exe", found[0]["offset"] + 2 * slot, "<h"
    rid = retail.archive.find(target)
    if rid < 0:
        raise ValueError("line %d: no archive file %s" % (edit["line"], target))
    data = retail.archive.resource(rid)
    if kind == "demo":
        index = int(subject)
        if field != "input" or not 0 <= index < len(data) - 12:
            raise ValueError("line %d: %s has no input %d" % (edit["line"], target, index))
        return rid, 12 + index, "<B"
    packets = entities.packet_offsets(data)
    emtp = packets["EMTP"]
    count = struct.unpack_from("<H", data, emtp + 8)[0]
    index = int(subject)
    if field not in MAP_FIELDS or not 0 <= index < count:
        raise ValueError("line %d: %s has no entity %d field %s" % (edit["line"], target, index, field))
    record = struct.unpack_from("<I", data, emtp + 12 + 4 * index)[0]
    at, fmt = MAP_FIELDS[field]
    return rid, record + at, fmt


def apply_edits(retail, spec):
    """The edited executable, the edited archive files by MWI index and one 'edit' row per edit."""
    exe = bytearray(retail.archive.exe_bytes)
    files = {}
    rows = []
    for edit in spec:
        resource, offset, fmt = resolve(retail, edit)
        if resource == "exe":
            target = exe
        else:
            target = files.setdefault(resource, bytearray(retail.archive.resource(resource)))
        old = struct.unpack_from(fmt, target, offset)[0]
        try:
            struct.pack_into(fmt, target, offset, edit["value"])
        except struct.error as issue:
            raise ValueError("line %d: value %d does not fit: %s" % (edit["line"], edit["value"], issue)) from issue
        rows.append([edit["kind"], edit["target"], edit["subject"], edit["field"], resource, "0x%X" % offset,
                     old, edit["value"]])
    return bytes(exe), {rid: bytes(data) for rid, data in files.items()}, rows


def form_rows(tables, names):
    rows = []
    for theme in sorted(tables["forms"]):
        for e in tables["forms"][theme]:
            if names is not None and e["name"] not in names:
                continue
            death = exe_tables.DEATH_TYPES[e["death"]] if 0 <= e["death"] < len(exe_tables.DEATH_TYPES) else ""
            rows.append([exe_tables.THEMES[theme], e["local"], e["global"], e["name"], e["entity_type"], e["entity"],
                         e["id"], e["script"], e["flags"], "0x%X" % e["collision"], e["radius2"], e["death"], death,
                         "0x%X" % e["bonus"]])
    return rows


def script_rows(tables, script_names, names):
    rows = []
    for i, s in enumerate(tables["scripts"]):
        name = script_names[i] if i < len(script_names) else ""
        if names is not None and name not in names:
            continue
        rows.append([i, name, "0x%X" % s["pointer"], len(s["commands"]), len(s["stream"]),
                     exe_tables.digest(s["stream"]), s["commands"][0] if s["commands"] else "",
                     s["commands"][-1] if s["commands"] else ""])
    return rows


def remap_rows(tables, names):
    rows = []
    for i, r in enumerate(tables["remaps"]):
        if names is not None and r["name"] not in names:
            continue
        rows.append([i, r["name"], "0x%X" % r["offset"], r["resource"], len(r["ids"]), exe_tables.digest(r["ids"]),
                     r["ids"][0] if r["ids"] else "", r["ids"][-1] if r["ids"] else ""])
    return rows


def demo_rows(retail, tables, files, resources):
    rows = []
    details = ("low", "high") if tables["low_poly"] else ("high",)
    for detail, table in zip(details, tables["demo_tables"]):
        for level, rid, unlock in table:
            if min(level, rid, unlock) < 0 or (resources is not None and rid not in resources):
                continue
            rows.append([detail, level, rid, *demo_facts(files.get(rid, retail.archive.resource(rid)))])
    return rows


def entity_rows(retail, tables, files):
    rows = []
    for code in LEVELS:
        rid = tables["map_rows"][exe_tables.LEVEL_CODES.index(code)]["high_map"]
        data = files.get(rid, retail.archive.resource(rid))
        facts = entities.decode_entity_map(data, tables["forms"], retail.entity_names, retail.overrides)
        rows.append([rid, retail.archive.name(rid), *facts])
    return rows


def placed_forms(retail, tables, files):
    """{(owner theme, local id): [level codes]} over the high-detail maps of LEVELS, and the maps' themes."""
    placed = {}
    themes = set()
    for code in LEVELS:
        rid = tables["map_rows"][exe_tables.LEVEL_CODES.index(code)]["high_map"]
        data = files.get(rid, retail.archive.resource(rid))
        packets = entities.packet_offsets(data)
        theme = struct.unpack_from("<H", data, packets["GENE"] + 10)[0]
        themes.add(theme)
        emtp = packets["EMTP"]
        for index in range(struct.unpack_from("<H", data, emtp + 8)[0]):
            record = struct.unpack_from("<I", data, emtp + 12 + 4 * index)[0]
            form_id = struct.unpack_from("<H", data, record + 4)[0]
            key = (0, form_id & 0x7FFF) if form_id & 0x8000 else (theme, form_id)
            levels = placed.setdefault(key, [])
            if code not in levels:
                levels.append(code)
    return placed, themes


def report_rows(retail, tables, files, spec):
    """Unmapped rows the edits add: a callback no retail form uses, on a form of a reported theme."""
    used = set()
    for entries in retail.tables["forms"].values():
        for form in entries:
            used.update((form["collision"], form["bonus"]))
    placed, themes = placed_forms(retail, tables, files)
    rows = []
    for edit in spec:
        if edit["kind"] != "form" or edit["field"] not in CALLBACK_FIELDS or edit["value"] in used:
            continue
        theme = exe_tables.THEMES.index(edit["target"])
        if theme != 0 and theme not in themes:
            continue
        local = retail.form_sections[edit["target"]].index(edit["subject"])
        if (theme, local) in placed:
            raise ValueError("line %d: a new callback on a placed form is not modelled" % edit["line"])
        rows.append(["callback", "0x%X" % edit["value"], "-", edit["subject"]])
    return rows


def committed_rows(file_name):
    with open(os.path.join(common.FACTS_DIR, file_name), encoding="utf-8") as f:
        return [line.split("\t") for line in f.read().split("\n") if line and not line.startswith("#")]


def check_formatting(retail, spec):
    """Requires the row builders, applied to the unedited data, to reproduce the committed retail rows."""
    tables = retail.tables
    demo_ids = {retail.archive.find(e["target"]) for e in spec if e["kind"] == "demo"}
    map_names = {retail.archive.name(row[0]) for row in entity_rows(retail, tables, {})}
    checks = [
        ("exe_forms.tsv", form_rows(tables, None), None),
        ("exe_scripts.tsv", script_rows(tables, retail.script_names, None), None),
        ("exe_remaps.tsv", remap_rows(tables, None), None),
        ("demos.tsv", demo_rows(retail, tables, {}, demo_ids), lambda row: int(row[2]) in demo_ids),
        ("entities_retail.tsv", entity_rows(retail, tables, {}), lambda row: row[1] in map_names),
    ]
    for file_name, rows, keep in checks:
        want = [row for row in committed_rows(file_name) if keep is None or keep(row)]
        got = [[str(cell) for cell in row] for row in rows]
        if sorted(got) != sorted(want):
            raise ValueError("the row builders do not reproduce the committed %s" % file_name)


def main():
    args = common.arguments(__doc__, "froglord_roundtrip.tsv",
                            lambda parser: parser.add_argument("--spec", default=SPEC, help="the edit specification"))
    spec = read_spec(args.spec)
    retail = Retail(args.data_dir)
    check_formatting(retail, spec)
    exe_bytes, files, edits = apply_edits(retail, spec)
    tables = retail.decode(exe_bytes)

    def named(kind):
        return {e["subject"] if kind == "form" else e["target"] for e in spec if e["kind"] == kind}

    demo_ids = {retail.archive.find(e["target"]) for e in spec if e["kind"] == "demo"}
    sections = [
        ("edit", edits),
        ("exe_forms", form_rows(tables, named("form"))),
        ("exe_scripts", script_rows(tables, retail.script_names, named("script"))),
        ("exe_remaps", remap_rows(tables, named("remap"))),
        ("demos", demo_rows(retail, tables, files, demo_ids)),
        ("entities_retail", entity_rows(retail, tables, files)),
        ("report", report_rows(retail, tables, files, spec)),
    ]
    lines = []
    for tag, rows in sections:
        lines.append("# " + "\t".join([tag] + SECTIONS[tag]))
        lines.extend("\t".join(str(cell) for cell in [tag] + row) for row in rows)
    text = "\n".join(lines) + "\n"
    common.finish(args, text, "%d edits, %d rows" % (len(edits), sum(len(rows) for _, rows in sections)))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build the golden EXE-table facts for a retail Frogger PC executable.

This is an independent, standard-library-only reading of the game tables the
Godot code decodes from FROGGER.EXE: the level list ("map book"), the theme
list ("theme book"), the per-theme form libraries, the texture remaps, the
texture pointer list, the entity scripts, the music list, the level-select
stacks, the attract-mode demo tables and the pickup (bug) animations.

It was written from FrogLord's Java sources (FroggerGameInstance and the
classes it calls: FroggerMapBookPC, FroggerThemeBookPC, FroggerFormEntry,
SCGameInstance's remap and texture-pointer readers, FroggerScript,
FroggerScriptCommandType, FroggerMusicTrack, FroggerLevelSelectEntry,
FroggerDemoTable, FroggerPickupData). It shares no code with the Godot
project; the Godot tests compare their own output with the files written here.

Only facts are written: ids, counts, addresses, names and SHA-256 digests of
decoded value lists. A "list digest" is always
    sha256(",".join(str(v) for v in values).encode("ascii")).hexdigest()
i.e. the decimal values joined by commas, so both sides agree by specification.

The script checks itself and refuses to report success when a check fails:
  * table spans agree with each other (the map book ends where the theme book
    starts, 36 bytes per row; texture pointers end where the remaps start);
  * every resource id named by the map and theme books exists in the MWI and
    has the type the game expects of it (map, WAD, VLO, palette);
  * form library sizes computed from pointer differences equal the name counts;
  * the two demo tables list the same levels in the same order;
  * for pc-retail-v3.0e only, the numbers the C port of the game documents
    independently (region offsets and lengths, 1858 texture pointers, the
    remap span 0x79560..+7874);
  * with --c-reference <froggy/engine>, the C port's generated files are read
    too: its four verbatim EXE regions are byte-compared with the executable,
    its per-level music table (xa_tunes_pc.c) is compared value by value with
    the music list read here, and its demo table offsets are compared.

Usage:
    python3 tools/make_golden_exe_tables.py <dir with FROGGER.EXE and FROGPSX.MWD> <out dir>
        [--c-reference <path to the froggy repository's engine folder>]
"""

import argparse
import hashlib
import os
import re
import struct
import sys
import zlib

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_golden_manifest import read_mwi  # noqa: E402  (the independent MWI reader)

CFG_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "third_party", "froglord_cfg")

# FroggerMapLevelID order (the map book is indexed by these).
LEVEL_CODES = [
    "CAV1", "CAV2", "CAV3", "CAV4", "CAV5", "CAVM",
    "DES1", "DES2", "DES3", "DES4", "DES5", "DESM",
    "FOR1", "FOR2", "FOR3", "FOR4", "FOR5", "FORM",
    "JUN1", "JUN2", "JUN3", "JUN4", "JUN5", "JUNM",
    "ORG1", "ORG2", "ORG3", "ORG4", "ORG5", "ORGM",
    "ARN1", "ARN2", "ARN3", "ARN4", "ARN5", "ARNM",
    "SWP1", "SWP2", "SWP3", "SWP4", "SWP5", "SWPM",
    "SKY1", "SKY2", "SKY3", "SKY4", "SKY5", "SKYM",
    "SUB1", "SUB2", "SUB3", "SUB4", "SUB5", "SUBM",
    "VOL1", "VOL2", "VOL3", "VOL4", "VOL5", "VOLM",
    "ISLAND", "QB",
]
# FroggerMapTheme order (the theme book is indexed by these).
THEMES = ["GENERAL", "CAVE", "DESERT", "FOREST", "JUNGLE", "ORIGINAL", "RUINS", "SWAMP", "SKY", "SUBURBIA", "VOLCANO"]
WORLDS = ["SUBURBIA", "ORIGINAL", "SEWER", "SKY", "FOREST", "VOLCANO", "DESERT", "CAVES", "JUNGLE_RIVER", "RUINED_CITY"]
DEATH_TYPES = ["SQUISHED", "DIE_ON_BACK", "DROWN", "BITTEN", "FLOP", "POP", "CRASH", "MOWED"]
FLY_TYPES = ["SCORE_10", "SCORE_25", "SCORE_50", "SCORE_100", "SCORE_200", "SCORE_500", "SCORE_1000", "SCORE_5000",
             "LIGHT_BOOST", "SUPER_LIGHT", "TIME_MIN", "TIME_MED", "TIME_MAX", "REDUCE_SCORE_100", "FAST_TIMER_SPEED",
             "ADD_EXTRA_LIFE", "FROG_SUPER_TONGUE", "FROG_QUICK_JUMP", "FROG_AUTO_HOP"]
# FroggerMusicTrack: name -> CD track number on the retail PC disc.
MUSIC_TRACKS = {2: "CAVE1", 3: "CAVE2", 4: "DESERT1", 5: "DESERT2", 6: "FOREST1", 7: "FOREST2", 8: "VOLCANO1",
                9: "VOLCANO2", 10: "JUNGLE1", 11: "JUNGLE2", 12: "JUNGLE3", 13: "LEVEL_SELECT", 14: "ORIGINAL1",
                15: "ORIGINAL2", 16: "SWAMP1", 17: "SWAMP2", 18: "SKY1", 19: "SKY2", 20: "SUBURBIA1", 21: "SUBURBIA2"}
# FroggerScriptCommandType: (name, argument count), in opcode order.
OPCODES = [
    ("WAIT_UNTIL_TIMER", 2), ("WAIT_UNTIL_ACTION_FINISHED", 0), ("WAIT_UNTIL_PATH_END", 0), ("SET_ACTION", 1),
    ("PLAY_SOUND", 1), ("RESTART", 0), ("END", 0), ("SET_TIMER", 2), ("DEVIATE", 5), ("WAIT_DEVIATED", 0),
    ("PLAY_RNDSOUND", 2), ("SETLOOP", 0), ("ENDLOOP", 0), ("SCRIPT_IF", 4), ("BREAKLOOP_IF_TIMER", 2),
    ("PAUSE_ENTITY_ON_PATH", 0), ("UNPAUSE_ENTITY_ON_PATH", 0), ("ROTATE", 4), ("WAIT_UNTIL_ROTATED", 0),
    ("HOME_IN_ON_FROG", 3), ("RETURN_GOSUB_IF", 1), ("EJECT_FROG", 3), ("CHOOSE_RND_CHECKPOINT", 0),
    ("APPEAR_ENTITY", 0), ("DISAPPEAR_ENTITY", 0), ("START_SCRIPT", 1), ("AWARD_FROG_POINTS", 1),
    ("AWARD_FROG_LIVES", 1), ("AWARD_FROG_TIME", 1), ("STOP_ROTATE", 0), ("STOP_DEVIATE", 0),
    ("PREPARE_REGISTERS", 2), ("CLEAR_DEVIATE", 0), ("RETURN_DEVIATE", 3), ("REGISTER_CALLBACK", 4),
    ("SET_ENTITY_TYPE", 1), ("PLAY_SOUND_DISTANCE", 5), ("PLAY_MOVING_SOUND", 4), ("STOP", 0),
    ("MUTATE_MESH_COLOR", 0), ("NO_COLL_CHECKPOINT", 0), ("COLL_CHECKPOINT", 0), ("KILL_SAFE_FROG", 2),
    ("CHANGE_ENTITY_ANIM", 1), ("CREATE_3D_SPRITE", 1), ("PITCH_BEND_MOVING_SOUND", 6), ("POP", 0),
    ("NO_COLLISION", 0), ("COLLISION", 0),
]
FINAL_OPCODES = {"STOP", "RESTART", "END"}

# What the C port of the game documents for pc-retail-v3.0e, found independently of FrogLord.
RETAIL_V30E_CRC = 378672750
RETAIL_V30E_FACTS = {
    "map_book": (0x70100, 2160), "bmp_pointers": (0x77858, 7432), "remaps": (0x79560, 7874),
    "txl_sky_land": 0x7A020, "bmp_pointer_count": 1858, "demo_tables": (0x83420, 0x835C4),
}

TYPE_MAP, TYPE_VLO, TYPE_PAL, TYPE_WAD = 0, 1, 7, -1


def digest(values):
    return hashlib.sha256(",".join(str(v) for v in values).encode("ascii")).hexdigest()


# ---- FrogLord's older config dialect, just enough for version files and name lists.

class Cfg:
    def __init__(self, name, layer):
        self.name, self.layer, self.values, self.text, self.children = name, layer, {}, [], []

    def child(self, name):
        found = None
        for c in self.children:
            if c.name == name:
                found = c
        return found


def parse_cfg(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().replace("\r\n", "\n").replace("\r", "\n").split("\n")
    root = Cfg(os.path.basename(path), 0)
    _load_cfg(root, lines)
    return root


def _strip(line):
    at = line.find("#")
    return (line if at < 0 else line[:at]).rstrip()


def _layer(line):
    n = 0
    while n < len(line) and line[n] == "[":
        n += 1
    return n


def _load_cfg(cfg, lines):
    reading_text = False
    i = 0
    while i < len(lines):
        line = _strip(lines[i])
        if not line:
            i += 1
            continue
        if line == "``":
            line = ""
        if line.startswith("[") and line.endswith("]"):
            layer = _layer(line)
            if layer != cfg.layer + 1:
                raise ValueError("bad section nesting: " + line)
            child = Cfg(line[layer:len(line) - layer], layer)
            i += 1
            sub = []
            while i < len(lines):
                s = _strip(lines[i])
                if s.startswith("[") and s.endswith("]") and _layer(s) <= layer:
                    break
                sub.append(s)
                i += 1
            _load_cfg(child, sub)
            cfg.children.append(child)
            continue
        eq = line.find("=")
        key = line if eq < 0 else line[:eq]
        if reading_text or eq < 0 or " " in key:
            reading_text = True
            cfg.text.append(line)
        else:
            cfg.values[key] = line[eq + 1:]
        i += 1


def name_list(folder, file_name, sections_extend_main=True):
    cfg = parse_cfg(os.path.join(CFG_ROOT, folder, file_name + ".cfg"))
    names = list(cfg.text)
    subs = {}
    for c in cfg.children:
        subs[c.name] = list(c.text)
        if sections_extend_main:
            names.extend(c.text)
    return names, subs, cfg


def java_int(text):
    return int(text, 16) if text.lower().startswith("0x") else int(text)


# ---- The tables.

class Exe:
    def __init__(self, data, ram_offset):
        self.data = data
        self.ram = ram_offset
        # A FrogLord-saved executable carries build information after the program;
        # tables are read from the program part only.
        self.length = len(data)
        if data.endswith(b"FROGLORD") and len(data) >= 16:
            self.length = struct.unpack_from("<i", data, len(data) - 12)[0]

    def s32(self, off):
        if off < 0 or off + 4 > self.length:
            raise IndexError("read at 0x%X outside the program" % off)
        return struct.unpack_from("<i", self.data, off)[0]

    def u32(self, off):
        return self.s32(off) & 0xFFFFFFFF

    def s16(self, off):
        if off < 0 or off + 2 > self.length:
            raise IndexError("read at 0x%X outside the program" % off)
        return struct.unpack_from("<h", self.data, off)[0]

    def u8(self, off):
        if off < 0 or off >= self.length:
            raise IndexError("read at 0x%X outside the program" % off)
        return self.data[off]

    def file_offset(self, pointer):
        return pointer - self.ram


def looks_like_pointer(value):
    """FrogLord's test for a Windows executable address (0x004xxxxx)."""
    return (value & 0xFFF00000) == 0x00400000


def read_map_book(exe, start, end):
    rows = []
    off = start
    while end > off:
        v = [exe.s32(off), exe.s32(off + 4), exe.u32(off + 8), exe.u32(off + 12), exe.s32(off + 16),
             exe.u32(off + 20), exe.s32(off + 24), exe.s32(off + 28), exe.s32(off + 32)]
        rows.append({"high_map": v[0], "low_map": v[1], "high_remap": v[2], "low_remap": v[3],
                     "cave_lights": 1 if v[4] == 1 else 0, "env_texture": v[5], "high_wad": v[6],
                     "low_wad": v[7], "palette": v[8]})
        off += 36
    return rows, off


def read_theme_book(exe, start):
    books = []
    for i in range(len(THEMES)):
        o = start + 40 * i
        v = [exe.s32(o), exe.u32(o + 4)] + [exe.s32(o + 8 + 4 * k) for k in range(8)]
        books.append({"high_wad": v[0], "form_library": v[1], "high_vlo": v[2], "death_height": v[3],
                      "high_mp_wad": v[4], "high_mp_vlo": v[5], "low_wad": v[6], "low_vlo": v[7],
                      "low_mp_wad": v[8], "low_mp_vlo": v[9]})
    return books


def read_forms(exe, themes, form_sections, problems):
    """FroggerGameInstance.readFormLibrary: a theme's size is its name count."""
    forms = {}
    order = []
    last = 0
    for i in range(1, len(THEMES)):
        cur = themes[i]
        prev = themes[last]
        if cur["form_library"] == 0 or prev["form_library"] == 0:
            continue
        count = len(form_sections.get(THEMES[last], []))
        computed = (cur["form_library"] - prev["form_library"]) // 32
        if computed != count:
            problems.append("%s: %d form names but %d entries between form libraries" % (THEMES[last], count, computed))
        order.append((last, count))
        last = i
    if themes[last]["form_library"] != 0:
        order.append((last, len(form_sections.get(THEMES[last], []))))
    global_id = 0
    for theme, count in order:
        entries = []
        base = exe.file_offset(themes[theme]["form_library"])
        for local in range(count):
            o = base + 32 * local
            entries.append({"local": local, "global": global_id, "entity_type": exe.s32(o), "id": exe.s32(o + 4),
                            "script": exe.s32(o + 8), "flags": exe.s32(o + 12), "collision": exe.u32(o + 16),
                            "radius2": exe.s32(o + 20), "death": exe.s32(o + 24), "bonus": exe.u32(o + 28)})
            global_id += 1
        forms[theme] = entries
    return forms


def read_bmp_pointers(exe, start):
    ptrs = []
    off = start
    while off + 4 <= exe.length:
        p = exe.u32(off)
        if not looks_like_pointer(p):
            break
        ptrs.append(p)
        off += 4
    return ptrs, off


def read_remaps(exe, entries, map_rows, sky_land_offset):
    """SCGameInstance.readTextureRemaps + updateRemap, for a Windows build."""
    remaps = {}

    def add(offset, name, resource):
        if offset not in remaps:
            remaps[offset] = {"name": name, "resource": resource}

    if sky_land_offset > 0:
        add(sky_land_offset, "txl_sky_land", -1)
    for row in map_rows:
        for map_id, pointer in ((row["high_map"], row["high_remap"]), (row["low_map"], row["low_remap"])):
            if map_id <= 0 or pointer <= 0:
                continue
            if map_id >= len(entries):
                continue
            path = entries[map_id]["path"]
            name = "txl_" + path.split("\\")[-1].rsplit(".", 1)[0].lower() if path else ""
            add(exe.file_offset(pointer), name, map_id)
    order = sorted(remaps)
    result = []
    i = 0
    while i < len(order):
        start = order[i]
        nxt = order[i + 1] if i + 1 < len(order) else None
        ids = []
        pos = start
        value = 0
        while pos + 2 <= exe.length:
            value = exe.s16(pos)
            pos += 2
            if value == 0 or (nxt is not None and pos - 2 >= nxt):
                break
            ids.append(value)
        if value != 0:
            if ids:
                pos -= 2
        else:
            end = nxt if nxt is not None else exe.length
            while end >= pos and pos + 2 <= exe.length:
                v = exe.s16(pos)
                pos += 2
                if v != 0:
                    break
            pos -= 2
        info = remaps[start]
        result.append({"offset": start, "name": info["name"], "resource": info["resource"], "ids": ids})
        extra = (nxt - pos) if nxt is not None else 0
        if extra > 4:
            remaps[pos] = {"name": "txl_unknown", "resource": -1}
            order.insert(i + 1, pos)
        i += 1
    return result


def read_scripts(exe, start, count):
    scripts = []
    for i in range(count):
        pointer = exe.u32(start + 4 * i)
        if pointer == 0:
            scripts.append({"pointer": 0, "stream": [], "commands": []})
            continue
        off = exe.file_offset(pointer)
        stream, commands = [], []
        while True:
            op = exe.s32(off)
            if op < 0 or op >= len(OPCODES):
                break
            name, argc = OPCODES[op]
            words = [exe.s32(off + 4 * k) for k in range(argc + 1)]
            stream.extend(words)
            commands.append(name)
            off += 4 * (argc + 1)
            if name in FINAL_OPCODES:
                break
        scripts.append({"pointer": pointer, "stream": stream, "commands": commands})
    return scripts


def read_music(exe, start):
    tracks = []
    off = start
    while exe.u8(off) != 0xFF:
        tracks.append(exe.u8(off))
        off += 1
    return tracks


def read_level_select(exe, start, problems):
    tables = []
    off = start
    for _ in range(2):
        rows = []
        while True:
            v = [exe.s32(off + 4 * k) for k in range(6)] + [exe.u32(off + 24 + 4 * k) for k in range(6)]
            if any(exe.u8(off + 48 + k) for k in range(44)):
                problems.append("level-select row at 0x%X has non-zero run-time bytes" % off)
            rows.append(v)
            off += 92
            if v[0] == -1:
                break
        tables.append(rows)
    return tables


def find_demo_table(exe, entries):
    """FroggerDemoTable.resolveDemoTableAddress: search for (SUB1, its demo's id)."""
    by_name = {}
    for e in entries:
        by_name.setdefault(e["path"].split("\\")[-1].upper(), e["index"])
    low_poly = "WSUB1DEMO.DAT" in by_name
    demo = by_name.get("WSUB1DEMO.DAT", by_name.get("SUB1DEMO.DAT"))
    if demo is None:
        return -1, low_poly
    return exe.data.find(struct.pack("<ii", LEVEL_CODES.index("SUB1"), demo), 0, exe.length), low_poly


def read_demo_tables(exe, offset, low_poly):
    tables = []
    off = offset
    for _ in range(2 if low_poly else 1):
        rows = []
        while off + 12 <= exe.length:
            level = exe.s32(off)
            if level == -1:
                off += 12
                break
            rows.append((level, exe.s32(off + 4), exe.s32(off + 8)))
            off += 12
        tables.append(rows)
    return tables


def read_pickups(exe, start):
    pickups = []
    for i in range(len(FLY_TYPES)):
        pointer = exe.u32(start + 4 * i)
        off = exe.file_offset(pointer)
        glow, size = exe.s32(off), exe.s32(off + 4)
        frames = []
        off += 8
        while off + 4 <= exe.length:
            f = exe.u32(off)
            off += 4
            if f == 0:
                break
            frames.append(f)
        pickups.append({"pointer": pointer, "glow": glow, "size": size, "frames": frames})
    return pickups


# ---- Cross-checks against the C port's generated files (optional).

def c_array(text, name):
    m = re.search(r"%s\[(\d+)\]\s*=\s*\{(.*?)\};" % re.escape(name), text, re.S)
    if not m:
        return None
    values = bytes(int(v, 16) for v in re.findall(r"0x[0-9a-fA-F]+", m.group(2)))
    return values if len(values) == int(m.group(1)) else None


def check_c_reference(root, exe, music, demo_offset, low_poly, problems, notes):
    tables = os.path.join(root, "real_source", "pc_resources", "pc_exe_tables.c")
    text = open(tables, encoding="utf-8").read()
    for region in re.findall(r'\{\s*"(\w+)",\s*0x([0-9A-Fa-f]+)UL,\s*(\d+)UL,\s*(\w+)\s*\}', text):
        name, offset, length, symbol = region[0], int(region[1], 16), int(region[2]), region[3]
        values = c_array(text, symbol)
        if values is None or len(values) != length:
            problems.append("C reference: cannot read region %s" % name)
        elif values != exe.data[offset:offset + length]:
            problems.append("C reference: region %s differs from the executable" % name)
        else:
            notes.append("C reference region %s (0x%X, %d bytes) is byte-identical to the executable" % (name, offset, length))
    tunes_text = open(os.path.join(root, "real_source", "pc_resources", "xa_tunes_pc.c"), encoding="utf-8").read()
    body = re.search(r"Game_xa_tunes\[\d+\]\s*=\s*\{(.*?)\};", tunes_text, re.S).group(1)
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    tunes = [int(v) for v in re.findall(r"-?\d+", body)]
    level_rows = tunes[:tunes.index(-1)]
    if level_rows != music:
        problems.append("C reference: xa_tunes_pc.c's %d level rows differ from the %d-entry music list" % (len(level_rows), len(music)))
    else:
        notes.append("C reference xa_tunes_pc.c: all %d per-level track numbers equal the music list" % len(music))
    demo_text = open(os.path.join(root, "asset_pipeline", "include", "frogger_demo_tables.h"), encoding="utf-8").read()
    w = int(re.search(r"MRSTUB_DEMO_TABLE_W_FILE_OFF\s+0x([0-9A-Fa-f]+)", demo_text).group(1), 16)
    v = int(re.search(r"MRSTUB_DEMO_TABLE_V_FILE_OFF\s+0x([0-9A-Fa-f]+)", demo_text).group(1), 16)
    if not low_poly or demo_offset != w:
        problems.append("C reference: low-poly demo table at 0x%X, found 0x%X" % (w, demo_offset))
    else:
        notes.append("C reference demo tables: low-poly at 0x%X, high-poly at 0x%X" % (w, v))
    return v


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("data_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--version", default="pc-retail-v3.0e")
    ap.add_argument("--c-reference", default="")
    args = ap.parse_args()

    ver = parse_cfg(os.path.join(CFG_ROOT, "versions", args.version + ".cfg"))
    cfg = {k: java_int(v.strip()) for k, v in ver.values.items()
           if k in ("mwiOffset", "mwiLength", "mapBook", "themeBook", "ramOffset", "arcadeLevelAddress",
                    "musicAddress", "bmpPointerAddress", "pickupData", "scripts", "txl_sky_land")}
    data = open(os.path.join(args.data_dir, "FROGGER.EXE"), "rb").read()
    exe = Exe(data, cfg["ramOffset"])
    entries = read_mwi(data[cfg["mwiOffset"]:cfg["mwiOffset"] + cfg["mwiLength"]])
    form_names, form_sections, _ = name_list("forms", ver.values.get("formList", "1997-09-12-psx-build57"))
    entity_names, _, entity_cfg = name_list("entities", ver.values.get("entityList", "1997-09-12-psx-build57"))
    script_names, _, _ = name_list("scripts", ver.values.get("scriptList", "1997-09-18-psx-build63"), False)
    overrides = entity_cfg.child("Override")
    problems, notes = [], []

    map_rows, map_end = read_map_book(exe, cfg["mapBook"], cfg["themeBook"])
    if map_end != cfg["themeBook"]:
        problems.append("map book rows overrun the theme book")
    themes = read_theme_book(exe, cfg["themeBook"])
    forms = read_forms(exe, themes, form_sections, problems)
    bmp, bmp_end = read_bmp_pointers(exe, cfg["bmpPointerAddress"])
    remaps = read_remaps(exe, entries, map_rows, cfg.get("txl_sky_land", 0))
    scripts = read_scripts(exe, cfg["scripts"], len(script_names))
    music = read_music(exe, cfg["musicAddress"])
    level_tables = read_level_select(exe, cfg["arcadeLevelAddress"], problems)
    demo_offset, low_poly = find_demo_table(exe, entries)
    demo_tables = read_demo_tables(exe, demo_offset, low_poly) if demo_offset >= 0 else []
    pickups = read_pickups(exe, cfg["pickupData"])

    def rtype(rid):
        return entries[rid]["type"] if 0 <= rid < len(entries) else None

    for i, r in enumerate(map_rows):
        if r["high_remap"] == 0 and r["low_remap"] == 0:
            continue
        for key, want in (("high_map", TYPE_MAP), ("low_map", TYPE_MAP), ("high_wad", TYPE_WAD), ("low_wad", TYPE_WAD), ("palette", TYPE_PAL)):
            if r["high_map"] <= 0:
                break
            if rtype(r[key]) != want:
                problems.append("map book row %d: %s %d has type %s, expected %d" % (i, key, r[key], rtype(r[key]), want))
    for i, t in enumerate(themes):
        for key, want in (("high_wad", TYPE_WAD), ("high_vlo", TYPE_VLO), ("high_mp_wad", TYPE_WAD), ("high_mp_vlo", TYPE_VLO),
                          ("low_wad", TYPE_WAD), ("low_vlo", TYPE_VLO), ("low_mp_wad", TYPE_WAD), ("low_mp_vlo", TYPE_VLO)):
            if t[key] != 0 and rtype(t[key]) != want:
                problems.append("theme %s: %s %d has type %s, expected %d" % (THEMES[i], key, t[key], rtype(t[key]), want))
    if bmp_end != remaps[0]["offset"]:
        problems.append("texture pointers end at 0x%X, the first remap starts at 0x%X" % (bmp_end, remaps[0]["offset"]))
    if len(demo_tables) == 2 and [(r[0], r[2]) for r in demo_tables[0]] != [(r[0], r[2]) for r in demo_tables[1]]:
        problems.append("the two demo tables list different levels")
    high_demo_offset = demo_offset + 12 * (len(demo_tables[0]) + 1) if len(demo_tables) == 2 else -1

    last = max(remaps, key=lambda r: r["offset"])
    remap_span = (remaps[0]["offset"], last["offset"] + 2 * len(last["ids"]) - remaps[0]["offset"])
    if zlib.crc32(data) == RETAIL_V30E_CRC:
        f = RETAIL_V30E_FACTS
        checks = [
            ("map book span", (cfg["mapBook"], map_end - cfg["mapBook"]), f["map_book"]),
            ("map book rows", len(map_rows), 60),
            ("texture pointer span", (cfg["bmpPointerAddress"], bmp_end - cfg["bmpPointerAddress"]), f["bmp_pointers"]),
            ("texture pointer count", len(bmp), f["bmp_pointer_count"]),
            ("remap span", remap_span, f["remaps"]),
            ("txl_sky_land offset", cfg.get("txl_sky_land"), f["txl_sky_land"]),
            ("demo table offsets", (demo_offset, high_demo_offset), f["demo_tables"]),
        ]
        for label, got, want in checks:
            if got != want:
                problems.append("%s: %r, the C port documents %r" % (label, got, want))
            else:
                notes.append("%s agrees with the C port's documentation: %r" % (label, got))
    if args.c_reference:
        check_c_reference(args.c_reference, exe, music, demo_offset, low_poly, problems, notes)

    write_outputs(args.out_dir, locals())
    for n in notes:
        print("ok: " + n)
    if problems:
        print("CROSS-CHECK FAILURES:\n  " + "\n  ".join(problems), file=sys.stderr)
        return 1
    print("cross-checks passed")
    return 0


def write_outputs(out_dir, v):
    exe, entries, bmp = v["exe"], v["entries"], v["bmp"]
    form_names, entity_names, script_names = v["form_names"], v["entity_names"], v["script_names"]
    overrides = v["overrides"]
    os.makedirs(out_dir, exist_ok=True)

    def name(names, i):
        return names[i] if 0 <= i < len(names) else ""

    def tex_id(pointer):
        return bmp.index(pointer) if pointer in bmp else -1

    def write(file_name, header, rows):
        with open(os.path.join(out_dir, file_name), "w", newline="\n") as f:
            f.write("# " + "\t".join(header) + "\n")
            for row in rows:
                f.write("\t".join(str(c) for c in row) + "\n")

    write("exe_map_book.tsv", ["row", "level", "high_map", "low_map", "high_remap", "low_remap", "cave_lights",
                               "env_texture_pointer", "env_texture_id", "high_wad", "low_wad", "palette", "dummy"],
          [(i, LEVEL_CODES[i], r["high_map"], r["low_map"], "0x%X" % r["high_remap"], "0x%X" % r["low_remap"],
            r["cave_lights"], "0x%X" % r["env_texture"], tex_id(r["env_texture"]) if r["env_texture"] else -1,
            r["high_wad"], r["low_wad"], r["palette"], int(r["high_remap"] == 0 and r["low_remap"] == 0))
           for i, r in enumerate(v["map_rows"])])
    forms = v["forms"]
    write("exe_theme_book.tsv", ["theme", "name", "high_wad", "form_library", "high_vlo", "death_height", "high_mp_wad",
                                 "high_mp_vlo", "low_wad", "low_vlo", "low_mp_wad", "low_mp_vlo", "valid", "forms"],
          [(i, THEMES[i], t["high_wad"], "0x%X" % t["form_library"], t["high_vlo"], t["death_height"], t["high_mp_wad"],
            t["high_mp_vlo"], t["low_wad"], t["low_vlo"], t["low_mp_wad"], t["low_mp_vlo"],
            int(t["high_vlo"] != 0 or t["low_vlo"] != 0 or t["form_library"] != 0), len(forms.get(i, [])))
           for i, t in enumerate(v["themes"])])
    rows = []
    for theme in sorted(forms):
        for e in forms[theme]:
            form_name = name(form_names, e["global"])
            entity = name(entity_names, e["entity_type"])
            if overrides is not None and form_name in overrides.values and overrides.values[form_name] in entity_names:
                entity = overrides.values[form_name]
            death = DEATH_TYPES[e["death"]] if 0 <= e["death"] < len(DEATH_TYPES) else ""
            rows.append((THEMES[theme], e["local"], e["global"], form_name, e["entity_type"], entity, e["id"], e["script"],
                         e["flags"], "0x%X" % e["collision"], e["radius2"], e["death"], death, "0x%X" % e["bonus"]))
    write("exe_forms.tsv", ["theme", "local_id", "global_id", "form", "entity_type", "entity", "model_id", "script",
                            "flags", "collision_callback", "radius_squared", "death_type", "death", "bonus_callback"], rows)
    write("exe_remaps.tsv", ["position", "name", "file_offset", "resource_id", "count", "ids_sha256", "first_id", "last_id"],
          [(i, r["name"], "0x%X" % r["offset"], r["resource"], len(r["ids"]), digest(r["ids"]),
            r["ids"][0] if r["ids"] else "", r["ids"][-1] if r["ids"] else "") for i, r in enumerate(v["remaps"])])
    write("exe_scripts.tsv", ["index", "name", "pointer", "commands", "words", "words_sha256", "first_command", "last_command"],
          [(i, name(script_names, i), "0x%X" % s["pointer"], len(s["commands"]), len(s["stream"]), digest(s["stream"]),
            s["commands"][0] if s["commands"] else "", s["commands"][-1] if s["commands"] else "")
           for i, s in enumerate(v["scripts"])])
    write("exe_music.tsv", ["level", "code", "track", "track_name"],
          [(i, LEVEL_CODES[i], t, MUSIC_TRACKS.get(t, "")) for i, t in enumerate(v["music"])])
    rows = []
    for table, entries_ in zip(("arcade", "race"), v["level_tables"]):
        for pos, r in enumerate(entries_):
            rows.append([table, pos] + r[:6] + ["0x%X" % p for p in r[6:]] + [",".join(str(tex_id(p)) for p in r[6:])])
    write("exe_level_select.tsv", ["table", "position", "level", "world", "stack_position", "theme", "local_level",
                                   "levels_in_world", "world_selectable_image", "world_visited_image",
                                   "world_not_tried_image", "level_image", "level_name_image", "ingame_level_name_image",
                                   "texture_ids"], rows)
    rows = []
    for table, entries_ in zip(("low_poly", "high_poly") if v["low_poly"] else ("demos",), v["demo_tables"]):
        for pos, (level, demo, unlock) in enumerate(entries_):
            rows.append((table, pos, level, LEVEL_CODES[level] if 0 <= level < len(LEVEL_CODES) else "", demo,
                         entries[demo]["path"].split("\\")[-1] if 0 <= demo < len(entries) else "", unlock))
    write("exe_demos.tsv", ["table", "position", "level", "code", "demo_resource", "demo_name", "unlock_level"], rows)
    write("exe_pickups.tsv", ["index", "fly_type", "pointer", "glow_colour", "sprite_size", "frames", "frame_texture_ids"],
          [(i, FLY_TYPES[i], "0x%X" % p["pointer"], "0x%06X" % (p["glow"] & 0xFFFFFFFF), p["size"], len(p["frames"]),
            ",".join(str(tex_id(f)) for f in p["frames"])) for i, p in enumerate(v["pickups"])])
    with open(os.path.join(out_dir, "exe_summary.txt"), "w", newline="\n") as f:
        facts = [
            ("map_book_rows", len(v["map_rows"])),
            ("themes", len(v["themes"])),
            ("forms", sum(len(x) for x in forms.values())),
            ("bmp_pointers", len(bmp)),
            ("bmp_pointers_sha256", digest(bmp)),
            ("bmp_pointers_first", "0x%X" % bmp[0]),
            ("bmp_pointers_last", "0x%X" % bmp[-1]),
            ("bmp_pointers_min", "0x%X" % min(bmp)),
            ("bmp_pointers_max", "0x%X" % max(bmp)),
            ("bmp_pointers_end", "0x%X" % v["bmp_end"]),
            ("remaps", len(v["remaps"])),
            ("remap_ids", sum(len(r["ids"]) for r in v["remaps"])),
            ("remap_span_offset", "0x%X" % v["remap_span"][0]),
            ("remap_span_length", v["remap_span"][1]),
            ("scripts", len(v["scripts"])),
            ("script_commands", sum(len(s["commands"]) for s in v["scripts"])),
            ("music_entries", len(v["music"])),
            ("arcade_entries", len(v["level_tables"][0]) - 1),
            ("race_entries", len(v["level_tables"][1]) - 1),
            ("demo_table_offset", "0x%X" % v["demo_offset"]),
            ("demo_low_poly", int(v["low_poly"])),
            ("demo_entries", len(v["demo_tables"][-1]) if v["demo_tables"] else 0),
            ("pickups", len(v["pickups"])),
        ]
        for key, value in facts:
            f.write("%s=%s\n" % (key, value))


if __name__ == "__main__":
    sys.exit(main())

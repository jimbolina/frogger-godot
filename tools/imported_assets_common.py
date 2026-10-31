"""Shared plumbing for the imported-asset golden generators (tests/golden/specs/imported-assets.md).

Argument handling, lazy archive access, list digests and the write-or-check
step. Format readers live in the make_golden_* modules this imports; nothing
here reads Godot output.
"""

import argparse
import difflib
import hashlib
import os
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_golden_exe_tables import CFG_ROOT, Exe, java_int, parse_cfg
from make_golden_manifest import FLAG_GROUP_ACCESS, SECTOR_SIZE, is_compressed, pp20_unpack, read_mwi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FACTS_DIR = os.path.join(ROOT, "tests", "golden", "pc-retail-v3.0e")
VERSION = "pc-retail-v3.0e"


def list_digest(values):
    """The shared list digest; '-' for an empty list."""
    if not values:
        return "-"
    return hashlib.sha256(",".join(str(v) for v in values).encode("ascii")).hexdigest()


def multiset_digest(digests):
    """Digest of a sorted list of digests, so the order of the items does not matter; '-' when empty."""
    return list_digest(sorted(digests))


def arguments(description, output_name, extra=None):
    """Parses --data-dir, --output and --check, plus any options added by extra(parser)."""
    parser = argparse.ArgumentParser(description=description, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data-dir", default=os.environ.get("FROGGER_DATA_DIR", ""),
                        help="folder with FROGGER.EXE and FROGPSX.MWD (default: $FROGGER_DATA_DIR)")
    parser.add_argument("--output", default=os.path.join(FACTS_DIR, output_name),
                        help="file to write (default: tests/golden/pc-retail-v3.0e/%s)" % output_name)
    parser.add_argument("--check", action="store_true", help="compare with --output instead of writing it")
    if extra is not None:
        extra(parser)
    args = parser.parse_args()
    if not args.data_dir:
        parser.error("no retail folder: pass --data-dir or set FROGGER_DATA_DIR")
    return args


def tsv(header, rows):
    """TSV text with a '# ' header line and LF line ends."""
    lines = ["# " + "\t".join(header)]
    lines.extend("\t".join(str(c) for c in row) for row in rows)
    return "\n".join(lines) + "\n"


def finish(args, text, summary):
    """Writes text to args.output, or with --check compares it and exits non-zero on a difference."""
    if args.check:
        old = open(args.output, encoding="utf-8").read() if os.path.exists(args.output) else ""
        if old != text:
            diff = list(difflib.unified_diff(old.splitlines(True), text.splitlines(True), args.output, "generated", n=0))
            sys.stdout.writelines(diff[:80])
            print("%s: committed facts differ from the generator" % args.output)
            sys.exit(1)
        print("%s: committed facts match the generator (%s)" % (args.output, summary))
        return
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w", newline="\n", encoding="utf-8") as f:
        f.write(text)
    print("wrote %s (%s)" % (args.output, summary))


class Archive:
    """The retail EXE, its MWI index and FROGPSX.MWD, decoded one resource at a time on request."""

    def __init__(self, data_dir, version=VERSION):
        self.version = parse_cfg(os.path.join(CFG_ROOT, "versions", version + ".cfg"))
        self.cfg = {k: java_int(v.strip()) for k, v in self.version.values.items()
                    if k in ("mwiOffset", "mwiLength", "mapBook", "themeBook", "ramOffset", "musicAddress",
                             "txl_sky_land", "bmpPointerAddress", "arcadeLevelAddress", "pickupData", "scripts")}
        self.exe_bytes = open(os.path.join(data_dir, "FROGGER.EXE"), "rb").read()
        self.mwd = open(os.path.join(data_dir, "FROGPSX.MWD"), "rb").read()
        self.exe = Exe(self.exe_bytes, self.cfg["ramOffset"])
        start = self.cfg["mwiOffset"]
        self.entries = read_mwi(self.exe_bytes[start:start + self.cfg["mwiLength"]])
        self._cache = {}
        self._wad_children = None

    def name(self, rid):
        """MWIResourceEntry.getDisplayName: the path without its folders."""
        if not 0 <= rid < len(self.entries):
            return ""
        return self.entries[rid]["path"].split("\\")[-1].split("/")[-1]

    def find(self, name):
        """The first resource id with display name name (case-insensitive), or -1."""
        wanted = name.upper()
        for e in self.entries:
            if self.name(e["index"]).upper() == wanted:
                return e["index"]
        return -1

    def resource(self, rid):
        """Decompressed bytes of resource rid, from the MWD or from the first WAD that carries it."""
        if rid in self._cache:
            return self._cache[rid]
        e = self.entries[rid]
        if e["flags"] & FLAG_GROUP_ACCESS:
            self.wad_children()
            if rid not in self._cache:
                raise KeyError("resource %d is in no WAD" % rid)
            return self._cache[rid]
        start = e["sector"] * SECTOR_SIZE
        raw = self.mwd[start:start + (e["packed"] if is_compressed(e["flags"]) else e["unpacked"])]
        data = pp20_unpack(raw)[0] if is_compressed(e["flags"]) else raw
        self._cache[rid] = data
        return data

    def wad_children(self):
        """{wad resource id: [(child resource id, type id), ...]} for every WAD, caching each child's bytes."""
        if self._wad_children is not None:
            return self._wad_children
        result = {}
        for e in self.entries:
            if e["type"] != -1 or (e["flags"] & FLAG_GROUP_ACCESS):
                continue
            data = self.resource(e["index"])
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
                self._cache.setdefault(rid, child)
                pos += size + (-(pos + size)) % 4
            result[e["index"]] = children
        self._wad_children = result
        return result

    def texture_banks(self):
        """[(resource id, bytes)] of every 2GRP texture bank: MWI types 0 and 1 and every WAD child, by id."""
        found = {}
        for rid, kids in self.wad_children().items():
            for child, _type in kids:
                if self.resource(child)[:4] == b"2GRP":
                    found[child] = self.resource(child)
        for e in self.entries:
            if e["type"] in (0, 1) and not e["flags"] & FLAG_GROUP_ACCESS and self.resource(e["index"])[:4] == b"2GRP":
                found[e["index"]] = self.resource(e["index"])
        return sorted(found.items())

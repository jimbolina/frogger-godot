#!/usr/bin/env python3
"""Build the golden container manifest for a retail Frogger PC install.

This is an independent, standard-library-only reading of the containers the
Godot code parses (the MWI index inside FROGGER.EXE, the FROGPSX.MWD archive,
PowerPacker "PP20" compression and the WAD bundles inside the MWD). The Godot
tests compare their own output against the files this script writes, so the
two implementations must stay independent: this script never imports or runs
anything from the Godot project.

Only facts are written (names, sizes, flags, counts and SHA-256 digests); no
byte of the game's data is copied into the output.

Besides writing the manifest, the script cross-checks itself against the
values the game's own build tools stored in the index:

  * every decompressed size equals the MWI's unpacked size, and
  * every recomputed PowerPacker "safety margin" (the in-place decompression
    headroom, computed the way FrogLord's PP20Unpacker does) equals the
    margin byte stored in the MWI.

Usage:
    python3 tools/golden/make_golden_manifest.py <dir with FROGGER.EXE and FROGPSX.MWD> <out dir>
        [--mwi-offset 0x8AE20] [--mwi-length 48840]
"""

import argparse
import collections
import hashlib
import os
import struct
import sys
import time
import zlib

SECTOR_SIZE = 2048
FLAG_SINGLE_ACCESS = 1 << 0
FLAG_GROUP_ACCESS = 1 << 1
FLAG_IS_GROUP = 1 << 2
FLAG_AUTOMATIC_COMPRESSION = 1 << 4
FLAG_MANUAL_COMPRESSION = 1 << 5
NO_NAME = 0xFFFFFFFF
PP20_SAFETY_MARGIN_CONSTANT = 4


class Pp20Error(Exception):
    pass


def pp20_unpack(data):
    """Decompress a PP20 stream. Returns (bytes, safety_margin_words).

    The stream is read backwards from its end (excluding the 4-byte size
    trailer), least significant bit of each byte first; multi-bit fields are
    assembled most significant bit first. Output is produced back to front.
    """
    if len(data) <= 11 or data[:4] != b"PP20":
        raise Pp20Error("not a PP20 stream")
    offset_bits = list(data[4:8])
    skip = data[-1]
    out_len = (data[-4] << 16) | (data[-3] << 8) | data[-2]
    body = data[:-4]
    bits = "".join(format(b, "08b")[::-1] for b in reversed(body))
    total_bits = len(bits)
    pos = skip
    out = bytearray(out_len)
    out_pos = out_len
    data_len = len(data)
    margin = 0

    def take(n):
        nonlocal pos
        if n == 0:
            return 0
        if pos + n > total_bits:
            raise Pp20Error("stream ran out of bits")
        value = int(bits[pos:pos + n], 2)
        pos += n
        return value

    def note_margin():
        nonlocal margin
        byte_pos = 4 + pos // 8
        writer_from_end = out_len - out_pos
        reader_from_end = out_len - (data_len - PP20_SAFETY_MARGIN_CONSTANT - 1) + byte_pos
        current = writer_from_end - reader_from_end
        if current > margin:
            margin = current

    while out_pos > 0:
        if take(1) == 0:
            count = 1
            while True:
                inc = take(2)
                if inc != 3:
                    break
                count += 3
            count += inc
            note_margin()
            if count > out_pos:
                raise Pp20Error("literal run overflows the output")
            for _ in range(count):
                out_pos -= 1
                out[out_pos] = take(8)
        if out_pos > 0:
            level = take(2)
            extra = level == 3
            if extra and take(1) == 0:
                nbits = 7
            else:
                nbits = offset_bits[level]
            off = take(nbits)
            length = level + 2
            if extra:
                while True:
                    more = take(3)
                    length += more
                    if more != 7:
                        break
            note_margin()
            if length > out_pos:
                raise Pp20Error("back reference out of range")
            for _ in range(length):
                src = out_pos + off
                if src >= out_len:
                    raise Pp20Error("back reference out of range")
                out[out_pos - 1] = out[src]
                out_pos -= 1
    return bytes(out), 2 + margin // 4


def read_mwi(blob):
    """Parse the fixed 32-byte entries, then resolve their blob-relative names."""
    entries = []
    cursor = 0
    lowest_name = len(blob)
    while cursor < lowest_name and cursor + 32 <= len(blob):
        (name_ptr, flags, type_id, sector, rt0, rt1, packed, unpacked_word) = struct.unpack_from("<8I", blob, cursor)
        if rt0 or rt1:
            raise ValueError("entry %d has non-zero runtime pointers" % len(entries))
        entries.append({
            "index": len(entries),
            "name_ptr": name_ptr,
            "flags": flags,
            "type": struct.unpack("<i", struct.pack("<I", type_id))[0],
            "sector": sector,
            "packed": packed,
            "unpacked": unpacked_word & 0xFFFFFF,
            "margin": unpacked_word >> 24,
        })
        if name_ptr != NO_NAME:
            lowest_name = min(lowest_name, name_ptr)
        cursor += 32
    for e in entries:
        if e["name_ptr"] == NO_NAME:
            e["path"] = ""
        else:
            end = blob.index(b"\0", e["name_ptr"])
            e["path"] = blob[e["name_ptr"]:end].decode("ascii")
    return entries


def is_compressed(flags):
    return (flags & (FLAG_AUTOMATIC_COMPRESSION | FLAG_MANUAL_COMPRESSION)) != 0


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("data_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--mwi-offset", default="0x8AE20")
    ap.add_argument("--mwi-length", default="48840")
    args = ap.parse_args()
    mwi_offset = int(args.mwi_offset, 0)
    mwi_length = int(args.mwi_length, 0)

    exe_path = os.path.join(args.data_dir, "FROGGER.EXE")
    mwd_path = os.path.join(args.data_dir, "FROGPSX.MWD")
    exe = open(exe_path, "rb").read()
    mwd = open(mwd_path, "rb").read()
    if mwd[:4] != b"DAWM" or mwd[4:8] != b"\0\0\0\0":
        sys.exit("FROGPSX.MWD: bad header")
    started = time.time()
    entries = read_mwi(exe[mwi_offset:mwi_offset + mwi_length])

    problems = []
    data_by_index = {}
    for e in entries:
        if e["flags"] & FLAG_GROUP_ACCESS:
            continue
        start = e["sector"] * SECTOR_SIZE
        size = e["packed"] if is_compressed(e["flags"]) else e["unpacked"]
        raw = mwd[start:start + size]
        if len(raw) != size:
            problems.append("entry %d: truncated in the MWD" % e["index"])
            continue
        if is_compressed(e["flags"]):
            out, margin = pp20_unpack(raw)
            if margin != e["margin"]:
                problems.append("entry %d: safety margin %d, MWI says %d" % (e["index"], margin, e["margin"]))
        else:
            out = raw
        if len(out) != e["unpacked"]:
            problems.append("entry %d: %d bytes, MWI says %d" % (e["index"], len(out), e["unpacked"]))
        data_by_index[e["index"]] = out
        print("\r%d/%d" % (e["index"] + 1, len(entries)), end="", file=sys.stderr, flush=True)
    print(file=sys.stderr)

    wad_rows = []
    child_digest = {}
    child_copies = collections.Counter()
    for e in entries:
        if e["type"] != -1 or e["index"] not in data_by_index:
            continue
        wad = data_by_index[e["index"]]
        pos = 0
        child_pos = 0
        while True:
            rid, ctype, csize, ccount = struct.unpack_from("<iiii", wad, pos)
            pos += 16
            if rid == -1:
                if (ctype, csize, ccount) != (0, 0, 0):
                    problems.append("WAD %d: terminator not zero-filled" % e["index"])
                break
            child = wad[pos:pos + csize]
            pos += csize
            pad = (-pos) % 4
            if wad[pos:pos + pad] != b"\0" * pad:
                problems.append("WAD %d child %d: non-zero padding" % (e["index"], child_pos))
            pos += pad
            child_entry = entries[rid]
            packed_child = child[:4] == b"PP20" and len(child) > 11
            if packed_child != is_compressed(child_entry["flags"]):
                problems.append("WAD %d child %d: PP20 marker disagrees with the MWI flags" % (e["index"], child_pos))
            if packed_child:
                out, margin = pp20_unpack(child)
                if margin != child_entry["margin"]:
                    problems.append("WAD child %d: safety margin %d, MWI says %d" % (rid, margin, child_entry["margin"]))
            else:
                out = child
            if len(out) != child_entry["unpacked"]:
                problems.append("WAD child %d: %d bytes, MWI says %d" % (rid, len(out), child_entry["unpacked"]))
            if not (child_entry["flags"] & FLAG_GROUP_ACCESS):
                problems.append("WAD child %d lacks the group-access flag" % rid)
            digest = sha(out)
            if rid in child_digest and child_digest[rid] != digest:
                problems.append("resource %d differs between the WADs that carry it" % rid)
            child_digest[rid] = digest
            child_copies[rid] += 1
            wad_rows.append((e["index"], child_pos, rid, ctype, csize, ccount, int(packed_child), len(out), digest))
            child_pos += 1
        if pos != len(wad):
            problems.append("WAD %d: %d trailing bytes" % (e["index"], len(wad) - pos))
    for e in entries:
        if (e["flags"] & FLAG_GROUP_ACCESS) and e["index"] not in child_digest:
            problems.append("group-access entry %d is in no WAD" % e["index"])
    elapsed = time.time() - started

    os.makedirs(args.out_dir, exist_ok=True)
    with open(os.path.join(args.out_dir, "mwi_entries.tsv"), "w", newline="\n") as f:
        f.write("# index\tpath\ttype_id\tflags\tsector\tpacked_size\tunpacked_size\tsafety_margin_words\twad_copies\tsha256\n")
        for e in entries:
            if e["index"] in data_by_index:
                digest = sha(data_by_index[e["index"]])
            else:
                digest = child_digest.get(e["index"], "-")
            copies = child_copies[e["index"]]
            f.write("%d\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\n" % (
                e["index"], e["path"], e["type"], e["flags"], e["sector"], e["packed"], e["unpacked"], e["margin"], copies, digest))
    with open(os.path.join(args.out_dir, "wad_children.tsv"), "w", newline="\n") as f:
        f.write("# wad_index\tchild_position\tresource_id\ttype_id\tstored_size\tfile_count\tpp20\tunpacked_size\tsha256\n")
        for row in wad_rows:
            f.write("\t".join(str(v) for v in row) + "\n")
    types = collections.Counter(e["type"] for e in entries)
    with open(os.path.join(args.out_dir, "summary.txt"), "w", newline="\n") as f:
        f.write("exe_size=%d\n" % len(exe))
        f.write("exe_crc32=%d\n" % zlib.crc32(exe))
        f.write("exe_sha256=%s\n" % sha(exe))
        f.write("mwd_size=%d\n" % len(mwd))
        f.write("mwd_sha256=%s\n" % sha(mwd))
        f.write("mwi_offset=%d\nmwi_length=%d\n" % (mwi_offset, mwi_length))
        f.write("mwi_entries=%d\n" % len(entries))
        f.write("mwd_resources=%d\n" % len(data_by_index))
        f.write("compressed_resources=%d\n" % sum(1 for e in entries if is_compressed(e["flags"])))
        f.write("wads=%d\n" % sum(1 for e in entries if e["type"] == -1))
        f.write("wad_children=%d\n" % len(wad_rows))
        f.write("distinct_wad_children=%d\n" % len(child_digest))
        f.write("pp20_wad_children=%d\n" % sum(r[6] for r in wad_rows))
        for t in sorted(types):
            f.write("entries_of_type[%d]=%d\n" % (t, types[t]))
    print("entries=%d wads=%d children=%d in %.1f s" % (len(entries), sum(1 for e in entries if e["type"] == -1), len(wad_rows), elapsed))
    if problems:
        print("CROSS-CHECK FAILURES:\n  " + "\n  ".join(problems[:50]), file=sys.stderr)
        return 1
    print("cross-checks: all sizes and safety margins match the MWI")
    return 0


if __name__ == "__main__":
    sys.exit(main())

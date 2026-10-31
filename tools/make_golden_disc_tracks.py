#!/usr/bin/env python3
"""Golden facts for the Redbook music tracks of the retail disc image.

Reads the Alcohol 120% table (.mds) with the layout and checks that
archive/source/sound/disc_audio.gd documents: one CD session, track 1 data,
later tracks audio, 2352-byte sectors laid out contiguously from offset 0,
the last ending at the .mdf's size. Each audio track's raw sectors (signed
16-bit little-endian stereo at 44100 Hz) are streamed from the .mdf, never
loaded whole, and described by frame count, seconds and SHA-256. The music
column lists the levels whose entry in the executable's music table plays
the track.

Usage:
    python3 tools/make_golden_disc_tracks.py [--data-dir DIR] [--disc FILE.mds] [--output FILE] [--check]
"""

import hashlib
import os
import struct
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from imported_assets_common import Archive, arguments, finish, tsv
from make_golden_exe_tables import LEVEL_CODES, MUSIC_TRACKS, read_music

SECTOR = 2352
FRAME_BYTES = 4
RATE = 44100
MODE_DATA, MODE_AUDIO = 0xEC, 0xA9
CHUNK = 8 * 1024 * 1024


def parse_mds(table):
    """Track rows (number, mode, sector size, start sector, start offset, length in sectors) of a validated table."""
    if table[:16] != b"MEDIA DESCRIPTOR" or table[16:18] != b"\x01\x05":
        raise ValueError("not a version 1.5 Media Descriptor table")
    medium, sessions = struct.unpack_from("<HH", table, 0x12)
    if medium != 1 or sessions != 1:
        raise ValueError("a CD with exactly one session is required")
    session = struct.unpack_from("<I", table, 0x50)[0]
    block_count = table[session + 0x0A]
    first, last = struct.unpack_from("<HH", table, session + 0x0C)
    blocks = struct.unpack_from("<I", table, session + 0x14)[0]
    tracks = []
    for index in range(block_count):
        block = blocks + index * 80
        point = table[block + 4]
        if 0xA0 <= point <= 0xA2:
            continue
        extra = struct.unpack_from("<I", table, block + 0x0C)[0]
        tracks.append({"number": point, "mode": table[block], "sector_size": struct.unpack_from("<H", table, block + 0x10)[0],
                       "start_sector": struct.unpack_from("<i", table, block + 0x24)[0],
                       "start_offset": struct.unpack_from("<Q", table, block + 0x28)[0],
                       "length": struct.unpack_from("<I", table, extra + 4)[0]})
    offset = 0
    for index, t in enumerate(tracks):
        if t["number"] != index + 1 or t["mode"] != (MODE_DATA if index == 0 else MODE_AUDIO) or t["sector_size"] != SECTOR:
            raise ValueError("track %d: unexpected number, mode or sector size" % t["number"])
        if t["start_offset"] != offset or t["length"] <= 0:
            raise ValueError("track %d is not contiguous" % t["number"])
        offset += t["length"] * SECTOR
    if len(tracks) < 2 or (first, last) != (1, len(tracks)):
        raise ValueError("session range %d-%d does not match %d tracks" % (first, last, len(tracks)))
    return tracks, offset


def track_digest(path, start, size):
    """SHA-256 of size bytes of path from start, read in chunks."""
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        f.seek(start)
        left = size
        while left:
            chunk = f.read(min(CHUNK, left))
            if not chunk:
                raise ValueError("%s ends inside a track" % path)
            digest.update(chunk)
            left -= len(chunk)
    return digest.hexdigest()


def extra_options(parser):
    parser.add_argument("--disc", default=os.environ.get("FROGGER_DISC", ""),
                        help="the .mds table, its .mdf beside it (default: $FROGGER_DISC)")


def main():
    args = arguments(__doc__, "disc_tracks.tsv", extra_options)
    if not args.disc:
        sys.exit("no disc image: pass --disc or set FROGGER_DISC")
    started = time.time()
    mds = args.disc if args.disc.lower().endswith(".mds") else os.path.splitext(args.disc)[0] + ".mds"
    mdf = os.path.splitext(mds)[0] + ".mdf"
    if not os.path.exists(mdf):
        mdf = os.path.splitext(mds)[0] + ".MDF"
    tracks, end = parse_mds(open(mds, "rb").read())
    if os.path.getsize(mdf) != end:
        raise ValueError("%s is %d bytes, its table ends at %d" % (mdf, os.path.getsize(mdf), end))
    archive = Archive(args.data_dir)
    music = read_music(archive.exe, archive.cfg["musicAddress"])
    rows = []
    for t in tracks[1:]:
        size = t["length"] * SECTOR
        frames = size // FRAME_BYTES
        levels = [LEVEL_CODES[level] for level, number in enumerate(music) if number == t["number"]]
        rows.append((t["number"], MUSIC_TRACKS.get(t["number"], "-"), t["start_sector"], t["length"], frames,
                     "%.3f" % (frames / RATE), track_digest(mdf, t["start_offset"], size), ",".join(levels) or "-"))
    unknown = sorted({n for n in music if not 2 <= n <= len(tracks)})
    if unknown:
        raise ValueError("the music table names tracks %s that the disc lacks" % unknown)
    text = tsv(["track", "name", "first_sector", "sectors", "frames", "seconds", "pcm_sha256", "music_levels"], rows)
    finish(args, text, "%d audio tracks, %.1f s" % (len(rows), time.time() - started))


if __name__ == "__main__":
    main()

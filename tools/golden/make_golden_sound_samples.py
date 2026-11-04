#!/usr/bin/env python3
"""Golden facts for every sound-effect sample the importer turns into a WAV.

The executable's sound tables name each bank's header and body resources;
each present header row is one mono sample. Its PCM is widened to signed
16-bit little-endian (16-bit rows as stored; unsigned 8-bit rows as
(u - 128) << 8, the rule of make_golden_sound_playback.py's pcm group) and
described by its frame count and SHA-256. The imported WAV plays at the
frozen 11025 Hz mix rate whatever the header's rate; both are listed.

Names come from FrogLord's sound list of the build (sections appended to the
main list in file order).

Usage:
    python3 tools/golden/make_golden_sound_samples.py [--data-dir DIR] [--output FILE] [--check]
"""

import hashlib
import os
import struct
import sys
import time
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden.imported_assets_common import Archive, arguments, finish, tsv
from tools.golden.make_golden_exe_tables import name_list
from tools.golden.make_golden_sound_tables import facts as sound_table_facts

BANKS = 0x6E890
BANK_COUNT = 12
SAMPLES = 0x6E938
SAMPLE_COUNT = 174
MIX_RATE = 11025


def pcm16(raw, bits):
    """Signed 16-bit little-endian PCM of a header row's span."""
    if bits == 16:
        return bytes(raw)
    if bits == 8:
        return b"".join(struct.pack("<h", (b - 128) << 8) for b in raw)
    raise ValueError("unsupported %d-bit PCM" % bits)


def main():
    args = arguments(__doc__, "sound_samples.tsv")
    started = time.time()
    archive = Archive(args.data_dir)
    exe = archive.exe_bytes
    names, _sections, _cfg = name_list("sounds", archive.version.values["soundList"].strip())
    banks = [struct.unpack_from("<ii", exe, BANKS + 12 * i) for i in range(BANK_COUNT)]
    sample_bank = [struct.unpack_from("<I8H", exe, SAMPLES + 32 * i)[1] for i in range(SAMPLE_COUNT)]
    rows = []
    for bank, (header_id, body_id) in enumerate(banks):
        if header_id < 0:
            continue
        header = archive.resource(header_id)
        body = archive.resource(body_id)
        count = struct.unpack_from("<i", header, 0)[0]
        for sound_id in range(count):
            present, offset, size, one, two, rate, bits = struct.unpack_from("<7i", header, 4 + 28 * sound_id)
            if present != 1:
                continue
            if (one, two) != (1, 1) or bits not in (8, 16) or offset < 0 or size <= 0 or offset + size > len(body) or size % (bits // 8):
                raise ValueError("bank %d sound %d: invalid header row" % (bank, sound_id))
            if sound_id >= SAMPLE_COUNT or sample_bank[sound_id] != bank:
                raise ValueError("bank %d holds sound %d, which the sample table puts elsewhere" % (bank, sound_id))
            pcm = pcm16(body[offset:offset + size], bits)
            name = names[sound_id] if sound_id < len(names) else ""
            rows.append((sound_id, bank, archive.name(body_id), name, bits, rate, len(pcm) // 2, MIX_RATE,
                         hashlib.sha256(pcm).hexdigest()))
    rows.sort()
    table_rows = sum(len(h["rows"]) for h in sound_table_facts(Path(args.data_dir))["headers"])
    if table_rows != len(rows):
        raise ValueError("%d samples, but the sound tables list %d present rows" % (len(rows), table_rows))
    text = tsv(["sound_id", "bank", "body", "name", "source_bits", "source_rate", "frames", "rate", "pcm16_sha256"], rows)
    finish(args, text, "%d samples, %.1f s" % (len(rows), time.time() - started))


if __name__ == "__main__":
    main()

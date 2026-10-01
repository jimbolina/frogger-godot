# `pc-retail-v3.0e/`

The container manifest of the PC retail build v3.0e (`FROGGER.EXE` CRC-32
378672750, 748,544 bytes; `FROGPSX.MWD` 16,766,976 bytes).

| File | One row per | Columns |
|---|---|---|
| `mwi_entries.tsv` | MWI entry (746) | index, path, type id, flags, start sector, packed size, unpacked size, safety margin (words), number of WADs carrying it, SHA-256 of its decompressed contents |
| `wad_children.tsv` | file inside a WAD (2,890 rows over 84 WADs; 434 distinct files, some shared by many WADs) | WAD's index, position in the WAD, resource id, type id, stored size, file-count field, PP20-packed (0/1), unpacked size, SHA-256 of its contents |
| `summary.txt` | fact | sizes, CRC-32 and SHA-256 of both files, MWI location, counts per type |

For an entry that lives inside WADs (flag bit 1), the MWD holds no data of
its own; its hash is that of its WAD copy, and every copy was checked to be
identical.

### How it was generated

```
python3 tools/make_golden_manifest.py <folder with FROGGER.EXE and FROGPSX.MWD> tests/golden/pc-retail-v3.0e
```

(Python 3.11, standard library only; 13 s.) The script is an independent
implementation of the MWI, MWD, WAD and PowerPacker formats: it shares no
code with the Godot project and was written from FrogLord's Java sources
(`MillenniumWadIndex`, `MWIResourceEntry`, `MWDFile`, `WADFile`,
`PP20Unpacker`). The Godot code was then made to reproduce every row; the
manifest was never derived from Godot output.

### Why the manifest can be trusted

The script checks itself against numbers the game's own build tools stored
in the index, and refuses to write a clean result if any disagree:

- every decompressed resource and WAD member has exactly the unpacked size
  its MWI entry records;
- for all 210 compressed resources, the PowerPacker "safety margin" (the
  in-place decompression headroom, recomputed the way FrogLord's
  `PP20Unpacker` does) equals the margin byte in the MWI. A decoder with a
  wrong bit order or copy rule could not reproduce these;
- every WAD ends with a zero-filled terminator, pads with zeros, and every
  WAD member's PP20 marker agrees with its MWI compression flag (no WAD
  member is individually compressed in this build);
- every group-access entry (flag bit 1) appears in some WAD, and copies of
  a file shared by several WADs are byte-identical.

[Golden data index and shared rules](../README.md). Commands above run from the repository root.

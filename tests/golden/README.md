# Golden data

Tests in this folder need the retail game files (`FROGGER_DATA_DIR`) and
compare what the Godot code reads with facts recorded here. The recorded
facts are **text only**: names, sizes, flags, counts and SHA-256 digests. No
byte of the game's data is stored.

## `pc-retail-v3.0e/`

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

## EXE tables (`pc-retail-v3.0e/exe_*`)

The game tables decoded from `FROGGER.EXE`, one file per table. Addresses
are written as `0x` hexadecimal program addresses (or file offsets where the
column says so); a texture record address is also given as its **texture
id**, its position in the texture pointer list (-1 when it is not in it).

A **list digest** is the SHA-256 of the list's decimal values joined by
commas, with no spaces: `sha256(",".join(str(v) for v in values))`. Both the
generator and the Godot tests compute it from decoded values, never from raw
bytes.

| File | One row per | Columns |
|---|---|---|
| `exe_map_book.tsv` | level-list row (60) | row, level code, high/low map ids, high/low remap addresses, cave lights, environment texture address and id, high/low WAD ids, palette id, dummy (both remap addresses zero) |
| `exe_theme_book.tsv` | theme (11) | theme, name, the eight WAD/VLO ids, form library address, death height, valid, number of forms |
| `exe_forms.tsv` | form (368) | theme, number in theme, number overall, form name, entity type and name (after FrogLord's overrides), model id, script id, flags, collision callback address, radius squared, death type and name, bonus callback address |
| `exe_remaps.tsv` | texture remap (79), in address order | position, name, file offset, map resource id (-1 = none), id count, list digest of the ids, first and last id |
| `exe_scripts.tsv` | script id (125) | id, name, address, command count, word count (opcodes + arguments), list digest of the words, first and last command name |
| `exe_music.tsv` | level (60) | level, code, CD track, FrogLord's track name |
| `exe_level_select.tsv` | level-select row, including each list's ending row (-1) | list, position, level, world, stack position, theme, level in world, levels in world, six texture record addresses, their texture ids |
| `exe_demos.tsv` | demo row, low-poly list then high-poly list | list, position, level, code, demo resource id and file name, unlock level |
| `exe_pickups.tsv` | bug kind (19) | kind, name, record address, glow colour, sprite size (16.16), frame count, frame texture ids |
| `exe_summary.txt` | fact | counts, the texture pointer list's digest, first/last/min/max and end, the remap span, the demo table offset |

### How it was generated

```
python3 tools/make_golden_exe_tables.py <folder with FROGGER.EXE> tests/golden/pc-retail-v3.0e \
    --c-reference <froggy repository>/engine
```

(Python 3, standard library only; under a second.) The script reads the
tables the way FrogLord's Java sources do (`FroggerGameInstance` and the
classes it calls, `SCGameInstance` for the texture pointers and remaps),
shares no code with the Godot project, and reuses only
`make_golden_manifest.py`'s MWI reader. Table lengths are worked out as
FrogLord does, since the executable stores none: the map book runs up to
the theme book; a theme's form library has as many forms as FrogLord's form
list names for that theme; the texture pointer list runs until a value that
is not a program address; remaps run to a zero id or the next remap; the
script table has one entry per name in FrogLord's script list; the music
list ends at 0xFF; level-select and demo lists end at a row whose level is
-1; the demo table is found by searching for Suburbia 1's row.

### Why the tables can be trusted

The script refuses to report success unless:

- the tables agree with each other: 60 map-book rows of 36 bytes end
  exactly where the theme book starts; the 1,858 texture pointers end
  exactly where the first remap starts; each theme's form count from
  FrogLord's names equals the distance to the next theme's library; the two
  demo lists name the same levels;
- every id in the map and theme books names an MWI entry of the right kind
  (map, WAD, texture bank, palette);
- the offsets agree with those the C port of the game (the `froggy`
  project) documents for this build, found there independently of FrogLord:
  map book 0x70100 + 2,160 bytes, texture pointers 0x77858 + 7,432 bytes
  (1,858 entries), remaps 0x79560 + 7,874 bytes (first remap to the end of
  the last one's ids; FrogLord's zero-terminator rule and the C port's
  "highest texture index used by the map" rule agree on the last remap,
  SWP5, at 117 ids), `txl_sky_land` at 0x7A020, demo lists at 0x83420 and
  0x835C4;
- with `--c-reference`: the C port's four verbatim copies of EXE regions
  (`real_source/pc_resources/pc_exe_tables.c`: MWI, map book, texture
  pointers, remaps) are byte-identical to the executable; its per-level
  music table (`real_source/pc_resources/xa_tunes_pc.c`, rows before its
  first -1) equals the 60 track numbers read here, value by value; its demo
  table offsets (`asset_pipeline/include/frogger_demo_tables.h`) equal the
  ones found by the search. Only numbers were compared; nothing from those
  files is stored here.

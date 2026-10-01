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

## Texture banks (`pc-retail-v3.0e/vlo_*`)

Every PC texture bank (VLO, signature `2GRP`) in the archive: 46 banks,
3,477 images, all stored directly in the MWD (none of the retail banks is
inside a WAD, though both the generator and the Godot side can read one there). No
pixel data is stored: each image is described by its header fields and two
SHA-256 digests of its decoded pixels.

**Decoded pixels, by specification** (both implementations follow this text,
which restates FrogLord's reading of the PC format):

- bytes R, G, B, A per pixel (8 bits each), rows top to bottom, pixels left
  to right, no row padding;
- the file stores each pixel as the bytes A, B, G, R; R, G and B are copied;
- A is 255, except 0 when the image's flag bit 5 ("black is transparent")
  is set and R, G and B are all below 8, i.e. `(R | G | B) & 0xF8 == 0`.
  The stored A byte is ignored (the game never reads it; it is 0 in every
  retail image);
- the **padded** digest covers the whole stored image (padded width x
  height), the texture the game uploads;
- the **unpadded** digest covers only the in-game region, width x height
  starting at `left = (padded width - width) / 2`,
  `top = (padded height - height) / 2`. This is what FrogLord's image
  export writes to PNG (its "no padding" export setting, transparency on).

| File | One row per | Columns |
|---|---|---|
| `vlo_files.tsv` | texture bank (46) | resource id, file name, where it is stored (`mwd` or `wad <id>`), image count, number of FrogLord texture renames |
| `vlo_images.tsv` | image (3,477) | resource id, position in the bank, texture id, VRAM x and y, padded width and height, width and height, u, v, flags, blend mode (bits 8-9 of the page word), page (VRAM y / 256), padded digest, unpadded digest |
| `vlo_summary.txt` | fact | bank and image counts, images with bit 5, fully transparent texels, stored non-zero alpha bytes (0), texels that are near-black but not exactly black (0: the "below 8" and "exactly 0" rules give identical results on retail data), banks inside WADs, renamed textures |

### How it was generated

```
python3 tools/make_golden_vlo.py <folder with FROGGER.EXE and FROGPSX.MWD> tests/golden/pc-retail-v3.0e
```

(Python 3, standard library only; about 15 s.) Written from FrogLord's
`vlo2/VloFile`, `VloImage` and `VloUtils` Java sources, sharing only
`make_golden_manifest.py`'s archive readers. It stops with an error unless
every header passes FrogLord's own load-time checks: headers start at byte
12; every image's pixels start at the next 4-byte boundary with zero bytes
in between; the texture page word equals `page | blend mode << 8`; the
stored u/v equal the image's position in its page plus its padding; and the
padding is the same horizontally and vertically.

## Models (`pc-retail-v3.0e/mof_*`)

Every model file (MOF) of the archive: 434 files, all of them inside WADs.
One is a 4-byte placeholder (`DUMY`), 355 are static models and 78 are
animated models holding 78 static models between them. 22 of the static
models are incomplete: they store their own polygons and take their shape
from another model. No model data is stored: each part is described by its
counts and by digests of its value lists.

Rows describe **what the file itself holds**. An incomplete model's rows
give the counts in its own headers and its own polygons; what it borrows is
in the rows of the model it borrows from. Nothing that FrogLord adds or
changes for display is included.

**Value lists, by specification** (both implementations follow this text).
Each is digested as a list digest (see above); an empty list is written `-`.

- vertices, normals: x, y, z of each vector of the part's first partcel, as
  signed 16-bit values, in stored order;
- bounding box: x, y, z of the 8 corners of the first partcel's box;
- indices: for each polygon in stored order, its type number, then its vertex
  indices, its environment normal indices and its normal indices, each **in
  the order the file stores them** (FrogLord swaps the last two of a quad
  when it loads; the digests do not);
- uvs: for each textured polygon, u then v of each corner in stored order;
- image ids: for each textured polygon, its image id;
- colours: for each polygon, red, green, blue and the code byte;
- hilites: for each hilite, its type, what it is attached to (1 vertex,
  2 polygon) and the index;
- texture animation image ids: the image id of every frame of every texture
  animation of the part, in stored order.

| File | One row per | Columns |
|---|---|---|
| `mof_models.tsv` | model file (434) | resource id, file name, type id, size, kind (`dummy`, `static`, `animated`), first four bytes in hexadecimal, flags, incomplete (0/1), the resource it borrows from (-1 = none), static models, model sets, then totals over its parts: parts, partcels, vertices, normals, polygons, textured polygons, hilites, collision primitives, matrices, flipbook animations, polygons with animated textures, texture animations; number of different image ids, digest of those ids in rising order |
| `mof_parts.tsv` | part (1,009) | resource id, static model inside the file, part, flags, partcels, vertices and normals per partcel, polygons, hilites, collision primitives, matrices, flipbook animations, polygons with animated textures, texture animations, different bounding boxes, polygons of each of the 16 types (comma separated), then the digests in the order listed above |
| `mof_forms.tsv` | form of a level (1,550) | level number and code (`GENERAL` and `GENERAL_MULTIPLAYER` with level -1 stand for the GENERAL forms on their own), theme, form number in its theme, form name, model id, the form's "no model" flag, whether the model comes from the GENERAL WAD, position in the WAD, then for high-poly and for low-poly: the WAD, the resource at that position (-1 = none) and its kind (`none`, `dummy`, `static`, `animated`) |
| `mof_summary.txt` | fact | counts of each kind, totals, polygons of each type, WAD slots of each kind |

Three GENERAL forms (`GEN_BONUS_FROG`, `GEN_BONUS_FLY_GRE`, `GEN_LADYFROG`)
have model id 0, which gives position -128 and so no model. FrogLord
computes the same position.

### How it was generated

```
python3 tools/make_golden_mof.py <folder with FROGGER.EXE and FROGPSX.MWD> tests/golden/pc-retail-v3.0e
```

(Python 3, standard library only; about 3 s.) Written from FrogLord's
`mof2` Java sources (`MRModel`, `MRBaseModelData`, `MRStaticMof`,
`MRMofPart`, `MRMofPartCel`, `MRMofPolygonBlock`, `MRMofPolygon`,
`MRAnimatedMof`, `MRMofHilite`, `MRCollprim`), `SCUtils.makeModel` for which
model an incomplete one borrows from, and `FroggerFormEntry` for which model
a form uses. It shares `make_golden_manifest.py`'s archive readers and
`make_golden_exe_tables.py`'s readers of the level, theme and form tables,
and no code with the Godot project.

### Why the facts can be trusted

The script stops with an error unless every file passes the checks FrogLord
makes when it loads a model:

- the signature fits the kind the flags state;
- the length a model states equals where its last polygon ends and the
  number of bytes present; for an animated file, where its model table ends;
- a static model inside an animated file runs exactly from its own start to
  the start of the next one (FrogLord's rule), and that span equals the
  length the model states for itself (the reference engine's rule);
- the flags of a model and of each part equal what the model holds
  (animated textures, flipbook); an animated file's flags are 0x110008;
- every word the game fills in while running is zero in the file, as are
  the clut and texture page words and the padding of every polygon;
- polygon types are below 16; every hilite and texture animation names a
  vertex or polygon that exists, of the stated type;
- every block of vertices and normals lies inside the model's vector pool,
  on an 8-byte step.

Its totals agree with those the C port of the game documents for this
build, found there independently: 731 static and 136 animated models
counted per WAD slot, and no polygon of the environment-mapped or line
types.

## Animation facts

Generate with `python tools/make_golden_animation.py <retail-folder>
tests/golden/pc-retail-v3.0e`. It uses the existing Python archive readers,
FrogLord's animation format definitions and the C engine's fixed-point
matrix and playback formulas. It shares no animation code with GDScript.
The earlier `mof_*` facts remain unchanged.

All digests use the decimal comma-separated list convention above. Raw
transform lists omit padding. Matrix sample lists contain nine row-major
4.12 basis integers followed by three whole-unit translations, ordered
by frame then part. Geometry includes every effective partcel: vertex
count and XYZ values, normal count and XYZ values, box count and XYZ values.
Incomplete models use their counterpart's geometry and animation data;
their original polygons and raw stored counts remain covered by `mof_*`.

| File | Rows and meaning |
|---|---|
| `animation_xar.tsv` | 78 files: resource, encoding, frame origin, set/transform counts, raw-transform digest, model metadata digest. Metadata is set model/action counts, then each model's static index, part count, flags, box length and XYZ values. |
| `animation_actions.tsv` | 187 actions: resource/static/set/action IDs, cel/part/frame counts, flags, availability, virtual-cel digest, transform-index digest, every sampled pose digest. |
| `animation_parts.tsv` | 1,009 parts: resource/static/part IDs, inheritance flag, effective cel count, geometry digest, ordered flipbook start/count pairs, target type/global polygon index/list index triples, and texture lists (length followed by image/duration pairs). |
| `animation_flipbooks.tsv` | 230 effective actions: resource/static/part/action IDs, start, length and availability. Includes 174 stored actions and the 19 unsafe authored ranges. |
| `animation_texture_cycles.tsv` | 613 targets: resource/static/part/target/list IDs, cycle duration, digest of entry/image pairs after each update through one cycle and its wrap. Zero durations take one update. |
| `animation_summary.txt` | Independent census of models, encodings, transforms, actions, virtual frames, raw flipbooks, unsafe actions and texture targets. |

`test_retail_animation.gd` verifies these against the readers and player.
The separate frog hash test uses the reference driver's FNV-1a over a
32-byte matrix, including its two zero padding bytes: action zero yields
`0x9655a8c6` at viewer tick zero and `0xa933ba38` after 179 further ticks.

On 2026-10-01 each of the six animation files was deliberately corrupted,
one fact at a time. Each run failed only its intended test (one row for
TSV files), and the original bytes were restored in a `finally` block.
Regenerating all six files subsequently reproduced them unchanged.

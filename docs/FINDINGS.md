# Findings

What each phase learned that later phases need. Add to this file at the end of every phase. Numbers are for `pc-retail-v3.0e` unless stated.

## Open questions

| Question | Evidence so far | Settle in |
|---|---|---|
| Is the PC game's logic rate 30 or 25 ticks per second? | The reference engine runs 30: the C source defines 30 logic calls per second and the PC build creates a 33 ms timer. FrogLord's editor converts entity delays to seconds using 25 for the PC release. | P7, against the reference engine's traces and the retail game |
| Does the PC game use the same camera projection distance (256) as the C source sets? | Every reference picture was rendered with 256. Not independently checked against the retail game. | P6 |
| Do image edges show seams on maps under linear filtering? | A texture coordinate of 255 lands on the edge of the in-game part of the image, next to its padding. On models no seam shows (see Models). Map polygons tile the same image side by side, where a seam would show most. | P6 |
| Which general WAD do general models use in a multiplayer level? | FrogLord picks the multiplayer general WAD for a multiplayer map, and this project does the same. Not checked against the running game. | P8 |

## Build detection (P0)

- A FrogLord-saved executable ends in the eight bytes `FROGLORD`. Before them: the config text in UTF-8, a zero byte, a version byte, and the original executable length as a 32-bit integer. The config text names the build.
- Otherwise the build is found by the CRC-32 of the whole executable, matched against `exeChecksum` in FrogLord's version files. The retail executable gives 378672750.
- FrogLord has two config formats: an older one for version files and name lists, and a newer one for the block in a saved executable and for the texture-bank tree. They parse differently, so there are two parsers.
- The PC version files leave out the form, entity and script name lists. FrogLord falls back to `forms` and `entities` `1997-09-12-psx-build57` and `scripts` `1997-09-18-psx-build63`, and so does this project.

## Archives (P1)

| Fact | Value |
|---|---|
| Index entries | 746 |
| WADs | 84 |
| Compressed resources | 210 |
| Resources stored directly in the archive | 312 |
| WAD children | 2,890, of which 434 are distinct |

- No WAD child is compressed on its own.
- The index inside the executable is the authoritative one. FrogLord writes the index back into the executable; the standalone `.MWI` file is a copy.
- Always resolve archive offsets through the loaded index. FrogLord moves and resizes files when it saves.
- Decompressing the whole archive takes about 4 seconds.

## Tables in the executable (P2)

| Table | Count |
|---|---|
| Map book rows | 60, of which 39 have a map |
| Themes | 11; one is empty |
| Forms | 368 across 10 themes |
| Texture remaps | 79, holding 3,811 ids |
| Texture pointers | 1,858 |
| Scripts | 125, with 647 commands |
| Script opcodes | 49 |
| Music entries | 60 |
| Demos | 34 rows in each of two lists |
| Level select | 33 arcade, 5 race |
| Pickups | 19 |

- **Table lengths are not stored.** The map book runs up to the theme book's address. Theme book and pickup sizes come from FrogLord's lists of themes and pickups. The script table's length is the number of names in the script name list, so name lists load before tables.
- **Addresses in the version files are file offsets. Pointers inside tables are memory addresses**; subtract `ramOffset` to get a file offset.
- **The demo table's address is in no version file.** FrogLord searches the executable for it. A FrogLord-saved executable records the address in its appended block.
- **There are two demo lists.** The first is for low-poly levels, the second for high-poly. This project uses the second.
- When reading a FrogLord-saved executable, table reads stay inside the original executable length.
- An unknown music track number is kept as read, so edited executables load.

### Where FrogLord and the reference engine read data differently

This project follows FrogLord in each case. None of them changes a value on retail data.

| Subject | FrogLord | Reference engine |
|---|---|---|
| End of the last remap | Stops at a zero | Uses the map's highest texture index plus one |
| Size of the sky-land remap | 76 ids | 154 bytes, counting the terminator |
| Black-is-transparent test | A pixel is black when the top five bits of each channel are zero | Exact zero |
| Map book rows 4 and 57, which have remap pointers but no map | Skipped | Used as boundaries |
| Which model is incomplete | The first part's partcel pointer is 0x40 | The same, and the model has one part |
| Where a static model inside an animated file ends | At the start of the next one; the last at the model table | At the length the model states |
| How many matrices a part stores | As many as fit before the next section | The highest matrix number its collision shapes use, plus one |
| What a hilite is attached to | A number: 1 vertex, 2 polygon | Flag bits with the same values |

Where they differ on how models **behave**, the reference engine is followed:

| Subject | FrogLord | Reference engine, followed here |
|---|---|---|
| Semi-transparent model polygons on PC retail | Never shown. `MRMofPolygon.isSemiTransparent` answers no for every build after build 8, while its own comment says the game starts doing this at build 11, so the test reads as the wrong way round. | Shown for textures with the translucent flag |
| Lighting of models | None: the polygon's colour is shown | Lit while running, from the map's lights |

## Textures (P3)

| Fact | Value |
|---|---|
| Texture banks | 46, all stored directly in the archive |
| Images | 3,477 |
| Time to decode every bank | About 0.3 seconds, plus 1.8 to read and decompress |

- Decoding is fast enough that no cache of converted textures is needed yet.
- Every image has a padded size (what the game uploads) and an in-game size (what FrogLord exports as PNG). The golden files record a hash of each.
- **In the original, black-is-transparent is a colour key over a whole 256x256 texture page**, not a per-image rule. Rendering has to apply it per page.
- **Texture ids repeat across banks**: the five language banks, the general bank and its high-poly variant, and the low-poly variants. The lookup checks the preferred bank first; otherwise the most recently loaded bank wins, which matches how the game overwrites its pointer table.

## For the map phase (P6)

- A map polygon's texture number is local to the map. The map's remap table turns it into a global texture id (`TextureRemap.global_id()`), and `TextureLibrary.image_for_id()` finds the image. Sky-land polygons use the sky-land remap.
- The theme's texture bank comes from the theme book (`ThemeBookEntry.vlo_id(multiplayer, low_poly)`).
- A polygon's UV bytes are pixel offsets inside the image's in-game region. The original adds the image's page position when it loads a map. In this project's padded textures, a UV maps to `(left padding + u, top padding + v) / padded size`; `TextureBuilder.pixel_rect()` gives the origin.

## Models (P4)

| Fact | Value |
|---|---|
| Model files | 434, all inside WADs: 1 placeholder, 355 static, 78 animated |
| Static models, counting those inside animated files | 433 |
| Incomplete models | 22 |
| Parts | 1,009 |
| Polygons | 15,456, of which 6,425 textured |
| WAD slots | 2,890: 2,023 placeholders, 731 static, 136 animated |
| Time to read every model | About 1.5 seconds; to build every mesh, about 1.7 |

- **What a file is shows in its first bytes, never in its name.** The four `.XMU` files are ordinary static models.
- **A model id is a position in a WAD, and placeholders count.** A level's WAD has a slot for every model of its theme. The slots the level does not use hold the same 4-byte placeholder (resource 188), which fills 2,023 of the 2,890 slots.
- Forms in the general theme, and any form whose model id is 128 or more, use model `id - 128` from the general WAD. Other forms use the level's own WAD from the map book. A multiplayer level uses the multiplayer general WAD. Maps set bit 15 on a form id that refers to the general theme.
- Three general forms (`GEN_BONUS_FROG`, `GEN_BONUS_FLY_GRE`, `GEN_LADYFROG`) have model id 0 and so no model, though only the second is flagged as having none.
- **There are 22 incomplete models, not only the checkpoints.** Checkpoints 2 to 5, multipoints 2 to 5 and the multiplayer frogs 2 to 4, each in a high-poly and a low-poly version. Each takes its shape from the nearest earlier complete model in the index, and differs only in the colours and textures of its polygons.
- **Every static model inside an animated file states its own length, and it equals the distance to the next one.** FrogLord's rule and the reference engine's give the same result on retail data.
- Only two models store matrices for their collision shapes: `JUN_PLANT.XAR` and its low-poly version.
- Only polygon types 0 to 7 occur. There is no environment-mapped polygon and no line.
- **A quad is stored going round its edge.** Its triangles are corners (0, 1, 3) and (1, 2, 3). Texture coordinate k and normal k belong to corner k. FrogLord swaps the last two entries of each list when loading; this project keeps the stored order.
- **Polygons keep their stored corner order in Godot.** Seen by eye on closed models with back-face culling on: the car, the kennel and the logs show no holes and no inside faces.
- **A polygon has one colour whatever its type**, and its normals are only for lighting.
- A texture coordinate is 0 to 255 across the in-game part of the image, with v counted from the top. The game turns it into a whole pixel, `coordinate * size / 255`.
- Each level's high-poly models find all their textures in the general bank and the theme's bank, with one exception: the multiplayer jungle WAD carries the eight plinths of the single-player levels, and some of their textures are not in the multiplayer jungle bank. Such polygons are drawn untextured.
- **No seams at image edges on models**, with nearest or with linear filtering: looked at on the kennel's roof and the turtle's shell, whose polygons meet at image edges.
- Dark models are often dark on purpose. The lower half of each log has polygon colour (7, 22, 51).

### Colours on screen

Measured with `tools/probe_model_shader.gd` on Godot 4.5.1, Compatibility renderer, no environment (NVIDIA GeForce RTX 4070 Ti SUPER). Background (100, 60, 20).

| Case | Expected | Measured |
|---|---|---|
| Texture (200, 120, 40), polygon colour 128 | (200, 120, 40) | (200, 120, 40) |
| Same texture, polygon colour 64 | (100, 60, 20) | (100, 60, 20) |
| Same texture, polygon colour 192 | (200, 120, 40) | (200, 120, 40) |
| Texture (200, 200, 200), polygon colour (32, 64, 128) | (50, 100, 200) | (50, 100, 200) |
| Untextured, polygon colour (90, 160, 30) | (90, 160, 30) | (90, 160, 30) |
| Untextured, polygon colour (4, 8, 16) | (4, 8, 16) | (4, 8, 16) |
| Texture (6, 12, 24), polygon colour 128 | (6, 12, 24) | (6, 12, 24) |
| Transparent texture pixel | background | (100, 60, 20) |
| Translucent, average, texture (200, 120, 40) | (150, 90, 30) | (150, 90, 30) |
| Translucent, add, texture (50, 40, 30) | (150, 100, 50) | (150, 100, 50) |
| Translucent, subtract, texture (50, 40, 30) | (50, 20, 0) | (50, 20, 0) |
| Translucent, add a quarter, texture (200, 120, 40) | (150, 90, 30) | (150, 90, 30) |

- **In the Compatibility renderer a shader's `ALBEDO` is a stored colour value, not linear light.** The renderer converts it to linear light and back before writing it (`drivers/gles3/shaders/scene.glsl` and `tonemap_inc.glsl` in Godot's source).
- **The two conversions are approximations that do not undo each other for dark colours.** Without correction a grey of 8 came out as 1, 20 as 16, 40 as 38; from 64 up the value was unchanged. The shaders now work out beforehand the value that comes out right, and every value from 0 to 255 that was tried comes out exact.
- Mixing with the background happens after the conversion, on stored values, which is what the original did. A renderer that mixes in linear light would give about 0.73 where the original gives 0.5.
- Textures are given to the shader without Godot's colour conversion, and vertex colours reach it unchanged.

### Lighting, for the map phase (P6)

Models are lit while the game runs; nothing is baked into the files. From the original's source (`API.SRC/MR_LIGHT.C`, `MR_VIEW.C`, `mr_stat.c`) and the reference engine:

- `lit = clamp((base * clamp0(ambient + colours * clamp0(directions * normal))) / 4096, 0, 255)`, per channel, where `base` is the polygon's colour, `ambient` is the sum of the ambient lights' colours times 16, `colours` holds each light's colour times 16 and `directions` each light's direction. At most three directional or point lights are used.
- A flat polygon is lit once from its one normal; a gouraud polygon once per corner.
- A level's lights are stored in its map file. The options screens use an ambient light of (0x60, 0x60, 0x60) and one parallel light of (0xA0, 0xA0, 0xC0).
- Lit values can exceed 128, so the stop at full brightness in `min(2 * lit, 255)` matters.
- Cave levels also scale each model's colour by distance from the frog's light, unless the form has the "don't fade colour" flag.

### Semi-transparency

A textured polygon is drawn semi-transparent when its texture has the translucent flag (bit 0), mixed the way the texture's blend mode says. Retail textures only use modes 0 (average) and 1 (add). Untextured polygons are never semi-transparent.

## Model animation (P5)

### Stored data and unsafe records

The retail archive contains 78 XAR files, 28,447 transforms, 187 actions and
4,016 virtual frames. Every XAR has one model set and one model, and uses
standard virtual-cel tables: 41 files use byte matrices and 37 byte
quaternions. The reader also supports short matrices, short quaternions,
scaled byte/short quaternions, multiple sets and authored interpolation;
synthetic files exercise the formats absent from retail.

There are 174 stored flipbook actions (230 after incomplete-model
inheritance). Nineteen readable records point past their partcel arrays:

| Files | Action IDs | Start/count | Available partcels |
|---|---|---|---|
| `GEN_GOLD_FROG.XMR`, `GEN_GOLD_FROG_WIN95.XMR` | 5 | 46/21 | 46 |
| `FOR_SQUIRREL_WIN95.XMR` | 2 | 41/20 | 41 |
| `SKY_SQUADRON.XMR`, `SKY_SQUADRON_WIN95.XMR` | 4, 5, 6, 7, 8 | 8/249 | 29 |
| Same squadron files | 9, 13, 14 | 19/238 | 29 |

These actions stay visible but unavailable. Their ranges are never
repaired. Structural truncation or impossible pointers still reject a
file. An invalid texture list disables only its target, which keeps its
original image. Incomplete models share their counterpart's effective
geometry and animation arrays while retaining their own polygons,
colours and image IDs. Raw stored counts remain separate; P4 facts did
not change.
Undefined scale flag bits are preserved and explicitly reported; as in
FrogLord and C, only bit zero affects sampling. Unsupported structural
format modes fail with a diagnostic.

### Clocks and transforms

`ModelAnimationPlayer` owns counters, independently of nodes and other
instances. It follows `MRAnimUpdateEnvironments`: selection sets cel -1;
the first update reaches zero regardless of the integer update period.
Viewer tick zero includes that initial update. Loop, hold and hide modes
operate on integer ticks. Seeking replays from a full restart; changing
an action leaves the texture counters independent.

Stored quaternions are converted with the C fixed-point formulas without
normalizing them. Matrix entries narrow to signed 16 bits, and scale
left-multiplies the matrix (scales its rows). Old standard virtual-cel
tables are one-based; authored interpolation endpoints are zero-based.
`GameSpace` applies `C * basis * C` and `C * translation / 256`, with
`C = diag(1,-1,-1)`. Part nodes sit beneath the model placement node.

The viewer uses the existing 30 Hz physics clock and three-step catch-up
limit. This adopts the frozen reference's clock for animation; the
retail 25/30 Hz timing investigation remains P7 work.

### Textures and smoothing

The 613 texture targets use the C increment-before-comparison rule.
A duration of one advances on the first update; a zero duration also
advances once on the next update. Each target has its own counters, even
when targets share a list. Polygon indices are global within a part,
not relative to a polygon-type block.

UV pixel offsets come from the original polygon image's dimensions.
Replacement images apply their own padding and padded dimensions to
those offsets. The original image's translucency flag remains in force;
the current image supplies the blend rate. Missing images use the
untextured fallback and are reported. If the original image is missing,
all entries for that target stay untextured because its pixel offsets
cannot be determined, even when a replacement image exists. Animated targets have separate
surfaces and instance-local overrides, with materials prepared during
model construction.

Smooth Motion defaults off. It interpolates transforms and normalized
flipbook blend-shape weights between ticks; images remain discrete.
Pause, step, seek, restart, action/model changes, loops and toggle changes
reset interpolation history. Exact endpoints preserve the sampled
matrices, including their stored scale. Manual interpolation disables
Godot's automatic interpolation on the render subtree. See Godot's
[manual interpolation](https://docs.godotengine.org/en/4.5/tutorials/physics/interpolation/advanced_physics_interpolation.html)
and [ArrayMesh blend-shape](https://docs.godotengine.org/en/4.5/classes/class_arraymesh.html)
documentation. Decoded resources and playback counters remain unchanged
by drawing at different fractions.
Singular transforms (zero scale) use component interpolation between
exact endpoints so optional smoothing never tries to extract an invalid
rotation quaternion.

### Reference capture setup

The unchanged `anim_slice.exe` ran with SDL's dummy driver and an external
`FROGGY_SCREENSHOT_DIR`, passing 10 checks. Its low-poly frog action zero
matches the required part-zero FNV hashes: `0x9655a8c6` on the first render
and `0xa933ba38` after 180 updates. The matrix serialization includes two
zero padding bytes between the nine signed-short basis values and three
signed-int translations.

The driver's camera is `(0,-100,-350)` and model placement `(0,0,1000)`.
Its projection constant is 1000, but `MR_VIEW.C` first scales X by
viewport width/320 and Y by height/256 (the driver's PAL configuration).
At 640x480 the effective focal lengths are 2000 horizontally and 1875
vertically. Godot's reference capture uses FOV `2 * atan(240 / 2000)`
and a reference-only 240/256 scale of model and camera Y. Omitting the
aspect matrix produced a silhouette half the reference's size; using
the NTSC height of 240 left a further vertical mismatch. This calibration
applies to the standalone driver; general map projection remains P6 work.

Authored quaternion interpolation uses analytic trigonometry in place of
the C lookup tables, while preserving integer translation/scale stepping,
short narrowing and the byte-quaternion normalization tolerance. The
synthetic rotation checks allow a few 4.12 units of rounding difference.
All retail actions use standard virtual cels and their matrix digests
match exactly.

### Performance and resource lifetime

One Windows/Godot 4.5.1 headless run measured the following. Build time
includes selecting the model, its textures and conservative action bounds;
tick/draw time covers 180 stepped and 180 smoothed CPU updates. These are
CPU measurements, not GPU frame rates.

| Model | Build (ms) | Tick and pose application (microseconds) |
|---|---:|---:|
| `GEN_FROG.XAR` | 264 | 176 |
| `GEN_FROG_WIN95.XAR` | 178 | 195 |
| `DES_VULTURE.XAR` | 87 | 52 |
| `OPT_TURTLE.XMR` | 93 | 91 |
| `GEN_CHECKPOINT_2.XMR` | 34 | 23 |

Mesh and material identities stayed unchanged throughout all five runs.
The synthetic texture test also kept the total resource count unchanged
over 300 updates while two instances shared the decoded model and mesh.
The full high-poly WAD build check constructs both static and animated
paths (435 model occurrences, 25,774 triangles) in about 3.7 seconds.

### Visual inspection, 2026-10-01

Captures and comparison reports are outside the repository in
`%TEMP%/frogger-p5-captures`; C driver captures are in
`%TEMP%/frogger-godot-p5-reference`. The inspected contact sheets cover:

- Low-poly frog action zero at ticks 0, 60, 120 and 179 beside C. Pose,
  silhouette and orientation agree. Silhouette intersection-over-union
  is 97.15% for the first three captures and 97.76% at 179; foreground
  bounds differ by at most two pixels. Lighting and depth-order details
  differ, as expected for this unlit viewer.
- High-poly frog at ticks 0, 2 and 5, vulture at 0, 10 and 20, turtle and
  incomplete checkpoint at 0, 6 and 12. Each has stepped and smoothed
  captures, with fraction 0.5 for the nonzero smoothed ticks. The low-poly
  frog also has an intermediate smoothed pose at tick 179. Parts remain
  connected, wing motion and flipbook poses are coherent, and the turtle's
  texture animation accompanies its geometry. Inherited checkpoint
  geometry keeps its own orange appearance.
- `SKY_SQUADRON` still displays and plays a safe action while reporting
  its eight unavailable actions. The compact diagnostic count and hover
  details keep the model area clear.

The animation controls required a smaller dedicated drawing area and
camera offset so poses do not overlap the panel or facts. Camera bounds
cover the selected action and remain fixed throughout playback. The
shader probe on Compatibility/NVIDIA GeForce RTX 4070 Ti SUPER returned
12/12 expected screen colours, with every measured RGB value exact.

### Final acceptance gate

The updated PowerShell wrapper ran end to end with hidden, awaited Godot
processes, a fresh writable user profile, explicit logs and the crash
handler disabled. It stops immediately if import or strict compilation
fails. Both wrappers retain their logs; Bash syntax was also checked.

| Check | Result |
|---|---|
| Strict compilation | 99 scripts, 0 failed |
| Retail tests | PASS=240 FAIL=0 SKIP=0 EXIT=0 |
| Asset-free tests | PASS=198 FAIL=0 SKIP=42 EXIT=3; all skips name their retail dependency |
| Frozen C driver | 10 passed, 0 failed; both canonical matrix hashes match |
| Shader screen probe | 12/12, exact RGB |
| Animation golden deliberate breaks | All six families failed as intended, then restored |
| Independent regeneration | All six animation fact files reproduced unchanged; P4 facts unchanged |

Final wrapper logs are under `%TEMP%/frogger-tests-20d3f2f615754326a862777b165b5e78`
(retail) and `%TEMP%/frogger-tests-952581db73b74319b7556efc2ee0859b`
(asset-free). The sandbox's root-certificate-store warning still appears;
it does not affect parsing, playback or rendering. No retail bytes or
captures were added to the repository, and the C reference was not edited
or rebuilt.

## Working in this repository

- GUT's loader does not enforce strict typing. `tools/check_scripts.gd` is the only headless check that every script compiles with warnings as errors.
- Godot's `--import` compiles nothing.
- Files with extensions Godot does not treat as resources (`.cfg`, `.tsv`) need an include filter in export presets.
- Running the boot scene saves the data folder to `user://settings.cfg`. Delete that file to test first-run behaviour.
- A headless run draws nothing, so anything that reads the screen (`tools/probe_model_shader.gd`, the viewers' screenshot mode) needs a window and is not part of the test run.
- A test script must not name a helper `_compare`: GUT has a member of that name.
- A conditional expression between two array literals gives an untyped array, which a typed variable refuses at run time. Assign the literals in an `if`.
- Godot stores mesh normals packed; they come back changed in the fifth decimal place.

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

## Working in this repository

- GUT's loader does not enforce strict typing. `tools/check_scripts.gd` is the only headless check that every script compiles with warnings as errors.
- Godot's `--import` compiles nothing.
- Files with extensions Godot does not treat as resources (`.cfg`, `.tsv`) need an include filter in export presets.
- Running the boot scene saves the data folder to `user://settings.cfg`. Delete that file to test first-run behaviour.
- A headless run draws nothing, so anything that reads the screen (`tools/probe_model_shader.gd`, the viewers' screenshot mode) needs a window and is not part of the test run.
- A test script must not name a helper `_compare`: GUT has a member of that name.
- A conditional expression between two array literals gives an untyped array, which a typed variable refuses at run time. Assign the literals in an `if`.
- Godot stores mesh normals packed; they come back changed in the fifth decimal place.

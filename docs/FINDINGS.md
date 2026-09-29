# Findings

What each phase learned that later phases need. Add to this file at the end of every phase. Numbers are for `pc-retail-v3.0e` unless stated.

## Open questions

| Question | Evidence so far | Settle in |
|---|---|---|
| Is the PC game's logic rate 30 or 25 ticks per second? | The reference engine runs 30: the C source defines 30 logic calls per second and the PC build creates a 33 ms timer. FrogLord's editor converts entity delays to seconds using 25 for the PC release. | P7, against the reference engine's traces and the retail game |
| Does the PC game use the same camera projection distance (256) as the C source sets? | Every reference picture was rendered with 256. Not independently checked against the retail game. | P6 |

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

## For the model phase (P4)

- Forms in the general theme, and any form whose model id is 128 or more, use model `id - 128` from the general WAD. Other forms use the level's own WAD from the map book.
- Maps set bit 15 on a form id that refers to the general theme.

## Working in this repository

- GUT's loader does not enforce strict typing. `tools/check_scripts.gd` is the only headless check that every script compiles with warnings as errors.
- Godot's `--import` compiles nothing.
- Files with extensions Godot does not treat as resources (`.cfg`, `.tsv`) need an include filter in export presets.
- Running the boot scene saves the data folder to `user://settings.cfg`. Delete that file to test first-run behaviour.

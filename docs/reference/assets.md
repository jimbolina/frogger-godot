# Assets

`assets/` holds the game's content as committed Godot resources, imported
once from the owner's `pc-retail-v3.0e` copy by the importer under
`archive/import/` and edited directly afterwards. The game, sandbox, viewers
and inspection tools read only these resources; see the
[roadmap](../PORTING.md#s1-and-s2-native-asset-and-modern-rendering-spikes)
and the [domain model](domain-model.md#asset-identities) for how they are keyed.

## Storage

Binary files under `assets/` (`.png`, `.wav`, `.ogg`, `.res`) are Git LFS
objects (`.gitattributes`). Text resources (`.tres`, `.tscn`), import sidecars
(`.import`) and script ids (`.uid`) stay in plain Git so they diff. A clone
needs `git lfs install` before checkout, or `git lfs pull` afterwards; the test
wrapper refuses to run while any asset is still an LFS pointer.

Import settings are fixed in `project.godot` under `importer_defaults`:
lossless textures without mipmaps, fractional fixed-size scaling for the bitmap fonts, alpha-border fixing or premultiplied alpha,
and uncompressed WAV without trimming, normalisation or baked loops. The
upscaled texture folders (`images_x4/`, `pages_x4/`) are the one exception:
their sidecars generate mipmaps. Loop modes are applied at runtime from the
sound definitions.

## Records

`src/data/` holds one statically typed `Resource` class per record kind, with
every public field exported: `archive/` (`MwiIndex`, `MwiEntry`, `WadFile`,
`WadChild`), `textures/` (`VloFile`, `VloImage` with its `texture`), `models/`
(`MofFile`, `MofStatic`, `MofPart`, `MofAnimated` and their promoted part
records), `maps/` (`MapFile` and its sections), `tables/` (`GameTables` and
every executable table), `sound/` (`SoundBankHeader`, `SoundBankEntry` with its
`stream`), `demos/` (`SourceDemoFile`) and `names/` (`GameNameLists`,
`NameBank`). Records are immutable once loaded: Godot shares loaded resources,
so nothing may mutate one. `MapFile` stores polygons, grid stacks and grid
squares as packed columns (`polygon_records`, `grid_stack_records`, ...) and
rebuilds the record arrays on first access, which keeps SUB1 under 1.7 MB as
a binary resource; compressed saving brings it under 0.4 MB.

`AssetCatalog` is the abstract provider the game is typed against.
`ImportedAssets` implements it over `assets/`; `GameData` in `archive/source/`
implements it over the retail files for the importer and the archive suite.

## Layout

| Path | Content |
|---|---|
| `catalog.tres` | `AssetIndex`: build name, SHA-256 of the retail executable and archive, the MWI index, the asset path of every resource id, WAD membership, model counterparts, page sets and the playable level codes. |
| `tables/<table>.tres`, `tables/game_tables.tres`, `tables/names.tres` | One file per executable table, linked from `game_tables.tres`; FrogLord's name lists. |
| `textures/images/tNNNN.png` | One padded RGBA8 image per texture id (1,858); exact black is alpha 0 where the image is colour-keyed. |
| `textures/images_x4/tNNNN.png` | The same images upscaled to exactly four times the padded size, drawn by the `x4` [texture set](#upscaled-textures). |
| `textures/banks/<BANK>.tres` | The bank's `VloFile` headers and placement; pixels live in the PNGs. |
| `textures/pages/<GENERAL>+<THEME>/page_NN.png`, `sky.png`, `page_set.tres` | The 14 VRAM pages a map set uses, baked by the importer with the page-wide colour key, plus the sky atlas. The game only loads a `TexturePageSet`; composing pages lives in the archive (`VramPages`). |
| `textures/pages_x4/<SET>/` | The same page sets at four times the size, baked locally and ignored by Git ([upscaled textures](#upscaled-textures)). |
| `fonts/<set>/newfont.fnt`, `newfont.png` | One BMFont text file per texture set (`retail`, `x4`) over a copy of that set's `t0310.png`, imported as a `FontFile` ([fonts](#fonts)). |
| `materials/model/tNNNN_bB[_2s].tres` | One shared `ShaderMaterial` per texture id, blend mode and sidedness. |
| `models/<NAME>/model.res`, `part_NN.res`, `mesh.res`, `model.tscn`, `preview.res` | The `MofFile` record (gameplay, collision and animation source of truth), one `ArrayMesh` per drawn part, the `ModelMesh` with cel atlases and texture tracks, a preview scene, and for animated models an `AnimationLibrary` derived for the editor. `models/options/` holds the options-page models. |
| `maps/<NAME>.res` | Each map and sky-land file as a compressed binary resource. |
| `audio/sfx/<BANK>/NNN_<name>.wav`, `audio/sfx/<BANK>.tres` | 16-bit mono 11,025 Hz effects and the bank headers that reference them. |
| `audio/music/track_NN.ogg` | The CD tracks, Ogg Vorbis quality 6, named by track number. |
| `demos/<NAME>.tres` | The recorded demos. |

Gameplay collision and hilites come from `model.res`; editing a part mesh
changes only what is drawn. Shared materials are files: a view draws a
committed mesh through `ModelMeshCopy`, which gives every surface its own
material copy (a flipbook part's morph surface shares its part's copy, so the
view's projection reaches it) and leaves geometry, cel atlases and textures
shared.

## Upscaled textures

`textures/images_x4/` holds an ML-upscaled counterpart of every image, made
outside the repository for S2. Each core is upscaled with its RGB filled
under transparent pixels, padded by wrapping on axes that tile and by edge
repeat otherwise, run through ffmpeg's `xbr` x2, a model at x4 and Lanczos
back down by two, then cropped and re-padded by edge repeat. Terrain,
sprites, effects and fonts use 4x-PBRify_UpscalerV4 (CC0); HUD and menu
images use Real-ESRGAN x4plus (BSD-3-Clause). Alpha is the nearest x4 of the
source mask, RGB is zero under alpha 0, and opaque pixels of colour-keyed
images are raised to at least 8 per channel so the 5-bit key cannot cut
them. `test_asset_textures_x4.gd` checks the file set, size and alpha.

The game draws from one `TextureSet` per launch: `retail` (the default, set
by `frogger/textures/default_set` in `project.godot`) or `x4`, chosen with
`--texture-set=x4` after `--`. Records, materials and page sets keep pointing
at the retail files; `ImportedAssets` maps each retail path into the set's
folders where a texture leaves a record (`texture_of`, `texture_counterpart`,
`page_set`), and `ModelMeshLibrary` keeps one retextured `ModelMeshCopy` per
model and set. An uninstalled set falls back to retail with a warning.
Model UVs are normalised from the record sizes, so they need no change; 2D
draws crop with `TextureBuilder.texture_rect` and draw at the record's retail
size; the set's 3D materials use the `_linear` shader variants, which sample
with mipmaps. Maps sample pages, so `tools/bake_pages_x4.py` composes each
set's pages and sky atlas at scale from the x4 images and the banks'
placement, with the retail page's colour key enlarged, into `pages_x4/`;
the test and play wrappers bake it when it is missing and `--check` it
otherwise, and `tests/golden/assets/test_asset_pages_x4.gd` compares the bake
with an [independent oracle](../../tests/golden/specs/imported-assets.md#texture-pages-at-scale).

## Fonts

All in-game text (the gameplay HUD, its ink layer and the level-stack score
lines) is drawn with `draw_string` from one bitmap font, `newfont`: texture
id 310, 96 ASCII glyphs in 8x8 cells, 32 per row. `tools/make_font_newfont.py`
writes `fonts/retail/newfont.fnt` and `fonts/x4/newfont.fnt`, BMFont text
files whose glyph rectangles follow the grid at the PNG's scale, each with a
byte copy of its set's `t0310.png` beside it as `newfont.png`: Godot's BMFont
importer marks a font's page image as not imported (`importer="skip"`), which
would take texture 310 away from the banks. `--check` diffs the text files and
compares the page bytes, and the test wrappers run it. Godot imports each as a `FontFile` with fixed
size 8 (x4: 32) and fractional scaling, so both are drawn at size 8 and the
x4 glyphs land one to one on screen pixels in a window four times the canvas.
`AssetCatalog.font("newfont")` returns the set's font, falling back to retail
with a problem line; `NewfontText` (`src/convert/`) owns the cell size and the
baseline. The import golden is
[bitmap fonts](../../tests/golden/specs/imported-assets.md#bitmap-fonts).
After a hand edit of a set's `t0310.png`, rerun the generator to refresh the
page copy; until then the wrappers stop at the font check.

# Assets

`assets/` holds the game's content as committed Godot resources, imported
once from the owner's `pc-retail-v3.0e` copy by the importer under
`archive/import/` and edited directly afterwards. The game, sandbox, viewers
and inspection tools read these resources, or another root the
[asset location](#asset-location) chooses; see the
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
upscaled texture folder (`images_x4/`) is the one exception: its sidecars
generate mipmaps. Loop modes are applied at runtime from the
sound definitions.

## Records

`src/data/` holds one statically typed `Resource` class per record kind, with
every public field exported: `archive/` (`MwiIndex`, `MwiEntry`, `WadFile`,
`WadChild`), `textures/` (`VloFile`, `VloImage` with its `texture`, and the hand-authored
`EmissiveImageTable` of `EmissiveImage` entries), `models/`
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
`ImportedAssets` implements it over an assets root; `GameData` in `archive/source/`
implements it over the retail files for the importer and the archive suite.

## Asset location

Every scene, viewer and inspection tool opens its catalog through
`AssetLocation` (`src/application/setup/`), which chooses the base root in
this order:

1. the folder given with `--assets-root=<folder>` after `--`, used as given;
   a folder without `catalog.tres` is reported, not skipped;
2. otherwise the imported root recorded in `user://launcher.cfg`, when it
   holds `catalog.tres`;
3. otherwise `res://assets`, when it holds `catalog.tres`.

When none is usable, the catalog's error lists each candidate and why it was
rejected; the [setup screen](setup.md) then imports the player's files. A source checkout without a
launcher file therefore plays the committed `assets/` as before. A
`--froglord` launch reads the overlay the `FrogLordPointer` names over the
chosen base root; with FrogLord on in the setup, a level reads it only when
the overlay was imported from the chosen save folder over that same base root
([FrogLord while playing](setup.md#froglord-while-playing)).

The catalog reads from two roots. The base root holds the retail-derived
records: the index, tables, maps, models, banks, sounds, music, demos and the
texture sets. The shippable root, `res://assets` in every scene, holds the port's own
work: the fonts, the lettering images and the emissive table. A base root
under `user://` therefore still finds them. A texture set whose images folder
is missing under the base root, such as `x4` over an import made at runtime,
falls back to retail with a warning. An import made at runtime stores each
image as `textures/images/tNNNN.res` (a lossless `PortableCompressedTexture2D`) and each music track
as `audio/music/track_NN.res` (an `AudioStreamWAV` saved without a loop);
texture-set mapping keeps the record's extension, lettering is always looked
up as `.png`, and the music player loops a copy of either track kind over the
whole track.

`user://launcher.cfg` is a `ConfigFile` read and written by `LauncherStore`
into a `LauncherSettings` record (`src/data/settings/`):

| Section | Keys |
|---|---|
| `meta` | `format_version` (2) |
| `game_data` | `game_data_dir`, `disc_image_path` |
| `import` | `fingerprint`, `imported_root` |
| `froglord` | `froglord_enabled`, `froglord_dir` |
| `start` | `show_setup_on_start` |
| `textures` | `texture_set` (`retail`, `x4`, or empty for the project default) |

A missing file gives the defaults without an error, and so does a missing key.
A version-1 file, which had no `textures` section, is read the same way and
the next save writes version 2. An unknown version, a missing version or a
value of the wrong type gives all the defaults, and the reason joins the
catalog's warnings. Saving writes `launcher.cfg.tmp` and renames it over the
file. The archive's `GameDataLocator` keeps its own remembered folder in
`user://settings.cfg`; the launcher file does not share it, because shipped
code may not depend on `archive/`, but the [setup screen](setup.md#pages)
reads that folder as a plain `ConfigFile` and suggests it once.

## Layout

An importer run may also write an overlay index outside `assets/`: its paths
point into its own folder for what the run wrote and into its fallback root
for the rest, and `ImportedAssets.open` reads it through its index-root
argument while texture sets and models still come from the base root and
fonts and lettering
from the shippable root
([archive](../../archive/README.md#regenerating-the-assets)). The fallback
root is `assets/` for the developer watch and the base root the game plays
from for the in-game watch, which may be an import made at runtime under
`user://assets/<fingerprint>/`; an overlay therefore holds only the save's
name lists, tables, demos and maps, `support_report.tsv` and its index, and
names textures, models and sounds of its fallback root. Overlays over
`assets/` live in `user://froglord/<key>/`, overlays over any other root in
`user://froglord/over-<root key>/<key>/`, and `user://froglord/current.cfg`
names the newest.

| Path | Content |
|---|---|
| `catalog.tres` | `AssetIndex`: build name, source kind (`retail` or `FrogLord mod`) with its executable and archive names, a FrogLord save's trailer build and FrogLord version (-1 for retail), the fallback root of an overlay (empty here), SHA-256 of the executable and archive, the MWI index, the asset path of every resource id, WAD membership, model counterparts and the playable level codes. |
| `tables/<table>.tres`, `tables/game_tables.tres`, `tables/names.tres` | One file per executable table, linked from `game_tables.tres`; FrogLord's name lists. |
| `textures/images/tNNNN.png` | One padded RGBA8 image per texture id (1,858); exact black is alpha 0 where the image is colour-keyed. |
| `textures/images_x4/tNNNN.png` | The same images upscaled to exactly four times the padded size, drawn by the `x4` [texture set](#upscaled-textures). |
| `textures/banks/<BANK>.tres` | The bank's `VloFile` headers and placement; pixels live in the PNGs. |
| `fonts/<set>/newfont.fnt`, `newfont.png` | One BMFont text file per texture set (`retail`, `x4`) and its generated 4x page built from that set's `t0310.png`, imported as a `FontFile` ([fonts](#fonts)). |
| `fonts/angular/` | The angular letter face: source SVGs, `derived.json`, the generated MSDF `frogger_angular.ttf` and `lettering.tsv` ([lettering](#lettering)). |
| `textures/lettering/tNNNN.png` | Vector lettering at eight times the padded size, drawn in every texture set in place of the retail image ([lettering](#lettering)). |
| `materials/model/tNNNN_bB[_2s].tres` | One shared `ShaderMaterial` per texture id, blend mode and sidedness, on the lit model shaders ([lighting](rendering/lighting.md#model-shaders)). |
| `models/<NAME>/model.res`, `part_NN.res`, `mesh.res`, `model.tscn`, `preview.res` | The `MofFile` record (gameplay, collision and animation source of truth), one `ArrayMesh` per drawn part, the `ModelMesh` with cel atlases and texture tracks, a preview scene, and for animated models an `AnimationLibrary` derived for the editor. `models/options/` holds the options-page models. |
| `maps/<NAME>.res` | Each map and sky-land file as a compressed binary resource. |
| `audio/sfx/<BANK>/NNN_<name>.wav`, `audio/sfx/<BANK>.tres` | 16-bit mono 11,025 Hz effects and the bank headers that reference them. |
| `audio/music/track_NN.ogg` | The CD tracks, Ogg Vorbis quality 6, named by track number (`track_NN.res` WAV streams in an import made at runtime). |
| `demos/<NAME>.tres` | The recorded demos. |
| `rendering/emissive_images.tres` | Hand-authored, not imported: the `EmissiveImageTable` of texture images that glow, by FrogLord image name, each with a colour, strength and light settings ([lava](rendering/lighting.md#lava)). Edit it as text; `test_asset_emissive_images` checks that it validates and every name resolves. |

Gameplay collision and hilites come from `model.res`; editing a part mesh
changes only what is drawn. Shared materials are files: a view draws a
committed mesh through `ModelMeshCopy`, which gives every surface its own
material copy (a flipbook part's morph surface shares its part's copy, so the
view's projection reaches it) and leaves geometry, cel atlases and textures
shared.

## Runtime import

A packaged build imports the player's copy at first run into
`user://assets/<fingerprint>/`, named by the first 16 hex digits of the
SHA-256 over the game files, with no editor import
([archive](../../archive/README.md#runtime-import)). The root has the
[layout](#layout) of the importer-written part of `assets/` (the index,
tables, banks, maps, models, materials, sound banks and demos are the same
files) with these differences:

| Path | Content |
|---|---|
| `textures/images/tNNNN.res` | A `PortableCompressedTexture2D` holding the padded RGBA8 pixels losslessly, without mipmaps; it keeps its compressed data. |
| `audio/sfx/<BANK>/NNN_<name>.res` | An `AudioStreamWAV`: 16-bit mono 11,025 Hz PCM, no loop. |
| `audio/music/track_NN.res` | Present only when the player gave a disc image: an `AudioStreamWAV` of the CD track's 16-bit stereo 44,100 Hz PCM, saved without a loop. |

Every external reference and every index path names the root itself. Nothing
under it is a `.png`, `.wav`, `.ogg` or `.import` file, and the fonts,
lettering, emissive table and `images_x4/` are not written there.

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
`--texture-set=x4` after `--`. Records and materials keep pointing at the
retail files; `ImportedAssets` maps each retail path into the set's folder
where a texture leaves a record (`texture_of`, `texture_counterpart`), and
`ModelMeshLibrary` keeps one retextured `ModelMeshCopy` per model and set. An uninstalled set falls back to retail with a warning.
Model UVs are normalised from the record sizes, so they need no change; 2D
draws crop with `TextureBuilder.texture_rect` and draw at the record's retail
size; the set's 3D materials use the `_linear` shader variants, which sample
with mipmaps, and map terrain samples the set's images directly
([terrain](rendering/lighting.md#terrain)). The original's VRAM page
composition stays in the archive as format knowledge (`VramPages`).

## Fonts

All in-game text (the gameplay HUD, its ink layer and the level-stack score
lines) is drawn with `draw_string` from one bitmap font, `newfont`: texture
id 310, 96 ASCII glyphs in 8x8 cells, 32 per row. `tools/make_font_newfont.py`
writes `fonts/retail/newfont.fnt` and `fonts/x4/newfont.fnt`, BMFont text
files, each with a page `newfont.png` built from its set's `t0310.png`: Godot's
BMFont importer marks a font's page image as not imported (`importer="skip"`),
which would take texture 310 away from the banks. Both pages hold the glyphs at
four page pixels per retail pixel (the retail texture's pixels repeated, the
x4 set's as they are), each cell inside a transparent border whose pixels next
to the glyph carry the stroke grey. `--check` diffs the text files and
compares the page pixels, and the test wrappers run it. Godot imports each as
a `FontFile` with fixed size 32 and fractional scaling, drawn at size 8. The
HUD ink layer and the stack panel draw the text linearly filtered (their
sprites stay nearest), so every retail pixel of a glyph covers the same
screen area at any window scale: exactly at whole-number scales up to 4, and
otherwise with an edge under one screen pixel soft.
`AssetCatalog.font("newfont")` returns the set's font, falling back to retail
with a problem line; `NewfontText` (`src/rendering/`) owns the cell size and the
baseline. The import golden is
[bitmap fonts](../../tests/golden/specs/imported-assets.md#bitmap-fonts).
After a hand edit of a set's `t0310.png`, rerun the generator to rebuild the
page; until then the wrappers stop at the font check. Godot does not track a
font's page, so each `.fnt` carries the page's pixel digest and changes with
it, which makes the next import pick the new page up.

No vector or higher-resolution master of `newfont` ships. Texture 1847
(FrogLord's guessed name `newfont4`) is the same glyphs doubled to 16x16
cells with a near-black drop shadow, and 1846 adds accented glyphs at 8x8.
The owner's pre-recode PlayStation disc (built 19 March 1997) has the same
grid with identical lowercase but unshaded capitals and digits with a black
drop shadow, so the grey-shaded capitals were drawn later. The angular
high-score letters are a separate face: the alpha's front-end models
`A.XMR`–`Z.XMR` and `0.XMR`–`9.XMR` (in `FRONT_0.WAD`) are flat single-colour
polygon glyphs, and retail's `hi_a`–`hi_z` lily-pad textures are those
shapes rasterised; retail has no number models. That face is drawn from a
vector font ([lettering](#lettering)); `newfont` stays a bitmap.

## Lettering

Every retail texture that shows the angular face (lily-pad letters, rank
turtles, score logs, HUD digits and `SEC` labels, menu, HUD and
level-complete words in all five languages, level names: 319 ids, excluding
the decorated `1up1`) is drawn from a vector rendering instead of its retail
pixels. The glyphs are a community trace of the alpha's letter models (36
SVGs under `fonts/angular/svg/`) plus punctuation and accented capitals
built in `fonts/angular/derived.json`. `uv run tools/make_angular_font.py`
writes `fonts/angular/frogger_angular.ttf`, which the catalog serves as
`font("angular")` in every set; nothing draws runtime text with it yet.
`fonts/angular/lettering.tsv` holds each texture's text (retail spelling
kept), style and background. `uv run tools/make_lettering.py` fits that text
to the retail image's ink box and writes `textures/lettering/tNNNN.png` at
eight times the padded size, mipmapped, with a one-retail-pixel outline; the
turtle shell is rebuilt without its digit from the ten retail tiles. Both
generators' `--check` runs in the test wrappers.

`ImportedAssets.texture_counterpart` prefers a lettering image in the retail
and x4 sets alike; `ModelMeshLibrary` converts a retail-set mesh that draws
one, so the lily pads, turtles and logs sample it linearly with mipmaps, and
`TextureLibrary.texture_for` hands 2D draws a linear, mipmapped
`CanvasTexture` so nearest-filtered nodes still shrink it smoothly. Draws
keep their retail sizes through `TextureBuilder.texture_rect` and
`retail_size`. The retail PNGs stay byte-exact as source data. Goldens:
[angular font](../../tests/golden/specs/imported-assets.md#angular-font) and
[lettering](../../tests/golden/specs/imported-assets.md#lettering).

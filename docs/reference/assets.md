# Assets

The game plays from Godot resources imported from the player's own
`pc-retail-v3.0e` copy by the importer under `archive/import/`. A developer's
import lives in `assets/`, which is git-ignored and written by
`tools/setup_dev.sh --import` (`archive/import/import_assets.sh`); a player's
lives in the user folder ([runtime import](#runtime-import)). Imported files
are never edited by hand: a change goes through the importer, a FrogLord
overlay or a [texture pack](#texture-packs). `content/` is tracked and holds
the port's own files ([content](#content)). The game, sandbox, viewers and
inspection tools read the root the [asset location](#asset-location)
chooses; see the
[roadmap](../PORTING.md#s1-and-s2-native-asset-and-modern-rendering-spikes)
and the [domain model](domain-model.md#asset-identities) for how they are keyed.

## Storage

The PNGs and the TTF under `content/` are Git LFS objects (`.gitattributes`);
its text files and import sidecars stay in plain Git so they diff. A clone
needs `git lfs install` before checkout, or `git lfs pull` afterwards; the test
wrapper refuses to run while any file is still an LFS pointer. Nothing under
`assets/` is tracked.

Import settings are fixed in `project.godot` under `importer_defaults`:
lossless textures without mipmaps, alpha-border fixing or premultiplied alpha,
and uncompressed WAV without trimming, normalisation or baked loops. The
lettering images are the one texture exception: their sidecars generate
mipmaps, and the tile masks use the `image` importer, which keeps their grey
values exactly. Loop modes are applied at runtime from the sound definitions.

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
3. otherwise the developer's local import `res://assets`
   (`ImportedAssets.COMMITTED_ROOT`), when it holds `catalog.tres`.

When none is usable, the catalog's error lists each candidate and why it was
rejected; the [setup screen](setup.md) then imports the player's files. A
source checkout with an imported `assets/` and no launcher file therefore
plays it; one without an import opens the setup like an exported game. A
`--froglord` launch reads the overlay the `FrogLordPointer` names over the
chosen base root; with FrogLord on in the setup, a level reads it only when
the overlay was imported from the chosen save folder over that same base root
([FrogLord while playing](setup.md#froglord-while-playing)).

The catalog reads from two roots. The base root holds the retail-derived
records: the index, tables, maps, models, banks, sounds, music, demos and the
retail images. The shippable root, `res://content`
(`ImportedAssets.SHIPPABLE_ROOT`) in every scene, holds the port's own work
([content](#content)), so a base root under `user://` still finds it, and a
packaged build ships it without its sources ([packaging](setup.md#packaging)).
[Texture packs](#texture-packs) live apart from both, in the player's user
data. An import made at runtime stores each
image as `textures/images/tNNNN.res` (a lossless `PortableCompressedTexture2D`) and each music track
as `audio/music/track_NN.res` (an `AudioStreamWAV` saved without a loop);
a pack image or lettering image replaces either extension by texture id, and
the music player loops a copy of either track kind over the whole track.

`user://launcher.cfg` is a `ConfigFile` read and written by `LauncherStore`
into a `LauncherSettings` record (`src/data/settings/`):

| Section | Keys |
|---|---|
| `meta` | `format_version` (3) |
| `game_data` | `game_data_dir`, `disc_image_path` |
| `import` | `fingerprint`, `imported_root` |
| `froglord` | `froglord_enabled`, `froglord_dir` |
| `start` | `show_setup_on_start` |
| `textures` | `texture_pack`: the [texture pack](#texture-packs)'s folder name, or empty for the original textures |

A missing file gives the defaults without an error, and so does a missing key.
Version-1 and version-2 files are read the same way and the next save writes
version 3. Version 1 had no `textures` section; version 2's
`textures/texture_set` (`retail`, or the removed ML-upscaled `x4`) names no
pack, so it is dropped and the original textures draw. An unknown version, a missing version or a
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
argument while models still come from the base root and the angular font and
lettering from the shippable root
([archive](../../archive/README.md#regenerating-the-assets)). The fallback
root is `assets/` for the developer watch and the base root the game plays
from for the in-game watch, which may be an import made at runtime under
`user://assets/<fingerprint>/`; an overlay therefore holds only the save's
name lists, tables, demos and maps, `support_report.tsv` and its index, and
names textures, models and sounds of its fallback root. Overlays over
`assets/` live in `user://froglord/<key>/`, overlays over any other root in
`user://froglord/over-<root key>/<key>/`, and `user://froglord/current.cfg`
names the newest.

An editor import (`assets/`) holds:

| Path | Content |
|---|---|
| `catalog.tres` | `AssetIndex`: build name, source kind (`retail` or `FrogLord mod`) with its executable and archive names, a FrogLord save's trailer build and FrogLord version (-1 for retail), the fallback root of an overlay (empty here), SHA-256 of the executable and archive, the MWI index, the asset path of every resource id, WAD membership, model counterparts and the playable level codes. |
| `tables/<table>.tres`, `tables/game_tables.tres`, `tables/names.tres` | One file per executable table, linked from `game_tables.tres`; FrogLord's name lists. |
| `textures/images/tNNNN.png` | One padded RGBA8 image per texture id (1,858); exact black is alpha 0 where the image is colour-keyed. |
| `textures/banks/<BANK>.tres` | The bank's `VloFile` headers and placement; pixels live in the PNGs. |
| `materials/model/tNNNN_bB[_2s].tres` | One shared `ShaderMaterial` per texture id, blend mode and sidedness, on the lit model shaders ([lighting](rendering/lighting.md#model-shaders)). |
| `models/<NAME>/model.res`, `part_NN.res`, `mesh.res`, `model.tscn`, `preview.res` | The `MofFile` record (gameplay, collision and animation source of truth), one `ArrayMesh` per drawn part, the `ModelMesh` with cel atlases and texture tracks, a preview scene, and for animated models an `AnimationLibrary` derived for the editor. `models/options/` holds the options-page models. |
| `maps/<NAME>.res` | Each map and sky-land file as a compressed binary resource. |
| `audio/sfx/<BANK>/NNN_<name>.wav`, `audio/sfx/<BANK>.tres` | 16-bit mono 11,025 Hz effects and the bank headers that reference them. |
| `audio/music/track_NN.ogg` | The CD tracks, Ogg Vorbis quality 6, named by track number (`track_NN.res` WAV streams in an import made at runtime). Tracks 2–6, 8–10, 12 and 14–21 are the level music (`MusicTable`), 11 the menu tune, 13 the level-select tune, 22 the game-over jingle and 23–32 the zone-complete tunes (`PlayCD(theme + 22)`); 7 is played by nothing ([front-end music](gameplay/front-end.md#music)). |
| `demos/<NAME>.tres` | The recorded demos. |

Gameplay collision and hilites come from `model.res`; editing a part mesh
changes only what is drawn. Shared materials are files: a view draws a
imported mesh through `ModelMeshCopy`, which gives every surface its own
material copy (a flipbook part's morph surface shares its part's copy, so the
view's projection reaches it) and leaves geometry, cel atlases and textures
shared.

## Content

`content/` is the shippable root. Nothing in it holds a retail pixel or
retail data; what depends on the player's copy is built at runtime.

| Path | Content |
|---|---|
| `fonts/angular/svg/`, `derived.json` | The angular face's sources: StarmanUltra's 36 SVG traces and the derived glyphs ([lettering](#lettering)). Not shipped. |
| `fonts/angular/frogger_angular.ttf` | The generated MSDF font, served as `font("angular")`. |
| `fonts/angular/lettering.tsv`, `lettering_layout.tsv` | Each lettered texture's text, style and background, and its padded size and ink boxes measured once from the retail images ([lettering](#lettering)). Not shipped. |
| `lettering/tNNNN.png` | The 270 transparent lettering images at eight times the padded size, mipmapped. |
| `lettering/masks/<background>/tNNNN.png` | The 49 tiles' 8-bit fill coverage (`green_pad` t0235–t0263, `log` t0566–t0575, `turtle` t0638–t0647), imported with the `image` importer. |
| `rendering/emissive_images.tres` | Hand-authored: the `EmissiveImageTable` of texture images that glow, by FrogLord image name, each with a colour, strength and light settings ([lava](rendering/lighting.md#lava)). Edit it as text; `test_asset_emissive_images` checks that it validates and every name resolves. |

## Runtime import

A packaged build imports the player's copy at first run into
`user://assets/<fingerprint>/`, named by the first 16 hex digits of the
SHA-256 over the game files, with no editor import
([archive](../../archive/README.md#runtime-import)). The root has the
[layout](#layout) of an editor import (the index,
tables, banks, maps, models, materials, sound banks and demos are the same
files) with these differences:

| Path | Content |
|---|---|
| `textures/images/tNNNN.res` | A `PortableCompressedTexture2D` holding the padded RGBA8 pixels losslessly, without mipmaps; it keeps its compressed data. |
| `audio/sfx/<BANK>/NNN_<name>.res` | An `AudioStreamWAV`: 16-bit mono 11,025 Hz PCM, no loop. |
| `audio/music/track_NN.res` | Present only when the player gave a disc image: an `AudioStreamWAV` of the CD track's 16-bit stereo 44,100 Hz PCM, saved without a loop. |

Every external reference and every index path names the root itself. Nothing
under it is a `.png`, `.wav`, `.ogg` or `.import` file.

## Texture packs

A texture pack replaces retail images with hand-drawn ones at a higher
resolution without touching the assets root. The ML-upscaled `images_x4/`
set it replaces was removed in L6.

**Location.** A pack is a folder named for the pack under
`user://texture_packs/` (on macOS
`~/Library/Application Support/Godot/app_userdata/Frogger/texture_packs/`, on
Windows `%APPDATA%\Godot\app_userdata\Frogger\texture_packs\`, on Linux
`~/.local/share/godot/app_userdata/Frogger/texture_packs/`). An exported game
also looks in a `texture_packs` folder beside its executable; a pack in user
data hides one of the same name there. The folder name is the pack's name on
the command line and in the launcher settings (`TexturePackReader`).

**`pack.cfg`.** A `ConfigFile` with one `[pack]` section:

| Key | Content |
|---|---|
| `name` | Required text: the name the settings page shows. |
| `base_build` | Required text: the build the images were drawn for, `pc-retail-v3.0e`. Another build draws with a warning. |
| `author`, `version`, `description` | Optional text. |
| `format_version` | Optional; 1 when present. |

A folder without `pack.cfg`, or whose file is unreadable or breaks these
rules, is not a pack; the reason joins the catalog's warnings when it is
chosen, and the settings page leaves it out.

**Images.** Each PNG is named by texture id, `tNNNN.png` with four digits
(`t0310.png`), or by FrogLord image name (`hi_a.png`), matched ignoring case
against the build's image names; the id form wins when both name the same
texture. Other files, and PNGs naming no texture, are ignored with a warning.
Each image is the whole padded texture, padding included, at a whole
multiple from 1 to 16 of the retail padded size, the same on both axes; the
scale is found per image, so one pack may mix scales. The image's own alpha
is drawn; colour keying does not apply. An image of any other size is
rejected with a problem line naming both sizes, and that texture draws as
if the pack lacked it. The golden facts file
[`vlo_images.tsv`](../../tests/golden/pc-retail-v3.0e/vlo_images.tsv) lists
every texture's padded size (`padded_width`, `padded_height`) and in-game
region; `textures/images/tNNNN.png` is the image to draw over.

**Precedence.** For each retail texture the catalog draws the pack's
accepted image, else its [lettering](#lettering) image, else its lettering
tile composited at runtime, else the retail image. A pack that redraws a lettered texture therefore wins over the
lettering. Every texture a pack omits keeps its retail or lettering image.

**Loading.** `ImportedAssets.open` resolves the pack named by
`--texture-pack=<name>` after `--` (an empty value draws none), else by the
launcher settings, which the [setup screen](setup.md#pages) fills. Each image
is read on first use with `Image.load_from_file`, so no editor import is
involved and an exported game loads packs as well. A scaled image gets its
transparent edges fixed and mipmaps; a texture loaded once is shared while
anything holds it. `TextureSet` records each accepted image's scale.

**Drawing at scale.** Records and materials keep pointing at the retail
files; `ImportedAssets.texture_of` and `texture_counterpart` answer with the
drawn texture, and `ModelMeshLibrary` keeps one retextured `ModelMeshCopy`
per model and pack. A texture larger than its record's padded size
(`TextureBuilder.is_upscaled`, which also covers lettering) samples linearly
with mipmaps: `TextureLibrary.texture_for` wraps it in a linear, mipmapped
`CanvasTexture` for 2D, and 3D materials draw it through the `_linear`
shader variants. Model UVs are normalised from the record sizes, so they need
no change; 2D draws crop with `TextureBuilder.texture_rect` and draw at the
record's retail size; map terrain samples each image directly and keeps an
upscaled one linear whatever the viewer's filter switch says; the sky's tile
array takes the largest scale among its tiles and enlarges the others by
repeating pixels ([terrain](rendering/lighting.md#terrain)). The original's
VRAM page composition stays in the archive as format knowledge (`VramPages`).

**Font.** A pack's `t0310.png` is drawn by the `newfont` font too:
`NewfontPage` builds the font's page from it, enlarging an image whose scale
divides 4 by repeating pixels and resampling any other scale with Lanczos to
four page pixels per retail pixel ([fonts](#fonts)).

## Fonts

All in-game text (the gameplay HUD, its ink layer and the level-stack score
lines) is drawn with `draw_string` from one bitmap font, `newfont`: texture
id 310, 96 ASCII glyphs in 8x8 cells, 32 per row. No font file is stored
anywhere, because its page would hold texture 310's pixels:
`AssetCatalog.font("newfont")` builds it at runtime with `NewfontFont`
around a `NewfontPage` page made from the base root's texture 310, or from a
[texture pack](#texture-packs)'s accepted `t0310.png`, and answers null with
a problem line only without that texture. The page holds the glyphs at four
page pixels per retail pixel (the retail texture's pixels repeated), each
cell inside a transparent border whose pixels next to the glyph carry the
stroke grey; the font has fixed size 32 and fractional scaling and is drawn
at size 8. `tools/make_font_newfont.py --out <folder>` writes the same font
as a BMFont `newfont.fnt` and page `newfont.png` from an import's
`t0310.png`; it is the golden generator, and the test wrappers run it into
their run folder for the imported suite to compare with
([bitmap fonts](../../tests/golden/specs/imported-assets.md#bitmap-fonts)).
The HUD ink layer and the stack panel draw the text linearly filtered (their
sprites stay nearest), so every retail pixel of a glyph covers the same
screen area at any window scale: exactly at whole-number scales up to 4, and
otherwise with an edge under one screen pixel soft. `NewfontText`
(`src/rendering/`) owns the cell size and the baseline.

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
SVGs under `content/fonts/angular/svg/`) plus punctuation and accented
capitals built in `content/fonts/angular/derived.json`.
`uv run tools/make_angular_font.py` writes
`content/fonts/angular/frogger_angular.ttf`, which the catalog serves as
`font("angular")` with or without a pack; nothing draws runtime text with it
yet.

`content/fonts/angular/lettering.tsv` holds each texture's text (retail
spelling kept), style and background, and `lettering_layout.tsv` its padded
size and the ink box of each line or letter, measured once from the retail
images with `uv run tools/make_lettering.py --layout` (sizes and boxes only,
never colours or pixels). `uv run tools/make_lettering.py` reads only those
two tables, the SVGs and `derived.json`, fits the text to the ink boxes at
eight times the padded size and writes:

- for the 270 transparent rows, `content/lettering/tNNNN.png`, mipmapped,
  with a one-retail-pixel outline;
- for the 49 tiles (lily pads t0235–t0263, logs t0566–t0575, turtles
  t0638–t0647), the 8-bit fill coverage
  `content/lettering/masks/<background>/tNNNN.png`.

`LetteringTile` (`src/application/loaders/`) composites each tile at runtime
from its mask and the player's imported images: the background is the most
common colour of `t0263` (`green_pad`) or `t0566` (`log`), or for `turtle`
the shell voted per pixel from `t0638`–`t0647` with the mirrored pixel where
every tile shows a digit; the fill is the most common colour of the tile's
retail ink (channels differing from the background by more than 0x10). The
background is enlarged by repeating pixels, the fill laid over it with
Pillow's rounding, every channel raised to at least 8, and the tile gets
mipmaps. A tile that cannot be built draws its retail texture with a problem
line. `make_lettering.py --composite <assets> --out <folder>` is the Python
golden generator of the same tiles. The generators' `--check` (the angular
font and the lettering without retail input) runs in both test wrappers.

`ImportedAssets.texture_counterpart` prefers a lettering image or tile to the
retail image, and a texture pack's own image to both
([precedence](#texture-packs)); `ModelMeshLibrary` converts a mesh that draws
one, so the lily pads, turtles and logs sample it linearly with mipmaps, and
`TextureLibrary.texture_for` hands 2D draws a linear, mipmapped
`CanvasTexture` so nearest-filtered nodes still shrink it smoothly. Draws
keep their retail sizes through `TextureBuilder.texture_rect` and
`retail_size`. The imported retail PNGs stay byte-exact as source data.
Packaged builds ship the images and masks ([packaging](setup.md#packaging)).
Goldens: [angular font](../../tests/golden/specs/imported-assets.md#angular-font)
and [lettering](../../tests/golden/specs/imported-assets.md#lettering).

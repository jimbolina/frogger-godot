# Imported assets (`pc-retail-v3.0e/model_meshes.tsv`, `sound_samples.tsv`, `asset_census.txt`, `archive/import/disc_tracks.tsv`)

The importer writes every retail asset into the developer's local `assets/`
(git-ignored). These facts say what each imported file must hold. They are
derived from the retail bytes by independent Python that reads no Godot
output. The import goldens of the imported suite decode the local import and
compare. Model facts
are the same for every texture bank context: the model generator checks that
every texture id has one size and padding in every bank that holds it.

| File | One row per | Columns |
|---|---|---|
| `model_meshes.tsv` | part of a static model (1,009, the keys of `mof_parts.tsv`) | resource id, file name, static model inside the file, part, surfaces, triangles, cels, `unresolved_textured_polygons`, `positions_sha256`, `colours_sha256`, `uvs_sha256` |
| `sound_samples.tsv` | present sound-bank row (174) | sound id, bank, body file name, FrogLord sound name, `source_bits`, `source_rate`, frames, `rate` (always 11025), `pcm16_sha256` |
| `archive/import/disc_tracks.tsv` | audio track of the disc image (31); it lives with the importer, whose music step checks every decoded track against it | track, FrogLord music name (`-` if none), first sector (from the table, pregap included), sectors, frames (44.1 kHz stereo), seconds (3 decimals), `pcm_sha256`, the levels whose music-table entry plays it (`-` if none) |
| `asset_census.txt` | count, `key=value` | MWI entries, maps (FROG and sky land), VLO banks, images, distinct texture ids, models by kind and incomplete models, model parts, sound banks and samples, demo tables, rows and distinct demos, disc tracks, rows of every EXE table (`rows[exe_*]`, as `make_golden_exe_tables.py` writes them, plus the two high-score tables) |

`-` is an empty list. List digests follow the
[shared convention](../README.md#digest-convention).

## Bitmap fonts

`newfont` is texture 310, 96 glyphs of ASCII 32 to 127 in square cells, 32
to a row in three rows, with no padding: `textures/images/t0310.png` is
256 x 24 (8-pixel cells). No font file is committed or shipped, since its
page holds texture 310's pixels; the game builds the font at runtime
(`NewfontFont` around a `NewfontPage` page). `tools/content/make_font_newfont.py
--out <folder>` is the golden generator: from an import's `t0310.png`
(`--images` names another images folder) it writes `newfont.fnt`, a BMFont
v3 text file, and `newfont.png`, the page the font names as its only page.
The page enlarges the PNG 4 times by
repeating pixels, so every glyph is 32 x 32, and sets each glyph inside a
4-pixel transparent border:
40 x 40 cells, 32 to a row, on a 1280 x 120 page. The two rings of
transparent pixels around each glyph's opaque pixels, within its cell, take
the per-channel maximum colour of their already filled 8-neighbours, ring by
ring; other transparent pixels keep the source's colour or zero. The font's
`size`, `lineHeight` and `base` are 32, `scaleW` and `scaleH` 1280 and 120,
and `alphaChnl=0` with the colour channels at 4, so a BMFont loader keeps the
RGBA pixels (the glyphs are eight grey levels; `alphaChnl=1` would turn them
white on alpha). The `info` line ends with `page_sha256`, the SHA-256 of
the page's RGBA rows. Glyph `id` sits at
`x = ((id - 32) % 32) * 40`,
`y = ((id - 32) / 32) * 40` with width and height 40, `xoffset` and
`yoffset` -4 and `xadvance` 32.

Both test wrappers run the generator on the local import into the run
folder's `generated/newfont/` and export the run's `generated/` folder as
`FROGGER_GENERATED_DIR`; the tests that read it fail when it is unset.
`test_asset_newfont_runtime.gd` loads the generated `.fnt` with Godot's
BMFont loader and the options of the project's `font_data_bmfont` defaults
(fixed size with fractional scaling, no fallbacks), and requires the font
`NewfontFont` builds from the imported texture 310 to store every property,
glyph and metric it stores, with a page equal pixel for pixel, and text to
measure the same. `test_asset_fonts.gd` checks the built font against the
grid (fixed size, ascent, UV rectangles, glyph size, advance and offset
(-4, -36)), that every glyph pixel's alpha, and colour where opaque, equals
the source PNG pixel it repeats and every border pixel is transparent, the
retail source's digest, and that "1 UP" measures 32 x 8 at size 8.
`ImportedAssets.font("newfont")` returns null with a problem line only when
texture 310 is missing.

A texture pack's `t0310.png` (any whole scale S from 1 to 16 of 256 x 24)
is drawn by a font whose page `NewfontPage` builds at runtime by the same
rule: an S dividing 4 is enlarged 4 / S times by repeating pixels, any other
S is resampled with Lanczos to 1024 x 96, then the borders and the two fill
rings are applied. The golden writes a synthetic pack holding the retail
`t0310.png` enlarged four times with its opaque pixels tinted, and checks
that pack's font against the same grid, pixel and string-size rules, with
the tinted PNG as the source. It also checks that `NewfontPage.build` of the
retail PNG enlarged 1, 2 and 4 times equals the generated page pixel for
pixel, so the runtime builder and the generator agree, and that a size that
is no multiple builds nothing.

## Angular font

The angular letter face (the retail lettering and the alpha's letter
models) is a TrueType font, `content/fonts/angular/frogger_angular.ttf`,
written by `uv run tools/content/make_angular_font.py` from two sources beside it:

- `svg/A.svg` to `svg/9.svg`: 36 third-party SVG traces, kept byte for byte
  (CRLF included, so `.gitattributes` marks them `-text`); `svg/.gdignore`
  keeps Godot from importing them. Each viewBox is `0 0 W 800`; only
  `<path>` (M, L, H, V, Z) and `<polygon>` are read, paths that never draw
  a third point are skipped, and the fill is even-odd.
- `derived.json`: `! ¡ ' : - . = ◀ É Ó Í Ù Ä Ü Ç` as hand-cut polygons in
  font units, optionally on a `base` glyph (`rotate` 180 for `¡`).

`tools/content/angular_glyphs.py` turns both into contours in font units (y up,
baseline 0, cap height 800, x from the ink box's left); the lettering
generator reuses it. The font has 1000 units per em, so source units are
font units; each glyph has side bearings of 40 units (`lsb` equals `xMin`)
and the space advances 320. Contours are oriented by nesting depth for the
nonzero fill, and crossing contours are refused. Ascent and descent are the
outline extremes (1060 and -250). The head timestamps are fixed, so the
bytes reproduce with the fontTools pinned in `uv.lock`. The TTF is the
generated artefact: `--check` names each glyph, metric or table that
differs and exits 1, and both wrappers run it before the suites.

It is imported by `font_data_dynamic` with the keys `ImportPolicyCheck`
holds (`tests/support/import_policy_check.gd`, run over `content/` by the
game suite's `test_content_import_settings.gd`): MSDF on (pixel range 16,
size 64), no hinting, no mipmaps and no system fallback.
`tests/golden/content/test_content_angular_font.gd` loads it as a `FontFile`
with MSDF on, requires a glyph with a positive advance for every capital,
digit, derived character and the space and no lowercase, and requires its
own character list to equal the SVG names plus `derived.json`'s keys, read
with Godot's directory listing and JSON parser. The imported suite's
`test_asset_angular_font.gd` requires a catalog over the local import to
serve it by name without problems.

## Lettering

The lettering replaces the retail texture `tNNNN` wherever the angular face
is baked into it (words in five languages, level names, HUD digits, the
high-score pads, rank turtles and score logs). The game draws it unless a
texture pack supplies that texture itself
([texture packs](../../../docs/reference/assets.md#texture-packs)).
`uv run tools/content/make_lettering.py` reads only `content/fonts/angular/lettering.tsv`,
`lettering_layout.tsv`, the SVGs and `derived.json` (no retail input),
draws the glyphs of `tools/content/angular_glyphs.py` and writes one file per table
row: `content/lettering/tNNNN.png` for a transparent row and the 8-bit fill
coverage `content/lettering/masks/<background>/tNNNN.png` for a tile row
(`green_pad`, `log`, `turtle`). Pillow's polygon rasteriser rounds edge
crossings differently on arm64 and x86_64 (its wheels fuse multiply-adds on
one and not the other), so `--check` and the write path treat an image as
the generator's when no channel differs by more than one coverage step
(`RASTER_STEP`, 16 of 255 at four-times supersampling) on at most
`RASTER_PIXELS` (16) pixels; anything larger is a real change.
`lettering.tsv`'s columns are `id`, `name` (FrogLord's
name or `-`), `language` (`en`, `s`, `g`, `i`, `f` or `-`), `text` (`|`
breaks a line; retail spelling and spacing), `style`, `background`
(`transparent`, `green_pad`, `log`, `turtle`) and `layout` (`line`, or
`components` for `hi_end`, whose letters are fitted one per retail ink
component). `lettering_layout.tsv` holds per row the retail padded width and
height and the ink box of each line or letter; `make_lettering.py --layout`
measures it from an import's retail images and `--layout --check` compares.
The generator's docstring defines the styles, the fit, the layout
measurement and the backgrounds.

Each file is exactly eight times the retail padded size. Transparent words
have straight alpha with the outermost colour under alpha 0; a mask is grey
coverage. No channel of an image is below 8. The files are generated
artefacts, not facts: `--check` decodes each committed PNG and compares its
pixels with a fresh rendering, checks each sidecar's importer and policy
keys, names every id that differs, is missing or has no row, and exits 1.
Both wrappers run it next to the angular font check. An image's sidecar uses
the texture importer with mipmaps and otherwise the project defaults; a
mask's uses the `image` importer, which keeps its values exactly. A new
file's seed sidecar is completed by `godot --headless --path . --import`.

The game suite's `tests/golden/content/test_content_lettering.gd` reads the
table and `vlo_images.tsv` with Godot's file access. It requires:

- one image or mask per row at eight times the row's padded size, and no
  file without a row;
- each image to import with mipmaps and each mask as an exact `Image`;
- `frogger_angular.ttf` to hold every character the table writes.

The opaque tiles exist only at runtime: `LetteringTile` composites each from
its mask and the import's retail images
([lettering](../../../docs/reference/assets.md#lettering)).
`make_lettering.py --composite <assets> --out <folder>` is their golden
generator: it measures the geometry from the import's images itself, draws
the fill coverage and lays the fill colour over the background with Pillow's
`Image.composite`. Both wrappers run it into the run folder's
`generated/lettering/`. In the imported suite, `test_asset_lettering.gd`
requires the catalog to draw every row's image or tile in place of its retail
texture at eight times the retail size with no problems, and
`test_asset_lettering_tiles.gd` requires every runtime tile to equal the
generated tile within the same `RASTER_STEP` and `RASTER_PIXELS` allowance.
Since the generator measures from the retail images rather than the
committed table and masks, this also checks the layout file and the masks.

## Model meshes

Each part is built from its rest pose, partcel 0. An incomplete model
borrows the partcels and texture-animation targets of the same part of its
counterpart. The counterpart is the nearest earlier complete model. An
animated file uses the counterpart's static model with the same index. A
borrowed target is valid only when its polygon index exists in this part
and has the same type.

- Surfaces: there is one surface per texture-animation target. Its polygon
  is the first one whose type and index match a valid target. Other polygons
  are grouped into one surface per texture id. Untextured polygons go to
  one plain surface, together with textured polygons whose image id is in
  no bank. `unresolved_textured_polygons` counts those textured polygons.
  It is 0 in retail. Polygons with fewer than three corners are skipped. A
  part with no partcel has no surfaces.
- Corners: polygons are processed in stored order within their surface. A
  triangle uses its stored corners 0, 1, 2. A quad uses corners
  (0, 1, 3) and (1, 2, 3). Every corner is its own vertex.
- Positions are the stored partcel x, y, z in game units, before
  `GameSpace` turns them into Godot space. A test applies
  `GameSpace.to_game`. An index past the partcel gives 0,0,0.
- Colours are the polygon's red, green, blue and 255 at every corner.
  Lighting and the code byte do not apply.
- UVs are whole pixels in the padded image:
  `left + u * width / 255` and `top + v * height / 255`, with integer
  division. Here `left = (padded width - width) / 2` and `top` is computed
  the same way. A texture-animation surface stores the unpadded part and
  adds the padding in its shader. Its pixel is the same.
- Cels are the effective partcel count. The animated mesh's blend shapes
  are cels - 1.

**Digests ignore surface order.** For each surface, a list digest is taken
of its positions, colours and UVs, each in corner order. Each part column
is the list digest of the sorted surface digests. `uvs_sha256` includes only
surfaces with a resolved image. `ModelMeshBuilder` sorts surfaces by blend
mode and then by the surface's name string. That is an implementation
choice, not a property of the data, so an importer may order surfaces
differently. Order within a surface is pinned.

## Sound samples and disc tracks

Each present row of a bank header named by the executable's bank table is
one mono sample. A 16-bit row is kept as stored. An unsigned 8-bit row
becomes `(u - 128) << 8`, as in the
[sound playback](sound.md#sound-playback) PCM rule. There is no 8-bit row
in retail. `pcm16_sha256` hashes the signed 16-bit little-endian samples.
The WAV is mono, 16-bit and 11025 Hz. The engine plays every sample at
that rate, so the six rows whose header says 22050 still import at 11025.
`source_rate` records the header rate.

The disc table is read as `archive/source/sound/disc_audio.gd` documents. Track
bytes come from each track's start offset, never its start sector. The
image stores no pregap. `pcm_sha256` hashes the raw 2352-byte sectors, which
are signed 16-bit little-endian stereo. Music is imported as Ogg Vorbis,
which is lossy. The import test therefore checks only that the decoded
frame count equals `frames`; the digest is checked on the decoded track at
import time.

## Import tests

The import goldens are imported-suite tests under
`tests/imported/golden/assets/` ([testing](../../../docs/reference/testing/README.md)).
They extend `AssetTest` (`tests/imported/support/asset_test.gd`), which
opens the local `assets/` once as an `ImportedAssets` catalog and reads these
facts; every imported file is compared with the retail facts directly. They
read no retail files themselves. Beside them,
`tests/imported/golden/test_sky_script_names.gd`,
`test_swamp_script_names.gd`, `test_jungle_script_names.gd` and
`test_frontend_language_names.gd` check the frozen facts that need the
imported FrogLord name lists, and the files under `content/` are checked by
the game suite's `tests/golden/content/` without an import.

| Test | Compares |
|---|---|
| `test_asset_textures.gd` | Every `vlo_images.tsv` row with its bank resource's image: texture id, VRAM position, sizes, `u`, `v`, flags, blend mode and page, and that `texture` is `textures/images/tNNNN.png` with no stored pixels. Each PNG, decoded from the file and through its imported texture, is RGBA8 at the padded size with `padded_rgba_sha256`; its in-game region has `rgba_sha256`. The front-end and HUD images load from the catalog. |
| `test_asset_fonts.gd` | For the local catalog and one drawing a synthetic texture pack with a tinted 4x `t0310.png`, `font("newfont")` is a `FontFile` built at runtime with fixed size 32, ascent 32, descent 0 and fractional fixed-size scaling; every glyph 32 to 127 has the grid rule's UV rect, size, advance and offset (-4, -36); texture image 0 is the 1280 x 120 RGBA8 page without mipmaps whose glyph pixels repeat the source PNG and whose borders are transparent, and the retail PNG has texture 310's `padded_rgba_sha256` from `vlo_images.tsv`; `"1 UP"` measures 32 x 8 at size 8 in both. `NewfontPage.build` rebuilds the generated page exactly from the retail PNG at scales 1, 2 and 4. The pack catalog opens without problems, and an unknown font name gives null and a problem line. |
| `test_asset_tables.gd` | Every row of `exe_map_book`, `exe_theme_book`, `exe_forms`, `exe_remaps`, `exe_scripts`, `exe_music`, `exe_level_select`, `exe_demos` and `exe_pickups` built from the imported tables as the archive suite builds them from the executable; the high-score row counts; each table in its own file; the name lists. Every `*.DAT` entry has a demo resource, and each demo of `demos.tsv` has its duration, start square, input count and input digest. |
| `test_asset_census.gd` | The `asset_census.txt` counts against the files present: MWI entries, map and sky-land resources, bank resources, images, texture PNGs, models by kind with incomplete models and parts, sound banks and WAVs, the demo table and the demos it names, and music tracks. |
| `test_asset_import_settings.gd` | Every `.png`, `.wav` and `.ogg` under `assets/` has a sidecar from the expected importer whose `[params]` equal each key of the matching `importer_defaults` entry in `project.godot` (`ImportPolicyCheck`). The game suite's `tests/golden/content/test_content_import_settings.gd` applies the same check to `content/`: the `.ttf` with its MSDF keys, the lettering images with mipmaps and the masks with the `image` importer. |
| `test_asset_maps.gd` | Every map entry (78 maps and the two sky-land files) is a compressed binary resource at `maps/<NAME>.res` whose sub-resources are numbered `<Class>_<n>` in walk order, so a rerun writes identical bytes. Each file is compared with every column of `map_facts.tsv`, the per-type rows of `map_polygons.tsv`, `map_animations.tsv` and `sky_land.tsv`, and its rebuilt groups, grid stacks and squares, forms, zones and paths with the header counts. |
| `test_asset_models.gd` | Every `model_meshes.tsv` row and its options-page copy against `models/<NAME>/mesh.res`: surfaces, triangles, cels and the position, colour and pixel-UV digests (track UVs through `uv_scale`/`uv_offset`); every multi-cel part's atlas loads; `model.res` part counts match `mof_parts.tsv` and `model.tscn` instantiates with that many `Part_NN` nodes; 78 `preview.res` libraries with one track per part; the catalog serves the frog and options meshes. |
| `test_asset_sounds.gd` | Every `sound_samples.tsv` row has `audio/sfx/<BANK>/<NNN>_<name>.wav` (`<name>` is `sample` when unnamed): mono, 16-bit, at `rate`, no loop, with `frames` and `pcm16_sha256`; the bank's `SoundBankHeader` resource holds every header row, no PCM, and points present rows at their WAV through `ImportedAssets.read_sound_bank`. |
| `test_asset_music.gd` | Each of the `disc_audio_tracks` tracks of `asset_census.txt` has `audio/music/track_NN.ogg` (`oggenc -q 6 --serial NN`, byte-identical on re-encode) with no baked loop, and every `exe_music.tsv` track is present. No music table resource is written; a track's Ogg is found by its number. |

The imported suite cannot read `archive/`, so the archive suite's
`test_retail_disc_tracks.gd` checks the lengths: every
`archive/import/disc_tracks.tsv` track's Ogg has a `get_length()` within 1 ms
of `frames / 44100`. The PCM digest is checked on the decoded track at import
time only. The game suite's `test_music_player.gd` needs no import: it plays
a silent fixture, `tests/fixtures/music/track_02.ogg`.

`test_asset_emissive_images.gd` sits beside them as a consistency check of
the hand-authored `content/rendering/emissive_images.tres`, not a
retail-fact golden: the table loads without problems and validates, every
image name resolves in the imported name list, and VOL1, VOL2 and VOL3 each
draw at least one listed image.

A bank resource keeps the image headers only: each image's pixels live in
its PNG, which every bank holding the texture id shares, and `pixels` is
empty.

## How they were generated

```
python3 tools/golden/make_golden_model_meshes.py --data-dir <retail folder>
python3 tools/golden/make_golden_sound_samples.py --data-dir <retail folder>
python3 tools/golden/make_golden_disc_tracks.py --data-dir <retail folder> --disc <FROGGER.mds>  # writes archive/import/disc_tracks.tsv
python3 tools/golden/make_golden_asset_census.py --data-dir <retail folder> --disc <FROGGER.mds>
```

The bitmap font is written from an import's `t0310.png` with
`python3 tools/content/make_font_newfont.py --out <folder>`, and the lettering tiles
with `uv run tools/content/make_lettering.py --composite assets --out <folder>`;
the test wrappers run both into their run folder.

`--data-dir` defaults to `FROGGER_DATA_DIR`, and `--disc` to
`FROGGER_DISC`. `--output` names another file. `--check` compares with the
committed file, prints a diff and exits 1 on a difference. The four fact
generators use only the Python standard library. The disc track generator streams the
.mdf in 8 MB chunks.

They share `tools/golden/imported_assets_common.py`, which covers arguments, lazy
archive access and write-or-check. They also reuse the existing FrogLord
readers: `make_golden_manifest.py` (MWI, PP20, WAD), `make_golden_vlo.py`
(texture decoding), `make_golden_mof.py` (models) and
`make_golden_exe_tables.py` (books, remaps, music, demos). They were
checked against `vlo_images.tsv` per bank, `mof_parts.tsv` keys and
partcels, `mof_summary.txt`, `sound_tables.json`, `exe_music.tsv` and
the `exe_*.tsv` row counts.

## Deliberate-break checks

For each family, change one fact and require a failing assertion in its
import test. Then restore the fact and rerun.

- **Model meshes:** change a `triangles` count, then a `uvs_sha256`. The
  test must name the part.
- **Sound samples:** change a `frames` value, then a `pcm16_sha256`; the
  test must name the WAV.
- **Disc tracks:** change a `frames` value in `archive/import/disc_tracks.tsv`
  by more than 44 (1 ms); the Ogg length check of `test_retail_disc_tracks.gd`
  must name the track.
- **Maps:** change a `polygon_count` in `map_facts.tsv`, then one digit of
  a `sky_land.tsv` digest; the test must name the map and column.
- **Census:** change one count, e.g. `images`.
- **Texture images:** change one digit of a `padded_rgba_sha256`; the PNG
  and imported-texture checks must name that PNG. Then change a `flags`
  value; the header check must name the bank and image.
- **Tables and demos:** change a map id in `exe_map_book.tsv`, then a
  duration in `demos.tsv`.
- **Import settings:** set `mipmaps/generate=true` in one `.png.import`;
  the test must name the PNG and key.
- **Bitmap fonts:** corrupt one glyph field in the generator's output:
  `test_asset_newfont_runtime.gd` must fail naming the property. Change one
  digit of texture 310's `padded_rgba_sha256` in `vlo_images.tsv`: the
  retail font texture check must name the font. Set `NewfontPage.FILL_RINGS`
  to 1: the runtime page checks must fail at every scale.
- **Angular font:** change one coordinate in one `svg/*.svg`:
  `tools/content/make_angular_font.py --check` must exit 1 naming the glyph.
  Remove one derived glyph from `derived.json` and rebuild the font: the
  font test must name the character.
- **Lettering:** change one text in `lettering.tsv`:
  `tools/content/make_lettering.py --check` must exit 1 naming the id. Delete one
  lettering PNG: the content lettering test must name the id. Set
  `mipmaps/generate=false` in one lettering sidecar: the content
  import-settings test must name the file.
- **Lettering layout and masks:** change one box in `lettering_layout.tsv`:
  both `tools/content/make_lettering.py --check` and `--layout --check` must exit 1
  naming the id. Change one pixel of one mask by more than `RASTER_STEP`:
  `make_lettering.py --check` must exit 1 and `test_asset_lettering_tiles.gd`
  must name the tile and its differing pixels. Both breaks were run (a mask
  pixel of t0263 failed both, the test reporting 1 pixel differing by up to
  224; a layout box failed both checks) and restored.

Restore each break and rerun the check.

## Map UV ranges

`imported/map_uv_ranges.tsv` pins the premise of map
[terrain](../../../docs/reference/rendering/lighting.md#terrain): a
textured map polygon drawn from its own padded image with repeat wrapping
lands on the texels the retail page held. `tools/golden/make_golden_map_uv_ranges.py`
measures it from the retail executable and archive.
`test_asset_map_uv_ranges.gd` (imported suite) measures the imported maps
and banks the same way through `MapAnimationPlayer` and compares. There is no tolerance.

Each map is measured with the remap and banks of the one map-book row and
detail that names it: the GENERAL theme's bank, then the map's theme bank
named by the map file's `GENE` header, each chosen by detail and, for a
multiplayer level (`level % 6 == 5`), the theme book's multiplayer bank when
it has one. A global id is looked up in
the theme bank first. A corner's pixel is `c * size / 255` per axis, kept in
a byte (`mapload.C` `ResolveMapPolys`). The page byte is
`(pixel + u) & 255`, so the corner lies `((pixel + u) & 255) - u` from the
image's left edge (rows likewise with `v`). The corner is inside when that
is in `[0, width] x [0, height]`. Reaching `width` or `height` lands on the
first padding column or row, which repeats the edge, so every image a map
shows needs at least one padding pixel on each side. A corner's reach is how
many pixels past that range it lands.

- Static polygons are the textured polygons (FT3, FT4, GT3, GT4) that no
  animation targets and that lack the ENVMAP flag (bit 1).
- An animated instance is one animation and one non-ENVMAP target. It is
  stepped through one period of `mapdisp.c` `MapUpdateAnimatedPolys` from
  the stored counters. The UV period is the duration, the cel period is the
  cel period times the cel count, and the period is their least common
  multiple. Base pixels come from the polygon's own image. Each state is
  measured against the image the animation shows, with the offset added
  before the byte wrap.
- ENVMAP polygons get camera-driven UVs. They are only counted, and their
  images get `env` rows.

| First column | Other columns |
|---|---|
| `map` | name (the file name without `.MAP`), `textured_polygons`, `static_polygons`, `outside_static` (static polygons with a corner outside), `max_static_reach`, `animated_instances`, `outside_scroll` (instances with a state outside), `max_scroll_reach`, `scroll_textures` (ids shown while a state is outside), `env_polygons`, `env_textures` (sorted ids) |
| `env` | texture id, bank (without `.VLO`), `u`, `v`, width, height, padded width, padded height, VRAM x, VRAM y, VRAM page; one row per ENVMAP image and bank |
| `padding` | `minimum`, then the smallest one-side padding of any image a map polygon or cel shows |

In retail no static corner leaves its image on any of the 78 maps. Two
scrolls leave it. On `SWP5_WIN95`, 32 instances of texture 1456 scroll down
4 rows a tick for 12 ticks from rows 47-96 of its 96 rows, up to 44 rows
past the bottom. On the multiplayer maps `VOLM` and `VOLM_WIN95`, 2
instances of texture 1068 scroll up 2 rows a tick for 16 ticks from row 0,
up to 30 rows above the top. The ENVMAP images are 221 (SUB), 222 (ORG),
293 (FOR and the multiplayer FORM bank) and 1361 (SWP): each sits at
`u = v = 1`, 254 x 254 padded to 256 at VRAM x 0, and fills its page. 1465
(SWP) is 253 x 253 padded to 255 at the top left of page 5. The minimum
padding is 1.

The test reads no retail files. It also checks that every imported map
has one row and that each ENVMAP image's PNG, through
`ImportedAssets.texture_of`, is its padded size. It measures all 78 maps in
about 3 s.

```
python3 tools/golden/make_golden_map_uv_ranges.py [<retail folder>] [<output>] --write
```

The folder defaults to `FROGGER_DATA_DIR` and the output to
`tests/golden/imported/map_uv_ranges.tsv`. Without `--write` the generator
compares with the output, prints a diff and exits 1 on a difference.

Deliberate break: change `outside_scroll` of `SWP5_WIN95`. The generator
without `--write` must exit 1 with the diff, and the test must name the map
and column. Restore with `--write` and rerun both.

## Runtime import

`archive/tests/golden/test_retail_runtime_import.gd` runs `RuntimeImport`
once through `AssetImporterFactory` on the main thread, from `FROGGER_DATA_DIR`
into `user://runtime_import_golden/assets`, and compares it with the local
`assets/`. There is no generator: the editor import is the oracle, since
Godot's editor import produced it from the same retail files and the import
goldens above check it against the independent facts.

- The run reports no problems, leaves no `.partial` or `.old` folder, reports
  rising progress that ends at 1, and notes that it has no music exactly when
  `FROGGER_DISC` is unset. Detection names `pc-retail-v3.0e` and a 16-digit
  fingerprint and rejects a missing folder; a run cancelled at once returns
  only `the import was cancelled` and leaves no folder.
- No `.png`, `.wav`, `.ogg` or `.import` file is written.
- `tables`, `demos`, `maps`, `textures/banks`, `textures/images`, `audio/sfx`,
  `models` and `materials` hold the same files, extensions aside.
- `catalog.tres` and every `.tres`, `.res` and `.tscn` under those folders
  except the images and sounds is resource-equal: every stored property
  compared recursively, embedded resources by their own properties, external
  ones and path strings by their path below the root without extension. This
  covers the index's keys and paths.
- Every texture is a `PortableCompressedTexture2D` whose image equals the
  editor-imported texture's in size, format, mipmaps and bytes (1,858).
- Every sound effect equals the editor-imported `AudioStreamWAV` in format, rate,
  channels, loop mode and points and PCM (174).
- `ImportedAssets.open` of the root loads ORG1's map without problems.
- With `FROGGER_DISC` set, each `archive/import/disc_tracks.tsv` track is a
  16-bit stereo 44,100 Hz `AudioStreamWAV` without a loop, `frames` x 4 bytes
  long, with `pcm_sha256`; without it, the root has no `audio/music` folder.
  The suite passes either way, with no skip.

Deliberate breaks, each in a runtime run only: change one pixel of texture
1 in `textures_step.gd`, and the pixel check names `t0001.res`; add one to
ORG1DEMO.DAT's `duration` in `demos_step.gd` and set GEN_FROG's `signature`
in `models_step.gd`, and the record comparison names
`demos/ORG1DEMO.tres.duration` and `models/GEN_FROG/model.res.signature`.
Each was restored and the test rerun.

## FrogLord round trip

`pc-retail-v3.0e/froglord_roundtrip.tsv` pins P14's exit check: an edited
map, script, remap and demo, and forms repointed to other behaviours, import
and load without code. The edits are a shared specification,
`synthetic/froglord_edits.tsv`. A GDScript fixture applies them to the
retail pair and writes a FrogLord save; the generator applies them to the
decoded retail data in memory. Each side implements the formats on its own.

The specification has one tab-separated row per edit, `#` lines and blank
lines skipped. Values are decimal or `0x` hexadecimal.

| kind | target | subject | field | width |
|---|---|---|---|---|
| `form` | theme | form name | `entity_type`, `model_id`, `script_id`, `flags`, `collision_callback`, `radius_squared`, `death_type` or `bonus_callback` (+0 to +28 of the 32-byte library entry) | 32-bit, callbacks unsigned |
| `script` | script name | word index | `word` | signed 32-bit |
| `remap` | remap name | slot | `slot` | signed 16-bit |
| `demo` | archive file | input index | `input` (byte 12 + index) | unsigned 8-bit |
| `map` | archive file | entity index | `form_grid_id`, `unique_id`, `form_id` or `flags` (+0 to +6 of the EMTP record) | unsigned 16-bit |

The sixth column is a note. Every premise was checked against the retail
data: the lorry has no `[Override]`, ORG_FLY's bonus is 0x4231D0, slot 8 of
`txl_org1` is 1462 and slot 0 is 883, ORG1 entity 45 is form 1 with unique id
127, input 9 of ORG1DEMO.DAT is 0x80, GEN_STAT_FALL_BLOCK is placed only in
CAV3 and CAV3_WIN95, and no map places ORG_TRUCK_GREEN.

### Fixture

`archive/tests/support/froglord_mod_fixture.gd` opens the retail pair.
`FrogLordExePatcher` resolves names through the archive readers and patches
the executable (forms, scripts, remaps) or an archive file's unpacked bytes
(demos, maps), little-endian. `FrogLordMwdWriter` then writes FrogLord's
three files:

- `modded_FROGPSX.MWD`: the retail first sector, then every entry that is
  not group access, in MWI index order, each from a 2048-byte boundary and
  zero-padded to the next. An edited entry flagged compressed is packed
  again as PP20 literals; an edited stored entry is written as it is; every
  other entry keeps its stored bytes. Each MWI record in the executable gets
  the new sector (+12), packed size (+24) and unpacked size (+28, the
  safety-margin byte kept).
- `modded_FROGPSX.MWI`: the 48,840-byte index region of the executable.
- `modded_FROGGER.EXE`: the patched program followed by FrogLord's trailer.
  Its text is `demoTableAddress=0x<file offset>` and `lowPolyDemoTable=true`
  at the top level, then `[BuildInfo]` with `gameType=frogger`,
  `gameVersion=pc-retail-v3.0e` and `frogLordVersion=1`.

### Facts

```
python3 tools/golden/make_golden_froglord_roundtrip.py --data-dir <retail folder>
```

`--data-dir` defaults to `FROGGER_DATA_DIR`, `--spec` to the shared
specification, `--output` to the committed file; `--check` compares, prints a
diff and exits 1. The generator reuses the readers of
`make_golden_exe_tables.py`, `make_golden_entities.py` (map entities),
`make_golden_demos.py` and `make_golden_manifest.py`. It decodes the patched
executable again, and first requires its row builders to reproduce the
committed retail rows of each schema from the unedited data. Each line starts
with its section's tag; a `#` line before each section names its columns.

| Section | Rows |
|---|---|
| `edit` | each edit: kind, target, subject, field, resource (`exe` or the MWI index), offset in the executable or unpacked file, retail value, new value |
| `exe_forms`, `exe_scripts`, `exe_remaps` | the edited forms, scripts and remaps, as in the executable tables |
| `demos` | the demo-table rows of the edited demos (both detail lists) |
| `entities_retail` | the high-detail maps of ORG1 and CAV3 |
| `report` | the rows the edits add to the unmapped and unplaced support-report rows of ORG1 and CAV3: a callback that no retail form uses, on a form no map of those levels places, gives `callback`, the address, `-` (unplaced) and the form name; the report's reason text is not pinned |

### Test

`archive/tests/golden/test_retail_froglord_roundtrip.gd` writes the fixture
to `user://froglord_fixture/` and requires:

- `GameDataLocator.open_directory` gives a `FrogLordModSource`; detection
  uses the trailer and finds `pc-retail-v3.0e`; `GameData` opens without an
  error or warnings, compared the standalone index and decodes every table;
- the demo table read from the build information equals the one the retail
  search finds;
- the patcher's resolved edits equal `edit`;
- the rows built with `RetailFactRows` from the modded files equal their
  sections;
- the importer's `names`, `tables`, `demos`, `maps` and `catalog` steps, run
  in-process into `user://froglord_roundtrip/` with `res://assets` as the
  fallback root, report no problems; `ImportedAssets.open` of that index has
  source kind `FrogLord mod`, the trailer's FrogLord version and the fallback
  root, draws texture banks from `res://assets` and ORG1's map from the
  overlay, and yields the same rows;
- `MapSceneData` and `GameplaySetup` load ORG1 and CAV3 from the overlay: the
  lorries are tongueable, entity 45 is ORG_CAR_PURPLE, the bonus fly scores
  as a cave firefly, remap slot 8 gives 883, the ORG1 demo's input 9 is 132
  and CAV3's fall blocks have waterfall-block contacts;
- `LevelSupportReport` of the overlay adds exactly the `report` rows (kind,
  key, levels and form) to the retail report's unmapped and unplaced rows.

Both folders are removed afterwards.

### Deliberate breaks

- Change ORG_LORRY's `entity_type` in `exe_forms`: the modded-file and
  overlay checks name the form row.
- Change a digit of the ORG1DEMO.DAT digest in `demos`: both checks name the
  demo.
- Change the remap value in `froglord_edits.tsv` without regenerating:
  `--check` exits 1 with the `edit` and `exe_remaps` lines of `txl_org1` slot
  8, and the test names the `edit` row and the remap row.

Each was restored and `--check` rerun.

[Golden data index and shared rules](../README.md). Commands above run from the repository root.

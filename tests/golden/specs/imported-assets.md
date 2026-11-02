# Imported assets (`pc-retail-v3.0e/model_meshes.tsv`, `sound_samples.tsv`, `disc_tracks.tsv`, `asset_census.txt`)

S1c imports every retail asset into `assets/`. These facts say what each
imported file must hold. They are derived from the retail bytes by
independent Python that reads no Godot output. The import goldens decode the
committed assets and compare. Model facts
are the same for every texture bank context: the model generator checks that
every texture id has one size and padding in every bank that holds it.

| File | One row per | Columns |
|---|---|---|
| `model_meshes.tsv` | part of a static model (1,009, the keys of `mof_parts.tsv`) | resource id, file name, static model inside the file, part, surfaces, triangles, cels, `unresolved_textured_polygons`, `positions_sha256`, `colours_sha256`, `uvs_sha256` |
| `sound_samples.tsv` | present sound-bank row (174) | sound id, bank, body file name, FrogLord sound name, `source_bits`, `source_rate`, frames, `rate` (always 11025), `pcm16_sha256` |
| `disc_tracks.tsv` | audio track of the disc image (31) | track, FrogLord music name (`-` if none), first sector (from the table, pregap included), sectors, frames (44.1 kHz stereo), seconds (3 decimals), `pcm_sha256`, the levels whose music-table entry plays it (`-` if none) |
| `asset_census.txt` | count, `key=value` | MWI entries, maps (FROG and sky land), VLO banks, images, distinct texture ids, models by kind and incomplete models, model parts, sound banks and samples, demo tables, rows and distinct demos, disc tracks, rows of every EXE table (`rows[exe_*]`, as `make_golden_exe_tables.py` writes them, plus the two high-score tables) |

`-` is an empty list. List digests follow the
[shared convention](../README.md#digest-convention).

## Bitmap fonts

`newfont` is texture 310, 96 glyphs of ASCII 32 to 127 in square cells, 32
to a row in three rows, with no padding: `textures/images/t0310.png` is
256 x 24 (8-pixel cells), `textures/images_x4/t0310.png` 1024 x 96. Its
scale S is the PNG width divided by 256, and the height must be 24 x S.
`tools/make_font_newfont.py` writes, for each set whose PNG exists,
`fonts/retail/` and `fonts/x4/` holding `newfont.fnt`, a BMFont v3 text file,
and `newfont.png`, the page the font names as its only page. S must divide 4.
The page enlarges the set's PNG 4 / S times by repeating pixels, so every
glyph is 32 x 32, and sets each glyph inside a 4-pixel transparent border:
40 x 40 cells, 32 to a row, on a 1280 x 120 page. The two rings of
transparent pixels around each glyph's opaque pixels, within its cell, take
the per-channel maximum colour of their already filled 8-neighbours, ring by
ring; other transparent pixels keep the source's colour or zero. The font's
`size`, `lineHeight` and `base` are 32, `scaleW` and `scaleH` 1280 and 120,
and `alphaChnl=0` with the colour channels at 4, so the importer keeps the
RGBA pixels (the glyphs are eight grey levels; `alphaChnl=1` would turn them
white on alpha). The `info` line ends with `page_sha256`, the SHA-256 of
the page's RGBA rows, which Godot ignores; it makes a page change change the
`.fnt`, since the importer does not track the page. Glyph `id` sits at
`x = ((id - 32) % 32) * 40`,
`y = ((id - 32) / 32) * 40` with width and height 40, `xoffset` and
`yoffset` -4 and `xadvance` 32. The page is a separate file because the font
importer sets the importer of every page image it reads to `skip`, which
would take `t0310.png` away from the texture banks.

The `.fnt` and the page are the generated artefacts, not facts: the
generator's `--check` is the comparison (page pixels, not bytes). It writes
nothing, prints a diff for each differing `.fnt`, names each differing or
missing file and exits 1;
both test wrappers run it before importing and stop with exit 2 on a
difference. Without `images_x4/t0310.png` the x4 font is skipped. A hand
edit of a set's `t0310.png` is carried into its font by rerunning the
generator.

Each `.fnt` is imported by `font_data_bmfont` with the `importer_defaults`
entry in `project.godot`: `compress` true, no `fallbacks` and
`scaling_mode` 2 (fractional), so both fonts, whose fixed size is 32, draw
at size 8 scaled by a quarter. Its page `newfont.png` has the `skip`
importer. The golden checks the grid (fixed size, ascent, UV rectangles,
glyph size, advance and offset (-4, -36)), that every glyph pixel's alpha,
and colour where opaque, equals the source PNG pixel it repeats and every
border pixel is transparent, the retail source's digest, and that "1 UP"
measures 32 x 8 at size 8 in both sets. The catalog's texture set chooses the font:
`ImportedAssets.font(name)` loads `fonts/<set>/<name>.fnt`, falls back to
the retail set's file with a line in `problems` when the set has none, and
returns null with a problem line when neither exists.

## Angular font

The angular letter face (the retail lettering and the alpha's letter
models) is a TrueType font, `fonts/angular/frogger_angular.ttf`, written by
`uv run tools/make_angular_font.py` from two sources beside it:

- `svg/A.svg` to `svg/9.svg`: 36 third-party SVG traces, kept byte for byte
  (CRLF included, so `.gitattributes` marks them `-text`); `svg/.gdignore`
  keeps Godot from importing them. Each viewBox is `0 0 W 800`; only
  `<path>` (M, L, H, V, Z) and `<polygon>` are read, paths that never draw
  a third point are skipped, and the fill is even-odd.
- `derived.json`: `! ¡ ' : - . = ◀ É Ó Í Ù Ä Ü Ç` as hand-cut polygons in
  font units, optionally on a `base` glyph (`rotate` 180 for `¡`).

`tools/angular_glyphs.py` turns both into contours in font units (y up,
baseline 0, cap height 800, x from the ink box's left); the lettering
generator reuses it. The font has 1000 units per em, so source units are
font units; each glyph has side bearings of 40 units (`lsb` equals `xMin`)
and the space advances 320. Contours are oriented by nesting depth for the
nonzero fill, and crossing contours are refused. Ascent and descent are the
outline extremes (1060 and -250). The head timestamps are fixed, so the
bytes reproduce with the fontTools pinned in `uv.lock`. The TTF is the
generated artefact: `--check` names each glyph, metric or table that
differs and exits 1, and both wrappers run it next to the newfont check.

It is imported by `font_data_dynamic` with the keys in
`test_asset_import_settings.gd`: MSDF on (pixel range 16, size 64), no
hinting, no mipmaps and no system fallback. `test_asset_angular_font.gd`
loads it as a `FontFile` with MSDF on, requires a glyph with a positive
advance for every capital, digit, derived character and the space and no
lowercase, and requires its own character list to equal the SVG names plus
`derived.json`'s keys, read with Godot's directory listing and JSON parser.

## Lettering

`textures/lettering/tNNNN.png` replaces the retail texture `tNNNN` wherever
the angular face is baked into it (words in five languages, level names, HUD
digits, the high-score pads, rank turtles and score logs). The game draws it
in every texture set. `uv run tools/make_lettering.py` writes one PNG per row
of `fonts/angular/lettering.tsv`, drawn from the glyphs of
`tools/angular_glyphs.py`. The table's columns are `id`, `name` (FrogLord's
name or `-`), `language` (`en`, `s`, `g`, `i`, `f` or `-`), `text` (`|`
breaks a line; retail spelling and spacing), `style`, `background`
(`transparent`, `green_pad`, `log`, `turtle`) and `layout` (`line`, or
`components` for `hi_end`, whose letters are fitted one per retail ink
component). The generator's docstring defines the styles, the fit and the
backgrounds.

Each PNG is exactly eight times the retail padded size. Transparent words
have straight alpha with the outermost colour under alpha 0; tiles are
opaque. No channel is below 8. The PNGs are generated artefacts, not facts:
`--check` decodes each committed PNG and compares its pixels with a fresh
rendering, checks each sidecar's importer and policy keys, names every id
that differs, is missing or has no row, and exits 1. Both wrappers run it
next to the angular font check. Each sidecar uses the texture importer with
mipmaps and otherwise the project defaults; a new image's seed sidecar is
completed by `godot --headless --path . --import`.

`test_asset_lettering.gd` reads the table and `vlo_images.tsv` with Godot's
file access. It requires:

- one PNG per row at eight times the row's padded size, and no PNG without
  a row;
- each imported texture to carry mipmaps;
- `ImportedAssets.texture_counterpart` of the retail texture to return the
  lettering image in the retail and x4 sets, with no problems;
- `frogger_angular.ttf` to hold every character the table writes.

The import-settings test holds the folder to mipmaps on.

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

The disc table is read as `src/source/sound/disc_audio.gd` documents. Track
bytes come from each track's start offset, never its start sector. The
image stores no pregap. `pcm_sha256` hashes the raw 2352-byte sectors, which
are signed 16-bit little-endian stereo. Music is committed as Ogg Vorbis,
which is lossy. The import test therefore checks only that the decoded
frame count equals `frames`. The digest applies to a lossless copy checked
with `tools/hash_asset.py`.

## Import tests

The import goldens are game-suite tests under `tests/golden/assets/`. They
extend `AssetTest` (`tests/support/asset_test.gd`), which opens `assets/` once
as an `ImportedAssets` catalog and reads these facts and the reviewed
overrides. They need no retail files.

| Test | Compares |
|---|---|
| `test_asset_textures.gd` | Every `vlo_images.tsv` row with its bank resource's image: texture id, VRAM position, sizes, `u`, `v`, flags, blend mode and page, and that `texture` is `textures/images/tNNNN.png` with no stored pixels. Each PNG, decoded from the file and through its imported texture, is RGBA8 at the padded size with `padded_rgba_sha256`; its in-game region has `rgba_sha256`. The front-end and HUD images load from the catalog. |
| `test_asset_fonts.gd` | For the retail and x4 catalogs, `font("newfont")` is a `FontFile` under `fonts/<set>/` with fixed size, ascent 8 x S, descent 0 and fractional fixed-size scaling; every glyph 32 to 127 has the grid rule's UV rect, size, advance and offset (0, -8S); texture image 0 is 256S x 24S RGBA8 without mipmaps and equals `textures/images[_x4]/t0310.png`, and the retail one has texture 310's `padded_rgba_sha256` from `vlo_images.tsv`; `"1 UP"` measures 32 x 8 at size 8 in both sets. The x4 catalog opens without problems, and an unknown font name gives null and a problem line. |
| `test_asset_tables.gd` | Every row of `exe_map_book`, `exe_theme_book`, `exe_forms`, `exe_remaps`, `exe_scripts`, `exe_music`, `exe_level_select`, `exe_demos` and `exe_pickups` built from the imported tables as the archive suite builds them from the executable; the high-score row counts; each table in its own file; the name lists. Every `*.DAT` entry has a demo resource, and each demo of `demos.tsv` has its duration, start square, input count and input digest. |
| `test_asset_census.gd` | The `asset_census.txt` counts against the files present: MWI entries, map and sky-land resources, bank resources, images, texture PNGs, models by kind with incomplete models and parts, sound banks and WAVs, the demo table and the demos it names, and music tracks. |
| `test_asset_import_settings.gd` | Every `.png`, `.wav`, `.ogg` and `.fnt` under `assets/` has a sidecar from the expected importer whose `[params]` equal each key of the matching `importer_defaults` entry in `project.godot`, except the keys `FOLDER_POLICIES` sets for a folder (`images_x4/` generates mipmaps). A font page `fonts/*/newfont.png` must have the `skip` importer (`FOLDER_IMPORTERS`). |
| `test_asset_maps.gd` | Every map entry (78 maps and the two sky-land files) is a compressed binary resource at `maps/<NAME>.res` whose sub-resources are numbered `<Class>_<n>` in walk order, so a rerun writes identical bytes. Each file is compared with every column of `map_facts.tsv`, the per-type rows of `map_polygons.tsv`, `map_animations.tsv` and `sky_land.tsv`, and its rebuilt groups, grid stacks and squares, forms, zones and paths with the header counts. |
| `test_asset_models.gd` | Every `model_meshes.tsv` row and its options-page copy against `models/<NAME>/mesh.res`: surfaces, triangles, cels and the position, colour and pixel-UV digests (track UVs through `uv_scale`/`uv_offset`); every multi-cel part's atlas loads; `model.res` part counts match `mof_parts.tsv` and `model.tscn` instantiates with that many `Part_NN` nodes; 78 `preview.res` libraries with one track per part; the catalog serves the frog and options meshes. |
| `test_asset_sounds.gd` | Every `sound_samples.tsv` row has `audio/sfx/<BANK>/<NNN>_<name>.wav` (`<name>` is `sample` when unnamed): mono, 16-bit, at `rate`, no loop, with `frames` and `pcm16_sha256`; the bank's `SoundBankHeader` resource holds every header row, no PCM, and points present rows at their WAV through `ImportedAssets.read_sound_bank`. |
| `test_asset_music.gd` | Every `disc_tracks.tsv` audio track has `audio/music/track_NN.ogg` (`oggenc -q 6 --serial NN`, byte-identical on re-encode) whose `get_length()` is within 1 ms of `frames / 44100` with no baked loop, and every `exe_music.tsv` track is present. The PCM digest is checked on the decoded WAV at import time only; no music table resource is written, a track's Ogg is found by its number. |

`test_asset_emissive_images.gd` sits beside them as a consistency check of
the hand-authored `rendering/emissive_images.tres`, not a retail-fact golden:
the table loads without problems and validates, every image name resolves in
the committed name list, and VOL1, VOL2 and VOL3 each draw at least one
listed image.

A bank resource keeps the image headers only: each image's pixels live in
its PNG, which every bank holding the texture id shares, and `pixels` is
empty.

## Reviewed overrides

A reviewed hand edit of a committed asset gets one row in
`tests/golden/imported/overrides.tsv`:

| Column | Meaning |
|---|---|
| asset | path under `assets/` |
| family | `model_meshes`, `sound_samples`, `disc_tracks` or `vlo_images` |
| field | the fact column it replaces, e.g. `rgba_sha256` |
| value | the new value |
| reason | why the edit was made; must not be empty |

The import tests look up (asset, family, field) before they use the retail
fact. `python3 tools/hash_asset.py <file>` prints the PNG digest (RGBA8,
padded) and opaque count, or the WAV frames and PCM digest. Its
`--self-test` round-trips PNG filters 0-4 and a WAV. Retail facts are never
edited to match an asset.

## How they were generated

```
python3 tools/make_golden_model_meshes.py --data-dir <retail folder>
python3 tools/make_golden_sound_samples.py --data-dir <retail folder>
python3 tools/make_golden_disc_tracks.py --data-dir <retail folder> --disc <FROGGER.mds>
python3 tools/make_golden_asset_census.py --data-dir <retail folder> --disc <FROGGER.mds>
```

The bitmap fonts are written from the committed PNGs with
`python3 tools/make_font_newfont.py`; it needs no retail folder.

`--data-dir` defaults to `FROGGER_DATA_DIR`, and `--disc` to
`FROGGER_DISC`. `--output` names another file. `--check` compares with the
committed file, prints a diff and exits 1 on a difference. All generators
use only the Python standard library. The disc track generator streams the
.mdf in 8 MB chunks.

They share `tools/imported_assets_common.py`, which covers arguments, lazy
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
- **Disc tracks:** change a `frames` value. The Ogg length check must fail.
- **Maps:** change a `polygon_count` in `map_facts.tsv`, then one digit of
  a `sky_land.tsv` digest; the test must name the map and column.
- **Census:** change one count, e.g. `images`.
- **Texture images:** change one digit of a `padded_rgba_sha256`; the PNG
  and imported-texture checks must name that PNG. Then change a `flags`
  value; the header check must name the bank and image. Adding an override
  row with the true digest must make the PNG checks pass again.
- **Tables and demos:** change a map id in `exe_map_book.tsv`, then a
  duration in `demos.tsv`.
- **Import settings:** set `mipmaps/generate=true` in one `.png.import`;
  the test must name the PNG and key. Set `mipmaps/generate=false` in one
  `images_x4/*.png.import`; the test must name it.
- **Bitmap fonts:** change one `x=` in `fonts/retail/newfont.fnt`:
  `tools/make_font_newfont.py --check` must exit 1 with a diff, and the font
  test must name the set and glyph. Set `scaling_mode=0` in
  `fonts/x4/newfont.fnt.import`: the x4 string-size check must fail and the
  import-settings test must name the file and key. Change one digit of
  texture 310's `padded_rgba_sha256` in `vlo_images.tsv`: the retail font
  texture check must name the font.
- **Angular font:** change one coordinate in one `svg/*.svg`:
  `tools/make_angular_font.py --check` must exit 1 naming the glyph.
  Remove one derived glyph from `derived.json` and rebuild the font: the
  font test must name the character.
- **Lettering:** change one text in `lettering.tsv`:
  `tools/make_lettering.py --check` must exit 1 naming the id. Delete one
  lettering PNG: the lettering test must name the id. Set
  `mipmaps/generate=false` in one lettering sidecar: the import-settings test
  must name the file.

The generators' `--check` mode was broken and restored in the same way for
all four files. Each import-test break was restored and the test rerun.

## Map UV ranges

`imported/map_uv_ranges.tsv` pins the premise of map
[terrain](../../../docs/reference/rendering/lighting.md#terrain): a
textured map polygon drawn from its own padded image with repeat wrapping
lands on the texels the retail page held. `tools/make_golden_map_uv_ranges.py`
measures it from the retail executable and archive.
`test_asset_map_uv_ranges.gd` measures the committed maps and banks the same
way through `MapAnimationPlayer` and compares. There is no tolerance.

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

The test needs no retail files. It also checks that every committed map
has one row and that each ENVMAP image's PNG, through
`ImportedAssets.texture_of`, is its padded size. It measures all 78 maps in
about 3 s.

```
python3 tools/make_golden_map_uv_ranges.py [<retail folder>] [<output>] --write
```

The folder defaults to `FROGGER_DATA_DIR` and the output to
`tests/golden/imported/map_uv_ranges.tsv`. Without `--write` the generator
compares with the output, prints a diff and exits 1 on a difference.

Deliberate break: change `outside_scroll` of `SWP5_WIN95`. The generator
without `--write` must exit 1 with the diff, and the test must name the map
and column. Restore with `--write` and rerun both.

[Golden data index and shared rules](../README.md). Commands above run from the repository root.

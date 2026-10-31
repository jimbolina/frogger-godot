# Imported assets (`pc-retail-v3.0e/texture_pages.tsv`, `model_meshes.tsv`, `sound_samples.tsv`, `disc_tracks.tsv`, `asset_census.txt`, `imported/texture_pages_x4.tsv`)

S1c imports every retail asset into `assets/`. These facts say what each
imported file must hold. They are derived from the retail bytes by
independent Python that reads no Godot output. The import goldens decode the
committed assets and compare. Model facts
are the same for every texture bank context: the model generator checks that
every texture id has one size and padding in every bank that holds it.

| File | One row per | Columns |
|---|---|---|
| `texture_pages.tsv` | page of a map texture set (28 sets x 14 pages), plus one sky-land atlas per sky set | set (`<GENERAL bank>+<theme bank>`, the two bank file names), page (0-13, or `sky:<pages>` for the atlas), `rgba_sha256`, `opaque_pixels` |
| `model_meshes.tsv` | part of a static model (1,009, the keys of `mof_parts.tsv`) | resource id, file name, static model inside the file, part, surfaces, triangles, cels, `unresolved_textured_polygons`, `positions_sha256`, `colours_sha256`, `uvs_sha256` |
| `sound_samples.tsv` | present sound-bank row (174) | sound id, bank, body file name, FrogLord sound name, `source_bits`, `source_rate`, frames, `rate` (always 11025), `pcm16_sha256` |
| `disc_tracks.tsv` | audio track of the disc image (31) | track, FrogLord music name (`-` if none), first sector (from the table, pregap included), sectors, frames (44.1 kHz stereo), seconds (3 decimals), `pcm_sha256`, the levels whose music-table entry plays it (`-` if none) |
| `imported/texture_pages_x4.tsv` | page of a map texture set at scale 4 (28 sets x 14 pages), plus one sky-land atlas per sky set | set, page (as `texture_pages.tsv`), width, height, `rgba_sha256`, `opaque_pixels` |
| `asset_census.txt` | count, `key=value` | MWI entries, maps (FROG and sky land), VLO banks, images, distinct texture ids, models by kind and incomplete models, model parts, sound banks and samples, demo tables, rows and distinct demos, disc tracks, rows of every EXE table (`rows[exe_*]`, as `make_golden_exe_tables.py` writes them, plus the two high-score tables) |

`-` is an empty list. List digests follow the
[shared convention](../README.md#digest-convention).

## Texture pages

A set is the two banks `MapSceneData` loads for a map: the GENERAL theme's
bank, then the map's theme bank. The theme comes from the map file's
`GENE` header. Each bank is chosen by detail and multiplayer level
(`level % 6 == 5`). The multiplayer bank is used when the theme book has
one, otherwise the ordinary bank. Every non-dummy map-book row in both
details is included, so there are 28 distinct sets.

A page is composed as follows:

1. Start with 256 x 256 RGBA8 pixels of RGB 0,0,0 and alpha 255.
2. Visit the images of the GENERAL bank, then the theme bank, in stored
   order. Skip an image whose upload is invalid: a negative VRAM position,
   an empty size, `vram_x + padded width > 256` or
   `vram_y + padded height > 14 * 256`.
3. Copy the overlap of each upload rectangle (`vram_x`, `vram_y`, padded
   width and height) with page rows `page * 256` to `page * 256 + 255`
   onto the page. Copy all four bytes; later uploads overwrite earlier ones.
   The source is the padded image decoded as in
   [textures](textures.md).
4. Apply the colour key only when a valid image whose own page
   (`vram_y / 256`) is this page has flag bit 5. In that case, every pixel
   on the page whose RGB is exactly 0,0,0 gets alpha 0, including padding
   and neighbouring images. Every other pixel gets alpha 255. Without such
   an image, every pixel is opaque.

`rgba_sha256` hashes the 262,144 page bytes in row order.
`opaque_pixels` counts alpha 255. This exact-RGB-zero key belongs only to
the map page. Individual textures keep the 5-bit rule in `vlo_images.tsv`.

### Sky-land atlas

A set used by a sky level (theme 8) gets one atlas row. Read the level's
sky-land file: `SKY_LAND.MAP` for high detail or `SKY_LAND_WIN95.MAP` for
low detail. For each tile in row-major order, mask the stored value with
`0x3FFF` to get its local texture id. Map the local id through the
executable's `txl_sky_land` remap. Find the image in the theme bank first,
then in the GENERAL bank. Pages are numbered in first-seen order. A missing
image counts as page -1. The `sky:` label lists the pages.

The atlas is 256 wide by 258 per page, filled with magenta
(255,0,255,255). Each page in slot `s` is copied to rows `258*s+1` to
`258*s+256`. Page row 0 is repeated at row `258*s`, and page row 255 at row
`258*s+257`. A page -1 slot stays magenta. Both sky-land files give the
same atlas. The generator fails if they ever differ.

### Texture pages at scale

`imported/texture_pages_x4.tsv` pins the pages `tools/bake_pages_x4.py`
bakes locally into `assets/textures/pages_x4/` from the committed x4 images.
It lives under `imported/` because it describes derived files, not retail
bytes. `make_golden_texture_pages_x4.py` composes each page at scale S (4)
with the rule above multiplied by S: placement, upload order, validity,
flags, set membership and sky order come from the retail executable and
banks; only each upload's RGB comes from `assets/textures/images_x4/tNNNN.png`
(S times the padded size, decoded with Pillow). A keyed page's alpha is the
nearest S-times enlargement of the retail page's key mask, with RGB 0 under
alpha 0; other pages are opaque. Each sky slot is 258 x S rows: the scaled
page's first row repeated S times, the scaled page, then its last row
repeated S times. `rgba_sha256` hashes the 1024 x 1024 x 4 bytes;
`opaque_pixels` counts alpha 255. The bake tool reads only `assets/` (the
bank and page-set resources as text) and composes every set at scale 1
first, stopping unless that reproduces the committed pages.

### Bitmap fonts

`newfont` is texture 310, 96 glyphs of ASCII 32 to 127 in square cells, 32
to a row in three rows, with no padding: `textures/images/t0310.png` is
256 x 24 (8-pixel cells), `textures/images_x4/t0310.png` 1024 x 96. Its
scale S is the PNG width divided by 256, and the height must be 24 x S.
`tools/make_font_newfont.py` writes, for each set whose PNG exists,
`fonts/retail/` and `fonts/x4/` holding `newfont.fnt`, a BMFont v3 text file,
and `newfont.png`, a byte copy of the set's `t0310.png` that the font names
as its only page. The font's `size`, `lineHeight` and `base` are 8 x S,
`scaleW` and `scaleH` the PNG size, and `alphaChnl=0` with the colour
channels at 4, so the importer keeps the RGBA pixels (the glyphs are eight
grey levels; `alphaChnl=1` would turn them white on alpha). Glyph `id` sits
at `x = ((id - 32) % 32) * 8S`, `y = ((id - 32) / 32) * 8S` with width,
height and `xadvance` 8 x S and no offsets. The page is a copy because the
font importer sets the importer of every page image it reads to `skip`,
which would take `t0310.png` away from the texture banks.

The `.fnt` and the page copy are the generated artefacts, not facts: the
generator's `--check` is the comparison. It writes nothing, prints a diff
for each differing `.fnt`, names each differing or missing file and exits 1;
both test wrappers run it before importing and stop with exit 2 on a
difference. Without `images_x4/t0310.png` the x4 font is skipped. A hand
edit of a set's `t0310.png` is carried into its font by rerunning the
generator.

Each `.fnt` is imported by `font_data_bmfont` with the `importer_defaults`
entry in `project.godot`: `compress` true, no `fallbacks` and
`scaling_mode` 2 (fractional), so the x4 font, whose fixed size is 32,
draws at size 8 scaled by a quarter. Its page `newfont.png` has the
`skip` importer. The catalog's texture set chooses the font:
`ImportedAssets.font(name)` loads `fonts/<set>/<name>.fnt`, falls back to
the retail set's file with a line in `problems` when the set has none, and
returns null with a problem line when neither exists.

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
| `test_asset_textures.gd` | Every `vlo_images.tsv` row with its bank resource's image: texture id, VRAM position, sizes, `u`, `v`, flags, blend mode and page, and that `texture` is `textures/images/tNNNN.png` with no stored pixels. Each PNG, decoded from the file and through its imported texture, is RGBA8 at the padded size with `padded_rgba_sha256`; its in-game region has `rgba_sha256`. Every `texture_pages.tsv` row with the page PNG of its `TexturePageSet` (`rgba_sha256`, `opaque_pixels`) or its sky atlas and `sky_pages`. The front-end and HUD images and `MapTexturePages` load from the catalog. |
| `test_asset_pages_x4.gd` | Every retail page set has a baked `pages_x4/<SET>/page_set.tres` with the same banks, colour keys and sky order and `scale()` 4; every `imported/texture_pages_x4.tsv` row's PNG at its size with `rgba_sha256` and `opaque_pixels`; x4 pages and images import with mipmaps, retail ones without. The catalog opened with `TextureSet.X4` draws them. |
| `test_asset_fonts.gd` | For the retail and x4 catalogs, `font("newfont")` is a `FontFile` under `fonts/<set>/` with fixed size, ascent 8 x S, descent 0 and fractional fixed-size scaling; every glyph 32 to 127 has the grid rule's UV rect, size, advance and offset (0, -8S); texture image 0 is 256S x 24S RGBA8 without mipmaps and equals `textures/images[_x4]/t0310.png`, and the retail one has texture 310's `padded_rgba_sha256` from `vlo_images.tsv`; `"1 UP"` measures 32 x 8 at size 8 in both sets. The x4 catalog opens without problems, and an unknown font name gives null and a problem line. |
| `test_asset_tables.gd` | Every row of `exe_map_book`, `exe_theme_book`, `exe_forms`, `exe_remaps`, `exe_scripts`, `exe_music`, `exe_level_select`, `exe_demos` and `exe_pickups` built from the imported tables as the archive suite builds them from the executable; the high-score row counts; each table in its own file; the name lists. Every `*.DAT` entry has a demo resource, and each demo of `demos.tsv` has its duration, start square, input count and input digest. |
| `test_asset_census.gd` | The `asset_census.txt` counts against the files present: MWI entries, map and sky-land resources, bank resources, images, texture PNGs, models by kind with incomplete models and parts, sound banks and WAVs, the demo table and the demos it names, and music tracks. |
| `test_asset_import_settings.gd` | Every `.png`, `.wav`, `.ogg` and `.fnt` under `assets/` has a sidecar from the expected importer whose `[params]` equal each key of the matching `importer_defaults` entry in `project.godot`, except the keys `FOLDER_POLICIES` sets for a folder (`images_x4/` and `pages_x4/` generate mipmaps). A font page `fonts/*/newfont.png` must have the `skip` importer (`FOLDER_IMPORTERS`). |
| `test_asset_maps.gd` | Every map entry (78 maps and the two sky-land files) is a compressed binary resource at `maps/<NAME>.res` whose sub-resources are numbered `<Class>_<n>` in walk order, so a rerun writes identical bytes. Each file is compared with every column of `map_facts.tsv`, the per-type rows of `map_polygons.tsv`, `map_animations.tsv` and `sky_land.tsv`, and its rebuilt groups, grid stacks and squares, forms, zones and paths with the header counts. |
| `test_asset_models.gd` | Every `model_meshes.tsv` row and its options-page copy against `models/<NAME>/mesh.res`: surfaces, triangles, cels and the position, colour and pixel-UV digests (track UVs through `uv_scale`/`uv_offset`); every multi-cel part's atlas loads; `model.res` part counts match `mof_parts.tsv` and `model.tscn` instantiates with that many `Part_NN` nodes; 78 `preview.res` libraries with one track per part; the catalog serves the frog and options meshes. |
| `test_asset_sounds.gd` | Every `sound_samples.tsv` row has `audio/sfx/<BANK>/<NNN>_<name>.wav` (`<name>` is `sample` when unnamed): mono, 16-bit, at `rate`, no loop, with `frames` and `pcm16_sha256`; the bank's `SoundBankHeader` resource holds every header row, no PCM, and points present rows at their WAV through `ImportedAssets.read_sound_bank`. |
| `test_asset_music.gd` | Every `disc_tracks.tsv` audio track has `audio/music/track_NN.ogg` (`oggenc -q 6 --serial NN`, byte-identical on re-encode) whose `get_length()` is within 1 ms of `frames / 44100` with no baked loop, and every `exe_music.tsv` track is present. The PCM digest is checked on the decoded WAV at import time only; no music table resource is written, a track's Ogg is found by its number. |

A bank resource keeps the image headers only: each image's pixels live in
its PNG, which every bank holding the texture id shares, and `pixels` is
empty. A page set is `textures/pages/<GENERAL bank>+<theme bank>/` with
`page_00.png` to `page_13.png`, `sky.png` for a sky set and `page_set.tres`;
bank names drop `.VLO`.

## Reviewed overrides

A reviewed hand edit of a committed asset gets one row in
`tests/golden/imported/overrides.tsv`:

| Column | Meaning |
|---|---|
| asset | path under `assets/` |
| family | `texture_pages`, `texture_pages_x4`, `model_meshes`, `sound_samples`, `disc_tracks` or `vlo_images` |
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
python3 tools/make_golden_texture_pages.py --data-dir <retail folder>
python3 tools/make_golden_model_meshes.py --data-dir <retail folder>
python3 tools/make_golden_sound_samples.py --data-dir <retail folder>
python3 tools/make_golden_disc_tracks.py --data-dir <retail folder> --disc <FROGGER.mds>
python3 tools/make_golden_asset_census.py --data-dir <retail folder> --disc <FROGGER.mds>
python3 tools/make_golden_texture_pages_x4.py --data-dir <retail folder>
```

The bitmap fonts are written from the committed PNGs with
`python3 tools/make_font_newfont.py`; it needs no retail folder.

`--data-dir` defaults to `FROGGER_DATA_DIR`, and `--disc` to
`FROGGER_DISC`. `--output` names another file. `--check` compares with the
committed file, prints a diff and exits 1 on a difference. All generators
use only the Python standard library, except the x4 page generator, which
decodes the upscaled PNGs with Pillow. The disc track generator streams the
.mdf in 8 MB chunks.

They share `tools/imported_assets_common.py`, which covers arguments, lazy
archive access and write-or-check. They also reuse the existing FrogLord
readers: `make_golden_manifest.py` (MWI, PP20, WAD), `make_golden_vlo.py`
(texture decoding), `make_golden_mof.py` (models) and
`make_golden_exe_tables.py` (books, remaps, music, demos). They were
checked against `vlo_images.tsv` per bank, `mof_parts.tsv` keys and
partcels, `mof_summary.txt`, `sound_tables.json`, `exe_music.tsv` and
the `exe_*.tsv` row counts. In the `GEN_HI_VRAM.VLO+ORG_VRAM.VLO` set,
every unkeyed page region that no later upload overwrites matches its
image's padded digest.

## Deliberate-break checks

For each family, change one fact and require a failing assertion in its
import test. Then restore the fact and rerun.

- **Texture pages:** change one digit of one `rgba_sha256`. The page test
  must fail for that set and page only. Then change an `opaque_pixels`.
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
- **Texture pages at scale:** change one digit of one `rgba_sha256` in
  `imported/texture_pages_x4.tsv`, then an `opaque_pixels`; the x4 page
  test must name the set and page. Punch a transparent pixel into one baked
  `pages_x4/` PNG: `tools/bake_pages_x4.py --check` must exit 1 naming the
  file, and the test wrapper's bake step restores it.
- **Bitmap fonts:** change one `x=` in `fonts/retail/newfont.fnt`:
  `tools/make_font_newfont.py --check` must exit 1 with a diff, and the font
  test must name the set and glyph. Set `scaling_mode=0` in
  `fonts/x4/newfont.fnt.import`: the x4 string-size check must fail and the
  import-settings test must name the file and key. Change one digit of
  texture 310's `padded_rgba_sha256` in `vlo_images.tsv`: the retail font
  texture check must name the font.

The generators' `--check` mode was broken and restored in the same way for
all five files. Each import-test break was restored and the test rerun.

[Golden data index and shared rules](../README.md). Commands above run from the repository root.

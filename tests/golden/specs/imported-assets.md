# Imported assets (`pc-retail-v3.0e/texture_pages.tsv`, `model_meshes.tsv`, `sound_samples.tsv`, `disc_tracks.tsv`, `asset_census.txt`)

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

## Reviewed overrides

A reviewed hand edit of a committed asset gets one row in
`tests/golden/imported/overrides.tsv`:

| Column | Meaning |
|---|---|
| asset | path under `assets/` |
| family | `texture_pages`, `model_meshes`, `sound_samples`, `disc_tracks` or `vlo_images` |
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
```

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
- **Sound samples:** change a `frames` value, then a `pcm16_sha256`.
- **Disc tracks:** change a `frames` value. The Ogg length check must fail.
- **Census:** change one count, e.g. `images`.

The generators' `--check` mode was broken and restored in the same way for
all five files.

[Golden data index and shared rules](../README.md). Commands above run from the repository root.

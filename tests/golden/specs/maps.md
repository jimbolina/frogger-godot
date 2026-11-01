# Maps and SkyLand

Run `C:\Python313\python.exe tools/make_golden_map.py RETAIL_DIR tests/golden/pc-retail-v3.0e`.
The generator independently reads the executable MWI and decompresses standalone
MAP entries in the owner's archive. It imports only existing independent Python
archive/configuration utilities. It never reads Godot results.

For a compiled C cross-check, `tools/map_oracle_adapter.c` links the existing
frozen `../froggy/engine/build/asset_pipeline/libasset_pipeline.a`, with headers
from `../froggy/engine/asset_pipeline/include`. Do not rebuild or modify that
tree. A compatible compiler is required; on this desktop its configured MinGW
compiler is `C:/msys64/mingw64/bin/gcc.exe` (its bin directory must be on PATH).
Build only the adapter, with its executable outside the repository:

```powershell
$env:PATH = 'C:\msys64\mingw64\bin;' + $env:PATH
$mapOracleExe = Join-Path $env:TEMP 'frogger-map-oracle-adapter.exe'
& C:/msys64/mingw64/bin/gcc.exe -std=c11 -Wall -Wextra -Werror '-I../froggy/engine/asset_pipeline/include' tools/map_oracle_adapter.c ../froggy/engine/build/asset_pipeline/libasset_pipeline.a -o $mapOracleExe
C:\Python313\python.exe tools/make_golden_map.py RETAIL_DIR tests/golden/pc-retail-v3.0e --c-oracle $mapOracleExe
```

The adapter receives each decompressed map on stdin and emits only decimal
facts; no asset blobs are saved. The generator compares its independent Python
decoding to compiled `map_reader.c` calls before writing facts. Coverage includes
all 78 maps: nine polygon type counts, general/group/grid/header
census, grid-square counts, maximum local texture indices and RGB-component
scans over FT3/FT4/GT3/GT4, 297 animation scalar/cel records, and 7,123 entity
identities. The frozen build no longer ships map-scan CLI executables, so this
adapter reuses its compiled library without compiling frozen implementation.

Format authorities are FrogLord commit `5416ae4f`, `map/packets`,
`map/data/FroggerMapGroup`, `FroggerMapLight`, `map/data/animation`,
`map/mesh/FroggerMapPolygonType`, and `file/FroggerSkyLand`; the frozen C
`asset_pipeline/src/map_reader.c`, `mapdisp.h`, `mapload.C` and `mapdisp.c`
independently pin sizes, pointer offsets, animation counters and cave falloff.

All digests use the [list convention](../README.md#digest-convention), with `-`
for an empty list. Nothing contains asset bytes or excerpts. Rows are ordered by
resource ID; inner lists keep file order.

| File | Coverage |
|---|---|
| `map_facts.tsv` | 78 FROG 2.00 files: sizes, general data, vertices, polygon lists, group references, lights, animation lists and retained section counts |
| `map_visibility_budget.tsv` | Visible group count, total eight-type polygon count and ordered count digest; excludes the invisible group and wireframe G2 |
| `map_polygons.tsv` | Nine polygon type rows per file, including empty types |
| `map_animations.tsv` | All 297 animation headers, target and cel digests |
| `map_animation_states.tsv` | Ten counter/offset samples per animation, from zero through tick 256 |
| `map_lighting.tsv` | Synthetic distinct-radius cave falloff facts at boundaries, adjacent distances and midpoints |
| `sky_land.tsv` | Two 39 by 35 tile maps, packed tiles, texture IDs and rotations |

`map_facts.tsv` names its columns in its header. General data is ten unsigned
16-bit values (start X/Z, rotation, theme, five timers, perspective), then twelve
signed 16-bit values (two padded camera vectors and four lighting words).
Vertices are signed X/Y/Z, excluding padding. Polygon records are decoded
unsigned 16-bit words in stored order, including padding: sizes are 12,12,28,28,
20,24,36,40,12 for F3,F4,FT3,FT4,G3,G4,GT3,GT4,G2. The combined polygon
digest prefixes every record with its type ordinal; per-type digests omit it.

Group header digests contain signed base X/Y/Z, unsigned dimensions X/Z and
sizes X/Z. Group list digests concatenate nine byte counts, nine file pointers,
and the static entity pointer per visible group in Z-major order, followed by
the invisible group. Runtime pointers/padding are excluded. Visible/invisible
counts are unique references; unreferenced polygons are retained. Six retail
low-poly maps have unreferenced records; this is valid data.

Light digests contain category, priority, parent ID, API type, packed color,
signed position X/Y/Z, signed direction X/Y/Z, and two unsigned attributes.
Padding and runtime pointers are excluded. Animation header digests use
`<bbHIHHI4H2I`: signed du/dv, duration, packed runtime UV word, cel count,
current cel, cel pointer, period, cel counter, flags, target count, runtime
texture pointer and target pointer. Target digests contain the file polygon
pointer followed by eight unsigned runtime UV bytes for every target. Cel
digests contain unsigned texture IDs only when the texture flag is set.

Animation state samples count completed updates: zero is the initial loaded
state. The player's `seek` uses a post-update tick, so the comparator calls
`seek(updates - 1)`. State values remain independently generated.
Animation state samples independently reproduce `MapUpdateAnimatedPolys`:
increment UV count; equality with duration resets its entire packed runtime
word; otherwise add the unsigned packed du/dv word modulo 65536. U carry
affects V. Texture counters advance before selecting the next cel and reset on
`>= period`. Samples describe counters and offsets, not final texture pixels.
SkyLand tiles use unsigned packed values, ID `value & 0x3fff` and rotation
`value >> 14`, in stored Z-major order.

Cave lighting uses integer factor `(128 << 16) / (maximum_r2-minimum_r2)`,
128 below minimum, zero above maximum, otherwise
`128 - ((factor * (distance_r2-minimum_r2)) >> 16)`. Fixtures use distinct
radii; the C equal-radius division is undefined and has no expected value.
Distance fixtures isolate falloff after signed-short vector subtraction and
squared-distance calculation. They do not validate scene illumination.

The generator checks all packet identifiers, bounds, group/animation target
resolution and the 78 plus two census. Section census fields match the frozen
C reader offsets and counts. Integrated retail tests compare each file, type
list and animation. New families require a deliberate-break check and
byte-exact restoration before delivery.

## Whole-map visibility bound

`map_visibility_budget.tsv` is independently decoded by `visibility_budget` in
`make_golden_map.py` from each GROU packet. Columns are resource ID, name,
visible group count, polygon total and the ordered per-group count digest.
The eight counted polygon types match `mapdisp.c:438–450`; the invisible extra
group and G2 wireframe polygons do not participate in gameplay visibility.
The retail map golden test compares the application lifecycle definition to
these facts. For high-detail ORG1 (resource 658), it additionally checks that
the entire map fits both the group pool and polygon budget. This proves the
conservative lifecycle selector accepts every selected subset, without sampling
camera routes. Deliberately change ORG1's total to exercise the assertion, then
restore the generated row before acceptance.

## Depth ordering biases

`synthetic/depth_biases.json` is written by
`python3 tools/make_golden_depth_biases.py --write`; without `--write` the
generator verifies the file. It transcribes the frozen C constants and shares
no GDScript. `test_depth_biases.gd` runs in both modes and compares
`MapShaders.TERRAIN_DEPTH_BIAS`, `GameplayWorldView.FROG_DEPTH_BIAS` (applied
to frog part, texture-track and instance materials) and the `depth_bias` that
`CaveSpriteView.configure` gives pickup frame, glow and firefly materials.
`tests/unit/rendering/test_depth_shaders.gd` checks that only ordinary terrain
shader sources contain the push.

| Field | Source | Arithmetic |
|---|---|---|
| `viewport` | `gamesys.H:63-64` (`MR_VP_VIEWDIST_8192`, `MR_VP_SIZE_4096`), `gamesys.C:953,956`, `API.SRC/MR_VIEW.H:43,57`, `API.SRC/MR_VIEW.C:445,2239` | slots `1<<12`, view distance `1<<(15-2)`, `otz_shift = 15-2-12 = 1` |
| `terrain_back` | `mapdisp.c:1569-1585` (`MapRenderQuads`), `1772-1786` (`MapRenderTris`), `mapdisp.H:40` | `gte_avsz4`/`gte_avsz3` average SZ, `>> otz_shift`, `+ MAP_POLY_OT_OFFSET` (64): `64<<1` |
| `frog_forward` | `FROG.C:334-335`, `FROG.H:139`, `API.SRC/MR_ANIM.C:660,677` | origin SZ `+ FROG_GLOBAL_OT_OFFSET` (−0x30) before the shift: 48 |
| `pickup_forward` | `PARTICLE.C:513-600` (`Pickup_disp`), `PARTICLE.H:26` | origin SZ `>> otz_shift`, `+ PICKUP_OT_OFFSET` (−0x10) for glow and image: `16<<1` |
| `firefly_forward` | `API.SRC/MR_SPRT.C:137,876-892`, `ENTITY.C:3164-3175` | average of four corner SZ, `>> otz_shift`, `+ sc_ot_offset` (0) |
| `terrain_hides` | derived | nearer-than distance at which terrain covers each drawing: frog 176, pickup 160, firefly and per-polygon models 128 |

Integers are game units of view depth; positive biases move toward the camera.
`gte_avsz4` divides the four-depth sum by four and `gte_avsz3` uses
`(1365*sum)>>12` (ZSF4/ZSF3 are set once in `MRInitialise`; `MR_MISC.C` is
absent from the vendored tree, and froggy's GTE stub records the values). Far-layer terrain (`MAP_POLY_MAX_OT`, environment map) is
placed at fixed slots before this block and keeps its own layer depth. The
port's per-vertex depth approximates whole-object (frog) and per-quad sorting.
For the deliberate-break check, change `pickup_forward` to 33 and confirm the
generator refuses the file and both pickup assertions fail, then restore with
`--write`.

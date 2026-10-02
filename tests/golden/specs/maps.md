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
| `map_polygons.tsv` | Nine polygon type rows per file, including empty types |
| `map_animations.tsv` | All 297 animation headers, target and cel digests |
| `map_animation_states.tsv` | Ten counter/offset samples per animation, from zero through tick 256 |
| `map_lighting.tsv` | Synthetic distinct-radius cave falloff facts at boundaries, adjacent distances and midpoints |
| `sky_land.tsv` | Two 39 by 35 tile maps, packed tiles, texture IDs and rotations |
| `map_projection.tsv` | 37 synthetic reference-camera projection, short-wrap, near-clamp and ordering-depth samples |

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

## Synthetic reference projection

Run `C:\Python313\python.exe tools/make_golden_map_projection.py tests/golden/pc-retail-v3.0e`.
This standalone generator uses no retail files, GDScript code/output or other
golden generators. `test_map_projection.gd` runs in asset-free mode too.

The fixed matrix rows are `(8192,0,0)`, `(0,5430,-5430)`, `(0,2896,2896)`.
They follow `MR_VIEW.C`'s 640/320 horizontal and 480/256 vertical aspect scale,
the map-slice -512/4096-turn camera pitch, and C matrix multiplication's 4.12
quantization. The frozen translation unit has no `MR_MODE_NTSC` definition.
`mapdisp.c/RenderMap` first narrows each negated camera coordinate to signed
short, then applies rotation with arithmetic `>>12` to create translation.
`mr_stub_math.c/ApplyMatrix` separately rotates each signed-short vertex, with
arithmetic `>>12`, before `mr_stub_gpu.c/perspective_transform_one` adds that
translation. Combining rotation and translation before quantization is wrong
at negative fractional boundaries; the `separate_floor` sample pins this.

Depth is `max(view_z, 500)` because map-slice retains H=1000. Screen coordinates
are `320 + trunc(view_x * 1000 / depth)` and
`240 + trunc(view_y * 1000 / depth)`, with signed division toward zero.
`gte_stsxy` stores signed-short screen coordinates; Win95 terrain stores the
clamped depth as unsigned short. Both stored representations have separate
columns so wrapping is explicit. Samples cover negative quotients, camera
short wrapping, signed vertex limits, depth 499/500/501, and 65535/65536.

The last four columns describe uniform-depth triangles and quads only.
`gte_avsz3` uses `(1365 * (z1+z2+z3)) >>12`; `gte_avsz4` divides the four-depth
sum by four. `mapdisp.c` rejects average depth <=16; ordinary terrain's ordering
bucket is `(average >>2) +64`, rejected at >=4096 for map-slice's default
4096-entry viewport. Thus uniform depth 16128 is rejected for a quad, while
the triangle's weighted average is 16124 and still maps to bucket4095.
These facts describe ordering depth only, without backface or screen clipping.

`tools/make_map_capture_masks.py RETAIL_DIR --level SUB1 --out EXTERNAL.json`
generates fixed comparison coverage without reading either capture. It reads the
supplied EXE map book and independent MAP parser, uses map_slice's vertex-extent
midpoint camera (target plus `(0,-10000,-10000)`), stable nearest 128 visible
groups when there are more than 128 (otherwise ascending index), and C's 2500
polygon budget, which skips whole groups exceeding the remaining count. It uses
ordinary C ordering depth cut. ENVMAP/MAX_OT bypass that cut. Projected
triangles are clipped to 640x480; invisible and unreferenced polygons and entities
are omitted. C NCLIP uses raw projected coordinates: triangles require positive
area; quads accept positive first area or negative second `(1,2,3)` area.
SKY levels include the full background. Output has identical eligible/include geometry and empty exclusions
and landmarks; declare entity rectangles and reference landmarks externally.
Coverage geometry must remain fixed when comparing candidate revisions. Outputs
are external JSON only, never retail images or bytes in the repository.

Masks declare `raster_edge_policy: eligible_union_silhouette`. The comparator
finds the inner one-pixel silhouette of the source eligible union, then applies
the fixed two-pixel Chebyshev band. Internal polygon seams remain fully tested.
Do not exclude image gradients or individual polygon perimeters: that would
hide texture errors and internal seams. Require channel error <=8, 95%
agreement, 50% eligible coverage, at least 1000 compared pixels, and three
landmarks within two pixels. Preserve the source denominator.
Clipping creates no artificial viewport-border edges.
`python tools/test_map_capture_masks.py`
checks the exact band width and that texture stripes retain their interior pixels.

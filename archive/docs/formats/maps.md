# PC maps

[Sources](../../../docs/reference/sources.md) locate read-only
FrogLord and frozen C; format authority is FrogLord, behavior authority is C.

## Data and source authority

The v3.0e survey found 78 `FROG` version `2.00` maps (39 high/low pairs), plus
two 39x35 sky-land tile files. SUB1 is largest by polygon count: 6,058 polygons,
8,165 vertices, 408 groups. All eight triangle/quad types occur; G2 is empty.
All four textured types are animation targets. Every group cell is 768x768.

Use FrogLord `map/packets/FroggerMapFilePacket*.java`, `FroggerMapPolygon`,
`FroggerMapPolygonType`, `FroggerMapGroup`, `FroggerMapLight`, map animation
data classes, and `file/FroggerSkyLand.java`. Header/graphical pointers are
map-relative byte offsets, not executable pointers. Final PC polygon strides
in F3/F4/FT3/FT4/G3/G4/GT3/GT4/G2 order are 12/12/28/28/20/24/36/40/12.

Keep source offsets and raw records immutable; resolve group/animation
references separately. Read visible groups and the extra invisible group.
The survey found invisible polygons in 68 files. Six low-detail maps have
polygons absent from serialized group lists: JUN1, JUN2, SWP1, SWP2, SWP4,
SWP5. Preserve/report these; don't reject the file or make them visible.
GRID now retains ordered stacks and squares, flags, polygon offsets and all
four calculation corners; [grid](../../../docs/reference/gameplay/grid.md) owns decoding, setup and query rules.
PATH retains source-ordered paths and segments. FrogLord's final-PC segment
ordinals are spline 0, arc 1 and line 2; their records occupy 120, 40 and 24
bytes including type and stored length. The spline stores a row-major 4×3
signed coefficient matrix, four smooth-t values and twelve smooth-c values.
Arc and line coordinates are signed 16-bit vectors with two padding bytes;
arc radius and pitch are signed 32-bit values. The decoder retains stored
lengths and coefficients without recomputation. Pointer tables and known
payloads must fit their PATH records. Unknown bounded segment types retain
identity and a warning, while malformed pointers or payloads fail the map.
The path entity-list pointer is retained as metadata: FrogLord reads that list
with GROU, so it need not point inside PATH. See [path behavior](../../../docs/reference/gameplay/paths.md).
FORM retains source-ordered grids: data count, runtime maximum-Y scratch word,
signed dimensions and offsets, FORM_DATA height mode and scalar height, pointer
metadata, and unsigned 16-bit square flags in Z-major order. Empty grids retain
their sometimes garbage dimensions. Each data and flag pointer must stay within
its enclosing record; malformed structure fails the map. The unused alignment
short after flags may be nonzero. Nonzero height modes and additional data
records remain visible with diagnostics; bounded contact uses the first record
only when its mode is GRID (zero). The scalar-height pointer is metadata and is
not dereferenced. FrogLord's `FroggerFormGrid` and `FroggerFormGridData` define
the layout; [entity contact](../../../docs/reference/gameplay/entities.md#form-contact-inspection)
follows frozen `mapload.C` and `COLLIDE.C` behavior. EMTP retains bounded
identity and payload; entity setup reads STATIC matrix and MOVING PATH_INFO
prefixes without discarding subtype bytes.

ZONE retains authored indices, offsets, type, bounds and child-region order.
FrogLord's common record is 16 bytes: type/count unsigned shorts, four signed
bounds and a map-relative region pointer. CAMERA type 0 adds 68 bytes: flags,
direction and eight padded signed16 vectors. Each child region occupies eight
bytes. The decoder bounds pointers and payloads to their records, retains
inverted bounds and reports unsafe records without hiding them. `ZoneSetup`
rejects the entire zone set on unsafe storage or unknown semantics.
Known flags use FrogLord's mask `0x1f`: bit 0 selects per-direction offsets in
the editor. Frozen C does not read that bit; it already indexes the eight
stored vectors by camera direction. Retain it as known storage metadata,
without treating retail flag 1 as unknown. Active-zone setup copies all eight
vectors, direction and flags without changing the decoded record.
FrogLord stores signed bounds; frozen `ZONE.H` interprets the outer four words
as unsigned and child words as signed. This difference is preserved at query
time, without rewriting decoded values. High-detail JUN1 zone 12 has inverted
Z bounds `(12,40,15,39)` and therefore never matches. The
[camera contract](../../../docs/reference/gameplay/gameplay-camera.md#zone-boundaries) owns queries
and active selection/transitions. Exploration restrictions remain separate.

## Rendering

Use [GameSpace](../../../docs/reference/rendering/coordinates.md) once. Map quads use GPU strip corner order,
unlike stored MOF quads; preserve each corner's colour and UV association.
One mesh per visible group, split by material/animation. Unreferenced and
invisible polygons are diagnostic-only. The map's local texture index resolves
through the supplied EXE remap and theme/general texture banks.
ENVMAP terrain keeps its own polygon texture; the flag changes UV calculation
and ordering only (`ResolveMapPolys`, `MapRenderQuads`). The EXE environment
pointer sets model environment mapping (`MRSetEnvMap`), not terrain imagery.
ORG/SUB low-detail and multiplayer maps retain this pointer without its image
in their loaded banks; FOR/SWP use ENVMAP terrain with a zero EXE pointer.

Stored UV bytes are normalized, then converted to integer pixels by
`coordinate * image_size / 255`. Animation deltas are pixels. See
[texture contract](textures.md#map-texture-contract). Frozen C
`mapload.C` resolves animation target flags, polygons, then animation base UVs;
`mapdisp.c/MapUpdateAnimatedPolys` owns counters, cel changes and byte wrapping.
No source bytes are mutated in the Godot representation.

Map sampling reconstructs fourteen physical 256x256 PC texture pages in
general-then-theme upload order. Final U/V bytes wrap independently before
page lookup; they must not clamp to an individual image. Frozen PC page
colour keying tests exact RGB zero, overriding the decoder's FrogLord-style
5-bit-black alpha only in this map page cache. Model texture decoding is
unchanged. Missing/invalid pages render magenta and produce diagnostics.
The reference rasterizer always samples linearly with taps at `floor(uv-1)`;
GPU linear sampling therefore needs an extra half-texel offset. Nearest
filtering is an inspection option, not the reference comparison mode.

Map polygon flags govern semi-transparency, environment UVs and far ordering.
Environment UVs depend on camera position. MAX_OT riverbed geometry sits
behind environment water and ordinary geometry. Ordinary terrain keeps the C
ordering-table offset as a depth-only push ([depth ordering](../../../docs/reference/rendering/README.md#depth-ordering)).
Use C `mapdisp.c` and
`mapload.C/MapCreateWibbleWater`, plus `WATER.C` for water vertex state.
The water sorting block is commented out in C: preserve unique vertex
encounter order (FT4 then GT4), rather than sorting their coordinates.
Sky-land has a separate tile/remap format, C camera-relative placement,
rotations, base colours and drift. It isn't an ordinary FROG map. In
gameplay the drift is state owned by the [simulation](../../../docs/reference/gameplay/simulation.md#sky-drift-and-the-global-frame-timer).
Sky tile endpoints use processed texture dimensions: subtract HIT_X/HIT_Y
from width/height as `MR_VRAM.C` does. A raw 256 endpoint would wrap to zero
and collapse a full-page tile; ordinary map normalized UVs have their own
conversion contract.
The C sky chain draws tiles in row-major order without backface rejection.
A single surface samples an immutable atlas of physical pages, preserving
triangle order across different tile textures. Duplicate atlas border rows
keep linear sampling clamped within each original page. Grouping tiles by
texture changes overlap order for depth-clamped tiles and is incorrect.

Terrain normally uses baked polygon colours. Cave rendering replaces Gouraud
colours with the C squared-distance grey ramp; it does not apply model lights
to all terrain. The named cave-light entity payload supplies initial radii
(`ent_cav.c`, `FroggerEntityDataCaveLight`); gameplay owns the per-tick radii and the game scene feeds them to the ramp, while the map viewer keeps this static initial ramp.
The static adapter accepts maximum radii 1..255 (FrogLord's grid-width editor
limit), preserving C unsigned squared-radius arithmetic and underflow clamping.
Radius one is a valid initial ramp; zero has no usable range. Gameplay's
separate minimum-radius assertions do not define this static preview adapter.
Models use ambient plus at most three parallel lights from LITE. C
`CreateMapLights` ignores point/spot records. See [rendering](../../../docs/reference/rendering/README.md).

## Camera and reference captures

The normal viewer uses map default offsets around bounds midpoint and H=256,
with no gameplay-follow claim. All surveyed maps store unused perspective 192.
Frozen `map_slice` differs: viewport H=1000, bounds-midpoint target, camera
offset (0,-10000,-10000), pitch -512/4096 turns. Its viewport aspect matrix
scales X/Y by 2/1.875 at 640x480, making effective projection 2000/1875; H alone does
not determine its field of view. For maps exceeding 128 groups it selects
the nearest 128 by stable squared distance from target, preserving index
order on ties; smaller maps retain index order. `CreateMapGroups` then has
a 2,500-polygon allocation budget (`MAP_MAX_POLYS_RENDERED`, eight terrain
types, excluding G2). Skip a whole group if it cannot fit and consider the
next group; stop when the budget is exhausted. These limitations belong only
to the reference preset, not the ordinary full-map viewer.
Cave light holder is the same target. `map_slice` updates map textures and sky
but does not call gameplay water wibble; match update count before comparison.
It includes entities absent from the map viewer, requiring declared comparison masks.

The reference preset reproduces fixed 4.12 rotation, separately rounded
translation, depth clamping at 500, truncating screen division and signed
16-bit screen wrapping. Ordinary polygon ordering-table depth rejection
also happens before rasterization; MAX_OT/environment polygons bypass it.
GPU projection is confined to the reference preset, with per-polygon depth
attributes so animation never rebuilds static geometry. Explicit custom
poses and the normal inspection camera use Godot projection.
Every material using reference projection receives camera translation updates,
including ordinary surfaces without environment UVs. Changing projection mode
rebuilds that material selection; otherwise a cached zero camera can project
the map against the near-depth clamp instead of the reference viewpoint.

Use `mr_stub/src/drivers/map_slice/mr_map_slice_main.c`, `API.SRC/MR_VIEW.C`,
`CAMERA.C`, `MAPVIEW.C`, `gamesys.C` and GPU rasterizer for behavior. The driver
uses affine interpolation. Do not confuse its H with Game_perspective=256
(used for view-list calculations). Reference images are external evidence,
never copied into this repository. Mask construction and acceptance tolerances are defined in the
[map golden specification](../../../tests/golden/specs/maps.md#synthetic-reference-projection).

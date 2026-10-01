# Model animation

Retail counts below refer to `pc-retail-v3.0e`. See [source locations](sources.md).

### Stored data and unsafe records

The retail archive contains 78 XAR files, 28,447 transforms, 187 actions and
4,016 virtual frames. Every XAR has one model set and one model, and uses
standard virtual-cel tables: 41 files use byte matrices and 37 byte
quaternions. The reader also supports short matrices, short quaternions,
scaled byte/short quaternions, multiple sets and authored interpolation;
synthetic files exercise the formats absent from retail.

There are 174 stored flipbook actions (230 after incomplete-model
inheritance). Nineteen readable records point past their partcel arrays:

| Files | Action IDs | Start/count | Available partcels |
|---|---|---|---|
| `GEN_GOLD_FROG.XMR`, `GEN_GOLD_FROG_WIN95.XMR` | 5 | 46/21 | 46 |
| `FOR_SQUIRREL_WIN95.XMR` | 2 | 41/20 | 41 |
| `SKY_SQUADRON.XMR`, `SKY_SQUADRON_WIN95.XMR` | 4, 5, 6, 7, 8 | 8/249 | 29 |
| Same squadron files | 9, 13, 14 | 19/238 | 29 |

These actions stay visible but unavailable. Their ranges are never
repaired. Structural truncation or impossible pointers still reject a
file. An invalid texture list disables only its target, which keeps its
original image. Incomplete models share their counterpart's effective
geometry and animation arrays while retaining their own polygons,
colours and image IDs. Raw stored counts remain separate; P4 facts did
not change.
Undefined scale flag bits are preserved and explicitly reported; as in
FrogLord and C, only bit zero affects sampling. Unsupported structural
format modes fail with a diagnostic.

### Clocks and transforms

`ModelAnimationPlayer` owns counters, independently of nodes and other
instances. It follows `MRAnimUpdateEnvironments`: selection sets cel -1;
the first update reaches zero regardless of the integer update period.
Viewer tick zero includes that initial update. Loop, hold and hide modes
operate on integer ticks. Seeking replays from a full restart; changing
an action leaves the texture counters independent.

Stored quaternions are converted with the C fixed-point formulas without
normalizing them. Matrix entries narrow to signed 16 bits, and scale
left-multiplies the matrix (scales its rows). Old standard virtual-cel
tables are one-based; authored interpolation endpoints are zero-based.
Space conversion follows the [coordinate contract](coordinates.md).

The viewer uses the existing 30 Hz physics clock and three-step catch-up
limit. This adopts the frozen reference's clock for animation; the
retail 25/30 Hz timing investigation remains P7 work.

### Textures and smoothing

The 613 texture targets use the C increment-before-comparison rule.
A duration of one advances on the first update; a zero duration also
advances once on the next update. Each target has its own counters, even
when targets share a list. Polygon indices are global within a part,
not relative to a polygon-type block.

UV pixel offsets come from the original polygon image's dimensions.
Replacement images apply their own padding and padded dimensions to
those offsets. The original image's translucency flag remains in force;
the current image supplies the blend rate. Missing images use the
untextured fallback and are reported. If the original image is missing,
all entries for that target stay untextured because its pixel offsets
cannot be determined, even when a replacement image exists. Animated targets have separate
surfaces and instance-local overrides, with materials prepared during
model construction.

Smooth Motion defaults off. It interpolates transforms and normalized
flipbook blend-shape weights between ticks; images remain discrete.
Pause, step, seek, restart, action/model changes, loops and toggle changes
reset interpolation history. Exact endpoints preserve the sampled
matrices, including their stored scale. Manual interpolation disables
Godot's automatic interpolation on the render subtree. See Godot's
[manual interpolation](https://docs.godotengine.org/en/4.5/tutorials/physics/interpolation/advanced_physics_interpolation.html)
and [ArrayMesh blend-shape](https://docs.godotengine.org/en/4.5/classes/class_arraymesh.html)
documentation. Decoded resources and playback counters remain unchanged
by drawing at different fractions.
Singular transforms (zero scale) use component interpolation between
exact endpoints so optional smoothing never tries to extract an invalid
rotation quaternion.

### Reference capture setup

Use the existing `anim_slice.exe` with SDL's dummy driver and an external
`FROGGY_SCREENSHOT_DIR`; never rebuild the frozen reference. Its source is
`../froggy/engine/mr_stub/src/drivers/anim_slice/mr_anim_slice_main.c`
(relative to the repository root). `verify_anim_retail` is the relevant
catalogue entry; `frog_anim_slice` tests sprite command lists instead.
The expected hashes and serialization are specified in the
[animation golden specification](../../tests/golden/specs/animation.md).
Completed comparisons are in [P5 validation](../validation/p5.md).

The driver's camera is `(0,-100,-350)` and model placement `(0,0,1000)`.
Its projection constant is 1000, but `MR_VIEW.C` first scales X by
viewport width/320 and Y by height/256 (the driver's PAL configuration).
At 640x480 the effective focal lengths are 2000 horizontally and 1875
vertically. Godot's reference capture uses FOV `2 * atan(240 / 2000)`
and a reference-only 240/256 scale of model and camera Y. Omitting the
aspect matrix produced a silhouette half the reference's size; using
the NTSC height of 240 left a further vertical mismatch. This calibration
applies to the standalone driver; general map projection remains P6 work.

Authored quaternion interpolation uses analytic trigonometry in place of
the C lookup tables, while preserving integer translation/scale stepping,
short narrowing and the byte-quaternion normalization tolerance. The
synthetic rotation checks allow a few 4.12 units of rounding difference.
All retail actions use standard virtual cels and their matrix digests
match exactly.

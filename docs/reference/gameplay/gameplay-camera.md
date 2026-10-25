# Terrain gameplay camera

`GameplayCamera` owns copied default offsets and mutable camera state;
`GameplayCameraTick` supplies frog world coordinates and per-tick scalars after
frog movement. Snapshots are detached and include source/target world positions,
fixed-12 axes and camera-relative controller directions. Presentation owns the
Godot camera and may interpolate snapshots without changing gameplay state.

The supported slice is frozen C's default and active-zone camera with bounded
platform attachment and dismount correction. Invalid zone payloads and entity
matrices are rejected before mutation. Map-default definitions require a
downward view with a nonzero horizontal look axis. Map defaults are supplied by
setup; debug-only CAMERA.H defaults are not an authority for each map.

Opt-in [entity visibility lifecycle](entities.md#visibility-lifecycle) consumes
the post-update camera source and fixed12 axes inside the same run transaction.
Rendering interpolation and host window size do not change selection. The
visibility mode rejects zone-bearing maps until combined zone/lifecycle behavior
is verified; it does not silently use default offsets for them.

The following anchors are under the frozen source directory in
[sources](../sources.md):

| Rule | Source |
|---|---|
| Original reset source `(200,-400,400)`, target `(0,100,0)`, 30-tick start | `CAMERA.C:149-172`, `CAMERA.H:49-57` |
| START holds while game start timer exceeds 30; transition tick retains current offsets | `CAMERA.C:275-305` |
| Fixed sweep decrements first, then divides offset remainder by remaining ticks; final tick switches to follow | `CAMERA.C:310-342` |
| Follow offset transition divides first, then decrements timer | `CAMERA.C:449-464` |
| Hop tracked Y interpolates old/landing Y with standard 6 or super 15 ticks, independent of ballistic frog Y | `CAMERA.C:468-484` |
| Tracked Y clamps destination at zero and approaches by 24 units; X/Z halve positive absolute distance, snapping below 5 | `CAMERA.C:485-487,596-657` |
| Quarter turn starts counter +/-1 and reaches +/-8, one angle increment 128 per camera tick | `FROG.C:1649-1686`, `CAMERA.C:492-528` |
| Turn-wait frog returns to stationary only when both camera timers were zero at frog movement | `FROG.C:1786-1789` |
| Death asks for `(0,-1000,-100)` source, zero target over 45 ticks | `FROG.C:793-802`, `CAMERA.H:72-80` |
| Camera matrix points its Z axis at target; derives X and Y by fixed-12 cross products | `API.SRC/MR_FRAME.C:467-478`, `API.SRC/MR_MATH.C:353-375` |
| Controller UP quadrant uses projected negative matrix Y; ties choose X; subsequent directions advance modulo four | `CAMERA.C:678-735` |

Division of signed integer offset remainders truncates toward zero. Rotation
products use arithmetic shift 12. The frozen stub synthesizes trig with libm
and rounds to 4096 scale (`mr_stub_gpu.c:36-43`); vector normalization uses
libm length and rounding (`mr_stub_math.c:313-328`). GameplayCamera follows
that frozen-source policy, including integer world translations and fixed-12
axes, rather than a generic easing tween.

`create(..., startup=false)` deliberately supports component-fixture starts
already in follow mode. `startup=true` reproduces reset/start/sweep. Requests
for turns/death occur before camera update; the coordinator owns frog control
gating and WAIT_FOR_CAMERA. A turn's last camera update makes the wait complete,
so source-ordered frog movement resumes on the following tick.

FIXED (4) is terrain reachable through `FrogKill` (`FROG.C:3153`).
`request_fixed()` freezes tracked position, offsets, timers and basis because
`UpdateCamera` has no FIXED switch arm. `ControlFrog` subsequently requests
45-tick death offsets (`FROG.C:793â€“802`) without changing FIXED; `request_death()`
models that separate request rather than implying a death animation.

Terrain stun invokes `ShakeCamera` with amplitude 128, duration 45 and frequency
20480 (`FROG.C:2375`, `CAMERA.C:777â€“799`). The run supplies two ordered MRrand
draws to `request_shake`; SourceRandom implements the unsigned32 LCG in
`MR_SYS.H:141â€“150` without global state or reseeding. The actual C fixture
seed 1 gives 16838, 5758 and state 2524885223. Shake executes after the camera mode
switch, including FIXED, changes translation only and retains the basis.
Presentation must retain that basis when rendering the shaken translation.
The 327-row independent C/Python corpus includes fixed freeze, follow shake
and accumulating fixed shake. Invalid zone payloads remain explicit errors.
Shake accepts the verified amplitude range 0–128; larger amplitudes are outside
this slice.

## Platform attachment

`transition_attachment(old, new, correct_quadrant)` validates detached matrices
before changing the candidate. Mount/transfer multiplies the modification matrix
by projected old rotation, then inverse projected new rotation; detachment
absorbs the old projection. Empty old/new arrays mean no corresponding entity.
`step` accepts an optional attached matrix and composes the projected entity
rotation after modification and turn/correction. This applies whenever the frog
retains its entity link, including angled departure in flight.

`COLLIDE.C:1075–1106` and `CAMERA.C:492–589,674–730,820–883` own the order.
Y correction advances by 32 angle units toward the selected quadrant. Controller
vectors retain their projected fixed-12 values as well as cardinal directions.
A quarter-turn completion persists its rotation in the modification matrix and
emits an entity-angle delta consumed within the run's transaction. Camera
snapshots copy those matrices, vectors, correction angles and per-tick delta.

The frozen acos lookup is reconstructed as
`min(2047, floor(acos(i / 4096.0) * 2048 / PI))`, except input zero yields 1023.
All 8,193 entries are checked against an independent digest generated from the
read-only original table; the C adapter explicitly loads that table. Runtime
uses only the mathematical reconstruction. Reproduction belongs to the
[entity golden specification](../../../tests/golden/specs/entities.md).

## Zone boundaries

`ZoneDefinition` owns detached signed storage values and ordered child regions.
`ZoneQueries.first_camera_match` follows unchanged `ZONE.C/CheckCoordsInZones`:
visit authored zones in order, filter CAMERA type 0, test inclusive unsigned16
outer bounds, then inclusive signed16 child bounds in order. Zero children
means the entire outer rectangle. Gaps, overlaps and inverted bounds retain
their source meaning; the first matching authored index wins.

`LevelDefinition.camera_zones` opts a run into active camera zones and requires
an integrated camera. Definitions include all eight signed16 offset vectors,
flags and direction. Bounds-only exploration guards remain a separate facility;
existing guarded routes retain their admission restrictions.

`RunSnapshot.camera_zone_index` and `camera_zone_region_index` retain the frog's
selection. Zone -1 means absent; region -1 with a present zone means its outer
rectangle. `FROG.C/UpdateFrogCameraZone` first retains the current signed region,
then searches that same zone, then searches all zones in authored order. Thus
an overlapping earlier zone cannot displace a still-valid current selection.
Zero-child regions alias the outer words as signed16 for the retention check.
The source `FROG_DO_NOT_UPDATE_CAMERA_ZONES` flag freezes this state.

Selection runs at the end of movement, before modifiers/collision. Contact
corrections do not query again. Reset selects the frog zone but leaves the
camera's consumed zone absent until its source update. Camera snapshots retain
the consumed zone and twist-quadrant count separately. All fields participate
in the aggregate transaction, copy and reset; late failure publishes none of them.

FOLLOW changes zones before interpolating offsets: entry, transfer and exit set
a 30-tick timer, use the projected platform/modification quadrant and apply any
forced 90/180-degree turn. The normal integer division/decrement order remains.
Absolute-Y zones use source world Y and target absolute Y, including the source's
different absolute-to-relative and absolute-to-no-zone restoration rules. START
selects the north offset pair when the hold ends, without forcing a turn. FIXED
retains its consumed zone even if frog selection changes; shake still follows it.

Manual turns obey the consumed zone's forced/semiforced flags in frog control.
Disallowed turns retain source input bits and do not enter WAIT_FOR_CAMERA.
Accepted turns choose offsets using the projected platform/modification quadrant,
run for eight ticks and update controller directions and entity angle. Invalid
payloads or a missing consumed zone reject the transaction before mutation.

### Frozen build compatibility

Vendored `FROG.C:1667-1694` expresses manual offsets with `ZONE` pointer arithmetic.
On the frozen 64-bit build, `sizeof(ZONE)=24` while offset pairs occupy 16 bytes.
The frozen build's `engine/tools/sanitize_frogger_source.sh` replaces those reads
with `SVEC[2 * quadrant]`, matching `CAMERA.C` entry behavior. Actual linked
`ControlFrog` verifies all four offset pairs; runtime follows this built behavior,
not the unsafe untransformed expression. The oracle records sanitized source
and linked-object provenance outside the repository. No frozen source is edited.

Editor flag bit 0 remains metadata; frozen behavior always reads directional
vectors. CHECKPOINT and OUTRO bits are retained, but checkpoint zoom and outro
flow are not implemented by this phase. Runtime source definitions are generic;
retail demonstration is limited to v3.0e high-detail JUN1 and uses prescribed
probe positions, not a playable route. See [inspection](../testing/terrain-inspection.md#active-camera-zone-inspection)
and [independent facts](../../../tests/golden/specs/camera-components.md#active-camera-zones).

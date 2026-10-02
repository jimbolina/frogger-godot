# Terrain gameplay camera

`GameplayCamera` owns copied default offsets and mutable camera state;
`GameplayCameraTick` supplies frog world coordinates and per-tick scalars after
frog movement. Snapshots are detached and include source/target world positions,
fixed-12 axes and camera-relative controller directions. Presentation owns the
Godot camera and may interpolate snapshots without changing gameplay state.

The supported slice is frozen C's default terrain camera without camera zones,
entity transforms or non-cardinal entity dismount correction. Unsupported
zone/entity input is rejected before mutation. Definitions require a
downward view with a nonzero horizontal look axis. Map defaults are supplied by
setup; debug-only CAMERA.H defaults are not an authority for each map.

The following anchors are under the frozen source directory in
[sources](sources.md):

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
and accumulating fixed shake. Unsupported zones/entity transforms remain
explicit errors. Shake accepts the verified terrain amplitude range0â€“128;
larger amplitudes are outside this slice.

Component validation (2026-10-01): retail wrapper passed 369 tests with no skips
and 170 scripts compiled. Deliberately changing camera corpus row0 sourceX
from200 to201 failed exactly row0 column14; restored focus passed8 tests,
9298 assertions. Logs are external temp runs7f88963308bc4d29a56bb749710e824c,
86d9962b5121451e9f411e9b7b7e8c50 (expected failure), and
47f1b9a39bc344b7ac18bb52cf222207 (restored). This component evidence does not
close the later integrated terrain or animation checks.

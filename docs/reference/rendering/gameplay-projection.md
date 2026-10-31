# Gameplay projection

Frozen `gamesys.C:438` sets `Game_perspective=256`; `gamesys.C:955` copies it
to the viewport. `MRSetViewportViewDistance(...,8192)` is a distinct culling
setting, not the perspective H. Map metadata perspective is not this setting.
The map inspection preset H1000 remains separate.

`MR_VIEW.C:505-515` gives aspect X=width/320, Y=height/256 unless
MR_MODE_NTSC is defined. The compiled Windows source has no MR_MODE_NTSC;
SYSTEM.H defines it inside the PSX block. Actual compiled MRChangeViewport
at 640x480 returns 8192/7680 in fixed12. Effective focal lengths are 512/480.
A symmetric Godot camera with vertical FOV `2 atan(240/512)=50.229669 degrees`
plus shader clip-Y scale 0.9375 reproduces those focal lengths. A bare vertical
53.130102 degree camera has the right Y but wrong X. Preserve existing shader
projection plumbing and inspection defaults.

Camera columns X/Y/Z become Godot columns S*X, -S*Y, -S*Z where
S=diag(1,-1,-1); translation becomes S*t/256. Existing GameSpace.transform
already performs this row-major conversion. The fixed source basis is retained
through shake; deriving a new look-at basis from shaken position is incorrect.
Native Camera3D orthonormalization and float32 arithmetic require pixel bounds,
whereas camera integer state and source projection facts compare exactly.

`tools/gameplay_projection_oracle.c` calls existing frozen MRPointMatrixAtVector,
MRChangeViewport, MRUpdateViewportRenderMatrices, MRApplyMatrix and GTE RTPS.
It supplies only caller-owned scalar fixtures, no replacement renderer.
`tools/make_golden_gameplay_projection.py` independently computes all 40 samples
and verifies all 40 integer fields against that executable. Fixtures include
follow, quarter-turn, death-offset and reset camera poses, terrain corners,
frog-height landmarks and adjacent 256-unit cells. The corpus is
`tests/golden/synthetic/gameplay_projection.csv`.

Each X/Y bound is declared before candidate inspection: signed rotation and
translation floors, ratio perturbation and C quotient truncation contribute
separately. Godot's concrete Gram-Schmidt order is independently applied to the exact
source basis; its difference from the ideal unit basis is calculated per point,
not replaced by a chosen tolerance. Float32 rounding uses gamma128=
128*2^-24/(1-128*2^-24) with absolute coordinate L1 error propagation.
The operation budget is 27 normalization operations, 33 dot/projection/subtraction
operations for Gram-Schmidt, 21 view-coordinate operations, 28 homogeneous
projection operations, 11 viewport operations and 8 input/setup roundings.
The depth denominator is reduced by the propagated error; all samples remain
above the 128-unit clamp. Maximum row bounds are 1.543992 pixels X and
2.248278 pixels Y. These apply
to camera-projected landmark centers, not shaded image RMS or arbitrary scenes.
The native projection test applies the same Y scale as the existing shaders.

Visual comparison masks are semantic: the 40 authored point IDs and their
camera/terrain/frog-height categories form the projection acceptance mask.
Exclude UI, entity/form meshes, lighting, texture filtering and raster coverage
from this numeric test. Silhouette comparison requires identical
frog action/cel, matrices, loaded mesh and source draw ownership; no image-wide
pixel tolerance is established here. Source images alone do not close that gate.

Build externally with `tools/build_gameplay_projection_oracle.ps1
-OutputDirectory <external-directory> -Run`; generate with
`python tools/make_golden_gameplay_projection.py
 tests/golden/synthetic/gameplay_projection.csv --c-oracle <external-exe>`.
The builder rejects repository/frozen-tree destinations, links only existing
reference objects and records hashes externally. It never rebuilds froggy.

Godot4.5 implementation anchors: [basis.cpp](https://github.com/godotengine/godot/blob/4.5-stable/core/math/basis.cpp#L52)
uses ordered Gram-Schmidt; [camera_3d.cpp](https://github.com/godotengine/godot/blob/4.5-stable/scene/3d/camera_3d.cpp#L235)
orthonormalizes the camera transform and its unproject method applies the
homogeneous projection then viewport conversion. This numeric comparison
uses the native method, rather than a GDScript reproduction of it.

The optional builder `-CaptureFacts` links existing frog_slice objects with
`gameplay_capture_facts.c`, a scalar tap around its screenshot function.
It calls the original writer without changing engine state. Actual ORG3
captures (MRFrame_number, not a guessed simulation tick) are:

| Capture | Frame | Frog world | Action/cel | Camera world |
|---|---:|---|---|---|
| start |142|128,-256,-1664|14/9|102,-2514,-1990|
| first jumping frame |335|170,-296,-1664|16/0|123,-2514,-1990|
| landed |350|384,-256,-1664|14/9|358,-2514,-1990|

All three camera matrices are row-major fixed12
`4096,-6,2; 0,1280,3891; -6,-3891,1280`. Source frog uses loaded resource 192.
The driver probes rejected north then resets and chooses east; frame numbers
include reset/probe swaps. Reproducing just a six-tick jump without that prior
history will not reproduce entity states or random consumption. Camera/frog
scalars permit a detached foreground comparison; matching a full image still
requires identical map/entity state.

Fixture cameras disable host physics interpolation because native unprojection
otherwise sees a cached prior transform when poses change in the same frame.

Foreground reference preparation adds one terminal render of the live frog
animation environment in a fresh viewport, with the retained camera and
viewport lighting matrices, against black. It uses existing MRAnimAddEnvToViewport,
MRRenderViewport and MRSwapDisplay; no subsequent game tick occurs. This
omits map/entities/shadows by viewport ownership rather than guessed image
segmentation.

Before rendering a candidate, `prepare_gameplay_foreground.py` records 227
actual frozen-C vertex landmarks, per-vertex X/Y bounds, source input/image
hashes and the exact action/cel/world matrices externally. The start-pose maximum bounds are
1.247466 pixels X and 1.255062 pixels Y; other poses use their own computed bounds. The float32 operation
budget is 146: 18 part-world transformation operations plus the 128 camera/view/
projection budget above. Integer part/view composition and projection errors
are computed from each C observation against the independent double transform.

The foreground mask is exactly nonblack RGB pixels on the black background.
Both masks must be nonempty. Source and candidate masks must each lie within
the other's Chebyshev dilation radius 3: ceil(maximum per-axis landmark bound)
plus one pixel for raster sample/edge ownership. The acceptance concerns
foreground coverage; color/lighting RMS and full-scene raster equivalence are
not inferred. This bound was fixed from source data before candidate capture.
The fixture and masks are external because they derive from player assets.

Only source-visible vertices belong in the comparison. The high-detail frog
contains 227 raw vertices, of which 207 are rendered in these fixtures.
Part 15 contains 20 hidden throat vertices: `MR_ANIM.C:775–790` skips the
part when `MR_ANIM_ENV_DISPLAY_LIMITED_PARTS` is enabled and its display bit
is clear. `FROG.C:317` clears that bit; the PC FrogLord configuration also
hides the part. Keep raw observations, but exclude that part from visible
landmark acceptance. Compare start, airborne and landed poses with the same
per-vertex bounds and radius-three silhouette rule.

## High-refresh camera presentation

Terrain playback interpolates the committed camera basis and translation with
the same fraction as frog and entity motion. Exact endpoints preserve the
fixed12 basis; singular bases use component interpolation. Camera-dependent
environment UVs and sky translation receive floating source coordinates from
this rendered camera. Projection and aspect scaling are unchanged. Interactive
smoothing defaults on; reference capture launchers explicitly select exact mode.

## Animated part lighting

The gameplay frog and entity models are lit per part in the vertex shader
from each part node's world matrix, the C's `MRLight_matrix * lw_transform`
(`API.SRC/MR_ANIM.C:904-907`). The frog's custom ambient and colour scale come
from the committed `FrogState`, as in `MRCalculateCustomInstanceLights`
(`API.SRC/MR_LIGHT.C`). The remaining difference is float transforms and
normals against GTE 4.12 truncation, within one byte per channel; see the
[golden spec](../../../tests/golden/specs/animation.md#animated-part-lighting)
and [model lighting](README.md#model-lighting). Under the
[modern profile](modern-profile.md) Godot's directional lights light the
parts instead, and the committed colour scale and custom ambient still apply
through a per-part tint.

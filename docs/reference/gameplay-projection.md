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
frog-height landmarks and adjacent256-unit cells. The corpus is
`tests/golden/synthetic/gameplay_projection.csv`.

Each X/Y bound is declared before candidate inspection: signed rotation and
translation floors, ratio perturbation and C quotient truncation contribute
separately. Godot's concrete Gram-Schmidt order is independently applied to the exact
source basis; its difference from the ideal unit basis is calculated per point,
not replaced by a chosen tolerance. Float32 rounding uses gamma128=
128*2^-24/(1-128*2^-24) with absolute coordinate L1 error propagation.
The operation budget is27 normalization operations,33 dot/projection/subtraction
operations for Gram-Schmidt,21 view-coordinate operations,28 homogeneous
projection operations,11 viewport operations and 8 input/setup roundings.
The depth denominator is reduced by the propagated error; all samples remain
above the 128-unit clamp. Maximum row bounds are 1.543992 pixels X and
2.248278 pixels Y. These apply
to camera-projected landmark centers, not shaded image RMS or arbitrary scenes.
The native projection test applies the same Y scale as the existing shaders.

Visual comparison masks are semantic: the 40 authored point IDs and their
camera/terrain/frog-height categories form the projection acceptance mask.
Exclude UI, entity/form meshes, lighting, texture filtering and raster coverage
from this numeric test. A future silhouette comparison requires identical
frog action/cel, matrices, loaded mesh and source draw ownership; no image-wide
pixel tolerance is established here. Source images alone do not close that gate.

Build externally with `tools/build_gameplay_projection_oracle.ps1
-OutputDirectory <external-directory> -Run`; generate with
`python tools/make_golden_gameplay_projection.py
 tests/golden/synthetic/gameplay_projection.csv --c-oracle <external-exe>`.
The builder rejects repository/frozen-tree destinations, links only existing
reference objects and records hashes externally. It never rebuilds froggy.

The existing frozen frog_slice.exe supported `--target=org3 --render` capture
was run from an external stage with FROG_SLICE_SCREENSHOT_DIR pointing there.
It loaded the owner's EXE/MWD and existing high-detail assets; exit 0 produced
start, first jumping frame and landed 640x480 images. Paths/provenance live in
the authorized visualization root under `p7/projection`. This provides an
actual source-rendered reference, not a guessed rasterizer. It is an authored
ORG3 scene containing P8 entities, so it cannot be scored against the current
synthetic P7 scene. Candidate screenshot inspection has not selected these
bounds or masks.

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
requires identical map/entity state. The scalar tap's logs are external
`source-capture-facts.log` and contain each PNG path.

Native helper validation: projection focus passed one test with 243 assertions,
181 strict scripts. Changing source row 0 screen X 320 to 330 failed exactly that
X comparison; restoration passed. Logs are external temp runs
10451b2e33a242fa914bddfb227d581e, ab65fe8c70c54620bc9f29841adc69aa
(expected failure), ef1a15ab1af34bc19a6e4e7ec92460fb (restored).
Fixture cameras disable host physics interpolation because native unprojection
otherwise sees a cached prior transform when poses change in the same frame.

Foreground reference preparation adds one terminal render of the live frog
animation environment in a fresh viewport, with the retained camera and
viewport lighting matrices, against black. It uses existing MRAnimAddEnvToViewport,
MRRenderViewport and MRSwapDisplay; no subsequent game tick occurs. This
omits map/entities/shadows by viewport ownership rather than guessed image
segmentation. Two independent source launches produced the identical PNG hash
`d42e9644b3110fb1e27c31acca2ab81fccd4f61b8942c10e215c55b4e5760f45`.

Before rendering a candidate, `prepare_gameplay_foreground.py` records 227
actual frozen-C vertex landmarks, per-vertex X/Y bounds, source input/image
hashes and the exact action/cel/world matrices externally. Maximum bounds are
1.247466 pixels X and 1.255062 pixels Y for this pose. The float32 operation
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

The first foreground comparison retained in external evidence failed only for
part 15: the oracle initially included all 227 vertices, including 20 vertices
of the hidden throat. The actual source reports part flags 2 with
`MR_ANIM_ENV_DISPLAY_LIMITED_PARTS` enabled. `MR_ANIM.C:775–790` skips that
part; `FROG.C:317` clears its display bit and the PC FrogLord configuration
also hides part 15. The corrected eligibility therefore compares 207 rendered
vertices while preserving all 227 raw scalar observations externally. Numeric
bounds are unchanged. Fresh start, airborne and landed comparisons passed after this correction.
All 207 visible vertices meet their individual bounds and both silhouette
directions have zero pixels outside the declared radius 3. Maximum errors
(X/Y pixels) are 1.1913/1.0734, 1.0708/1.1572 and 1.0931/1.0796 respectively.
External evidence directories under `p7/projection` are
`foreground-e2fa1cfa0588419688e04de3cf37f4ba`,
`foreground-be512da0e4484ff38e563dfd14dc4664` and
`foreground-9b5fb4ea4a954ea294c054d303b5e8a8`. Each strict check parsed
190 scripts without failure. The original failure remains in
`foreground-3724d870a0514d4eb9559e27816a16e5`. This establishes foreground
geometry and coverage for these poses, not lighting or whole-level parity.

Visual inspection finds the candidate frog brighter and more uniformly green.
The source isolation copies the live viewport lighting/color matrices; the
candidate uses the existing model shaders without those source lighting
matrices. The existing `ModelMeshBuilder.lighting` path prelights static probes once with
a single build-time basis. Animated frog parts move afterward, so supplying
map lights there would freeze lighting against undeformed normals. Exact
animated part lighting needs a dedicated rendering change and independent
color samples; it is a future graphics follow-up. No color or lighting
acceptance metric was declared, so these
geometry and coverage passes do not establish lighting equivalence.

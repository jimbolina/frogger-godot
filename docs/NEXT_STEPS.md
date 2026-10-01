# Next steps after the project review

Reviewed 2026-10-01 at commit `b3188cd`.

**Current next phase: P6.** P5 is implemented and its acceptance gate passed.
Map parsing, rendering and camera work come next, including the first
FrogLord-saved map. The owner-supplied folder with the three `modded_*`
files is due for that phase.

The rest of this document is the historical pre-P5 review. The animation
implementation supersedes its work list; see `PORTING.md` and `FINDINGS.md`
for current status and evidence.

## Current state

Continue with **P5: animated models, flipbooks and texture animation**.
The earlier instruction to continue with P4 is stale. P4 landed in
`b3188cd` ("Read models (MOF), build their meshes, and add a model viewer"),
and `PORTING.md` already marks it done and P5 next.

The project reads retail archives, executable tables, textures and model
geometry, and has texture and static-model viewers. There is no gameplay
yet. The frozen C engine in `../froggy` remains the behaviour reference;
FrogLord's local Java source remains the format reference.

The remaining animation work is visible in the implementation:

- `src/legacy/formats/mof_animated.gd` reads the animated header and embedded
  static-model ranges, but not model sets, action/cel data or transforms.
- `src/legacy/formats/mof_part.gd` counts flipbook actions but skips their
  frame counts and starting partcel indices. It reads texture animation
  targets and lists for validation, but does not retain their associations
  or frame durations for playback.
- `src/convert/model_mesh_builder.gd` always builds partcel zero.
- `src/presentation/tools/model_viewer.gd` displays parts without animation
  transforms and has no playback controls.

The committed model census gives the scope: 78 animated files, 101 static
models with flipbooks, 174 flipbook actions, and 59 static models with
texture animation affecting 613 polygons. These are separate animation
mechanisms; animating only the frog would leave part of P5 unfinished.

## Recommended P5 work order

1. **Survey the animation data and stepping rules.** Read FrogLord's
   `mof2/animation/` classes and the reference engine's animation loader,
   `API.SRC/MR_ANIM.C`, `MR_ANIM2.H`, `mr_anim3.C`, and relevant model code.
   Inventory transform encodings, action/cel modes, shared data and frame
   origins actually present across all retail models. Follow the C engine
   for playback behaviour, including action changes and loop boundaries.
   Keep playback tick-driven; use the reference's 30 Hz for comparison and
   document the existing tick-rate question rather than using render FPS.
2. **Complete the pure-data readers and independent golden facts.** Decode
   model sets, poses and transforms; retain flipbook start/count pairs and
   texture target/list/duration relationships. Extend the independent
   Python reader from FrogLord's format definitions, with counts and
   digests for the new data. Cover malformed ranges, frame indexing and
   incomplete-model counterparts with synthetic tests. Store facts only,
   never retail bytes.
3. **Implement reusable playback and rendering.** Add explicit action,
   frame and tick state. Apply per-part transforms through `GameSpace`,
   select flipbook partcels, and advance texture lists by their durations.
   Keep instance playback state separate from shared decoded resources.
   Account for texture changes that change UV sizing or blend mode, and
   separate animated polygons from surfaces that must remain static.
   Avoid rebuilding a whole model on every render frame.
4. **Make animation demonstrable in the model viewer.** Add action
   selection, play/pause, single-tick stepping and current-frame display.
   Exercise skeletal/part animation, flipbooks and texture animation,
   including incomplete models and both high- and low-poly resources.
5. **Close the phase with evidence.** Check frame selection, transforms,
   texture durations and boundaries automatically; compare the frog's
   animation visually against the C reference and inspect examples of the
   other two mechanisms. Save screenshots outside the repository. Run
   strict compilation and both test modes, deliberately corrupt one new
   golden fact to verify the failure and restore it, then update README,
   PORTING and FINDINGS and make the phase commit.

For a focused C reference, inspect
`../froggy/engine/mr_stub/src/drivers/anim_slice/mr_anim_slice_main.c`
and the `verify_anim_retail` row in the engine's test catalogue. The
similarly named `frog_anim_slice` tests sprite command lists, so it is not
the skeletal animation comparison. Inspect invocation and output paths
before using a reference executable; do not rebuild or modify the frozen
reference tree.

## What follows

- **P6:** map decoding/rendering and camera, map lighting, projection and
  texture-seam checks, plus loading a FrogLord-saved map. The plan requests
  a folder with all three `modded_*` files from a small FrogLord edit by
  this phase. It is not a prerequisite for starting P5.
- **P7:** grid, frog movement, camera behaviour, collision and deaths.
- **P8:** entity framework, paths, zones, script interpreter and the
  general/original/suburbia themes. This is the planned first playable
  level milestone.

The project licence decision remains due before publication.

## Validation in this review

Using Godot 4.5.1 and the owner's existing `pc-retail-v3.0e` files:

| Check | Result |
|---|---|
| Strict script compilation | 90 scripts, 0 failed; exit 0 |
| Tests with retail files | PASS=174 FAIL=0 SKIP=0 EXIT=0 |
| Tests without retail files | PASS=140 FAIL=0 SKIP=34 EXIT=3 (expected skips) |

The initial PowerShell wrapper run crashed when Godot could not write its
normal `user://logs` file under the sandbox, producing exception windows.
The successful reruns used a process-local `APPDATA` directory under
`%TEMP%/frogger-godot-review-20261001`, explicit log files,
`--headless --disable-crash-handler`, and `Start-Process -WindowStyle Hidden
-Wait -PassThru` to capture the windowed executable's exit code reliably.
The isolated logs also contain a root-certificate-store access error;
compilation and tests completed successfully despite it.

This review did not rerun visual comparisons or implement P5. The P4
visual evidence is recorded in FINDINGS; the fresh checks above establish
the automated baseline. Only this review document was added.

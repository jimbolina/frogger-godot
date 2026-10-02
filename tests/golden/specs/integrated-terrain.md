# Integrated terrain component records

The C adapter links frozen compiled objects and calls ControlFrog, MoveFrog,
CollideFrog, UpdateCamera, UpdateFrogAnimationScripts and MRAnimUpdateEnvironments
in that order. Each phase emits the represented state. Python independently
composes the terrain, camera and animation rules before accepting any golden.
No expected values come from Godot or from copying C output.

`integrated_terrain.csv` has 1,464 records with 42 columns named in its header.
Four authored fixtures cover simultaneous north/east arbitration, clockwise
camera wait with held ordinary input, a 513-unit fall followed by stun/shake and
idle animation on the shared random stream, and water death deferred until the
next control call. Horizons are 24, 24, 120 and at most 80 calls; the death
fixture stops at the actual mainloop request. Counts are fixture horizons,
not predictions of movement completion.

Follow mode starts with a caller-supplied tracked spawn position and a real
camera update composing its initial matrix. Level-start ResetCamera sweeping
is covered separately. Action metadata uses 34 authored counts `3 + index % 3`.
The seed is explicitly one for each fixture. At tick 12 collision, stun requests
the two source shake draws. Subsequent idle script evaluation consumes that
same stream; it resets the no-input timer at scripts tick 87.

Audio and AddFrogScore are omitted; the latter suppresses authoritative score,
lives, light/time and powerup mutations. Renderer effect factories return
writable storage without constructing visuals. Their full-engine random draws
are omitted without compensation. The mainloop wrapper records the requested
mode without running its setup callbacks. Animation pose construction clears
and restores MR_ANIM_ENV_UPDATE while actual cel stepping runs. These explicit
boundaries prohibit a whole-engine parity claim.

The game test compares the five public phase snapshots, including the final
post-pose state. The isolated animation family also checks the intermediate
script phase. Additional game fields and presentation geometry are outside this
42-column family and need their own source evidence.

The integration test separately checks selected draw counts and consumer order
from the source's two ShakeCamera macro expressions and one idle IF expression.
MRrand is a macro, so these are source-expression counts constrained by the C
seed records rather than intercepted C function-call counters.

Build `tools/build_integrated_terrain_oracle.ps1` into an external directory,
then run `tools/make_golden_integrated_terrain.py --c-oracle EXE`. `--verify`
checks existing golden facts. Link inputs and hashes are saved in external
provenance JSON. Both source repositories remain untouched by linking.

`tools/compare_integrated_terrain.py REFERENCE_CSV CANDIDATE_JSONL --scenario N`
compares this explicit numeric scope with the five public game trace phases.
It validates ordered rows, exact integers, authored seed/action metadata and
command masks, rejecting missing/extra phases. Other JSONL fields are outside
this component comparison; `compare_run_trace.py` checks complete replay traces.

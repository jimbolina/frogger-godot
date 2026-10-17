# Terrain inspection

`TerrainScenario` resolves setup outside the rules. Built-ins are authored
synthetic inputs, not expected outputs. A JSON file may replace `grid`, `level`
and `start`, and supply explicit tick commands. `TerrainScenarioJson` rejects
malformed scalar/vector records; `TerrainRun.create` checks detached rule
definitions. Commands contain logical pressed and held masks, never host keys. Optional
`start_timer_context` and `start_sequence_complete` carry explicit external
startup milestones. Detached command copies preserve every typed field. Seeds
and square flags accept the full unsigned 32-bit range; coordinates and other
scalar fields use signed 32-bit bounds.

Grid JSON contains `dimensions`, `base`, `[first_square,count]` stacks and
squares with flags and four integer `[x,y,z]` vertices. Optional square source
offsets and polygon identities remain diagnostics. Level inputs include spawn,
collision bounds, theme, camera offsets and action lengths. Start inputs include
seed, controller mapping, modifiers, lives and explicit startup mode/timer.
`--seed` and `--tick-limit` overrides use the same decoder in both drivers.

Player data optionally supplies the high-detail frog and real action lengths.
`--level` resolves the selected map's GRID, spawn, camera and theme through
existing `GameData` APIs. By default entities, forms, platforms, zones and
authored entity boundary markers are omitted. `--entity-reactions=pop` or
`--entity-reactions=platforms` opts into the bounded modes below. None is a
complete playable level. `--entity-lifecycle visibility` additionally enables
the bounded lifetime below; `all-attached` remains the command-line default.

Direct interactive launches with `--level` select live keyboard input unless
`--scenario`, `--scenario-file` or `--run-scenario` explicitly selects a replay.
Space starts/pauses; Tab switches LIVE/REPLAY, shown with the playback state in
the overlay. Live input has no fixture tick limit and reset retains its selection.
A finished replay stays paused and explains how to select live input.

The viewer borrows injected `GameData` unless ownership is transferred.
Replacement closes an owned source once; reattaching the same source retains
ownership. Detaching or replacing a data-derived level clears its scene, run
and displayed source identity before loading another source. Synthetic detached
definitions may remain. Frog resources are loaded once per attachment and shared
between setup and drawing.

Drawing consumes copied snapshots. Interpolation, overlays and projection never
advance rules. Completion pauses the viewer and ends automated capture. The
overlay shows destination, layer flags, source identity, camera, death and
ordered outcomes. Projection scaling reaches terrain, frog and animated texture
frame materials after resize; see [gameplay projection](../rendering/gameplay-projection.md).

`tools/run_terrain.py` runs either driver with an isolated profile, hidden awaited
processes and external logs. `--viewer --render-rate=30|60|144` uses explicit
scheduled presentation deltas with one awaited draw per frame. These are render
schedule tests, not measurements of host FPS. JSONL records initial start/camera metadata, complete typed commands and every
represented phase/snapshot, ordered outcome and RNG consumer. Full trace equality checks
headless/render parity; the independent C comparator checks its explicitly
defined field scope. `tools/verify_terrain_schedules.py` runs the four independent
fixtures against all three render schedules sequentially.

Captures and traces must be outside this checkout and frozen `froggy`.
Generated resources are released on reset/replacement rather than accumulated.

For actual host frame pacing, use `python tools/run_terrain_performance.py
--godot <executable> --data-dir <game-folder> --output-directory <external-folder>`.
The launcher strictly compiles scripts, isolates user data, and runs both complete
ORG1 routes three times at 2560×1440 with VSync disabled and no frame cap. Each run
warms for five seconds and resets before measuring real frame completion intervals.
JSON reports retain individual frame times, percentiles, tick-frame costs, cadence,
route outcome, hardware, effective viewport, draw calls and resource counts.
At a 2560×1440 window, the preserved 4:3 aspect renders 1920×1440 natively
with 320-pixel side bars. The probe explicitly sizes the window after startup
to avoid Windows work-area clamping. It derives the native extent from the
logical viewport and stretch transform: Godot 4.5.1's viewport texture size
accessor applies that stretch twice.
Loading and reset costs are separate. Reports and logs stay outside the repository.

Use `--resolution 640x480 --sync default --smoothing false` to reproduce the older
configuration; `--route round-trip --repetitions 1` shortens diagnostic iteration.
`--mode paused|simulation|no-inspector` isolates rendering, pure simulation, or
inspection drawing respectively. `--profile` enables Godot's script profiler in a
separate diagnostic run; `--threaded false` compares synchronous simulation and
`--window-mode exclusive` isolates window-compositor effects. Script and visual
profiler packets are retained together with a readable script timing summary.
These are not acceptance modes. `--require-target` requires
both routes three times, smooth uncapped 1440p, average above 200 FPS, p99 at most
5 ms, correct outcome and 30 Hz cadence within one tick. The target is specific to
the owner's i7-10700K/RTX 4070 Ti SUPER; it is not a portable test-suite threshold.
Passing schedule parity alone never establishes interactive performance. Full phase
tracing remains deliberately more expensive than ordinary LIVE/REPLAY.

## POP entity inspection

`--entity-reactions=pop` attaches copied STATIC/MOVING definitions and FORM
reaction facts to the same `TerrainRun`. Entity paths, frog, camera and animation
advance through one commit; the viewer consumes its snapshots. Cactus models,
FORM outlines, contacted cells, authored indices and death requests make the
reaction visible. Particle effects are requested, not rendered. Support and
all-attached lifetime assumptions are defined in the
[entity contract](../gameplay/entities.md#bounded-pop-reactions).

With `--data-dir <game-folder> --level DES2 --entity-reactions pop`, the scenario
uses an explicit safe inspection start and one east hop into the first cactus.
This is not the map's normal player spawn. The airborne hit precedes the
destination terrain's own lethal reaction. Golden inputs and source facts are
specified [beside the tests](../../../tests/golden/specs/entities.md).

Integrated traces use `entity-pop-v1`, retaining ordered phase snapshots, entity
transforms/path cursors, contact/reaction outcomes, per-tick hits and the first
lethal entity identity. Failed ticks publish none of those candidate outcomes.
The terrain-only `terrain-run-v1` and fixed-probe `entity-contact-v1` modes remain
available. Render interpolation never changes contact decisions.

```powershell
python tools/verify_entity_reaction_schedules.py --godot <godot-executable> --data-dir <game-folder> --level DES2 --output-directory <external-output>
python tools/verify_entity_reaction_schedules.py --godot <godot-executable> --scenario-file tests/golden/fixtures/integrated_entities.json --case-index 0 --output-directory <external-output>
```

The verifier runs headless and rendered 30/60/144 schedules serially through
completion. `--case-index` selects an authored case from the grouped synthetic
fixture; a standalone scenario needs no index. Inspect the pre-contact, hit,
POP-animation and death-camera images,
including the full controls at 640x480. All evidence stays outside both repos.

## SAFE platform inspection

`--entity-reactions platforms` enables SAFE plus existing POP reactions, with
an integrated camera. `--data-dir <game-folder> --level JUN1` explicitly starts
at water cell `(18,5)`, facing NORTH, presses NORTH at command tick zero, and
observes 90 ticks. This is an inspection start, not a verified route from safe
terrain. The first log contact must occur at command tick 3 / entity tick 4.
The [entity contract](../gameplay/entities.md#bounded-safe-platforms) defines
support; [golden reproduction](../../../tests/golden/specs/entities.md) owns
the independent retail facts. No airborne-start API is involved.

`entity-platform-v1` extends the ordered trace with attachment/forbidden authored
identities, local cell/offset/relative transform, transient carry indices and
camera modification/correction state. The HUD shows attachment and carry state;
the existing play, step, reset, interpolation, live input and turn controls apply.

```powershell
python tools/verify_platform_schedules.py --godot <godot-executable> --data-dir <game-folder> --output-directory <external-output>
python tools/verify_platform_schedules.py --godot <godot-executable> --scenario-file tests/golden/fixtures/platforms.json --case-index 0 --output-directory <external-output>
```

The verifier runs headless and rendered 30/60/144 schedules serially, checks
complete trace equality, source stability and retail contact identity, and saves
640×480 captures. Inspect approach, attachment, centring, carrying and camera
transition; synthetic cases also demonstrate departure. Keep logs, provenance,
selected scenarios and captures outside both repositories. Freeze source edits
while verifying a candidate.

## Guarded JUN1 bank exploration

`--level JUN1 --exploration jun1-log-bank` admits the independently audited
v3.0e high-detail map and its determining EXE/model facts. It starts on safe
bank cell `(22,10)`, LIVE and paused, with no automatic commands or live tick
limit. The preset supplies platform reactions, all-attached lifetime and a
half-open world boundary, X `[1900,2304)`, Z `[-5376,-4864)`. It rejects active
camera-zone entry and cannot be combined with visibility lifetime. The
[entity contract](../gameplay/entities.md#guarded-jun1-bank-route) owns the
admission proof and limitations; the existing water-start inspection is separate.

For the reproducible route, use the explicit fixture: logical WEST mask `8`
at command tick 0, EAST mask `2` at tick 12, and observe all 60 ticks. Contact
is tick 3, centring finishes at tick 11, and tick 17 returns detached and alive
to safe cell `(22,9)`. The new `entity-exploration-v1` trace records Control,
Move, Collision, Camera, Scripts and Final, including unchanged script-phase
state; it does not execute entity scripts. The verifier rejects truncated or
prematurely completed runs, compares every represented command, snapshot,
contact, camera, animation, RNG consumer and outcome across schedules, and
checks the independently defined frozen-C movement/contact/camera fields.

```powershell
python tools/verify_platform_schedules.py --godot <godot-executable> --data-dir <game-folder> --scenario-file tests/golden/fixtures/jun1_log_bank.json --exploration jun1-log-bank --output-directory <external-output>
```

Inspect safe start, airborne approach, attachment, centring, carry and safe
return captures at 640×480. Exercise actual Godot keyboard dispatch separately:
idle past ticks 16 and 90 without movement, pause/reset, Left onto the log,
Right after centring, Space pause/resume, Q/E turns, Period step, Shift hop and
Tab mode switching. A rejected boundary move must pause with a readable reason
and leave the complete prior tick intact. R must clear buffered input and
presentation clocks, restore the whole inspection, pause and retain LIVE.
This is an inspection reset, not checkpoint or death recovery. Animated-lighting
limitations remain those of the existing renderer.

## Guarded ORG1 turtle/log exploration

`--level=ORG1 --exploration=org1-turtle-log-bank` opens LIVE and paused with no
automatic commands or live tick limit. The [entity contract](../gameplay/entities.md#org1-admission)
owns the source proof, bounds, supported closure and frozen route schedules.
Setup pins the supplied resources, named bindings and every neighbor exclusion.
Changed dependencies and visibility lifetime reject; boundary/animated-pose
violations discard the entire tick and pause. R restores inspection/input and
presentation state while retaining the selected input mode.

The two fixtures exercise the connected round trip through full dive/rise
cycles and a separate attached-diver drowning case. Run each complete fixture:

```powershell
python -B tools/verify_platform_schedules.py --godot <godot-executable> --data-dir <game-folder> --level ORG1 --exploration org1-turtle-log-bank --scenario-file tests/golden/fixtures/org1_turtle_log_bank.json --output-directory <external-output>
python -B tools/verify_platform_schedules.py --godot <godot-executable> --data-dir <game-folder> --level ORG1 --exploration org1-turtle-log-bank --scenario-file tests/golden/fixtures/org1_attached_diver.json --output-directory <external-output>
```

The verifier streams complete six-phase records externally, checks independent
source phase facts and ordered entity-update digests, then compares every
represented field and outcome at rendered 30/60/144 schedules. Inspect each
transfer, bank return and visible attached dive/death at 640×480. Audio playback
and splash rendering remain deferred. Entity action/cel, colour and ambient
state come from committed snapshots; materials are instance-local.

`tools/probe_org1_keyboard.gd` dispatches `InputEventKey` through Godot's input
system and checks the round trip, Space/Period, camera-relative controls,
boundary rollback, R, mode retention and unlimited live ticks. Run it rendered
with the same level/exploration/data arguments and an external screenshot
directory, using the isolated-profile, hidden/awaited process rules in the
[testing guide](README.md). Check its log for errors as well as its exit code.

## Visibility lifecycle inspection

`--entity-lifecycle visibility` requires integrated entity reactions and a
camera. Authored JSON may supply `level.entity_collision.lifecycle` with
`polygon_counts`, one total per authored map group; the enclosing collision geometry
defines the group base, dimensions and size. Setup rejects zone-bearing maps.
The [entity contract](../gameplay/entities.md#visibility-lifecycle) owns the
supported behavior, polygon guard and delayed creation/culling rules.

`entity-lifecycle-v1` adds live membership, pending destruction, generation,
actual live-list order, selected groups and ordered lifecycle observations to
the integrated trace. The display distinguishes those states and preserves
authored indices. Model instances are released when killed and restart animation
on recreation; persistent path state is independent. Rendering never decides
the live set. Existing contact/POP/platform schemas and all-attached behavior
remain available.

```powershell
python tools/run_terrain.py --godot <godot-executable> --scenario-file tests/golden/fixtures/lifecycle_integrated.json --entity-lifecycle visibility --viewer --output-directory <external-output>
python tools/verify_lifecycle_schedules.py --godot <godot-executable> --output-directory <external-output>
python tools/verify_lifecycle_schedules.py --godot <godot-executable> --scenario-file tests/golden/fixtures/lifecycle_safe_moving.json --output-directory <external-output>
python tools/verify_lifecycle_schedules.py --godot <godot-executable> --scenario-file tests/golden/fixtures/lifecycle_safe_static.json --output-directory <external-output>
```

The synthetic fixture follows the ordinary camera as the frog walks east and
returns. Require creation, disappearance, continuously advancing dormant paths
and later recreation; an empty live set throughout is not success. Compare
headless and rendered 30/60/144 schedules serially. Inspect initial, created,
pending, destroyed and recreated captures, plus lifecycle-enabled SAFE landing
and departure. Keep captures/logs outside both repositories.

FOR1's script-free jay/path facts are independent retail setup evidence, not a
verified automatic-camera demonstration. A fixture selecting its group directly
is component-only. Retail runtime coverage must retain that distinction.

## Reproducing schedule comparisons

Generate the independent integrated fixtures with
`tools/make_golden_integrated_terrain.py --scenario-dir <external-scenarios>`;
see the [integrated corpus specification](../../../tests/golden/specs/integrated-terrain.md)
for the full generator invocation and C reference requirement. Then run:

```powershell
python tools/verify_terrain_schedules.py --godot <godot-executable> --scenario-directory <external-scenarios> --reference tests/golden/synthetic/integrated_terrain.csv --output-directory <external-output>
```

The complete-trace comparator requires ticks starting at zero and Control,
Move, Collision, Camera and Final in order. A trace must reach `tick_limit` or
end in explicit completion; a zero limit permits metadata only. Missing,
reordered, truncated, error and post-completion records fail comparison.

# Terrain inspection

`TerrainScenario` resolves setup outside the rules. Built-ins are authored
synthetic inputs, not expected outputs. A JSON file may replace `grid`, `level`
and `start`, and supply explicit tick commands. `TerrainScenarioJson` rejects
malformed scalar/vector records; `GameplayRun.create` checks detached rule
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
existing `GameData` APIs. ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and SKY1–SKY4 without an exploration preset use
whole-map dependency validation, authored zones, entity contacts, visibility
lifecycle and level flow. The explicit JUN1 platform-reaction probe without a
visibility lifecycle keeps its bounded inspection path, as the DES2 POP probe does. Other levels omit entities, forms, platforms, zones and authored
entity boundary markers by default. For those inspections,
`--entity-reactions=pop` or `--entity-reactions=platforms` selects the bounded
component modes below, and `--entity-lifecycle visibility` enables the bounded
lifetime probe instead of the default `all-attached` mode. The explicit exploration
presets retain their regression bounds.

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
processes and external logs. `--viewer --render-rate=30|60|144|200|240` uses explicit
scheduled presentation deltas with one awaited draw per frame. These are render
schedule tests, not measurements of host FPS. JSONL records initial start/camera metadata, complete typed commands and every
represented phase/snapshot, ordered outcome and RNG consumer. Full trace equality checks
headless/render parity; the independent C comparator checks its explicitly
defined field scope. `tools/verify_terrain_schedules.py` runs the four independent
fixtures against all three render schedules sequentially.

Captures and traces must be outside this checkout and frozen `froggy`.
Generated resources are released on reset/replacement rather than accumulated.

For actual host frame pacing, use `python tools/run_terrain_performance.py
--godot <executable> --output-directory <external-folder>`.
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

For the playable P8c workload, add `--route whole-map-idle --repetitions 1`.
This diagnostic uses whole-map ORG1 dependency setup with authored startup and
600 input-free ticks, including normal PLAY time after startup. It rejects
simulation errors and requires an idle living frog at the spawn with unchanged
score/checkpoints and time remaining. Reports identify the workload, final flow
phase and remaining time. It does not run either bounded route and cannot satisfy
`--require-target`; a measurement on different hardware remains a diagnostic.
Add `--route whole-map-hops` instead to measure 16 alternating lateral hops
following startup. The probe validates the two spawn-row terrain cells, runs full
contacts, checks each landing and reports the final cell, score and landing count.
A departure from the prescribed safe route fails the diagnostic. These two
workloads cover startup and the spawn row; they do not establish frame pacing
through arbitrary keyboard routes, river contacts or checkpoint resets. Compare
interactive runs only with the same window size, synchronization and tracing
settings. The viewer FPS display averages host frames over half-second windows;
the report also retains individual frame times and tail percentiles.
Run acceptance on an otherwise idle system: another game or profiler makes the
results unsuitable for comparison. Engine-reported VSync/cap values cannot prove
a driver override is absent. A forced driver VSync override is a known local
blocker; the 200+ FPS gate requires an application-controlled Godot driver profile.

Use `--resolution 640x480 --sync default --smoothing false` to reproduce the older
configuration; `--route round-trip --repetitions 1` shortens diagnostic iteration.
`--mode paused|simulation|no-inspector` isolates rendering, pure simulation, or
inspection drawing respectively. `--profile` enables Godot's script profiler in a
separate diagnostic run; `--threaded false` compares synchronous simulation and
`--window-mode exclusive` isolates window-compositor effects. Add
`--profile-kind visual` for a separate rendering profile. Raw profiler packets
and readable script or per-stage CPU/GPU timing summaries are retained externally.
These are not acceptance modes. `--require-target` requires
both routes three times, smooth uncapped 1440p, average above 200 FPS, p99 at most
5 ms, correct outcome and 30 Hz cadence within one tick. The target is specific to
the owner's i7-10700K/RTX 4070 Ti SUPER; it is not a portable test-suite threshold.
Passing schedule parity alone never establishes interactive performance. Full phase
tracing remains deliberately more expensive than ordinary LIVE/REPLAY.

## Whole-map keyboard playthrough

Run `python tools/run_org1_playthrough.py --godot <executable> --output-directory <external-folder>` to exercise all five ORG1
checkpoints through the viewer's keyboard event handling. The launcher imports
and strictly compiles in an isolated profile, then runs an awaited rendered probe.

`tests/golden/fixtures/org1_keyboard_playthrough.json` is sparse input stimulus,
not a golden of expected runtime state. Each `[tick, mask]` supplies the held keys at that sample; omitted ticks release
all keys. Consecutive samples of one key produce one press edge, matching the host. The route starts through the normal single-start
sequence and uses no teleports or state overrides. The probe dispatches key events
and Period steps while paused, comparing every committed state with a separate
fresh `GameplayRun` receiving the same logical commands. It requires all five
checkpoint bits, COMPLETE and no deaths, permitting earned extra lives. Captures
are limited to checkpoint transitions and completion; the external report records
milestones and final state. `--route <file>` selects another stimulus with the same
acceptance requirements by default. A supplemental route may set `goal` to
`pink_delivery` or `tongue_collection`: the probe requires the pink delivery
reward and home state, or a targeted tongue gulp and hidden collected entity,
respectively. Collection captures and flags are included in the report. The
default route alone does not establish these collections. Exact stepping is
not a frame-pacing measurement.

The supplemental fixtures are `org1_keyboard_pink_delivery.json` and
`org1_keyboard_tongue_collection.json` in the same fixture directory. Run each
through the launcher with `--route tests/golden/fixtures/<filename>` to verify
its collection goal with the same real keyboard events and per-tick parity.

## POP entity inspection

`--entity-reactions=pop` attaches copied STATIC/MOVING definitions and FORM
reaction facts to the same `GameplayRun`. Entity paths, frog, camera and animation
advance through one commit; the viewer consumes its snapshots. Cactus models,
FORM outlines, contacted cells, authored indices and death requests make the
reaction visible. Particle effects are requested, not rendered. Support and
all-attached lifetime assumptions are defined in the
[entity contract](../gameplay/entities.md#bounded-pop-reactions).

With `--level DES2 --entity-reactions pop`, the scenario
keeps the bounded all-attached POP probe rather than whole-map play and
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
python tools/verify_entity_reaction_schedules.py --godot <godot-executable> --level DES2 --output-directory <external-output>
python tools/verify_entity_reaction_schedules.py --godot <godot-executable> --scenario-file tests/golden/fixtures/integrated_entities.json --case-index 0 --output-directory <external-output>
```

The verifier runs headless and rendered 30/60/144 schedules serially through
completion. `--case-index` selects an authored case from the grouped synthetic
fixture; a standalone scenario needs no index. Inspect the pre-contact, hit,
POP-animation and death-camera images,
including the full controls at 640x480. All evidence stays outside both repos.

## SAFE platform inspection

`--entity-reactions platforms` enables SAFE plus existing POP reactions, with
an integrated camera. `--level JUN1` explicitly starts
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
python tools/verify_platform_schedules.py --godot <godot-executable> --output-directory <external-output>
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
[entity contract](../../../tests/golden/specs/entities.md#guarded-jun1-route-and-zones) owns the
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
python tools/verify_platform_schedules.py --godot <godot-executable> --scenario-file tests/golden/fixtures/jun1_log_bank.json --exploration jun1-log-bank --output-directory <external-output>
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
automatic commands or live tick limit. The [entity contract](../../../tests/golden/specs/entities.md#org1-route-proof)
owns the source proof, bounds, supported closure and frozen route schedules.
Setup pins the supplied resources, named bindings and every neighbor exclusion.
Changed dependencies and visibility lifetime reject; boundary/animated-pose
violations discard the entire tick and pause. R restores inspection/input and
presentation state while retaining the selected input mode.

The two fixtures exercise the connected round trip through full dive/rise
cycles and a separate attached-diver drowning case. Run each complete fixture:

```powershell
python -B tools/verify_platform_schedules.py --godot <godot-executable> --level ORG1 --exploration org1-turtle-log-bank --scenario-file tests/golden/fixtures/org1_turtle_log_bank.json --output-directory <external-output>
python -B tools/verify_platform_schedules.py --godot <godot-executable> --level ORG1 --exploration org1-turtle-log-bank --scenario-file tests/golden/fixtures/org1_attached_diver.json --output-directory <external-output>
```

The verifier streams complete six-phase records externally, checks independent
source phase facts and ordered entity-update digests, then compares every
represented field and outcome at rendered 30/60/144/200/240 and irregular
schedules. Reference captures explicitly select `--smoothing=false`.
Use `run_terrain.py --viewer --smoothing=true` to inspect interpolated motion;
add `--motion-capture --tick-limit 90` to save a short external PNG sequence.
`--frame-schedule=irregular` supplies a repeating mix of 240/60/200/30/144 Hz
intervals. These schedules measure correctness, not achievable throughput. Inspect each
transfer, bank return and visible attached dive/death at 640×480. Audio playback
remains deferred; the terrain viewer draws no effects. Entity action/cel, colour and ambient
state come from committed snapshots; materials are instance-local.

`tools/probe_org1_keyboard.gd` dispatches `InputEventKey` through Godot's input
system and checks the round trip, Space/Period, camera-relative controls,
boundary rollback, R, mode retention and unlimited live ticks. Run it rendered
with the same level/exploration/data arguments and an external screenshot
directory, using the isolated-profile, hidden/awaited process rules in the
[testing guide](README.md). Check its log for errors as well as its exit code.

## Scripted ORG1 visibility

The separate `org1-turtle-log-bank-visibility` preset uses the existing river
corridor with source live-list updates, immortal initialization and pink frog
pickup/riding. Bounds and other exclusions remain; see the
[contract](../gameplay/entities.md#pink-frog-behavior).

```sh
python -B tools/verify_platform_schedules.py --godot <godot-executable> --level ORG1 --exploration org1-turtle-log-bank-visibility --scenario-file tests/golden/fixtures/org1_visibility_round_trip.json --output-directory <external-output>
python -B tools/verify_platform_schedules.py --godot <godot-executable> --level ORG1 --exploration org1-turtle-log-bank-visibility --scenario-file tests/golden/fixtures/org1_visibility_diver.json --output-directory <external-output>
python -B tools/verify_platform_schedules.py --godot <godot-executable> --level ORG1 --exploration org1-turtle-log-bank-visibility --scenario-file tests/golden/fixtures/org1_visibility_pickup.json --output-directory <external-output>
python -B tools/verify_platform_schedules.py --godot <godot-executable> --level ORG1 --exploration org1-turtle-log-bank-visibility --scenario-file tests/golden/fixtures/org1_visibility_pickup_death.json --output-directory <external-output>
```

These compare headless state and 30/60/144 Hz rendered schedules. The existing
`probe_org1_keyboard.gd` also accepts this preset to exercise input dispatch,
round-trip movement, pause, rejection and complete reset. Use the same isolated
profile, explicit log and hidden awaited process rules as other keyboard probes.

## Guarded ORG1 road to river

`--level=ORG1 --exploration=org1-road-river` opens LIVE and paused at the
southern road edge. The [vehicle contract](../gameplay/entities.md#vehicle-primitive-contacts)
defines its separate admission and source collision timing. The overlay shows
the first death entity and accepted frog part/hilite; external full traces
include ordered primitive diagnostics and the stored collision-pose cache.

Run the successful crossing and deliberate vehicle-death fixtures separately:

```powershell
python -B tools/verify_platform_schedules.py --godot <godot-executable> --level ORG1 --exploration org1-road-river --scenario-file tests/golden/fixtures/org1_road_river.json --output-directory <external-output>
python -B tools/verify_platform_schedules.py --godot <godot-executable> --level ORG1 --exploration org1-road-river --scenario-file tests/golden/fixtures/org1_road_vehicle_death.json --output-directory <external-output>
```

Both use the six scheduled render cadences and complete source comparisons
described above. Inspect captures of the start, traffic, bank, river platform
and vehicle death. Use 640×480 for correctness checks; these are not performance
measurements. Reset and boundary rollback remain atomic.

## Visibility lifecycle inspection

`--entity-lifecycle visibility` requires integrated entity reactions and a
camera. Authored JSON may supply `level.entity_collision.lifecycle` with
`polygon_counts`, one total per authored map group; the enclosing collision geometry
defines the group base, dimensions and size. Ordinary retail terrain setup
rejects zone-bearing maps; authored scenarios can combine zones and lifecycle.
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

## Active camera zone inspection

`--camera-inspection jun1-camera-zones` selects a separate prescribed camera
probe through the existing terrain launcher. It requires v3.0e player data and
uses the supplied high-detail JUN1 map, camera defaults and zone records.
Gameplay scenarios, entity-reaction switches and tick-limit overrides cannot be
combined with it. `--entity-lifecycle visibility` opts into the bounded log probe
below. No entity collision or playable-route admission is implied.

The first sequence holds each cell `(10,3)`, `(11,3)`, `(11,4)`, `(11,5)` for
40 ticks, entering and exiting zone 15. The second resets camera state, starts
with the opposite camera quadrant, and holds `(14,22)`, `(15,22)`, `(14,23)`,
`(14,24)` for 40 ticks each. It enters zone 0, forces a half-turn, changes child
region while retaining the zone, and exits. Probe world Y is explicitly zero.
The pink probe is drawn through geometry because its prescribed Y=0 can lie
below terrain. The overlay distinguishes frog zone/region, camera-consumed zone,
offset timer and twist counter/quadrants. Both sequences together contain 320 source updates.

```powershell
python tools/run_terrain.py --godot <executable> --camera-inspection jun1-camera-zones --viewer --output-directory <external-folder>
python tools/verify_camera_zone_schedules.py --godot <executable> --output-directory <external-folder>
```

The verifier requires complete JSONL traces, checks independent reference fields
and compares every published field across headless and rendered 30/60/144 Hz.
`camera-zone-inspection-v1` metadata records definitions and the prescribed tick
count; each row records its sequence, cell/world position, frog selection and
full camera snapshot. Captures include entry, mid-turn, settled offsets, region
change and exit. Inspect both map framing and the probe; trace equality alone
is not visual acceptance.

For manual inspection, open `scenes/tools/camera_zone_viewer.tscn` with the data
folder argument and without `--run-scenario`. It starts paused. Space toggles
playback, Period steps, and R clears the clock, selection and both sequences,
then pauses. This is inspection reset, not checkpoint/death recovery.
The [camera contract](../gameplay/gameplay-camera.md#zone-boundaries) owns runtime
semantics and [golden specification](../../../tests/golden/specs/camera-components.md#active-camera-zones)
owns the independent generators and known frozen-build source difference.

## Combined zone and lifecycle inspection

`lifecycle_zones.json` adds active-zone entry/exit to the synthetic out-and-back
terrain scenario. Authored JSON accepts `level.camera_zones`: ordered objects
with `zone_index`, four `bounds`, optional `regions`, `camera_flags`,
`camera_direction` and eight XYZ `camera_offsets`. Omitted scalar values use
`ZoneDefinition` defaults. Existing scenarios without this field are unchanged.

The JUN1 camera probe accepts `--entity-lifecycle visibility`, admitting only
the eleven verified logs. Its camera/path/lifecycle state resets between the
two existing sequences, and R resets everything to dormant tick zero. The
overlay shows live count, selected-group count and lifecycle events. Models
and markers disappear/reappear according to committed generations. Metadata
lists every omitted authored entity. No frog movement or contact runs here.

```powershell
python tools/run_terrain.py --godot <executable> --scenario-file tests/golden/fixtures/lifecycle_zones.json --entity-lifecycle visibility --viewer --output-directory <external-folder>
python tools/run_terrain.py --godot <executable> --camera-inspection jun1-camera-zones --entity-lifecycle visibility --viewer --output-directory <external-folder>
python tools/verify_zone_lifecycle_schedules.py --godot <executable> --output-directory <external-folder>
```

The verifier checks independent facts and complete headless/30/60/144 Hz
snapshots for both demonstrations. Synthetic traces retain `entity-lifecycle-v1`;
retail uses `camera-zone-lifecycle-v1`, adding admitted definitions, diagnostics,
complete lifecycle state and selected polygon total to the camera probe trace.
Captures include lifecycle transitions and zone transitions; inspect map framing,
log placement and retirement/recreation. The camera-only command/schema remains
unchanged. Input admission and remaining limitations belong to the
[entity contract](../gameplay/entities.md#combined-camera-zones-and-lifecycle).

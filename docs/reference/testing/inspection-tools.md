# Inspection tools

This page covers the developer tools for inspecting and play-checking the
port: direct level launches, the terrain viewer, the sandbox, the model viewer
and the map viewer. The sandbox is a play-check tool, not acceptance evidence.
Every capture, trace and output folder must be an absolute path outside the
checkout.

## Terrain viewer

### Launching a level

Launch a level directly in the game scene with:

```text
godot --path . res://scenes/game/gameplay.tscn -- --level=SUB1
```

The default is high-detail ORG1. `--level=` also opens a level that has a map
but is not yet accepted, such as JUN2, with a warning; the front end lists only
accepted levels.

A direct launch reads the project's class-name cache in `.godot/`, which goes
stale when new scripts arrive and then fails with a script parse error. Prefer
`tools/play.sh --level=SUB1` (or `tools/play.ps1`), which refreshes the cache
before launching; `--scene=` selects another scene. No data folder is needed
once `assets/` holds an import ([developer setup](../developer-setup.md)).

Add `--record-inputs` to record your play. When the level completes, the held
keys of every tick are written as a replay fixture to
`user://playthroughs/<level>_keyboard_playthrough.json`; the completion message
shows the absolute path, and `--record-inputs=<file>` chooses another. The
capture launcher replays such files through real key events with per-tick
parity checks. Recording is optional diagnostic material, not a requirement.

The 0 key (top row) opens the debug graphics panel on the right: display,
quality, shadows, bloom, effects and look settings apply at once and are saved
to `user://graphics.cfg`. The panel is mouse-driven, so game keys keep working
while it is open.

### Interactive terrain inspection

The terrain inspection driver uses the same rules as the tests:

```text
godot --path . res://scenes/tools/terrain_viewer.tscn
```

A direct retail-map launch selects live arrow-key input:

```text
godot --path . res://scenes/tools/terrain_viewer.tscn -- --level=ORG1
```

| Key | Action |
|---|---|
| Space | Play or pause; in live input, press it to start hopping |
| Period | Step |
| R | Reset |
| I | Change interpolation |
| Tab | Switch input mode |
| Shift | Super hop, or skip the current checkpoint bonus phase |
| Ctrl | Tongue |
| Q / E | Turn the gameplay camera |

The overlay shows LIVE/REPLAY and running/paused, score, time, lives,
checkpoint progress and completion/game-over state. FPS, average frame time
and the last simulation tick time refresh twice per second. Reset pauses and
retains the selected input mode. Pause and reset also reset drawing
interpolation. Explicit scenario fixtures and automated captures still replay
their bounded command sequence.
[Repeatable keyboard checks](terrain-inspection.md#whole-map-keyboard-playthrough)
verify completion and collection routes without manual screen-by-screen
control.

Interactive terrain playback enables smoothing by default. Use
`--smoothing=false` after `--` for exact committed poses, or
`--smoothing=true` for smooth captures. Rendering frequency does not change the
30 Hz game clock.

Supported playable levels load their authored zones and entity dependencies
across the whole map. Death and checkpoint transitions use selective source
resets; R starts a fresh run. Unsupported levels retain their explicit
inspection fixtures. Animated lighting remains a
[documented renderer limitation](../rendering/gameplay-projection.md). For
real frame-time measurements and the machine-specific 1440p target, use the
[ORG1 performance launcher](terrain-inspection.md).

### Headless and rendered evidence

For isolated headless or rendered evidence:

```text
python tools/run_terrain.py --godot <executable> --scenario buffer --output-directory <external-folder>
```

The launcher explicitly defaults to exact mode. Add `--viewer` for a captured
scene and `--frog-assets` for the real frog model. Use
`--scenario-file <file>` for a typed JSON fixture, `--seed <integer>` and
`--tick-limit <integer>` for overrides, or `--level <name>` to inspect a
player's selected map. The [inspection contract](terrain-inspection.md)
defines scenario fields and omitted level systems.

### Recorded demos

Recorded demo inspection uses the imported high-detail demo table:

```text
python tools/run_demo.py --godot <executable> --level ORG1 --output-directory <external-folder>
```

Add `--viewer` for rendered playback and a capture, `--render-rate
30|60|144|irregular` for a frame schedule, or `--tick-limit <ticks>` for a
bounded run. The default level is ORG1. Evidence includes reference-layout
frog and live-entity CSVs, complete committed state/events in
`committed.jsonl`, and `playback.json` with the initialization, consumed
inputs, committed ticks and termination reason. Exit 3 means incomplete
playback; missing resources and unsupported dependencies remain explicit. The
complete ORG1, SUB1, FOR1 and VOL1 attract demos match the frozen native
terminal states, routes and inputs. See the
[demo verification commands](README.md#diagnostics-demo-playback-and-native-comparison)
for reference comparisons and schedule checks.

### Exploration presets

Bounded regression inspections remain available through `--exploration`:

| Level | Preset | Coverage |
|---|---|---|
| JUN1 | `jun1-log-bank` | Safe bank, moving log and return |
| ORG1 | `org1-turtle-log-bank` | Turtle/log round trip and diving neighbor |
| ORG1 | `org1-road-river` | Vehicle collision and river entry |
| ORG1 | `org1-turtle-log-bank-visibility` | Scripted visibility and pink frog pickup |

These fixtures retain their audited bounds and input dependencies. Normal ORG1
play and demos use whole-map dependency validation. The
[inspection guide](terrain-inspection.md) owns fixture commands, synthetic
lifecycle examples, JUN1 camera-zone probes and capture instructions.
[Entity behavior](../gameplay/entities.md) describes supported callbacks and
explicit exclusions.

## Sandbox

The start screen's **Sandbox** button (or `godot --path . -- --sandbox`;
`--level=SANDBOX` also works) opens a flat 32×32 arena of coloured terrain
zones: plain floor, water, ice, freeform ice, bouncy, deadly, soft,
checkpoint, cliff steps, a sloped cliff and a camera zone. The frog, HUD and
entities use the real models, and the palette offers every entity kind a
supported level places, with that level's forms, scripts and payloads.

In a synthetic scenario without models, the frog is a marker, entities are
orange footprint placeholders, and only `STATIC`, `DYNAMIC`,
`FOR_SWAYING_BRANCH`, `MOVING` and `MOVING_TONGUEABLE` spawn, as one-cell
platforms. The sandbox never ends: when a run completes or the last life is
lost, it restarts with full lives.

The side panel chooses the entity, form, path (static, line, loop, speed) and
speed, loads named presets, teleports to a zone or cell, and shows the zone
colours and keys. Gameplay keys are unchanged (arrows, Shift, Ctrl, Q/E,
Space, Escape), except that C clears entities here instead of croaking.
Sandbox keys:

| Key | Action |
|---|---|
| Tab | Show or hide the panel |
| P / F | Place the selected entity on the frog's cell / the cell ahead |
| Backspace | Delete the last placed entity |
| X or Delete | Delete every entity on the frog's cell |
| C | Clear every entity |
| [ / ] | Previous / next entity kind |
| 1–4 | Path: static, line, loop, speed |
| O | Next preset |
| L / K | Load the preset (replace the layout) / add it to the layout |
| Z / T | Go to the selected zone / cell |
| H | Reset the frog to the spawn |
| R | Restart the sandbox, keeping the placed entities |
| F3 | Debug overlay |

The presets are river, ice slide, platform gauntlet, enemy lane, zone tour,
desert, jungle, swamp and sky hazards, effects, and sounds.

The effects preset starts the frog on (16, 4). The ice zone (columns 11–14,
rows 6–11) gives slide particles and the water zone (columns 3–8, rows 6–9)
the splash and bubbles. Column 16 leads north between the ice zones to the
blue car's exhaust on row 12 (from column 17) and the bison's dust on row 13
(columns 3–11). Row 4 leads east to the rubber balloon (20, 2), the lava
spray's fire (22, 4) and the nuclear barrel's loop from (27, 0), and west to
the bonus fly (13, 3), the gold frog (10, 3) and the checkpoint (8, 2).

The sounds preset starts the frog on (16, 19) beside the vulture, swamp press
and crusher, beaver, tumbleweed, bonus fly, gold frog and checkpoint, for
listening to moving sounds, doppler and loops.

The sandbox's [limitations](../architecture.md#sandbox) are listed with its
design.

## Model viewer

The start screen's **Model viewer** button (or
`godot --path . res://scenes/tools/model_viewer.tscn`) shows the game's models
(MOF files). Models live in WADs, one for each level plus the GENERAL and
options ones: pick a WAD in the upper list and a model in the lower one. A
level's WAD has a slot for every model of its theme, and the slots the level
does not use hold placeholders.

| Key | Action |
|---|---|
| Tab | Move between the lists |
| Up / Down | Choose |
| A / D, W / S | Turn the model (or drag with the mouse) |
| Q / E | Move closer and away (or use the wheel) |
| F | Switch nearest/linear filtering |
| B | Draw both sides of every polygon |
| H | Show the parts FrogLord's settings hide |
| N | Show the next model inside an animated file |
| L | List the low-poly WADs too |
| Esc | Return to the start screen |

The animation panel selects actions by number and configured name. Space plays
or pauses, Period steps one tick, R restarts, and I toggles smooth motion.
Dragging the frame slider pauses at an exact pose. Looping and texture
animation have separate switches. Playback uses the project's 30 Hz clock;
smooth motion defaults off and changes only presentation. Unsafe authored
actions remain listed with an explanation.

For a deterministic capture, add:

```text
-- --model=GEN_FROG.XAR --action=0 --tick=60 --smooth=false --screenshot-dir=<absolute folder outside the repository>
```

The standalone model viewer remains unlit; the map viewer offers a lighted
model probe.

## Map viewer

The start screen's **Map viewer** button (or
`godot --path . res://scenes/tools/map_viewer.tscn`) opens SUB1 in high
detail. Choose a level and detail, drag to orbit, right-drag to pan and use
the wheel to zoom. R resets the camera, F changes filtering, Space plays or
pauses, and Period steps one 30 Hz tick. The tick control seeks
deterministically. The normal camera uses the map offsets; **Map slice
reference** reproduces the frozen reference camera, 128-group limit and
2,500-polygon group budget. Dragging switches to a custom inspection pose; R
restores the preset.

Maps include stored terrain colours, cave illumination, animated textures,
water and sky-land. The entity overlay shows bounded STATIC/MOVING transforms
and can inspect one entity's FORM contact against a fixed point. The separate
terrain inspector supports bounded SAFE-platform interactions and all FORM
death policies, plus whole-map keyboard play with scripts, vehicle cuboids,
tongue collection and level transitions. Use **Play** for the dedicated scene
and original-style HUD. Named entity scripts are checked by their instructions
and dependencies, including path/matrix motion, homing and live
visibility/collision changes; unsupported behavior still reports a boundary.
See [script support](../gameplay/entities.md#supported-script-components). The
explicit hidden-geometry inspection switch includes invisible and unreferenced
polygons; ordinary viewing omits them.

### Path controls

The right-side path controls select a supported PATH record and set a
component inspection start: segment, distance, speed, active state, direction
and endpoint mode. **Show path** draws its sampled shape, runner position and
tangent; it starts off. The default start is segment 0, distance 0, speed 16,
active, forward and repeat. Changing a control resets the shared tick.
Playback, step and seek move the selected cursor with map animation. These
settings inspect a detached path runner; map entity attachment has its own
authored starts. See the [path](../gameplay/paths.md) and
[entity](../gameplay/entities.md) contracts.

### Entity controls

In the **Entities** tab, enable **Show entity axes** to draw attached base
transforms and choose a source-indexed entity for its path and position
readout; the axes start hidden. Set the FORM probe's X/Y/Z world coordinates,
or choose **Place probe in first cell**. The viewer draws the selected FORM
outline and contacted cell and reports contact status, cell and raw flags. An
unsupported form shows its reason. This query does not move or kill the frog.
The panel counts omitted records; hover over the count for source diagnostics.

### Path and entity traces

For reproducible path traces and an optional rendered capture:

```text
python tools/run_paths.py --godot <executable> --scenario line --output-directory <external-folder>
```

Add `--viewer` for the map overlay, `--scenario arc` or `--scenario spline`
for other built-in paths, or `--scenario-file <JSON-file>` for a custom case.
With an imported map, use `--level SUB1 --path-index 0`; `--tick-limit` and
`--render-rate 30|60|144` select the duration and rendered frame schedule. The
wrapper writes a JSONL trace. With `--viewer` it also writes a world-only path image and a full
window image of the inspection controls, framing the selected path for that
capture. To compare the complete headless trace against rendered runs at 30,
60 and 144 frames per second:

```text
python tools/verify_path_schedules.py --godot <executable> --scenario line --output-directory <external-folder>
```

See the [path verification specification](../../../tests/golden/specs/paths.md).

For source-ordered entity transforms:

```text
python tools/run_entities.py --godot <executable> --scenario shared-path --output-directory <external-folder>
```

Use `--viewer` to capture world and full-window images, or `--level ORG1` to
inspect an imported map. `--tick-limit` and `--render-rate 30|60|144` control
the trace duration and render schedule. To compare schedules, including the
fixed contact probe:

```text
python tools/verify_entity_schedules.py --godot <executable> --scenario shared-path --output-directory <external-folder>
```

### Map captures

For repeatable captures on Windows, set `GODOT`, then:

```powershell
tools/capture_map.ps1 -OutputDirectory C:\captures\frogger -Level SUB1 -Tick 0 -Linear -Benchmark
```

`python3 tools/capture_map.py` is the cross-platform equivalent. Captures use
a fixed 640×480 viewport and write PNG plus metadata.
Use `-Linear` for linear filtering; omit it for nearest. Add `-LowDetail` to
inspect the matching low-detail map and textures. High- and low-detail maps
are separate resources: select the detail variant you want. For fixed-pose
comparisons, the capture wrapper accepts `-CameraSource 'x,y,z'` and
`-CameraTarget 'x,y,z'` (game units).

The viewer also accepts:

```text
-- --level=SUB1 --low-poly=false --tick=0 --linear=false --screenshot-dir=<absolute external folder>
```

An optional `--probe-model=GEN_CHECKPOINT_1.XMR` shows a static model under
the map's scene lights.

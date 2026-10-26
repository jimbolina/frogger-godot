# Frogger (1997) in Godot

A rewrite of **Frogger** (Hasbro Interactive / Millennium Interactive, 1997;
the PC release, also known as *Frogger: He's Back*) in
[Godot 4](https://godotengine.org) with statically typed GDScript. The aim is
the original game's feel on modern desktops (Windows, Linux, macOS), running
on the data from the player's own copy of the PC game, and staying compatible
with levels and changes made in [FrogLord](https://github.com/Kneesnap/FrogLord),
the community's Frogger editor.

This is an early stage: the project can find and identify the game files,
read every file in their archives (the MWI index, the MWD archive, WAD
bundles and PowerPacker compression) and decode the game tables held in the
executable (levels, themes, forms, texture remaps and pointers, entity
scripts, music, level select, demos, bugs), decode every texture, and read
and animate models, flipbooks and polygon textures. The map inspection viewer
renders terrain, water, sky and map animations, including FrogLord-saved edits.
There is no playable level yet.

Terrain movement, collision/deaths, gameplay camera and animation control
follow the frozen C port's 30 Hz target; see the
[terrain contract](docs/reference/gameplay/terrain-movement.md).

The terrain inspection driver uses the same rules as the tests:
`godot --path . res://scenes/tools/terrain_viewer.tscn`.
Space plays/pauses, Period steps, R resets and I changes interpolation.
A direct retail-map launch selects live arrow-key input:
`godot --path . res://scenes/tools/terrain_viewer.tscn -- --data-dir=<game-folder> --level=ORG1`.
Press Space to start hopping. The overlay shows LIVE/REPLAY and running/paused;
Tab switches input mode, Shift requests a super hop and Q/E turn the gameplay
camera. Reset pauses and retains the selected input mode. Explicit scenario
fixtures and automated captures still replay their bounded command sequence.
Pause and reset also reset drawing interpolation.
Interactive terrain playback enables smoothing by default. Use `--smoothing=false`
after `--` for exact committed poses, or `--smoothing=true` for smooth captures.
The `run_terrain.py` reference launcher explicitly defaults to exact mode.
Rendering frequency does not change the 30 Hz game clock.
Optional POP and SAFE-platform interactions are available below;
level progression remains deferred. Animated lighting remains a
[documented renderer limitation](docs/reference/rendering/gameplay-projection.md).
For real frame-time measurements and the machine-specific 1440p target, use the
[ORG1 performance launcher](docs/reference/testing/terrain-inspection.md).
The game runs in GDScript. C files under `tools/` are offline reference
validation adapters; playing or loading data does not require C code or a compiler.
For isolated headless or rendered evidence, use `python tools/run_terrain.py
--godot <executable> --scenario buffer --output-directory <external-folder>`;
add `--viewer` for a captured scene and `--data-dir <game-folder>` for frog assets.
Use `--scenario-file <file>` for a typed JSON fixture, `--seed <integer>` and
`--tick-limit <integer>` for overrides, or `--level <name>` to inspect a player's
selected map. The [inspection contract](docs/reference/testing/terrain-inspection.md)
defines scenario fields and omitted level systems.

Recorded demo inspection uses the player's high-detail demo table and archive:

```text
python tools/run_demo.py --godot <executable> --data-dir <game-folder> --level ORG1 --output-directory <external-folder>
```

Add `--viewer` for rendered playback and a capture, `--render-rate
30|60|144|irregular` for a frame schedule, or `--tick-limit <ticks>` for a bounded
run. The default level is ORG1. Evidence includes reference-layout frog and
live-entity CSVs plus `playback.json` with the initialization, consumed inputs,
committed ticks and termination reason. Exit 3 means incomplete playback;
missing resources, unsupported actions and existing admission limits remain
visible. Full retail level playback is unfinished. See the
[demo verification commands](docs/reference/testing/README.md#demo-playback-and-comparison)
for reference comparisons and schedule checks.

For the bounded entity demonstration, run `python tools/run_terrain.py --godot
<executable> --data-dir <game-folder> --level DES2 --entity-reactions pop
--viewer --output-directory <external-folder>`. This starts at an explicit safe
inspection cell and hops into a cactus. All eligible nearby obstacles are checked;
the overlay shows FORM contact and death requests. Entity paths and the frog
advance atomically.

For landing, centring and riding a moving log, use the same command with
`--level JUN1 --entity-reactions platforms`. This explicitly starts on water
cell `(18,5)` and hops NORTH; it is an inspection start, not a verified route
from safe terrain. Platform mode also supports local hops, departure and camera
attachment. This inspection omits scripts, active zones and form callback dispatch; see the
[entity contract](docs/reference/gameplay/entities.md).

For guarded exploration from a safe bank, launch:

```text
godot --path . res://scenes/tools/terrain_viewer.tscn -- --data-dir=<game-folder> --level=JUN1 --exploration=jun1-log-bank
```

This opens LIVE and paused at bank cell `(22,10)`, facing west. It has no
automatic commands or live tick limit. From reset, the verified route presses
Left at tick 0 and Right at tick 12, after centring on log 24; the frog reaches
bank `(22,9)` at tick 17. Period steps one tick, including while an arrow is
held. R resets the whole inspection and drawing clocks, then pauses while
retaining the selected LIVE/REPLAY mode.
The overlay shows the world boundary and the all-attached lifetime assumption.
Leaving the boundary or entering an unsupported camera zone rejects the entire
tick and pauses with a reason. It does not create a wall or clamp the frog.
This preset admits only the audited high-detail `pc-retail-v3.0e` map, behavior,
script and model inputs; it rejects changed proof dependencies and visibility
mode. Ordinary inspection remains available for edited data. See the
[bounded route contract](tests/golden/specs/entities.md#guarded-jun1-route-and-zones).

The guarded ORG1 inspection connects safe bank, turtle, small log, turtle and
bank, including the diving turtle's behavior:

```text
godot --path . res://scenes/tools/terrain_viewer.tscn -- --data-dir=<game-folder> --level=ORG1 --exploration=org1-turtle-log-bank
```

It opens LIVE and paused. Press Space to run or Period to step; Up hops toward
the turtles/logs and Down returns toward the bank. Time hops after centring.
The exact replay uses `tests/golden/fixtures/org1_turtle_log_bank.json`.
Ordinary playback omits diagnostic phase copies; trace capture enables them
and is more expensive. The [frame-pacing probe](docs/reference/testing/terrain-inspection.md)
measures actual host FPS separately from deterministic replay schedules.
R restores the whole inspection while retaining LIVE/REPLAY mode. Boundary or
unsupported-pose rejection pauses and rolls back the tick. The preset requires
audited high-detail v3.0e inputs and all-attached lifetime; visibility mode is
rejected. Scripts, diving animation/colour and logical neighbor effects run;
sound and splash sprites remain ordered requests. See the
[ORG1 contract](tests/golden/specs/entities.md#org1-route-proof) and
[verification instructions](docs/reference/testing/terrain-inspection.md#guarded-org1-turtlelog-exploration).

For the guarded road crossing into that corridor, use
`--exploration=org1-road-river` instead. It starts south of traffic and adds
vehicle cuboid collision and squish deaths. Wait for gaps before hopping north;
R resets after a death. The exact successful replay is
`tests/golden/fixtures/org1_road_river.json`; the deliberate lorry collision is
`tests/golden/fixtures/org1_road_vehicle_death.json`. The same supplied-data and
boundary restrictions apply. See the
[road contract](docs/reference/gameplay/entities.md#vehicle-primitive-contacts).

To explore the bank/turtle/log corridor with scripted visibility, use:

```sh
godot --path . res://scenes/tools/terrain_viewer.tscn -- --data-dir=<game-folder> --level=ORG1 --exploration=org1-turtle-log-bank-visibility
```

This separate v3.0e preset creates and retires entities with camera visibility.
It opens LIVE and paused with the same movement controls. Touch the pink frog
to pick her up; she rides on Frogger and disappears if he dies. R restores the
complete inspection. Checkpoint delivery and tongue pickup are not implemented;
the corridor bounds still apply. See the [scripted visibility contract](docs/reference/gameplay/entities.md#pink-frog-behavior).

For the synthetic visibility lifecycle demonstration, use
`python tools/run_terrain.py --godot <executable> --scenario-file
tests/golden/fixtures/lifecycle_integrated.json --entity-lifecycle visibility
--viewer --output-directory <external-folder>`. The frog walks out and back;
the camera controls entity creation, retirement and recreation. Existing modes
default to all-attached lifetime. Use `lifecycle_zones.json` in the same fixture
folder to include active camera zones. Visibility supports script-free generic
entities within its polygon-budget limit; ordinary retail terrain setup still
requires zero-zone maps. These demonstrations do not
make a level playable. See [inspection](docs/reference/testing/terrain-inspection.md#visibility-lifecycle-inspection).

Active camera zones have a separate JUN1 inspection. It moves a visible probe
through prescribed cells and shows zone selection, offset transitions and a
forced half-turn; it does not establish a playable route. Run
`python tools/run_terrain.py --godot <executable> --data-dir <game-folder>
--camera-inspection jun1-camera-zones --viewer --output-directory <external-folder>`
for deterministic playback and captures. Open `scenes/tools/camera_zone_viewer.tscn`
with `--data-dir=<game-folder>` for paused interactive inspection: Space plays or
pauses, Period advances one tick, and R resets both sequences. See
[zone inspection](docs/reference/testing/terrain-inspection.md#active-camera-zone-inspection).
Add `--entity-lifecycle visibility` to the JUN1 camera command to show its
eleven audited logs appearing, retiring and returning as the zone camera changes.
Other entities are omitted and the probe does not execute frog contact.

## macOS setup

Install the standard **Godot 4.5.1 macOS Universal** build from the
[official archive](https://godotengine.org/download/archive/4.5.1-stable/)
as `/Applications/Godot.app`. It runs natively on Apple Silicon and Intel.
The project uses GDScript; .NET, Java, a C compiler and export templates are
not required to run it or its Godot tests. GUT is already included.
Python 3 is needed for the Mac test runner and inspection launchers.

Double-click `tools/launch_macos.command` in Finder to open the project in the editor.
Let the initial import finish, then press F5 (Fn-F5 when the keyboard uses media
keys) to run the start screen.
It uses `FROGGER_DATA_DIR` when set, otherwise the existing retail folder at
`../froggy/resources/pc-version/extracted/FROGGER` when present.
The same launcher works from Terminal. After the initial editor import,
launch guarded exploration directly with:

```sh
tools/launch_macos.command res://scenes/tools/terrain_viewer.tscn -- --level=ORG1 --exploration=org1-road-river
```

For other commands in this README, use the executable inside the app:

```sh
export GODOT=/Applications/Godot.app/Contents/MacOS/Godot
export FROGGER_DATA_DIR="$(cd ../froggy/resources/pc-version/extracted/FROGGER && pwd)"
"$GODOT" --path .
bash tools/run_tests.sh
env -u FROGGER_DATA_DIR bash tools/run_tests.sh
```

The last command expects exit 3 for the approved retail-only skips. See the
[testing guide](docs/reference/testing/README.md) for isolated Mac profiles.
Use `python3` for Python commands on macOS. The frozen sibling C engine's
Windows binaries and PowerShell oracle builders are separate reference tooling;
they are not part of this Mac runtime setup. Packaged exports remain future work.

## No game data is included

This repository contains **no part of the original game**: no executable, no
archives, no textures, models, sounds, music or video. You need your own copy
of the retail PC game. The project reads everything it needs at run time from
your files; nothing from them is ever copied into this repository, and tests
that need them only store facts about them (file sizes, counts, checksums).

Supported data: the PC retail builds FrogLord knows as `pc-retail-v3.0e`
(the common worldwide release, the reference for this project),
`pc-retail-v1.0` and `pc-retail-v3.0e-vogons`. PlayStation data is not supported.

## Pointing the game at your files

The game needs the folder holding `FROGGER.EXE` and `FROGPSX.MWD` from the
installed game (or FrogLord's saved `modded_FROGGER.EXE` and
`modded_FROGPSX.MWD`; when both kinds are in one folder the modded files are
used). It looks, in this order, at:

1. the command line: `godot --path . -- --data-dir=<folder>`
2. the environment variable `FROGGER_DATA_DIR=<folder>`
3. the folder remembered from the last successful start.

The build is recognised the way FrogLord recognises it: by the build
information FrogLord writes into a modded executable, or else by the CRC-32
checksum of the executable, which FrogLord's version files list.

Running the project currently opens a screen saying which files and which
build were found (with a summary of the archive index and counts of the
tables read from the executable), or how to set the folder.

### Texture viewer

The start screen's **Texture viewer** button (or
`godot --path . res://scenes/tools/texture_viewer.tscn`) shows every texture
bank (VLO file) of the game: pick one on the left to see its images with
their position, texture id, name, size and flags. Keys: Up/Down choose a
bank, F switches nearest/linear filtering, C switches the checkerboard
behind transparent pixels, Page Up/Page Down scroll, Esc returns to the
start screen.

### Model viewer

The start screen's **Model viewer** button (or
`godot --path . res://scenes/tools/model_viewer.tscn`) shows the game's
models (MOF files). Models live in WADs, one for each level plus the GENERAL
and options ones: pick a WAD in the upper list and a model in the lower one.
A level's WAD has a slot for every model of its theme, and the slots the
level does not use hold placeholders.

Keys: Tab moves between the lists and Up/Down choose; A/D and W/S turn the
model and Q/E move closer and away (or drag with the mouse and use the
wheel); F switches nearest/linear filtering, B draws both sides of every
polygon, H shows the parts FrogLord's settings hide, N shows the next model
inside an animated file, L lists the low-poly WADs too, Esc returns to the
start screen.

The animation panel selects actions by number and configured name. Space
plays or pauses, Period steps one tick, R restarts, and I toggles smooth
motion. Dragging the frame slider pauses at an exact pose. Looping and
texture animation have separate switches. Playback uses the project's
30 Hz clock; smooth motion defaults off and changes only presentation.
Unsafe authored actions remain listed with an explanation.

For a deterministic capture, add `-- --model=GEN_FROG.XAR --action=0
--tick=60 --smooth=false --screenshot-dir=<absolute folder outside the repository>`.
The standalone model viewer remains unlit; the map viewer offers a lighted model probe.

### Map viewer

The start screen's **Map viewer** button (or
`godot --path . res://scenes/tools/map_viewer.tscn`) opens SUB1 in high detail.
Choose a level and detail, drag to orbit, right-drag to pan and use the wheel
to zoom. R resets the camera, F changes filtering, Space plays or pauses,
and Period steps one 30 Hz tick. The tick control seeks deterministically.
The normal camera uses the map offsets; **Map slice reference** reproduces
the frozen reference camera, 128-group limit and 2,500-polygon group budget.
Dragging switches to a custom inspection pose; R restores the preset.

Maps include stored terrain colours, cave illumination, animated textures,
water and sky-land. The entity overlay shows bounded STATIC/MOVING transforms
and can inspect one entity's FORM contact against a fixed point. The separate
terrain inspector supports bounded POP, SAFE-platform and SQUISHED interactions,
plus the admitted ORG1 scripts and vehicle cuboids; HUD and
complete level play remain deferred.
The explicit hidden-geometry inspection
switch includes invisible and unreferenced polygons; ordinary viewing omits them.

The right-side path controls select a supported PATH record and set a component
inspection start: segment, distance, speed, active state, direction and endpoint
mode. **Show path** draws its sampled shape, runner position and tangent;
it starts off. The default start is segment 0, distance 0, speed 16, active,
forward and repeat. Changing a control resets the shared tick. Playback,
step and seek move the selected cursor with map animation. The map-slice
reference preset hides the path drawing. These settings inspect a detached
path runner; map entity attachment has its own authored starts. See the
[path](docs/reference/gameplay/paths.md) and
[entity](docs/reference/gameplay/entities.md) contracts.

In the **Entities** tab, enable **Show entity axes** to draw attached base
transforms and choose a source-indexed entity for its path and position
readout. Set the FORM probe's X/Y/Z world coordinates, or choose **Place probe
in first cell**. The viewer draws the selected FORM outline and contacted cell
and reports contact status, cell and raw flags. An unsupported form shows its
reason. This query does not move or kill the frog. The panel counts omitted
records; hover over the count for source diagnostics. The axes start hidden
and the map-slice reference preset hides them.

For reproducible path traces and an optional rendered capture, run
`python tools/run_paths.py --godot <executable> --scenario line --output-directory <external-folder>`.
Add `--viewer` for the map overlay, `--scenario arc` or `--scenario spline`
for other built-in paths, or `--scenario-file <JSON-file>` for a custom case.
With player data, use `--data-dir <game-folder> --level SUB1 --path-index 0`;
`--tick-limit` and `--render-rate 30|60|144` select the duration and rendered
frame schedule. The wrapper writes a JSONL trace and keeps captures and logs
outside the repository. With `--viewer` it also writes a world-only path image
and a full window image of the inspection controls, framing the selected path
for that capture. To compare the complete
headless trace against rendered runs at 30, 60 and 144 frames per second, use
`python tools/verify_path_schedules.py --godot <executable> --scenario line
--output-directory <external-folder>`. See the
[path verification specification](tests/golden/specs/paths.md).

For source-ordered entity transforms, run `python tools/run_entities.py --godot
<executable> --scenario shared-path --output-directory <external-folder>`.
Use `--viewer` to capture world and full-window images, or `--data-dir
<game-folder> --level ORG1` to inspect player data. `--tick-limit` and
`--render-rate 30|60|144` control the trace duration and render schedule.
`python tools/verify_entity_schedules.py --godot <executable> --scenario
shared-path --output-directory <external-folder>` compares schedules, including
the fixed contact probe. Traces,
logs and captures stay outside the repository.

For repeatable captures on Windows, set `GODOT` and `FROGGER_DATA_DIR`, then:

```powershell
tools/capture_map.ps1 -OutputDirectory C:\captures\frogger -Level SUB1 -Camera map-slice -Tick 0 -Linear -Benchmark
```

Captures use a fixed 640×480 viewport and write PNG plus metadata outside the
repository. Use `-Linear` for frozen-C comparisons; omit it for nearest filtering.
Add `-LowDetail` to inspect the matching low-detail map and textures. The viewer also accepts
`-- --level=SUB1 --low-poly=false --camera=map-slice --tick=0 --linear=false
--screenshot-dir=<absolute external folder>`. An optional `--probe-model=GEN_CHECKPOINT_1.XMR`
shows a static model with map ambient/parallel lighting. Saved FrogLord files
use the EXE's embedded index; a supplied standalone MWI is compared and any
mismatch is reported.
High- and low-detail maps are separate resources: select the detail variant
you edited in FrogLord. For fixed-pose comparisons, the capture wrapper accepts
`-CameraSource 'x,y,z'`, `-CameraTarget 'x,y,z'` (game units) and `-Projection 500`.

## Running the tests

Contributors: start with the [domain language](docs/reference/domain.md) and
[architecture and ownership](docs/reference/architecture.md). These describe
source identities, viewer lifetimes, and ownership of gameplay state.

Tests use [GUT](https://github.com/bitwes/Gut) and run headless:

```
GODOT=/path/to/godot tools/run_tests.sh              # bash (Linux, macOS, Git Bash on Windows)
$env:GODOT="C:\path\to\Godot.exe"; tools\run_tests.ps1   # PowerShell
```

Set `FROGGER_DATA_DIR` to also run the tests that need the retail files
(`tests/golden/`); without it those are listed as `SKIPPED` by name. The
report includes a summary such as `SUMMARY: PASS=70 FAIL=0 SKIP=3 EXIT=3`,
followed by the wrapper's result-validation status.

| Exit code | Meaning |
|---|---|
| 0 | every test ran and passed |
| 1 | a test failed, or a script does not compile |
| 2 | runner setup failed (for example, Godot was not found) |
| 3 | only approved asset-free retail skips (a skip is never a pass) |

Every script is compiled before the tests run (`tools/check_scripts.gd`),
with the project's strict typing warnings treated as errors. The wrappers also
check architecture dependencies and validate the complete test report. Only
reviewed retail tests may skip when `FROGGER_DATA_DIR` is unset; a supplied but
invalid retail folder, an unexpected skip or an empty selection fails.
The wrappers isolate writable user data, save explicit logs in a temporary
folder, disable the crash handler and stop at the first failed stage.
For a focused iteration, append `-gselect=test_model_viewer` to either wrapper.
The complete retail and asset-free runs remain required before each commit.

## Layout

| Path | What |
|---|---|
| `src/source/` | Readers for the original data formats and executable: `io/` (byte reading, PowerPacker), `config/` (FrogLord configs and name lists), `source/` (finding the game files), `formats/` (MWI, MWD, WAD, texture banks, models), `exe/` (the game tables in the executable). `game_data.gd` puts them behind one object. Pure data classes with no scene tree, testable headless. |
| `src/convert/` | Turning decoded game data into Godot resources: textures, model meshes, the shaders that draw them, and the conversion between the game's space and Godot's. |
| `src/game/` | Detached terrain, path and entity definitions and run state, grid queries, movement/collision, gameplay camera, animation control and source RNG. Rules have no scene tree or file access. |
| `src/application/` | Source-to-game adapters and resolved behavior catalog. |
| `src/inspection/` | Developer scenarios, validated options, guards and manifests. |
| `src/presentation/` | Screens (`frontend/`), shared viewer helpers, and development tools (`tools/`, the texture, model, map and terrain viewers). |
| `scenes/` | Godot scenes (`boot.tscn` is the start scene; `tools/` holds the viewers). |
| `tests/unit/` | Tests that need no game files. |
| `tests/golden/` | Tests against the retail files, and the committed facts they compare with. |
| `tools/` | Test runners, a script compile check, the golden-data generators `make_golden_*.py` (see `tests/golden/README.md`), and `probe_model_shader.gd`, which measures the colours the model shaders put on screen. |
| `third_party/` | FrogLord's configuration files, unmodified (see `third_party/README.md`). |
| `addons/gut/` | The GUT test framework, unmodified. |

## Contributing and project documentation

Start with [AGENTS.md](AGENTS.md) and the short [current checkpoint](docs/CURRENT.md).
The [roadmap](docs/PORTING.md) owns status and remaining work. The
[domain index](docs/reference/domain.md) groups references by data, gameplay
and rendering; the [testing guide](docs/reference/testing/README.md) covers checks and
inspection tools. Documentation describes current behavior and use. Run logs
stay outside the repository, and Git retains development history.

## Licence

The licence for this project's own code is **to be decided by the project
owner**; until then, no licence is granted. Third-party material keeps its own
licence: FrogLord's configuration files (MIT, `third_party/froglord_cfg/LICENSE.md`)
and GUT (MIT, `addons/gut/LICENSE.md`).

## Credits

- **FrogLord** by Kneesnap and the [Highway Frogs](https://highwayfrogs.net)
  community: the file-format research this project builds on, and the
  configuration files it ships.
- The Highway Frogs community's documentation of Frogger's formats and the
  released original PlayStation source code.
- **GUT** by Butch Wesley, for testing.

Frogger is a trademark of Konami. This is an unofficial fan project and is not
affiliated with or endorsed by the rights holders.

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
The dedicated game scene supports ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3 and CAV1/CAV3/CAV4, with the original-style
single-player HUD, tongue collection, pickup and firefly sprites, the cave light and the complete level loop.

Terrain movement, collision/deaths, gameplay camera and animation control
follow the frozen C port's 30 Hz target; see the
[terrain contract](docs/reference/gameplay/terrain-movement.md).

Choose a level on the start screen and press **Play**. Each level starts a fresh
session. Arrow keys hop; press Shift alone to super-hop in the current facing
direction (or skip the current checkpoint bonus stage). Ctrl uses the tongue,
and Q/E turn the camera. Space pauses/resumes,
R restarts, and Escape returns to the start screen. Completion and game over
offer **Replay** and **Return**. The game starts automatically after loading.

To launch a level directly:

```text
godot --path . res://scenes/game/gameplay.tscn -- --data-dir=<game-folder> --level=SUB1
```

The default is high-detail ORG1. Add `--record-inputs` to record your play: when
the level completes, the held keys of every tick are written as a replay fixture
to `user://playthroughs/<level>_keyboard_playthrough.json` (the completion message
shows the absolute path; `--record-inputs=<file>` chooses another). The capture
launcher replays such files through real key events with per-tick parity checks,
which is how level completion evidence is produced. The HUD uses the player's English retail UI
assets. Full menus, progression between levels, saves, audio playback and
decorative particles remain future work. Forest bee swarms are visible gameplay hazards.

The terrain inspection driver uses the same rules as the tests:
`godot --path . res://scenes/tools/terrain_viewer.tscn`.
Space plays/pauses, Period steps, R resets and I changes interpolation.
A direct retail-map launch selects live arrow-key input:
`godot --path . res://scenes/tools/terrain_viewer.tscn -- --data-dir=<game-folder> --level=ORG1`.
Press Space to start hopping. The overlay shows LIVE/REPLAY and running/paused;
Tab switches input mode, Shift requests a super hop (or skips the current
checkpoint bonus phase), Ctrl uses the tongue, and
Q/E turn the gameplay camera. The overlay shows score, time, lives, checkpoint
progress and completion/game-over state. FPS, average frame time and the last
simulation tick time refresh twice per second. Reset pauses and retains the selected input mode. Explicit scenario
fixtures and automated captures still replay their bounded command sequence.
Pause and reset also reset drawing interpolation.
[Repeatable keyboard checks](docs/reference/testing/terrain-inspection.md#whole-map-keyboard-playthrough)
verify completion and collection routes without manual screen-by-screen control.
Interactive terrain playback enables smoothing by default. Use `--smoothing=false`
after `--` for exact committed poses, or `--smoothing=true` for smooth captures.
The `run_terrain.py` reference launcher explicitly defaults to exact mode.
Rendering frequency does not change the 30 Hz game clock.
Supported playable levels load their authored zones and entity dependencies across the whole map.
Death and checkpoint transitions use selective source resets; R starts a fresh run.
Unsupported levels retain their explicit inspection fixtures. Animated lighting remains a
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
live-entity CSVs, complete committed state/events in `committed.jsonl`, and
`playback.json` with the initialization, consumed inputs,
committed ticks and termination reason. Exit 3 means incomplete playback;
missing resources and unsupported dependencies remain explicit. The complete
ORG1, SUB1, FOR1 and VOL1 attract demos match the frozen native terminal states, routes and inputs. See the
[demo verification commands](docs/reference/testing/README.md#demo-playback-and-comparison)
for reference comparisons and schedule checks.

Bounded regression inspections remain available through `--exploration`:

| Level | Preset | Coverage |
|---|---|---|
| JUN1 | `jun1-log-bank` | Safe bank, moving log and return |
| ORG1 | `org1-turtle-log-bank` | Turtle/log round trip and diving neighbor |
| ORG1 | `org1-road-river` | Vehicle collision and river entry |
| ORG1 | `org1-turtle-log-bank-visibility` | Scripted visibility and pink frog pickup |

These fixtures retain their audited bounds and input dependencies. Normal ORG1
play and demos use whole-map dependency validation. The
[inspection guide](docs/reference/testing/terrain-inspection.md) owns fixture
commands, synthetic lifecycle examples, JUN1 camera-zone probes and capture
instructions. [Entity behavior](docs/reference/gameplay/entities.md) describes
supported callbacks and explicit exclusions.

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
launch whole-map ORG1 directly with:

```sh
tools/launch_macos.command res://scenes/tools/terrain_viewer.tscn -- --level=ORG1
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
Use `python3` for Python commands on macOS.

For reference comparisons on this Mac, reuse the verified native arm64 build
outside the frozen source tree. The [reference source instructions](docs/reference/sources.md#exporting-reference-material-from-the-engine)
provide its location, export commands, provenance and comparison limits.
The PowerShell oracle builders remain Windows-only. Packaged exports remain
future work.

## No game data is included

This repository contains **no part of the original game**: no executable, no
archives, no textures, models, sounds, music or video. You need your own copy
of the retail PC game. The project reads everything it needs at run time from
your files; nothing from them is ever copied into this repository, and tests
that need them only store facts about them (file sizes, counts, checksums).

The compatibility target is `pc-retail-v3.0e`, the common worldwide PC release,
including FrogLord-saved edits based on that build. Other PC builds are outside
the current compatibility scope. PlayStation data is not supported.

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

Running the project opens the level picker and inspection tools, with a report
of the files/build found or instructions for setting the data folder.

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
terrain inspector supports bounded SAFE-platform interactions and all FORM death policies,
plus whole-map keyboard play with scripts, vehicle cuboids, tongue collection
and level transitions. Use **Play** for the dedicated scene and original-style HUD. Named entity scripts are checked by their
instructions and dependencies, including path/matrix motion, homing and live
visibility/collision changes;
unsupported behavior still reports a boundary. See [script support](docs/reference/gameplay/entities.md#supported-script-components).
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

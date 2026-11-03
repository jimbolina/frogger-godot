# Frogger (1997) in Godot

A rewrite of **Frogger** (Hasbro Interactive / Millennium Interactive, 1997;
the PC release, also known as *Frogger: He's Back*) in
[Godot 4](https://godotengine.org) with statically typed GDScript. The aim is
the original game's feel on modern desktops (Windows, Linux, macOS), playing
from the player's own copy of the retail PC game, which it imports on the
first run. The repository holds none of the original game's content. The
formats were decoded following [FrogLord](https://github.com/Kneesnap/FrogLord),
the community's Frogger editor, and the port plays FrogLord's saves.

The importer under `archive/` reads every file in the retail archives (the
MWI index, the MWD archive, WAD bundles and PowerPacker compression), decodes
the game tables held in the executable (levels, themes, forms, texture remaps
and pointers, entity scripts, music, level select, demos, bugs), every
texture, every model with its flipbooks and polygon textures, the sound banks
and the CD music, and writes them as Godot resources: into the game's user
folder for a player, or into a developer's local `assets/`. The map
inspection viewer renders terrain, water, sky and map animations.
The dedicated game scene supports ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and SKY1–SKY4, with the original-style
single-player HUD, tongue collection, pickup and firefly sprites, the cave light, Desert rock explosions, Swamp crushers and presses, Sky balloons and the complete level loop.

Terrain movement, collision/deaths, gameplay camera and animation control
follow the frozen C port's 30 Hz target; see the
[terrain contract](docs/reference/gameplay/terrain-movement.md).

The game opens on the main menu, the scrolling high-score table with **Start**,
**Options** and **Exit** below it (the top-right **Inspection tools** button opens the
older start screen): choose **Start**, then a level on the 3D stack
(Up/Down move, Enter or Space shows the level and then starts it, Escape backs
out of the picture or, before the first level, to the menu);
only unlocked levels can be picked, and score, lives and unlocks carry from level
to level and are saved to `user://progress.cfg`. When a game ends with a score
that beats the main table or a level's table, the name-entry page opens: hop the
frog over the letter lilies with the arrow keys, Enter picks a letter (BACK rubs
one out, END finishes), then the tour shows the new rows and the scrolling table
(Escape skips it); scores are saved to `user://high_scores.cfg`. Escape during a
level pauses it; Quit on the pause page returns to the menu without name entry. The older start screen lets a level be played fresh without the menu. In a level the retail keys apply: arrow keys hop; Return super-hops in the current facing
direction (or skips the current checkpoint bonus stage). Right Ctrl uses the tongue,
right Shift croaks (the throat swells, in Cave levels the light swells, and the nearest
baby frog or gold frog within sixteen squares answers), and `'` and `;` turn the
camera. **Options** on the main menu sets the music and effects volume and, under
control configuration, rebinds these keys (F1 redefine, F3 key list, Esc back), and
**View high scores** shows the level stack (Enter spins a level out to its three
rows, Left shows the main table, Escape backs out); the main menu scrolls the main
table behind its buttons. Menu images follow your system language, or pass `--language=en|it|de|fr|es`.
Left alone for 27 seconds, the main menu plays the attract demos in the game scene and
returns between them; Start and Options still work over a demo. Pass `--attract` to
start the first demo as soon as the menu has flown on. The inspection
tools and sandbox keep their own keys. Escape pauses: PAUSED shows over the level
with Continue and Quit (arrows move, Enter picks, Escape resumes); R restarts a
direct launch, and Quit leads to the game-over page. From the menu, completion offers **Next level** or **Level select**;
losing the last life shrinks the level away under GAME OVER (Enter skips it after a moment) and
goes on to name entry or the menu; a direct launch offers **Replay** and **Return** afterwards. The game starts automatically after loading.

The 0 key (top row) opens the debug graphics panel on the right: display, quality, shadows, bloom,
effects and look settings apply at once and are saved to `user://graphics.cfg`.
The panel is mouse-driven, so game keys keep working while it is open.

To launch a level directly:

```text
godot --path . res://scenes/game/gameplay.tscn -- --level=SUB1
```

`--level=` also opens a level that has a map but is not yet accepted, such as
JUN2, with a warning; the front end lists only accepted levels.

A direct launch reads the project's class-name cache in `.godot/`, which goes
stale when new scripts arrive and then fails with a script parse error. Prefer
`tools/play.sh --level=SUB1` (or `tools/play.ps1`), which refreshes the cache
before launching; `--scene=` selects another scene. No data folder is needed
once `assets/` holds an import ([developer setup](#developer-setup)).
`tools/run_tests.sh` also refreshes the
checkout cache after strict compilation, and on Windows the wrapper's import
stage already targets the checkout.
The default is high-detail ORG1. Add `--record-inputs` to record your play: when
the level completes, the held keys of every tick are written as a replay fixture
to `user://playthroughs/<level>_keyboard_playthrough.json` (the completion message
shows the absolute path; `--record-inputs=<file>` chooses another). The capture
launcher replays such files through real key events with per-tick parity checks;
recording is optional diagnostic material, not a requirement. The HUD uses the player's English retail UI
assets. The frog's shadow, hop trail, slide, bubble and fire particles, death
ring, splash, drowning tints and score popups are drawn from the player's
data; entity particles, pops and glows follow. Forest bee swarms are visible gameplay hazards.

### Setup and first run

The game starts on its setup screen when it has nothing to play from. On the
first run, choose the folder of your own Frogger PC game (version
`pc-retail-v3.0e`, with `FROGGER.EXE` and `FROGPSX.MWD`) and, for the music,
its Alcohol 120% disc image (the `.mds` file with its `.mdf` beside it). The
game imports them into its user folder (about twenty seconds, with a progress
bar and Cancel), then lets you choose the language, window, volumes and
[texture pack](#texture-packs) and, optionally, a FrogLord save folder; Play saves the choices
and opens the main menu. Later starts go straight to the menu. Hold Shift while
the game starts, or start it with `-- --setup`, to open the setup again, for
example `godot --path . -- --setup`; the last page can also make it open every
time. On Windows and Linux the last page puts a shortcut on the desktop; on
macOS drag the exported app to Applications or the Dock. A source checkout
whose `assets/` holds an import plays it and skips the setup unless asked;
without one it opens the setup and imports into the user folder like an
exported game. See
[first-run setup](docs/reference/setup.md).

### Audio

Sound effects play from the imported banks and music from the imported CD
tracks (`audio/music/track_NN` of the import, NN being the disc track
number); without a disc image there is no music. A missing track stays silent
with a diagnostic. `--no-audio` turns all sound off.

The terrain inspection driver uses the same rules as the tests:
`godot --path . res://scenes/tools/terrain_viewer.tscn`.
Space plays/pauses, Period steps, R resets and I changes interpolation.
A direct retail-map launch selects live arrow-key input:
`godot --path . res://scenes/tools/terrain_viewer.tscn -- --level=ORG1`.
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
add `--viewer` for a captured scene and `--frog-assets` for the real frog model.
Use `--scenario-file <file>` for a typed JSON fixture, `--seed <integer>` and
`--tick-limit <integer>` for overrides, or `--level <name>` to inspect a player's
selected map. The [inspection contract](docs/reference/testing/terrain-inspection.md)
defines scenario fields and omitted level systems.

Recorded demo inspection uses the imported high-detail demo table:

```text
python tools/run_demo.py --godot <executable> --level ORG1 --output-directory <external-folder>
```

Add `--viewer` for rendered playback and a capture, `--render-rate
30|60|144|irregular` for a frame schedule, or `--tick-limit <ticks>` for a bounded
run. The default level is ORG1. Evidence includes reference-layout frog and
live-entity CSVs, complete committed state/events in `committed.jsonl`, and
`playback.json` with the initialization, consumed inputs,
committed ticks and termination reason. Exit 3 means incomplete playback;
missing resources and unsupported dependencies remain explicit. The complete
ORG1, SUB1, FOR1 and VOL1 attract demos match the frozen native terminal states, routes and inputs. See the
[demo verification commands](docs/reference/testing/README.md#diagnostics-demo-playback-and-native-comparison)
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
The same launcher works from Terminal. After the initial editor import,
launch whole-map ORG1 directly with:

```sh
tools/launch_macos.command res://scenes/tools/terrain_viewer.tscn -- --level=ORG1
```

For other commands in this README, use the executable inside the app:

```sh
export GODOT=/Applications/Godot.app/Contents/MacOS/Godot
export FROGGER_DATA_DIR=/path/to/FROGGER   # the retail folder, for the import and the tests
"$GODOT" --path .
bash tools/run_tests.sh
```

Only the importer and the test wrapper read `FROGGER_DATA_DIR`; the game
itself reads its import. See [running the tests](#running-the-tests) and the
[testing guide](docs/reference/testing/README.md) for isolated Mac profiles.
Use `python3` for Python commands on macOS.

For reference comparisons on this Mac, reuse the verified native arm64 build
outside the frozen source tree. The [reference source instructions](docs/reference/sources.md#exporting-reference-material-from-the-engine)
provide its location, export commands, provenance and comparison limits.
The PowerShell oracle builders remain Windows-only. Packaged exports are
described under [packaged builds](#packaged-builds).

## Assets

The repository holds no part of the original game. Its content comes from
the player's own copy, imported as Godot resources: textures, model meshes,
scenes and preview animations, maps, the executable's tables, demos, sound
effects and the CD music. A player's import lives in the game's user folder;
a developer's lives in `assets/`, which is git-ignored and filled by
`tools/setup_dev.sh --import` ([developer setup](#developer-setup)). Imported
content is never edited by hand: change the importer, play a FrogLord save as
an overlay or draw a [texture pack](#texture-packs).

`content/` holds the port's own files, tracked in the repository: the angular
lettering font traced from the alpha's letter models, the lettering images
that replace the retail lettering textures, the masks from which the
lily-pad, log and turtle lettering tiles are composited over the player's own
textures at run time, and the table of glowing images. Its images and font
are Git LFS objects: run `git lfs install` before cloning (or `git lfs pull`
afterwards); the test wrapper refuses to run while any file is still an LFS
pointer. See [assets](docs/reference/assets.md).

The game draws on Godot's Forward+ renderer (Metal on Apple Silicon, Vulkan
or Direct3D 12 on Windows, Vulkan on Linux) with scene lights and real
shadows from the map light records, lit model materials and lit terrain; see
[lighting](docs/reference/rendering/lighting.md). On another renderer it
still runs and logs a warning that shadows and lighting differ.
`--shadows=off` compares without real shadows, and `--effect-shadows=retail`
keeps the original's blob shadows beside them. In-game text draws with a
bitmap font built at run time from the imported `newfont` glyph texture.

The importer and the retail readers live in `archive/`, which the game loads
only through its runtime-import seam. `tools/setup_dev.sh --import` runs
`archive/import/import_assets.sh`, which writes `assets/` from your copy of
`pc-retail-v3.0e`; see
[archive](archive/README.md). The folder may instead hold a FrogLord save of
that build (`modded_FROGGER.EXE` and `modded_FROGPSX.MWD`): FrogLord is the
level editor and this port plays its output. `--assets-root=` and
`--fallback-root=` import such a save as an overlay beside `assets/` without
touching it. `tools/asset_report.sh [--index-root=<folder>] [--strict]` lists,
per level, the forms, entity names, scripts, FORM callbacks and texture remaps
a build uses and which of them the port cannot play; a mod may repoint data
only to behaviour the port already implements. Other builds are not supported.
To edit a level while it runs, start `archive/import/froglord_watch.sh --data-dir=<FrogLord folder>`
in one terminal and `tools/play.sh --level=ORG1 --froglord` in another; each
save in FrogLord is imported and the level reopens with the edit. `F5` reloads
on demand. Textures and sounds need a full import and a relaunch.

### Texture packs

A texture pack swaps some or all of the game's textures for redrawn,
higher-resolution images. To install one, copy its folder (the one holding
`pack.cfg`) into `texture_packs` in the game's user folder:

- macOS: `~/Library/Application Support/Godot/app_userdata/Frogger/texture_packs/`
- Windows: `%APPDATA%\Godot\app_userdata\Frogger\texture_packs\`
- Linux: `~/.local/share/godot/app_userdata/Frogger/texture_packs/`

An exported game also finds packs in a `texture_packs` folder beside its
executable. Choose the pack on the setup screen's settings page (hold Shift
at start, or start with `-- --setup`); "None (original textures)" turns it
off. For one launch, `--texture-pack=<folder name>` after `--` picks a pack
and `--texture-pack=` draws none, for example
`tools/play.sh --level=ORG1 --texture-pack=crisp`. Textures a pack leaves
out keep their original look, and an image of the wrong size is skipped with
a note in the log. To make a pack, see
[texture packs](docs/reference/assets.md#texture-packs).

### Sandbox

The start screen's **Sandbox** button (or `godot --path . -- --sandbox`;
`--level=SANDBOX` also works) opens a flat 32×32
arena of coloured terrain zones: plain floor, water, ice, freeform ice, bouncy,
deadly, soft, checkpoint, cliff steps, a sloped cliff and a camera zone. The
frog, HUD and entities use the real models, and the palette offers every entity
kind a supported level places, with that level's forms, scripts and payloads.
In a synthetic scenario without models, the frog is a marker, entities are
orange footprint placeholders, and only `STATIC`, `DYNAMIC`,
`FOR_SWAYING_BRANCH`, `MOVING` and `MOVING_TONGUEABLE` spawn, as one-cell
platforms. The sandbox never ends: when a run completes or the last life is
lost, it restarts with full lives.

The side panel chooses the entity, form, path (static, line, loop, speed) and
speed, loads named presets, teleports to a zone or cell, and shows the zone
colours and keys. Gameplay keys are unchanged (arrows, Shift, Ctrl, Q/E, Space,
Escape), except that C clears entities here instead of croaking. Sandbox keys:

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
desert, jungle, swamp and sky hazards, effects, and sounds. The effects preset starts
the frog on (16, 4). The ice zone (columns 11–14, rows 6–11) gives slide
particles and the water zone (columns 3–8, rows 6–9) the splash and bubbles.
Column 16 leads north between the ice zones to the blue car's exhaust on row 12
(from column 17) and the bison's dust on row 13 (columns 3–11). Row 4 leads
east to the rubber balloon (20, 2), the lava spray's fire (22, 4) and the
nuclear barrel's loop from (27, 0), and west to the bonus fly (13, 3), the gold
frog (10, 3) and the checkpoint (8, 2). The sounds preset starts the frog on
(16, 19) beside the vulture, swamp press and crusher, beaver, tumbleweed, bonus
fly, gold frog and checkpoint, for listening to moving sounds, doppler and loops.

The sandbox is a play-check tool, not acceptance evidence; its
[limitations](docs/reference/architecture.md#sandbox) are listed with its design.

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
step and seek move the selected cursor with map animation. These settings inspect a detached
path runner; map entity attachment has its own authored starts. See the
[path](docs/reference/gameplay/paths.md) and
[entity](docs/reference/gameplay/entities.md) contracts.

In the **Entities** tab, enable **Show entity axes** to draw attached base
transforms and choose a source-indexed entity for its path and position
readout. Set the FORM probe's X/Y/Z world coordinates, or choose **Place probe
in first cell**. The viewer draws the selected FORM outline and contacted cell
and reports contact status, cell and raw flags. An unsupported form shows its
reason. This query does not move or kill the frog. The panel counts omitted
records; hover over the count for source diagnostics. The axes start hidden.

For reproducible path traces and an optional rendered capture, run
`python tools/run_paths.py --godot <executable> --scenario line --output-directory <external-folder>`.
Add `--viewer` for the map overlay, `--scenario arc` or `--scenario spline`
for other built-in paths, or `--scenario-file <JSON-file>` for a custom case.
With an imported map, use `--level SUB1 --path-index 0`;
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
Use `--viewer` to capture world and full-window images, or `--level ORG1`
to inspect an imported map. `--tick-limit` and
`--render-rate 30|60|144` control the trace duration and render schedule.
`python tools/verify_entity_schedules.py --godot <executable> --scenario
shared-path --output-directory <external-folder>` compares schedules, including
the fixed contact probe. Traces,
logs and captures stay outside the repository.

For repeatable captures on Windows, set `GODOT`, then:

```powershell
tools/capture_map.ps1 -OutputDirectory C:\captures\frogger -Level SUB1 -Tick 0 -Linear -Benchmark
```

Captures use a fixed 640×480 viewport and write PNG plus metadata outside the
repository (`python3 tools/capture_map.py` is the cross-platform equivalent).
Use `-Linear` for linear filtering; omit it for nearest.
Add `-LowDetail` to inspect the matching low-detail map and textures. The viewer also accepts
`-- --level=SUB1 --low-poly=false --tick=0 --linear=false
--screenshot-dir=<absolute external folder>`. An optional `--probe-model=GEN_CHECKPOINT_1.XMR`
shows a static model under the map's scene lights.
High- and low-detail maps are separate resources: select the detail variant
you want. For fixed-pose comparisons, the capture wrapper accepts
`-CameraSource 'x,y,z'` and `-CameraTarget 'x,y,z'` (game units).

## Running the tests

Contributors: start with the [domain language](docs/reference/domain.md) and
[architecture and ownership](docs/reference/architecture.md). These describe
source identities, viewer lifetimes, and ownership of gameplay state.

### Developer setup

A fresh checkout needs git LFS, Python 3, [uv](https://docs.astral.sh/uv/)
and Godot 4.5.1, and your own copy of the game to play from source:

```sh
export FROGGER_DATA_DIR=/path/to/FROGGER   # holds FROGGER.EXE and FROGPSX.MWD
export FROGGER_DISC=/path/to/FROGGER.mds   # optional: the disc image, for the music
tools/setup_dev.sh --download-godot --import
```

`tools/setup_dev.sh` (Bash) or `tools/setup_dev.ps1` (PowerShell, `-DownloadGodot`
and `-Import`) checks each tool, pulls the LFS objects, syncs the Python
tools' environment and imports the project once. `--download-godot` fetches
the pinned editor into `build/godot/` when none is installed; set `GODOT` to
use an existing executable instead. `--import` imports your copy into
`assets/` (several minutes); with `FROGGER_DISC` set it also encodes the CD
music, which needs `oggenc` (vorbis-tools). `--check` only reports. Without
an import the game still runs from source: it opens the setup screen and
imports into its user folder like an exported game. Nothing else in the
checkout depends on other repositories: the `../froggy` reference engine named
in the references is only needed to regenerate goldens or compare traces.

### Test suites

Tests use [GUT](https://github.com/bitwes/Gut) and run headless:

```
GODOT=/path/to/godot tools/run_tests.sh              # bash (Linux, macOS, Git Bash on Windows)
$env:GODOT="C:\path\to\Godot.exe"; tools\run_tests.ps1   # PowerShell
```

The game suite under `tests/` needs no game files and allows no skips; it is
the suite hosted CI runs. Set `FROGGER_DATA_DIR` to the folder holding the
retail `FROGGER.EXE` and `FROGPSX.MWD` to also run the archive suite
(`archive/tests/`), which checks the retail readers against the committed
text facts, and the imported suite (`tests/imported/`), which checks your
import in `assets/` and stops with a pointer to `tools/setup_dev.sh --import`
when there is none. The [testing guide](docs/reference/testing/README.md)
says what each suite needs. Each suite prints a summary such
as `SUMMARY: PASS=70 FAIL=0 SKIP=0 EXIT=0`, followed by the wrapper's
result-validation status.

| Exit code | Meaning |
|---|---|
| 0 | every test ran and passed |
| 1 | a test failed or skipped, or a script does not compile |
| 2 | runner setup failed (for example, Godot was not found, or the checkout holds unfetched Git LFS pointers) |

Every script is compiled before the tests run (`tools/check_scripts.gd`),
with the project's strict typing warnings treated as errors. The wrappers also
check architecture dependencies, including that nothing in the game depends on
`archive/`, and validate the complete test report. A supplied but invalid
retail folder, any skip or an empty selection fails.
The wrappers isolate writable user data, save explicit logs in a temporary
folder, disable the crash handler and stop at the first failed stage.
For a focused iteration, append `-gselect=test_model_viewer` to either wrapper.
The complete run with `FROGGER_DATA_DIR` set and `assets/` imported remains
required before each commit.

## Layout

| Path | What |
|---|---|
| `assets/` | Git-ignored: your local import of the game as Godot resources, with `catalog.tres` as the index, written by `tools/setup_dev.sh --import`; see [assets](docs/reference/assets.md). |
| `content/` | The port's own files, tracked (images and font through Git LFS): the angular font and its sources, the lettering images and tile masks, the glowing-image table. |
| `src/data/` | The typed `Resource` records the game plays from: `archive/` (index and WADs), `textures/`, `models/`, `maps/`, `tables/` (the executable's tables), `sound/`, `demos/`, `names/`, `AssetCatalog` (the abstract data provider) and `AssetIndex`. No scene tree, no file access. |
| `src/rendering/` | Turning game data and committed gameplay state into Godot resources: model meshes and materials, the shaders that draw them, scene-lighting and tint specifications, effect geometry, and the conversion between the game's space and Godot's. |
| `src/game/` | Gameplay definitions, run state and rules: terrain, frog, entities, paths, camera, animation, sound logic, level flow, and the front-end rules (`frontend/`, `options/`). No scene tree, no file access. |
| `src/application/` | Adapters from data records to gameplay definitions, the behavior and callback catalogs, `ImportedAssets` (`loaders/`), the save files (`storage/`) and the setup's asset location, importer interface and page rules (`setup/`). |
| `src/inspection/` | Developer scenarios, validated options, guards, presets and their manifests, and the sandbox arena. |
| `src/presentation/` | The game and front-end screens (`frontend/`), the setup screen (`setup/`), the sandbox screen (`sandbox/`), audio, input and effect views, and development tools (`tools/`: the model, map, terrain and camera-zone viewers). |
| `scenes/` | Godot scenes (`setup.tscn` is the main scene, which opens `front_end.tscn` once the game is set up, and `boot.tscn` the developer tools menu; `game/` holds the game and sandbox scenes, `tools/` the viewers). |
| `tests/unit/` | The game suite's unit tests, one folder per layer. |
| `tests/golden/` | Golden tests over committed synthetic facts, `content/` and keyboard fixtures, and the retail text facts the archive and imported suites compare with. |
| `tests/imported/` | The imported suite: tests that need your import in `assets/`. |
| `archive/` | Everything that reads the retail files, which the game reaches only through the runtime-import seam: `source/` (the readers and the retail-backed `GameData`), `import/` (the importer that writes `assets/` or a player's import), `tests/` (the archive suite, run only with `FROGGER_DATA_DIR`), `tools/`, `docs/formats/` (the retail format references) and `third_party/froglord_cfg/` (FrogLord's configuration files, unmodified; see `archive/third_party/README.md`). |
| `tools/` | The play and test wrappers, the script and architecture checks, the golden-data generators `make_*.py` (see `tests/golden/README.md`), the C oracles, and the inspection runners, verifiers and probes. |
| `addons/gut/` | The GUT test framework, unmodified. |

## Contributing and project documentation

Start with [AGENTS.md](AGENTS.md) and the short [current checkpoint](docs/CURRENT.md).
The [roadmap](docs/PORTING.md) owns status and remaining work. The
[domain index](docs/reference/domain.md) groups references by data, gameplay
and rendering, and the [domain model](docs/reference/domain-model.md) maps the
contexts, aggregates and asset identities; the [testing guide](docs/reference/testing/README.md) covers checks and
inspection tools. Documentation describes current behavior and use. Run logs
stay outside the repository, and Git retains development history.

## Packaged builds

A packaged build holds the port's code and its own files from `content/`,
and no part of the original game: on the first start the
[setup screen](#setup-and-first-run) imports your own copy of Frogger into
the game's user folder. The lily-pad letters, score logs and rank turtles
are composited from the port's lettering masks over textures of that copy. Each release on
the repository's GitHub Releases page carries the three zips below.

- **macOS** (Apple Silicon and Intel): unzip `Frogger-<version>-macos.zip` and
  move `Frogger.app` to Applications. The app is signed ad hoc, not by a
  registered developer, so Gatekeeper refuses the first open of a downloaded
  copy. Open it once, then choose **Open Anyway** in System Settings, Privacy &
  Security (on older macOS, Control-click the app and choose Open), or run
  `xattr -dr com.apple.quarantine /Applications/Frogger.app` in Terminal.
  Start it from Launchpad or keep it in the Dock.
- **Windows** (x86_64): unzip `Frogger-<version>-windows-x86_64.zip` and run
  `Frogger.exe`, keeping `Frogger.pck` beside it. SmartScreen warns about an
  unsigned program: choose More info, then Run anyway. The setup's last page
  puts a shortcut on the desktop.
- **Linux** (x86_64): unzip `Frogger-<version>-linux-x86_64.zip` and run
  `./Frogger.x86_64`, keeping `Frogger.pck` beside it. The setup's last page
  adds the game, with its icon, to the applications menu and the desktop;
  `frogger.desktop` beside the program starts it from that folder too.

Settings and the imported game live in the user folder:
`~/Library/Application Support/Godot/app_userdata/Frogger` on macOS,
`%APPDATA%\Godot\app_userdata\Frogger` on Windows and
`~/.local/share/godot/app_userdata/Frogger` on Linux. The setup's last page
shows the credits and licences.

To build the packages, install the Godot 4.5.1 export templates (Editor,
Manage Export Templates), then run `tools/export.sh` (or `tools/export.ps1`
on Windows); `tools/export.sh macOS` builds one. The builds and their zips go
to `build/`. The script stops when a build would carry any file under
`assets/`, or any file of `content/` other than the angular font, the
glowing-image table, the lettering images and the tile masks. The icon is a
placeholder drawn for the port, `icon/frogger_icon.svg`; after editing it,
run `godot --headless --path . -s res://tools/make_icons.gd`. See
[packaging](docs/reference/setup.md#packaging).

## Licence

The repository holds none of the original game's files: its levels, models,
textures, sounds and music come from the player's own copy, imported on the
first run. The test facts in `tests/golden/pc-retail-v3.0e/`, decoded from
the retail files, stay until the owner decides on them. A licence for the project's own code has not been chosen yet; that
is the owner's decision. Third-party material keeps its own licence:
FrogLord's configuration files (MIT, `archive/third_party/froglord_cfg/LICENSE.md`)
and GUT (MIT, `addons/gut/LICENSE.md`).

## Credits

- **FrogLord** by Kneesnap and the [Highway Frogs](https://highwayfrogs.net)
  community: the file-format research this project builds on, and the
  configuration files it ships.
- The Highway Frogs community's documentation of Frogger's formats and the
  released original PlayStation source code.
- **StarmanUltra**: the traced letter outlines of the 1997 alpha's letter
  models, from which the angular lettering font and images are drawn.
- **GUT** by Butch Wesley, for testing.

Frogger is a trademark of Konami. This is an unofficial fan project and is not
affiliated with or endorsed by the rights holders.

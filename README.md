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
Space plays/pauses the command fixture, Period steps, R resets and I changes
interpolation. Tab switches to live arrow-key input, Shift requests a super hop,
and Q/E turn the gameplay camera. Pause and reset also reset drawing interpolation.
This is terrain inspection; entities, moving platforms and progression arrive
in later phases. Animated lighting remains a
[documented renderer limitation](docs/reference/rendering/gameplay-projection.md).
The game runs in GDScript. C files under `tools/` are offline reference
validation adapters; playing or loading data does not require C code or a compiler.
For isolated headless or rendered evidence, use `python tools/run_terrain.py
--godot <executable> --scenario buffer --output-directory <external-folder>`;
add `--viewer` for a captured scene and `--data-dir <game-folder>` for frog assets.
Use `--scenario-file <file>` for a typed JSON fixture, `--seed <integer>` and
`--tick-limit <integer>` for overrides, or `--level <name>` to inspect a player's
selected map. The [inspection contract](docs/reference/testing/terrain-inspection.md)
defines scenario fields and omitted level systems.

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
water and sky-land. This is an inspection tool: frogs, moving entities, HUD
and gameplay cameras are deferred. The explicit hidden-geometry inspection
switch includes invisible and unreferenced polygons; ordinary viewing omits them.

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
| `src/legacy/` | Readers for the original data formats and executable: `io/` (byte reading, PowerPacker), `config/` (FrogLord configs and name lists), `source/` (finding the game files), `formats/` (MWI, MWD, WAD, texture banks, models), `exe/` (the game tables in the executable). `game_data.gd` puts them behind one object. Pure data classes with no scene tree, testable headless. |
| `src/convert/` | Turning decoded game data into Godot resources: textures, model meshes, the shaders that draw them, and the conversion between the game's space and Godot's. |
| `src/game/` | Detached terrain definitions, ordered run state, grid queries, movement/collision, gameplay camera, animation control and source RNG. Rules have no scene tree or file access. |
| `src/presentation/` | Screens (`frontend/`), runtime setup (`setup/`), shared viewer helpers, and development tools (`tools/`, the texture, model, map and terrain viewers). |
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

# Developer setup

This page is for contributors working from a source checkout. The game plays
from `assets/`, each developer's own import of their retail copy, which is
git-ignored and never committed. Without an import the game still runs from
source and imports into its user folder like an exported game.

## Prerequisites and first import

A fresh checkout needs git LFS, Python 3, [uv](https://docs.astral.sh/uv/)
and Godot 4.5.1, and your own copy of the game to play from source:

```sh
export FROGGER_DATA_DIR=/path/to/FROGGER   # holds FROGGER.EXE and FROGPSX.MWD
export FROGGER_DISC=/path/to/FROGGER.mds   # optional: the disc image, for the music
tools/setup_dev.sh --download-godot --import
```

`tools/setup_dev.sh` (Bash) or `tools/setup_dev.ps1` (PowerShell, `-DownloadGodot`
and `-Import`) checks each tool, pulls the LFS objects, syncs the Python
tools' environment and imports the project once.

- `--download-godot` fetches the pinned editor into `build/godot/` when none
  is installed; set `GODOT` to use an existing executable instead.
- `--import` imports your copy into `assets/` (several minutes); with
  `FROGGER_DISC` set it also encodes the CD music, which needs `oggenc`
  (vorbis-tools).
- `--check` only reports.

The images and font in `content/` are Git LFS objects: run `git lfs install`
before cloning (or `git lfs pull` afterwards). The test wrapper refuses to run
while any file is still an LFS pointer.

Without an import the game opens the setup screen and imports into its user
folder. Nothing else in the checkout depends on other repositories: the
`../froggy` reference engine named in the references is only needed to
regenerate goldens or compare traces.

## macOS setup

Install the standard **Godot 4.5.1 macOS Universal** build from the
[official archive](https://godotengine.org/download/archive/4.5.1-stable/)
as `/Applications/Godot.app`. It runs natively on Apple Silicon and Intel.
The project uses GDScript; .NET, Java, a C compiler and export templates are
not required to run it or its Godot tests. GUT is already included.
Python 3 is needed for the Mac test runner and inspection launchers; use
`python3` for Python commands on macOS.

Double-click `tools/launch_macos.command` in Finder to open the project in the
editor. Let the initial import finish, then press F5 (Fn-F5 when the keyboard
uses media keys) to run the start screen. The same launcher works from
Terminal. After the initial editor import, launch whole-map ORG1 directly with:

```sh
tools/launch_macos.command res://scenes/tools/terrain_viewer.tscn -- --level=ORG1
```

For other commands, use the executable inside the app:

```sh
export GODOT=/Applications/Godot.app/Contents/MacOS/Godot
export FROGGER_DATA_DIR=/path/to/FROGGER   # the retail folder, for the import and the tests
"$GODOT" --path .
bash tools/run_tests.sh
```

Only the importer and the test wrapper read `FROGGER_DATA_DIR`; the game
itself reads its import. See [test suites](#test-suites) and the
[testing guide](testing/README.md) for isolated Mac profiles.

For reference comparisons on a Mac, reuse the verified native arm64 build
outside the frozen source tree. The
[reference source instructions](sources.md#exporting-reference-material-from-the-engine)
provide its location, export commands, provenance and comparison limits.
The PowerShell oracle builders remain Windows-only. Packaged exports are
described under [packaged builds](#packaged-builds).

## Playing from source

Launch a level with the play wrapper:

```text
tools/play.sh --level=SUB1
```

`tools/play.ps1` is the PowerShell equivalent, and `--scene=` selects another
scene. The default is high-detail ORG1. No data folder is needed once
`assets/` holds an import.

The direct launch also works:

```text
godot --path . res://scenes/game/gameplay.tscn -- --level=SUB1
```

It reads the project's class-name cache in `.godot/`, which goes stale when
new scripts arrive and then fails with a script parse error. The play wrapper
refreshes the cache before launching. `tools/run_tests.sh` also refreshes the
checkout cache after strict compilation, and on Windows the wrapper's import
stage already targets the checkout.

`--level=` also opens a level that has a map but is not yet accepted, such as
JUN2, with a warning; the front end lists only accepted levels.

The retail folder may instead hold a FrogLord save of `pc-retail-v3.0e`
(`modded_FROGGER.EXE` and `modded_FROGPSX.MWD`); other builds are not
supported. `--assets-root=` and `--fallback-root=` import such a save as an
overlay beside `assets/` without touching it.
`tools/asset_report.sh [--index-root=<folder>] [--strict]` lists, per level,
the forms, entity names, scripts, FORM callbacks and texture remaps a build
uses and which of them the port cannot play; a mod may repoint data only to
behaviour the port already implements. The importer is described in
[archive](../../archive/README.md).

To edit a level while it runs, start
`archive/import/froglord_watch.sh --data-dir=<FrogLord folder>` in one terminal
and `tools/play.sh --level=ORG1 --froglord` in another. Each save in FrogLord
is imported and the level reopens with the edit; `F5` reloads on demand.
Textures and sounds need a full import and a relaunch. The full rules are in
[FrogLord while playing](setup.md#froglord-while-playing).

## Test suites

Tests use [GUT](https://github.com/bitwes/Gut) and run headless:

```
GODOT=/path/to/godot tools/run_tests.sh              # bash (Linux, macOS, Git Bash on Windows)
$env:GODOT="C:\path\to\Godot.exe"; tools\run_tests.ps1   # PowerShell
```

There are three suites:

- The game suite under `tests/` needs no game files and allows no skips; it
  is the suite hosted CI runs.
- The archive suite (`archive/tests/`) checks the retail readers against the
  committed text facts.
- The imported suite (`tests/imported/`) checks your import in `assets/` and
  stops with a pointer to `tools/setup_dev.sh --import` when there is none.

The archive and imported suites also run when `FROGGER_DATA_DIR` is set to the
folder holding the retail `FROGGER.EXE` and `FROGPSX.MWD`. The
[testing guide](testing/README.md) says what each suite needs. Each suite
prints a summary such as `SUMMARY: PASS=70 FAIL=0 SKIP=0 EXIT=0`, followed by
the wrapper's result-validation status.

| Exit code | Meaning |
|---|---|
| 0 | every test ran and passed |
| 1 | a test failed or skipped, or a script does not compile |
| 2 | runner setup failed (for example, Godot was not found, or the checkout holds unfetched Git LFS pointers) |

Every script is compiled before the tests run (`tools/check/check_scripts.gd`),
with the project's strict typing warnings treated as errors. The wrappers also
check architecture dependencies, including that nothing in the game depends on
`archive/`, and validate the complete test report. A supplied but invalid
retail folder, any skip or an empty selection fails. The wrappers isolate
writable user data, save explicit logs in a temporary folder, disable the
crash handler and stop at the first failed stage.

For a focused iteration, append `-gselect=test_model_viewer` to either
wrapper. The complete run with `FROGGER_DATA_DIR` set and `assets/` imported
remains required before each commit.

## Layout

| Path | What |
|---|---|
| `assets/` | Git-ignored: your local import of the game as Godot resources, with `catalog.tres` as the index, written by `tools/setup_dev.sh --import`; see [assets](assets.md). |
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

## Packaged builds

A packaged build holds the port's code and its own files from `content/`,
and no part of the original game: on the first start the
[setup screen](setup.md) imports your own copy of Frogger into the game's
user folder. The lily-pad letters, score logs and rank turtles are composited
from the port's lettering masks over textures of that copy. Each release on
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

- macOS: `~/Library/Application Support/Godot/app_userdata/Frogger`
- Windows: `%APPDATA%\Godot\app_userdata\Frogger`
- Linux: `~/.local/share/godot/app_userdata/Frogger`

The setup's last page shows the credits and licences.

To build the packages, install the Godot 4.5.1 export templates (Editor,
Manage Export Templates), then run `tools/export.sh` (or `tools/export.ps1`
on Windows); `tools/export.sh macOS` builds one. The builds and their zips go
to `build/`. The script stops when a build would carry any file under
`assets/`, or any file of `content/` other than the angular font, the
glowing-image table, the lettering images and the tile masks. The icon is a
placeholder drawn for the port, `icon/frogger_icon.svg`; after editing it,
run `godot --headless --path . -s res://tools/content/make_icons.gd`. The preset table
and release workflow are in [packaging](setup.md#packaging).

# Testing and visual checks

## Required commit gate

Run the wrapper before every commit that touches code, tests, goldens, assets,
tools or project configuration; documentation-only commits need no run. It
checks that `assets/` holds no git LFS pointers, imports, strictly compiles
every script (including `archive/`), refreshes the checkout's class cache,
checks architecture, then runs two suites and verifies each saved result report
against its log and process exit. Stop on a failed stage; fix it before starting
subsequent checks.

- Game suite (`tests/`, `.gutconfig.json`): always runs, needs no player files
  and never sees `FROGGER_DATA_DIR`. Every test must pass; a skip or pending
  test is a failure.
- Archive suite (`archive/tests/`, `archive/tests/.gutconfig.json`): runs only
  when `FROGGER_DATA_DIR` is set. The wrapper first checks that the folder holds
  FROGGER.EXE and FROGPSX.MWD; a set but invalid or empty value fails. Skips
  and pending tests fail here too. When the variable is unset the wrapper prints
  `run_tests: archive suite not run (FROGGER_DATA_DIR unset)`.

```powershell
$env:GODOT = 'C:\path\to\Godot.exe'
$env:FROGGER_DATA_DIR = 'C:\path\to\FROGGER'
& .\tools\run_tests.ps1
```

For Bash: `GODOT=/path/to/godot FROGGER_DATA_DIR=/path/to/retail tools/run_tests.sh`.
`tools/setup_dev.sh` or `tools/setup_dev.ps1` prepares a fresh checkout for
the wrapper (LFS objects, uv environment, a Godot 4.5.1 editor, the first
import); see [running the tests](../../../README.md#running-the-tests).
Commands run from the repository root. Before a commit, run with
`FROGGER_DATA_DIR` set so both suites run. Exit codes: 0 = every stage passed;
1 = compile, architecture, input, test or result failure; 2 = setup failure
(Godot missing, run folder, or git LFS pointers under `assets/`: run
`git lfs pull`).

On macOS, the Bash wrapper also finds `/Applications/Godot.app/Contents/MacOS/Godot`
when `godot` is not on PATH. After strict compilation it imports the checkout
itself once, so its `.godot/` class-name cache stays current for direct
launches; the stage warns but does not fail the run when that import fails. Python 3 is required (`PYTHON` can select its executable).
The Bash wrapper and Python inspection launchers use `tools/godot_project.py`:
each run gets an external project file and import cache, with links to the current
checkout's sources. A generated override selects a unique user-data directory in
`~/Library/Application Support/Frogger Automation/`; `profile/user-data-path.txt`
(or `data/user-data-path.txt` for Bash tests) records the location.
macOS Godot ignores `APPDATA` and `XDG_DATA_HOME`, so these variables alone do
not isolate `user://`. The user's home and interactive Frogger settings stay
unchanged. A checkout-local `override.cfg` must be removed before isolated runs.
Retained run folders and their matching user-data directories may be deleted
after diagnosis. Sandbox environments must allow the unique Library directory.

## Hosted CI

`.github/workflows/tests.yml` runs `tools/run_tests.sh` unchanged on an Ubuntu
runner for every push to any branch and on manual dispatch; a newer push to the
same ref cancels a run in progress. `FROGGER_DATA_DIR` is never set there, so
only the game suite runs: retail data never leaves the owner's machine, and
the archive suite stays a local check. A green hosted run therefore does not
replace the local run before a commit.

The runner installs Python 3.12, uv 0.11.19 and Godot 4.5.1-stable, which
`.github/actions/setup-godot` downloads from the official release, checks
against a pinned SHA-512 and caches. `.github/actions/lfs-cache` restores
`.git/lfs` from the Actions cache, keyed on the commit's LFS object list, and
pulls only what is missing, so a run spends the repository's
[Git LFS bandwidth](../../PORTING.md#needed-from-the-owner) only when the
assets change or the cache has expired.
The run's logs are kept as the artifact `test-logs-<commit sha>` for 14 days.

The release pull request gets no run, because GitHub starts no workflow for
commits made with the workflow's own token; it changes only the changelog, the
manifest and `config/version`, and the push run of the `main` commit beneath
it covers the rest. The release workflow is described under
[packaging](../setup.md#packaging).

## Feature checks

- [Whole-map keyboard playthrough](terrain-inspection.md#whole-map-keyboard-playthrough):
  repeatable completion, pink delivery and tongue collection through viewer input.
- [Terrain inspection](terrain-inspection.md): scenarios, headless/rendered traces
  and schedule comparisons.
- [Terrain component oracle](terrain-trace-oracle.md): controller/mover,
  separate camera and integrated source comparisons.
- [Terrain collision oracle](terrain-collision-oracle.md): height, death and
  effect-request boundaries.
- [Path behavior](../gameplay/paths.md): decoded records, detached runner and
  map inspection; [path golden specification](../../../tests/golden/specs/paths.md)
  defines the independent data and trace checks.
- [Entity transforms and FORM contact](../gameplay/entities.md): source-ordered
  setup, independently owned paths and a fixed world-point query against one
  selected entity, with unit tests and headless/rendered inspection.
  `python tools/run_entities.py --godot <executable> --scenario shared-path
  --output-directory <external-folder>` writes a trace; add `--viewer` for
  world and full-window captures. `--level ORG1`
  selects player data. The Entities tab has probe X/Y/Z controls and a
  first-cell placement button. `--tick-limit` and `--render-rate 30|60|144`
  select duration and frame schedule. Use `tools/verify_entity_schedules.py`
  with the same selection arguments to compare headless and rendered
  `entity-contact-v1` traces.
- [POP entity inspection](terrain-inspection.md#pop-entity-inspection): optional
  atomic frog/entity advancement and all eligible nearby FORM reactions, with
  the DES2 cactus demonstration and `entity-pop-v1` schedule comparisons.
- [SAFE platform inspection](terrain-inspection.md#safe-platform-inspection):
  JUN1 moving-log landing/carry and synthetic departure, with atomic camera
  transitions and `entity-platform-v1` schedule comparisons.
- [Guarded JUN1 exploration](terrain-inspection.md#guarded-jun1-bank-exploration):
  safe bank/log/return, decoded zone guards and complete six-phase comparisons.
- [Guarded ORG1 exploration](terrain-inspection.md#guarded-org1-turtlelog-exploration):
  turtle/log round trip, diving neighbor, all logical updates and keyboard checks.
- [Scripted ORG1 visibility](terrain-inspection.md#scripted-org1-visibility):
  live-list scripts, immortal initialization, parent recreation and guarded gameplay.
- [ORG1 road crossing](terrain-inspection.md#guarded-org1-road-to-river):
  animated frog points, vehicle cuboids, squish/callback timing and river entry.
- [Active camera zones](terrain-inspection.md#active-camera-zone-inspection):
  prescribed JUN1 probe sequences, independent reference fields and complete
  headless/rendered schedule parity.
- [Visibility lifecycle](terrain-inspection.md#visibility-lifecycle-inspection):
  opt-in source camera selection and atomic live-instance creation/retirement,
  with synthetic headless/rendered parity and external visual captures.
- [Combined zones and lifecycle](terrain-inspection.md#combined-zone-and-lifecycle-inspection):
  synthetic gameplay and prescribed JUN1 logs, independent coupled reference
  facts, transaction failures and complete schedule parity.
- [Front-end flow and unlock goldens](../../../tests/golden/specs/frontend.md):
  `python3 tools/make_golden_frontend.py --check` diffs the committed facts;
  `python3 tools/make_golden_attract.py --check` does the same for the
  [attract cycle](../../../tests/golden/specs/frontend.md#attract-cycle).
- [Golden specifications](../../../tests/golden/README.md): expected-data schemas
  and independent generator commands, grouped by feature.
- [Bitmap fonts](../../../tests/golden/specs/imported-assets.md#bitmap-fonts):
  both wrappers run `python3 tools/make_font_newfont.py --check --quiet`, which
  compares the committed `assets/fonts/*/newfont.fnt` and their pages with the generator;
  `tests/golden/assets/test_asset_fonts.gd` checks the imported fonts.
- [Angular font](../../../tests/golden/specs/imported-assets.md#angular-font)
  and [lettering](../../../tests/golden/specs/imported-assets.md#lettering):
  both wrappers run `uv run --locked tools/make_angular_font.py --check --quiet`
  and `uv run --locked tools/make_lettering.py --check --quiet`, which need
  [uv](https://docs.astral.sh/uv/) on PATH (`UV` can select it); the pinned
  fontTools and Pillow live in `pyproject.toml` and `uv.lock`. The lettering
  check allows the one-supersample rounding that differs between Pillow's
  arm64 and x86_64 wheels, so the hosted Linux run matches images generated
  on a Mac ([lettering](../../../tests/golden/specs/imported-assets.md#lettering)).
- [Packaging](../setup.md#packaging): `test_export_presets` checks that every
  preset excludes each retail-derived file under `assets/` except the
  shipped lettering images, which it requires, and the tests, tools,
  documentation and GUT; `test_app_icons` checks the icon files against
  `icon/frogger_icon.svg` (`godot --headless --path . -s
  res://tools/make_icons.gd` rewrites them); `tools/export.sh` fails an
  export whose log stores any other retail-derived file.
- [ORG1 admission checks](../../../tests/golden/specs/entities.md#org1-corridor-counterexample):
  independent background diagnostics and the [bounded route proof](../../../tests/golden/specs/entities.md#org1-route-proof).
  The older general-pose diagnostic remains blocked; the narrower route has
  its own complete proof and pinned inputs.

## Diagnostics: demo playback and native comparison

The recorded-input checks in this section and the
[keyboard replays](#dedicated-game-scene-captures) are on-demand diagnostics.
They are not part of the commit gate, not phase deliverables and not acceptance
evidence (owner decision, 2026-10-30): the sandbox and the owner's level play
checks are the system checks. Recorded inputs replay only while the port's
random stream matches the original's at every tick, and effects in the port
draw none of the original's shared random values (see
[simulation](../gameplay/simulation.md#effects-and-the-random-stream)), so a
replay that desyncs is a diagnostic to read, not a failure to fix.

`tools/run_demo.py` resolves the high-detail demo for `--level` (ORG1 by default)
from the supplied executable and archive, then drives recorded commands through
`GameplayHost`. ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and SKY1–SKY4 share whole-map dependency setup; recorded
playback uses the supplied demo starting cell and FAST_RESET initialization.
A level without an enabled demo reports that missing resource. Other themes
retain explicit unsupported-dependency diagnostics.

```text
python tools/run_demo.py --godot <executable> --output-directory <external-folder>
python tools/compare_demo_trace.py <reference.csv> <run-folder>/frog.csv --status <run-folder>/playback.json --map 24 --segment 0
python tools/verify_demo_schedules.py --godot <executable> --output-directory <external-folder>
python -m unittest discover -s tools -p test_demo_trace.py
```

The launcher uses an isolated project/profile, explicit logs, hidden awaited
processes on Windows and `--disable-crash-handler`; import, strict compilation
and architecture checks precede playback. Exit 0 means the demo duration elapsed,
3 means an explicitly incomplete run and 1 means launcher/verification failure.
A tick limit, unsupported action or failed dependency validation cannot become
a complete result. Internal resets preserve elapsed demo duration and input position. Duration completion alone establishes no retail
gameplay or reference match. Playback provenance records that distinction.

`frog.csv` uses `call,page,map,frog,grid_x,grid_z,x,y,z,mode,flags,input`.
Its companion `frog.csv.entities.csv` uses
`call,map,index,unique_id,form_book_id,entity_type,x,y,z`, with original form/type
identities and live-list walk order. Local calls start at zero and count committed
logic ticks; `input=-1` means no byte was consumed. Positions use integer matrix
translations. `committed.jsonl` also records complete detached gameplay states,
ordered events and RNG consumers. Schedule checks compare all three traces and
playback provenance byte for byte.

The comparator validates LF-terminated integer CSVs, ordered calls and per-call
identities. `--segment <index>` selects a contiguous reference visit to the map;
a nonempty candidate must contain one visit. It checks declared duration, committed row
count and consumed-input count before accepting completion and matching terminal
frog state. Route cells and consumed-input differences are diagnostic, with no
invented distance tolerance. Reference hook calls may include multiple logic
ticks after level transitions, so their global counters are not aligned to local
ticks. A correctly formatted header-only candidate is a valid incomplete
comparison only when playback status records zero committed ticks and consumed
inputs, a matching map and an explicit reason. It reports `complete: false`,
`accepted: false`, `terminal_comparable: false`, `terminal_differences: null`
and the original reason, with exit 1. It cannot establish a reference match or passing schedule check.
Missing or malformed status, an empty reference, or an empty completed run
fails as invalid input (exit 2). Complete status must match its declared
duration.

The schedule verifier compares both CSVs, committed JSONL and playback provenance byte for byte
across headless and rendered 30/60/144 Hz and irregular frames. To exercise a
complete synthetic run independently of current retail admission, supply paired
`--scenario-file <terrain-json>` and `--demo-file <synthetic-demo>` instead of
`--level`. The JSON uses the existing terrain fixture schema; the binary demo
is three little-endian signed integers (duration, start X, start Z), then action
bytes. These supplied fixtures are inputs, never expected-data goldens. Rendered
runs reuse `TerrainViewer` and retain `demo.png` outside the checkout; inspect it.

Use the [verified external native build](../sources.md#exporting-reference-material-from-the-engine)
and export traces to a folder outside the repositories. The reference maps are ORG1 (24), SUB1 (48), FOR1 (12) and VOL1 (54), each segment 0.
These whole-map demos complete and match the verified native terminal state,
route and consumed input.
Select SUB1 with `--level SUB1` for playback and schedule verification, and
`--map 48` for comparison. Select FOR1 with `--level FOR1` and compare with `--map 12`.
Select VOL1 with `--level VOL1` and compare with `--map 54`.
VOL2/VOL3 completion is established through normal-start keyboard replay and
independent behavior facts; only VOL1 has a verified native Volcano attract baseline.
FOR2 has supplied demo data but no verified native attract baseline; its dedicated
scene keyboard completion supplies level acceptance alongside the Forest component
facts. CAV1 and CAV4 have supplied demo data but no native attract baseline: the
native export plays only the fresh-boot attract route and Cave stays locked there,
and `../froggy` is read-only. Their demos are checked for duration completion and
schedule parity; CAV3 has no enabled demo. DES1–DES5 all have enabled demos
and no native baseline for the same reason, so they receive the same duration
and schedule-parity check, as do SWP2–SWP4. SWP1 and SWP5 have native
baselines from a native run whose scratch store had every arcade row
selectable (see [sources](../sources.md#exporting-reference-material-from-the-engine)):
both complete and match the native rows per tick, the only difference being
the level-start camera, which leaves the start one tick later than frozen C
before any input is read. The native SWP1 demo dies five times and plays to its
full length, which is why demo playback starts with ten lives. All four Sky
demos are gated on SKY1, so a scratch store that opens only that row reaches
SKY3, SKY2, SKY4 and finally SKY1 (the sixteenth demo) inside the sound-journal
cap; SKY1–SKY4 complete, keep schedule parity and match the native rows per
tick (`--map 42` through `45`), with the same level-start camera tick as Swamp.
The frozen `Game_timer` at demo start is not in a trace, so the drift's RNG
phase is unverified there; it moves only the backdrop and sound choices. The
executable enables no Jungle demo, so JUN1 has no demo check. Level acceptance is the owner's play
check in the dedicated game scene: the agent hands over the launch command and
what to look for, and the owner confirms the level looks and plays well.
Independent facts in the test gate are the regression coverage beneath that
check; replays and demo comparisons are diagnostics. Bounded incomplete fixtures still exercise rejection paths.

## Dedicated game scene captures

Use `python tools/run_gameplay_capture.py --godot <executable> --level ORG1 --output-directory <external-folder>` to capture
startup and normal play in the dedicated game scene. Select ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3, CAV1, CAV3, CAV4, DES1–DES5, JUN1, SWP1–SWP5 or SKY1–SKY4;
`--ticks` controls an idle inspection's duration. Add `--route <JSON-file>` to
replay the existing sparse keyboard stimulus format through actual key events.
The ORG1 completion, pink-delivery and tongue-collection fixtures listed in the
[playthrough guide](terrain-inspection.md#whole-map-keyboard-playthrough) work
with this launcher too. ORG2–ORG5 completion stimuli are
`tests/golden/fixtures/org2_keyboard_playthrough.json` through
`org5_keyboard_playthrough.json`, plus `sub1_keyboard_playthrough.json`; select
the matching `--level`. Forest uses `for1_keyboard_playthrough.json` and
`for2_keyboard_playthrough.json`. Volcano uses `vol1_keyboard_playthrough.json`
through `vol3_keyboard_playthrough.json`. Cave uses `cav1_keyboard_playthrough.json`
and `cav4_keyboard_playthrough.json`; CAV3 has no replay. Desert, Jungle and Swamp have no replays.
These are normal-start inputs, not expected-state goldens. An inspection run does
not establish level completion. New replays are optional and come only from
human play through `--record-inputs` (see the [README](../../../README.md)); they
are never generated by search and never requested from the owner.

The launcher isolates writable user data, imports and strictly compiles scripts,
checks architecture, then awaits the rendered process with explicit logs and the
crash handler disabled. Each committed scene state must match a fresh pure run
receiving the same sampled inputs. Captures cover startup, early HUD animation,
checkpoint/bonus-stage transitions and the final state; `gameplay.json` records
the goal, result and milestones. Forest captures also record the first visible
occurrence of each custom behavior mode. Volcano captures include visible switch
colours/actions, platform carrying/collapse and scripted hazards. Cave captures record
the first light decay, firefly and pickup light gains, visible fireflies and fat fire
fly, and partial and dark entity fade. Desert captures show rock arcs and
explosions, crack opening and sinking, croc-head timing, snake turns and
vulture swoops. Jungle captures show plant snaps, the rope bridge drop, hippo
dives, scorpions and the door bounce-back. Swamp captures show acid drips,
crusher rams and press stamps, the rat's jumps and run, slugs, nuclear barrel
ejections and bobbing waste barrels.
All evidence stays outside repositories.

Use `--flow-check --ticks 10000` without a route to verify idle timeout,
respawn, game over and a fresh session through the R key. Use
`--resolution 960x540` to inspect widescreen letterboxing; the report records
window and logical viewport sizes. These captures supplement the complete test
wrappers.

## Sandbox play checks

The [sandbox](../../../README.md#sandbox) is an owner play-check tool for trying
terrain and entity mechanics in isolation. It is not acceptance evidence: level
acceptance remains the owner's play check of real levels in the dedicated game
scene. Asset-free tests (`tests/unit/inspection/test_sandbox_*.gd`,
`tests/unit/presentation/test_sandbox_screen.gd` and
`test_gameplay_mapless_entities.gd`) cover the synthetic arena, data-free
spawning, path presets, preset application with reported skips, placeholders,
restart and hotkeys. Archive-suite tests (`archive/tests/golden/test_retail_sandbox_*.gd` and
`test_retail_mapless_entities.gd`) cover data-backed templates and forms, real
model nodes and every preset applying fully with player data. Neither drives a
route or establishes level behaviour. The effects preset (ice, water, a car,
a bison, a lava spray, a balloon, a barrel, a fly, a gold frog and a
checkpoint) is the play check for the [effects](../rendering/effects.md); the sounds preset
(vulture, press, crusher, beaver, tumbleweed, fly, gold frog and checkpoint) is
the by-ear check for [audio playback](../../../archive/docs/formats/archives.md#sound-playback).

## Focused iteration and guardrails

Append `-gselect=test_model_viewer` to either wrapper to select one script.
GUT arguments are forwarded unchanged; `-gunit_test_name=<substring>` narrows
test names further. Every focused run still compiles all scripts and checks
architecture. A selection matching no tests fails. Before committing, always
run both complete modes without selectors.
In PowerShell, quote options containing resource paths, for example
`'-gdir=res://tests/unit/presentation'`.
For a focused group, use `'-gdir='` and
`'-gtest=res://tests/unit/game/test_terrain_run.gd,res://tests/unit/game/test_terrain_specials.gd'`.
The empty directory list prevents the configured broad scan; exact scripts
still use the same strict compilation, architecture and report validation.

The [architecture contract](../architecture.md#automated-checks) explains the
scanner and its limits. Its `ARCHITECTURE FAILED` diagnostics identify the
file, line and dependency rule. New gameplay directories are checked when added;
no empty gameplay scaffolding is needed now.

Extra wrapper arguments (`-gselect=`, `-gunit_test_name=`, `-gdir=`, `-gtest=`)
apply to the game suite only; the archive suite always runs whole.

The GUT hook saves `user://test_results_game.json` or
`user://test_results_archive.json` (chosen by `FROGGER_TEST_SUITE`, which the
wrapper sets) in the isolated profile and prints named failures, skips and the
summary. The wrapper's independent check (`check_test_results.gd -- <log>
<exit> [--suite=archive]`) recounts the records and checks the suite, named
skips, summary and process exit. Missing, duplicate, inconsistent or empty
reports fail. New tests that read retail files live in `archive/tests/` and
extend `RetailTest`. Retain the printed run folder for diagnosis.

On macOS each isolated project starts from an APFS clone of the checkout's
`.godot/imported`, `uid_cache.bin` and `global_script_class_cache.cfg`, so only
changed sources are re-imported.

Use isolated writable Godot user data, explicit logs, awaited hidden
processes and `--disable-crash-handler` for automated runs. The wrappers
already enforce this and retain log paths in their output. Do not bypass
them with a bare automated Godot launch; determine success from
compilation/tests and exit status. The wrappers match error patterns
case-sensitively, so expected engine messages such as `ConfigFile parse error`
do not fail a run.

Godot 4.5.1 on Windows segfaults at exit once a loaded script inherits a
script that declares `static var` (strict compilation loads every script,
so it crashed on every run). Keep static state in classes nothing extends,
as `AssetTestCache` and `FrontEndSession` do.

## Tools and visual verification

The game implementation is GDScript. `tools/*.c` files are offline validation
adapters that call unchanged frozen reference objects and emit text facts;
they are not loaded by the game. Their builders need a developer compiler,
but normal runtime use and the Godot test suites do not build or load them.

- Godot 4.5.1 Compatibility; see [Mac setup](../../../README.md#macos-setup).
  Windows windowed builds do not reliably print to a console; use log files.
- Python 3 for inspection launchers and independent generators. Use `python3`
  on macOS; Homebrew Python can be selected by its absolute path when needed.
- GUT 9.5.0 is vendored in `addons/gut/`.
- Visually inspect visual changes. Store screenshots outside the repository.
  Hash agreement establishes decoding, not appearance.
- All viewers require absolute capture folders outside the checkout. Output
  creation/write failures report the path and exit nonzero. Shared validation
  normalizes lexical paths; callers must not use filesystem links to redirect
  an external destination into the checkout.
- After changing Godot, the renderer, the environment or the lighting, run
  `godot --path . --script tools/probe_scene_lighting.gd -- --output=<external-folder>`
  with a window: it reports the lit, source-facing and ambient-only bytes and
  the `LAMBERT_SCALE` that makes the lit face exact
  ([lighting](../rendering/lighting.md#verification)); `tools/probe_model_morph.gd`
  checks cel geometry through both shader families.
- Captures run on the project renderer, for example
  `python3 tools/capture_map.py --output-directory <external-folder> --level SUB1`
  or `python3 tools/run_gameplay_capture.py --godot <executable> --level ORG1 --output-directory <external-folder>`
  (`--game-argument=--shadows=off` and the like pass launch options through).
  The headless suites never compile shaders, so any `SHADER ERROR` in a
  capture log fails the capture, and a map capture also fails when its image is
  a single colour. `python3 tools/test_capture_tools.py` checks the command
  lines without Godot; the wrappers run it.
- Every new golden family needs an independent generator and a deliberate-break
  check, with the original fact restored. See [golden rules](../../../tests/golden/README.md).
- `tools/asset_report.sh [--index-root=<folder>] [--levels=ORG1,CAV3] [--strict]`
  prints the `LevelSupportReport` of the committed assets or an overlay index;
  `--strict` exits 1 on an unmapped row or a read problem. The archive suite's
  `test_retail_froglord_roundtrip` writes a synthetic FrogLord save under
  `user://`, imports it in-process as an overlay and loads ORG1 and CAV3 from it
  ([FrogLord round trip](../../../tests/golden/specs/imported-assets.md#froglord-round-trip)).
- `archive/import/froglord_watch.sh --data-dir=<folder> --once` runs one watcher cycle
  into the real `user://froglord/` and exits 1 when it was not clean; the round
  trip also runs a cycle in-process under `user://froglord_roundtrip_watch/`.

## GDScript and runner pitfalls

- GUT's loader does not enforce strict typing. `tools/check_scripts.gd` is the only headless check that every script compiles with warnings as errors.
- Godot's `--import` compiles nothing.
- Files with extensions Godot does not treat as resources (`.cfg`, `.tsv`) need an include filter in export presets.
- Running the boot scene saves the data folder to `user://settings.cfg`. Delete that file to test first-run behaviour.
- A headless run draws nothing, so anything that reads the screen (`tools/probe_scene_lighting.gd`, the viewers' screenshot mode) needs a window and is not part of the test run.
- A test script must not name a helper `_compare`: GUT has a member of that name.
- Autoloads run in `-s` runs too, including GUT and `tools/check_scripts.gd`. `GraphicsDebug` is inert under the headless display server; tests call `GraphicsPanel.activate()` with their own settings path.
- A test that changes `GraphicsProfile` calls `GraphicsProfile.reset()` in `after_each`.
- A conditional expression between two array literals gives an untyped array, which a typed variable refuses at run time. Assign the literals in an `if`.
- Godot stores mesh normals packed; they come back changed in the fifth decimal place.
- Assign a `Variant` to a typed local before passing it to a GUT assertion.
- Never name a class enum `Variant`: a field typed with it reads as the built-in type and every call that passes it fails strict compilation.

Report completed runs in the delivery message and commit body. Keep raw logs,
captures and per-run provenance outside the repository.

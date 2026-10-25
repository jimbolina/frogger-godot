# Testing and visual checks

## Required commit gate

Run both modes before every commit, including documentation changes.
Use the wrappers: they import, strictly compile every script, check architecture,
validate retail input, run GUT, then verify the saved result report against the
log and process exit.
Stop on a failed stage; fix it before starting subsequent checks.

```powershell
$env:GODOT = 'C:\Users\janit\Desktop\Godot.exe'
$env:FROGGER_DATA_DIR = 'C:\Users\janit\Desktop\repos\froggy\resources\pc-version\extracted\FROGGER'
& .\tools\run_tests.ps1
# Continue only after exit 0.
Remove-Item Env:FROGGER_DATA_DIR
& .\tools\run_tests.ps1
# Expect exit 3 only for named retail-dependent skips, with no failures.
```

For Bash, use `GODOT=/path/to/godot FROGGER_DATA_DIR=/path/to/retail tools/run_tests.sh`,
then run again with `FROGGER_DATA_DIR` unset. Commands run from the repository root.
Exit codes: 0 = all passed; 1 = test, compile, architecture or result failure;
2 = setup failure; 3 = only approved asset-free skips. A skip is never a pass.
Retail mode must have none. A supplied but invalid `FROGGER_DATA_DIR` fails;
unset the variable explicitly for asset-free mode.

## Feature checks

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
  world and full-window captures. `--data-dir <game-folder> --level ORG1`
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
- [Golden specifications](../../../tests/golden/README.md): expected-data schemas
  and independent generator commands, grouped by feature.
- [ORG1 admission checks](../../../tests/golden/specs/entities.md#org1-admission-counterexample):
  independent background diagnostics and the [bounded route proof](../../../tests/golden/specs/entities.md#org1-route-proof).
  The older general-pose diagnostic remains blocked; the narrower route has
  its own complete proof and pinned inputs.

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

`tests/support/retail_skips.json` is the reviewed manifest of exact test
identities and their sole allowed reason: `FROGGER_DATA_DIR` is unset. Add a
retail test deliberately to this manifest and its inventory assertion; neither
inheritance nor residence under `tests/golden/` grants skip permission.
Pending tests and unexpected script skips fail, as do fixture/runner errors.

The GUT hook saves `user://test_results.json` in the isolated profile and prints
the named outcomes and summary. The wrapper's independent validation stage
recounts those records and checks the environment mode, named skips, summary
and process exit. Missing, duplicate, inconsistent or empty reports fail.
Retain the printed run folder for diagnosis; never convert arbitrary exit 3
results to success in an external runner. Hosted CI remains deferred.

Use isolated writable Godot user data, explicit logs, awaited hidden
processes and `--disable-crash-handler` for automated runs. The wrappers
already enforce this and retain log paths in their output. Do not bypass
them with a bare automated Godot launch; determine success from
compilation/tests and exit status.

## Tools and visual verification

The game implementation is GDScript. `tools/*.c` files are offline validation
adapters that call unchanged frozen reference objects and emit text facts;
they are not loaded by the game. Their builders need a developer compiler,
but normal runtime use and the Godot test suites do not build or load them.

- Godot 4.5.1 Compatibility: `C:\Users\janit\Desktop\Godot.exe`.
  Its windowed executable does not reliably print to a console; use log files.
- Python: `C:\Python313\python.exe`; MSYS2 tools are also available.
- GUT 9.5.0 is vendored in `addons/gut/`.
- Visually inspect visual changes. Store screenshots outside the repository.
  Hash agreement establishes decoding, not appearance.
- All viewers require absolute capture folders outside the checkout. Output
  creation/write failures report the path and exit nonzero. Shared validation
  normalizes lexical paths; callers must not use filesystem links to redirect
  an external destination into the checkout.
- After changing Godot, renderer or environment, run `tools/probe_model_shader.gd`
  with a window and inspect the measured colours; see [rendering](../rendering/README.md).
- Every new golden family needs an independent generator and a deliberate-break
  check, with the original fact restored. See [golden rules](../../../tests/golden/README.md).

## GDScript and runner pitfalls

- GUT's loader does not enforce strict typing. `tools/check_scripts.gd` is the only headless check that every script compiles with warnings as errors.
- Godot's `--import` compiles nothing.
- Files with extensions Godot does not treat as resources (`.cfg`, `.tsv`) need an include filter in export presets.
- Running the boot scene saves the data folder to `user://settings.cfg`. Delete that file to test first-run behaviour.
- A headless run draws nothing, so anything that reads the screen (`tools/probe_model_shader.gd`, the viewers' screenshot mode) needs a window and is not part of the test run.
- A test script must not name a helper `_compare`: GUT has a member of that name.
- A conditional expression between two array literals gives an untyped array, which a typed variable refuses at run time. Assign the literals in an `if`.
- Godot stores mesh normals packed; they come back changed in the fifth decimal place.
- Assign a `Variant` to a typed local before passing it to a GUT assertion.

Report completed runs in the delivery message and commit body. Keep raw logs,
captures and per-run provenance outside the repository.

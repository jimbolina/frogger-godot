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
- [Golden specifications](../../../tests/golden/README.md): expected-data schemas
  and independent generator commands, grouped by feature.

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

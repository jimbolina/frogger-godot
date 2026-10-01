# Domain foundation validation

## Baseline (2026-10-01)

Started from `6329cf3` with only the untracked domain proposal present. Godot
4.5.1 Compatibility on Windows; all baseline runs used the PowerShell wrapper,
isolated writable profiles, explicit logs and disabled crash handling.

| Run | Strict scripts | Result | Wall time |
|---|---:|---|---:|
| Retail | 131 | 297 passed, 0 failed, 0 skipped; exit 0 | 105.34 s |
| Asset-free | 131 | 246 passed, 0 failed, 51 named skips; exit 3 | 22.01 s |
| Focused `-gselect=test_model_viewer` | 131 | 10 passed; exit 0 | 18.44 s |

Baseline log folders under `%LOCALAPPDATA%/Temp/`:
`frogger-tests-9412cac0221640aca6d7254ca042a2b7`,
`frogger-tests-64b3317d6ca441e48a4572221e0a281f`, and
`frogger-tests-56ab8be8ff2b406684d8c06ecbd84313`, respectively.
These are local measurements, not performance thresholds.

Ownership reproduction before the fix: instantiate two viewers with
`auto_open = false`, attach the same open `GameData` to both, free one viewer,
then read an uncached archive resource through the survivor. Each viewer's
exit handler unconditionally closes the shared archive. Model and texture
replacement also omit closing data they opened. The new lifetime tests encode
these steps with synthetic archive data. No historical bug-reproduction timing
was available; the baseline records the steps rather than inventing a duration.

Capture artifacts live outside the repository at
`C:/Users/janit/.codex/visualizations/2026/10/01/01a0f94d-7d02-7993-9d81-c3efe4c6aa2d/foundation/`.

## Final checks

Both final PowerShell wrapper modes passed strict compilation and architecture
checks for 141 scripts, followed by verified machine/log/process agreement:

| Mode | Result | GUT time |
|---|---|---:|
| Retail | 350 passed, 45,199 assertions, zero failures/skips; exit 0 | 78.212 s |
| Asset-free | 299 passed, 2,197 assertions, 51 approved skips; exit 3 | 1.667 s |

Final log folders under `%LOCALAPPDATA%/Temp/` are
`frogger-tests-80adc6254e4d4fe3ba37e49b2c6d43bb` (retail) and
`frogger-tests-c17a7f06d4bc4b65baa1ff1a384575b3` (asset-free).
The retail stage log interval was 100.50 s; the asset-free wrapper stopwatch
was 24.81 s. Stage/GUT times exclude some wrapper overhead and should not be
treated as directly comparable to the baseline wrapper stopwatch.
All existing retail golden comparisons and the 78 map/detail resource switches
passed. No new golden family is introduced; existing facts remain unchanged.

## Guardrails and viewer evidence

- Architecture scenarios: 22 passed, 62 assertions. A temporary legacy script
  containing `var forbidden: Node` compiled, then failed the architecture stage
  at its exact line with exit 1 before GUT. The probe and generated UID were
  removed; the clean check passed. Failure log: `frogger-tests-c2c6bb90b308465dacd2a71c6e86b747`.
- Result policy scenarios: 15 passed, including malformed/missing summaries,
  unexpected skips, pending tests, empty selections and report/exit disagreement.
  Both PowerShell and MSYS Bash ran these successfully. The Bash focus took
  23.65 s; its isolated run folder is `frogger-tests.e56fdL` under the authorized
  visualization root above (outside the `foundation` subfolder).
- End-to-end PowerShell probes returned exit 1 for a temporary pending test,
  an empty selection and an invalid supplied retail folder. A single selected,
  reviewed retail test returned exit 3 with exactly one named skip. The temporary
  test and UID were removed. Probe console logs are
  `foundation-policy-{pending,empty,invalid-input,retail-skip}.log` under that
  visualization root. A malformed GUT invocation also failed for a missing report.
- The final model-viewer focus passed 12 tests/80 assertions in 23.91 s, versus
  the baseline's 10 tests in 18.44 s. This includes two additional tests and the
  added guardrail stages; it does not isolate their individual costs. Log folder:
  `frogger-tests-cefb0c9ea6a34c13bbf49a998f418d83`.
- Viewer scenarios: 34 passed, including actual synthetic archive reads after
  shared borrowers detach, independent ownership, replacement, reattachment,
  invalid inputs, deferred resource release and expected filesystem failures.
- Successful windowed captures: SUB1 high-detail map slice, GEN_FROG action 0
  at tick 60, and four texture banks. Inspected the map, frog model and SUB_VRAM
  images. The SUB1 PNG is byte-identical before/after, SHA-256
  `313dc84e79587be185e42efd13010808037dbf0a9339a2f2962694eee4d7c667`.
- Actual capture processes rejected a relative texture destination, a model
  destination inside the checkout, a map directory blocked by a regular file,
  and a model PNG destination blocked by a directory. All returned exit 1 with
  the destination and reason. Neither rejected checkout path was created.

The final startup validity checks also preserve a failed `GameData.open` reason
and stop capture mode, rather than continuing with an unusable archive.
Lexical capture containment does not resolve filesystem links; architecture
checking is conservative static analysis, as documented in its contract.

The ownership scenario now runs with one wrapper command,
`tools/run_tests.ps1 -gselect=test_viewer_ownership`; it uses synthetic files and
needs no retail setup. Hosted CI and gameplay timing remain deferred. The Bash
runner creates direct children of its already-created temporary folder, avoiding
unnecessary ancestor probes in restricted environments. The local MSYS invocation
supplied `/usr/bin:/bin` on PATH and a writable `TMPDIR`.

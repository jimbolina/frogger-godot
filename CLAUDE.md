# frogger-godot — CLAUDE.md

Orientation for any session working in this repository. Read this, then `docs/PORTING.md` for the phase plan and status, `docs/FINDINGS.md` for what earlier phases learned, and `docs/REFERENCE_SOURCES.md` for where the reference material is.

## What this project is

A rewrite of **Frogger (1997, the PC release, "Frogger: He's Back")** in **Godot 4.5 with statically typed GDScript**, for Windows, Linux and macOS.

Two requirements shape everything:

1. **The game runs on the player's own retail files, read at run time.** Nothing from the original game is in this repository or in a build of it.
2. **FrogLord stays usable.** FrogLord is the community's Frogger editor. A level, texture, script or table edited and saved in FrogLord must load here. FrogLord saves three files (`modded_FROGPSX.MWD`, `modded_FROGGER.EXE`, `modded_FROGPSX.MWI`) and writes many tables only into the executable, so this project reads every table from the executable it is given.

## Fixed decisions

| Topic | Decision |
|---|---|
| Language | GDScript, statically typed, warnings as errors |
| Fidelity | "Faithful feel": floats and Godot timing are allowed; verified side by side against the reference engine. Not bit-exact. |
| Data | PC retail builds only (`pc-retail-v3.0e` is the reference; `pc-retail-v1.0` and `pc-retail-v3.0e-vogons` through FrogLord's version files). No PlayStation data. |
| Level detail | High-poly maps and models by default, with the matching demo list |
| Targets | Desktop. Web and mobile are out: the game needs large user files from disk. |
| Behaviour | Entity behaviour is code. Entity types, forms and script callbacks map by FrogLord's names to GDScript classes. A mod can re-point existing behaviours; it cannot add new ones. Unknown entries warn, fall back, and are listed in a mod report. |

## Standing rules

- **No retail bytes in the repository, ever.** No executable, archive, texture, model, sound or video, and no excerpt of one. Committed test data under `tests/golden/` is text holding facts only: hashes, sizes, counts, ids, names.
- **Golden data comes from an independent implementation.** The Python generators in `tools/` are written from FrogLord's Java and share no code with the GDScript. Never derive a golden file from the GDScript's own output. How each file is generated is recorded in `tests/golden/README.md`.
- **Where FrogLord and the reference C engine disagree on how data is read, follow FrogLord** and record the disagreement in `docs/FINDINGS.md`. Where they disagree on how the game *behaves*, the reference engine wins: it was matched against the retail PC game.
- **`src/legacy/` has no dependency on nodes or the scene tree.** Its classes extend `RefCounted`, so they are testable headless.
- **One responsibility per class.** Every class and public method has a `##` doc comment saying what it does and why.
- **Plain language in code and docs.** This repository must read cleanly to someone from the Frogger modding community. Do not bring over milestone numbers, ruling ids or other bookkeeping from the reference repository.
- **FrogLord's config files under `third_party/froglord_cfg/` are never edited.** They are unmodified copies; updating them means copying a newer FrogLord's files and recording the commit.
- **Commits:** a plain descriptive summary. Never add a `Co-Authored-By` line or any other attribution to a commit message. Never push; there is no remote.
- **Other repositories:** `../froggy` is read-only reference material. `../frogger-multiplatform` is never touched, read or written.
- **The project's own licence is undecided** and is the owner's decision. Do not add one.

## Running tests

```
FROGGER_DATA_DIR='C:/Users/janit/Desktop/repos/froggy/resources/pc-version/extracted/FROGGER' \
GODOT=/c/Users/janit/Desktop/Godot.exe tools/run_tests.sh
```

The script imports the project, compiles every script strictly (`tools/check_scripts.gd`), then runs GUT headless.

| Exit code | Meaning |
|---|---|
| 0 | Every test passed |
| 1 | A test failed or a script does not compile |
| 2 | Godot was not found |
| 3 | No failure, but some tests were skipped. A skip is never a pass. |

Tests that need the retail files skip by name when `FROGGER_DATA_DIR` is unset. Run both modes before every commit: with the folder set (everything passes, nothing skipped) and unset (asset-free tests pass, the rest skip).

Every new golden family gets a deliberate-break check: change one value, confirm exactly that row fails, restore it.

GUT quirk: assign a `Variant` value to a typed local before passing it to an assert, or strict typing rejects the call.

## Tools on this machine

- Godot 4.5.1: `C:\Users\janit\Desktop\Godot.exe`. The windowed executable does not print reliably to a console; use `--log-file` or write results to a file.
- Python 3 and the MSYS2 tools: `export PATH="/c/msys64/mingw64/bin:$PATH"`.
- Test framework: GUT 9.5.0, vendored in `addons/gut/`.
- No GUI automation is available. Anything that needs FrogLord's window is a hand-off to the owner.

## How work is done here

Work goes phase by phase (`docs/PORTING.md`). Each phase ends in one commit, passes the gate above, updates the README's "what works now", records its status in `docs/PORTING.md`, and adds what it learned to `docs/FINDINGS.md`.

For anything visual, look at the result. Matching hashes prove the decoder agrees with FrogLord; they do not prove the picture is right. Save screenshots outside the repository and inspect them.

## Act. Don't ask.

Reversible and cheap? Do it, then tell me. Research, data pulls, analysis, drafts, refactors inside the scope I gave you, testing an API. A question costs me more than a re-run costs you.

Ask first only for: anything reaching an audience, anything we cannot undo, anything expensive.

Before you hand something back as blocked, try it. Read the API. Check the flag. Run the command. "Can you do X?" when the answer was yes wastes a round trip and buys nothing.

Something is broken? Fix it. Reporting an issue you could have fixed turns your work into my to-do list.

## A question is a question

When I ask a question, answer it. Do not implement it.

"Why is this failing?" is not "make it stop failing." "Should we use X?" is not "migrate everything to X." "What would it take to add Y?" is not "add Y."

When in doubt, assume it is a question. Answer first. Act when I say go. Full freedom about how. None about what.

## Done means done

Not half done. Not done except for the part you decided to skip. Not a report about how it will be done. Five things asked means five things delivered. If the fifth is genuinely blocked, finish the other four and name the specific blocker in one sentence. "I'll continue in the next message" is not a state this project has.

## A report is not an artifact

If it is not in a file in the tree, it does not exist. Findings, measurements, decisions: the file lands first, then you report. Write the file, then say you wrote it. Never the reverse.

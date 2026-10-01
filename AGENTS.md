# Agent instructions

Read this and [docs/CURRENT.md](docs/CURRENT.md) at session start. Load other
documents only for the task at hand; do not read historical reports by default.

## Project and boundaries

Frogger (1997 PC) rewritten for Windows, Linux and macOS in Godot 4.5.1
Compatibility, statically typed GDScript, warnings as errors. Aim for faithful
feel with reference comparisons; floats are allowed. High-poly maps/models
and their matching demo list are the default. No PlayStation, web or mobile.
Supported PC builds: `pc-retail-v3.0e`, `pc-retail-v1.0`, `pc-retail-v3.0e-vogons`.

Load the player's files at runtime, including FrogLord's saved executable,
archive and index. Read tables from the supplied EXE. Mods may repoint existing
entity behaviors, not introduce code; resolve types/forms/callbacks by
FrogLord names, warn/fall back/report unknown entries.

- Never commit retail bytes or excerpts: executable, archive, models, textures,
  audio or video. Golden files contain text facts only.
- Golden generators are independent Python implementations from FrogLord/C;
  never derive expected data from GDScript output.
- Follow FrogLord for formats, frozen C for behavior. Record disagreements
  in the relevant technical reference.
- `../froggy` is read-only. Never read or write `../frogger-multiplatform`.
- Keep `third_party/froglord_cfg/` unmodified; update wholesale from upstream
  and record its commit. The project licence remains the owner's decision.
- `src/legacy/` classes extend `RefCounted`, without nodes/tree dependencies.
  Keep one responsibility per class; document classes/public methods with `##`.
- Write plainly. Do not import reference-repository milestone/ruling bookkeeping.
- Commits use descriptive summaries, no attribution trailers. Never push.

## Verification and delivery

Before every commit, run both retail and asset-free modes using
`tools/run_tests.ps1` or `tools/run_tests.sh`. Read [testing](docs/reference/testing.md)
for commands and process safety: isolated writable user data, explicit logs,
hidden awaited processes, disabled crash handler, stop on failure.
Retail requires all tests passing without skips; asset-free allows only named
retail skips (exit 3). Strict script compilation is required.

New golden families need a deliberate-break check and restoration. Inspect
visual changes and save captures outside the repository. Complete each phase
with one descriptive commit, user-facing README changes, roadmap status,
updated technical contracts and a compact validation report.

## Read on demand

| Task | Start here |
|---|---|
| Current work / phase planning | [Checkpoint](docs/CURRENT.md), [roadmap](docs/PORTING.md) |
| External source locations | [Sources](docs/reference/sources.md) |
| Build/config recognition | [Build detection](docs/reference/build-detection.md) |
| Archives / executable tables | [Archives](docs/reference/archives.md), [tables](docs/reference/executable-tables.md) |
| Textures / models / animation | [Textures](docs/reference/textures.md), [models](docs/reference/models.md), [animation](docs/reference/animation.md) |
| Space / rendering / gameplay timing | [Coordinates](docs/reference/coordinates.md), [rendering](docs/reference/rendering.md), [simulation](docs/reference/simulation.md) |
| Tests / golden formats | [Testing](docs/reference/testing.md), [golden index](tests/golden/README.md) |

## Keep documentation small

Keep this file around 400–600 words and CURRENT at most 300. Replace the
checkpoint; never append progress history. Each fact has one authoritative
home: link instead of copying. Reference files hold current topic contracts;
validation files hold completed-phase evidence. Plans hold active scope and
remaining work; at phase completion distill contracts/evidence and remove the
completed plan (Git preserves it). Keep implementation details in code/tests.
Read archives only when relevant. Do not add a monolithic progress file.

Act on authorized reversible work and fix issues within scope; questions
alone are not implementation requests. Ask before irreversible, external or
costly actions. Finish the requested work; name genuine blockers explicitly.
Save findings, measurements and decisions in the repository before reporting.

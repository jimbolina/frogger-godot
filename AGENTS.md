# Agent instructions

Read this and [docs/CURRENT.md](docs/CURRENT.md) at session start.

## Project and boundaries

Frogger (1997 PC) rewritten for Windows, Linux and macOS in Godot 4.5.1
Compatibility, statically typed GDScript, warnings as errors. Verify faithful
feel against references; floats are allowed. Default to high-poly maps/models
and matching demos. No PlayStation, web or mobile.
Compatibility target: `pc-retail-v3.0e`, including FrogLord-saved edits based on
that build. Other PC builds are outside the current compatibility scope.

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
- `src/source/` classes extend `RefCounted`, without nodes/tree dependencies.
  Keep one responsibility per class; document classes/public methods with `##`.
- Keep only genuine docstrings in project code, plus required directives and
  licence notices. Omit ordinary comments.
- Write plainly. Do not import reference-repository milestone/ruling bookkeeping.
- Commits use descriptive summaries, no attribution trailers. Never push.

## Verification and delivery

Delegate independent implementation, investigation and review to sub-agents
without asking again. Use Sol or Opus appropriate to the orchestrator. Assign clear scopes and file ownership, avoid overlapping
edits, and have the orchestrator integrate and verify the complete result.

Before every commit, run both retail and asset-free modes using
`tools/run_tests.ps1` or `tools/run_tests.sh`. Read [testing](docs/reference/testing/README.md)
for commands and process safety: isolated writable user data, explicit logs,
hidden awaited processes, disabled crash handler, stop on failure.
Retail requires all tests passing without skips; asset-free allows only named
retail skips (exit 3). Strict script compilation is required.

New golden families need deliberate-break checks and restoration. Inspect
visual changes; save captures externally. Complete each phase with one
descriptive commit and update affected user documentation, roadmap and technical
contracts. Report tests in delivery messages and commit bodies; keep raw logs
external.

## Read on demand

| Task | Start here |
|---|---|
| Current work | [Checkpoint](docs/CURRENT.md), [roadmap](docs/PORTING.md) |
| Data, gameplay and rendering | [Domain index](docs/reference/domain.md), [architecture](docs/reference/architecture.md) |
| External sources | [Sources](docs/reference/sources.md) |
| Verification | [Testing](docs/reference/testing/README.md), [golden index](tests/golden/README.md) |

## Keep documentation small

Keep this file around 400–600 words and CURRENT at most 300. Replace CURRENT
with current capability, next work and blockers; never append history. PORTING
owns roadmap status; README owns user instructions. References own behavior,
formats, limitations and source disagreements. Golden schemas and reproduction
belong beside their tests. Give each fact one home; link instead of copying.

Extend existing subject files unless a new topic has a distinct responsibility;
link new topics from the domain index or testing guide. Do not create milestone
reports, validation directories, retrospectives, audit journals or duplicate
plans. Keep implementation details in code/tests. Test counts, timings, hashes
and session paths belong in external logs or commit messages. Document only
measurements defining current behavior or compatibility limits, with context.
Git owns history.

Before delivery, check links and remove obsolete or duplicate prose.

Act on authorized reversible work within scope. Questions alone are not
implementation requests. Ask before irreversible, external or costly actions.
Finish requested work; name genuine blockers. Save durable findings and
decisions in their owning topic before reporting.

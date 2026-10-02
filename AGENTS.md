# Agent instructions

Read this and [docs/CURRENT.md](docs/CURRENT.md) at session start. Load other
documents only for the task at hand.

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
`tools/run_tests.ps1` or `tools/run_tests.sh`. Read [testing](docs/reference/testing/README.md)
for commands and process safety: isolated writable user data, explicit logs,
hidden awaited processes, disabled crash handler, stop on failure.
Retail requires all tests passing without skips; asset-free allows only named
retail skips (exit 3). Strict script compilation is required.

New golden families need a deliberate-break check and restoration. Inspect
visual changes and save captures outside the repository. Complete each phase
with one descriptive commit and update affected user-facing documentation,
roadmap status and technical contracts. Report test results in the delivery
message and commit body; keep raw logs outside the repository.

## Read on demand

| Task | Start here |
|---|---|
| Current work | [Checkpoint](docs/CURRENT.md), [roadmap](docs/PORTING.md) |
| Data, gameplay and rendering | [Domain index](docs/reference/domain.md), [architecture](docs/reference/architecture.md) |
| External sources | [Sources](docs/reference/sources.md) |
| Verification | [Testing](docs/reference/testing/README.md), [golden index](tests/golden/README.md) |

## Keep documentation small

Keep this file around 400–600 words and CURRENT at most 300. CURRENT holds only
the current capability, next work and blockers; replace it, never append history.
PORTING owns roadmap status and remaining work. README owns user instructions.
Reference files explain current behavior, formats, limitations and source
disagreements. Golden schemas and reproduction belong
beside the golden tests. Each fact has one home; link instead of copying.

Before adding a document, extend the existing subject file unless the new topic
has a distinct responsibility. Name new files for that topic and link them from
the domain index or testing guide. Do not create phase/milestone reports,
validation directories, retrospective summaries, audit journals or duplicate
plans. Keep implementation details in code/tests. Test counts, timings, run
hashes and session paths belong in external logs or commit messages. Preserve
only measurements that define a current behavior or compatibility limit, in
the matching topic file with enough context to interpret them. Git owns history.

Before delivery, check links and remove obsolete or duplicate prose.

Act on authorized reversible work and fix issues within scope; questions
alone are not implementation requests. Ask before irreversible, external or
costly actions. Finish the requested work; name genuine blockers explicitly.
Save durable domain findings and decisions in their owning topic before reporting.

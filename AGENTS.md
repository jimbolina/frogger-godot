# Agent instructions

Read this and [docs/CURRENT.md](docs/CURRENT.md) at session start.

## Project and boundaries

Frogger (1997 PC) rewritten for Windows, Linux and macOS in Godot 4.5.1
Forward+, statically typed GDScript, warnings as errors. Verify faithful
feel against references; floats are allowed. Default to high-poly maps/models.
No PlayStation, web or mobile.

The game plays from committed assets under `assets/`, imported once from the
owner's `pc-retail-v3.0e` copy and edited directly afterwards. `archive/`
holds the retail readers, the importer, the retail-format goldens and
FrogLord's configuration; nothing under `src/`, `scenes/`, `assets/`,
`tests/` or `tools/` may depend on it, except the one runtime-import seam
(`src/application/setup/asset_importer_factory.gd`). Packaged builds import
the player's own copy at first run; FrogLord saves import as overlays. Mods may repoint
existing entity behaviors, not introduce code.

- Commit retail-derived content only as imported assets under `assets/`
  (binaries through Git LFS); never the executable, archives, disc images or
  videos. The repository stays private.
- Golden generators are independent Python implementations from FrogLord/C;
  never derive expected data from GDScript output. Hand-edited assets get
  reviewed golden overrides.
- Follow FrogLord for the archive formats, frozen C for behavior. Record
  disagreements in the relevant technical reference.
- `../froggy` is read-only. Never read or write `../frogger-multiplatform`.
- Keep FrogLord's configuration files unmodified; update wholesale from
  upstream and record the commit. The licence remains the owner's decision.
- `src/game`, `src/application` and the archive readers extend `RefCounted`;
  `src/data` records extend `Resource`; none depend on nodes or the tree.
  Keep one responsibility per class; document classes/public methods with `##`.
- Keep only genuine docstrings in project code, plus required directives and
  licence notices. Omit ordinary comments.
- Write plainly. Do not import reference-repository bookkeeping.
- Commits use descriptive summaries, no attribution trailers. Never push.

## Verification and delivery

Delegate independent implementation, investigation and review to Opus
sub-agents without asking again, with clear scopes and non-overlapping file
ownership; the orchestrator integrates and verifies the whole result.

Before every commit that touches code, tests, goldens, assets, tools or
project configuration, run `tools/run_tests.ps1` or `tools/run_tests.sh` with
`FROGGER_DATA_DIR` set, so the game suite and the archive suite both run;
documentation-only commits need no run. Read
[testing](docs/reference/testing/README.md) for commands and process safety.
Every test passes with no skips; exit 0 is the only pass. Strict script
compilation is required.

New golden families need deliberate-break checks and restoration. Inspect
visual changes; save captures externally. Level acceptance is the owner's play
check: give the `tools/play.sh` command and what to look for; never search routes,
machine-read gameplay or request input recordings. Complete each phase with one
descriptive commit and update affected documentation. Report tests in delivery
messages and commit bodies; keep raw logs external.

## Read on demand

| Task | Start here |
|---|---|
| Current work | [Checkpoint](docs/CURRENT.md), [roadmap](docs/PORTING.md) |
| Data, gameplay and rendering | [Domain index](docs/reference/domain.md), [architecture](docs/reference/architecture.md) |
| Assets and the archive | [Assets](docs/reference/assets.md), [archive](archive/README.md) |
| External sources | [Sources](docs/reference/sources.md) |
| Verification | [Testing](docs/reference/testing/README.md), [golden index](tests/golden/README.md) |

## Keep documentation small

Keep this file around 400–600 words and CURRENT at most 300. Replace CURRENT
with current capability, next work and blockers; never append history. PORTING
owns roadmap status; README owns user instructions. References own behavior,
formats, limitations and source disagreements. Golden schemas belong beside
their tests. Give each fact one home; link instead of copying.

Extend existing subject files unless a new topic has a distinct responsibility;
link new topics from the domain index or testing guide. No milestone reports,
retrospectives, audit journals or duplicate plans. Test counts, timings,
hashes and session paths belong in external logs or commit messages. Git owns
history.

Act on authorized reversible work within scope. Questions alone are not
implementation requests. Ask before irreversible, external or costly actions.
Finish requested work; name genuine blockers. Save durable findings in their
owning topic before reporting.

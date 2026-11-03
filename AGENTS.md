# Agent instructions

Read this and [docs/CURRENT.md](docs/CURRENT.md) at session start.
`CLAUDE.md` only imports this file.

## Project and boundaries

Frogger (1997 PC) rewritten for Windows, Linux and macOS in Godot 4.5.1
Forward+, statically typed GDScript, warnings as errors. Verify faithful
feel against references; floats are allowed. Default to high-poly maps/models.
No PlayStation, web or mobile.

The game plays from `assets/`, each developer's own import of their
`pc-retail-v3.0e` copy (`tools/setup_dev.sh --import`), never committed;
`content/` holds the port's own and community files. `archive/` holds the
retail readers, the importer, the retail goldens and FrogLord's
configuration; nothing under `src/`, `scenes/`, `assets/`, `tests/` or
`tools/` may depend on it except the runtime-import seam
(`src/application/setup/asset_importer_factory.gd`). Packaged builds import
the player's copy at first run; FrogLord saves import as overlays. Mods may
repoint existing entity behaviors, not introduce code.

- Never commit retail-derived content: imported assets, the executable,
  archives, disc images or videos. The repository is public. Change imported
  content through the importer, FrogLord overlays or texture packs.
- Golden generators are independent Python implementations from FrogLord/C;
  never derive expected data from GDScript output.
- Follow FrogLord for the archive formats, frozen C for behavior. Record
  disagreements in the relevant technical reference.
- `../froggy` is read-only. Never read or write `../frogger-multiplatform`.
- Keep FrogLord's configuration files unmodified; update wholesale from
  upstream and record the commit. The licence remains the owner's decision.
- `src/game`, `src/application` and the archive readers extend `RefCounted`;
  `src/data` records extend `Resource`; none depend on nodes or the tree.
  One responsibility per class; document classes and public methods with `##`.
- Keep only genuine docstrings, required directives and licence notices in
  project code. Omit ordinary comments.
- Write plainly. Do not import reference-repository bookkeeping.
- Commit summaries are descriptive with a Conventional Commits type (`feat:`,
  `fix:`, `docs:`, `chore:`, `ci:`, `refactor:`, `test:`; `!` for breaking)
  and no attribution trailers. Never push. Only the release pull request
  changes `config/version` and `CHANGELOG.md`.

## Verification and delivery

Delegate independent implementation, investigation and review to Opus
sub-agents without asking again, with clear scopes and non-overlapping file
ownership; the orchestrator integrates and verifies the whole result.

Before every commit that touches anything but documentation, run
`tools/run_tests.ps1` or `tools/run_tests.sh` with `FROGGER_DATA_DIR` set and
`assets/` imported, so all three suites run. Every test passes with no skips;
exit 0 is the only pass. Strict script compilation is required.

New golden families need deliberate-break checks and restoration. Inspect
visual changes; save captures externally. Level acceptance is the owner's
play check: give the `tools/play.sh` command and what to look for; never
search routes, machine-read gameplay or request input recordings. Complete
each phase with one descriptive commit and update affected documentation.
Report tests in delivery messages and commit bodies; keep raw logs external.

## Read on demand

| Task | Start here |
|---|---|
| Current work | [Checkpoint](docs/CURRENT.md), [roadmap](docs/PORTING.md) |
| Setup, layout, packaging | [Developer setup](docs/reference/developer-setup.md), [first-run setup](docs/reference/setup.md) |
| Data, gameplay and rendering | [Domain index](docs/reference/domain.md), [architecture](docs/reference/architecture.md) |
| Assets and the archive | [Assets](docs/reference/assets.md), [archive](archive/README.md) |
| External sources | [Sources](docs/reference/sources.md) |
| Verification | [Testing](docs/reference/testing/README.md), [inspection tools](docs/reference/testing/inspection-tools.md), [golden index](tests/golden/README.md) |

## Keep documentation small

Keep this file around 400–600 words and CURRENT at most 300. CURRENT holds
current capability, next work and blockers, never history. PORTING owns
roadmap status. README is for players and newcomers: what the port is, how
to play, how to start contributing, where the docs are. References own
behavior, formats, limitations, tools and source disagreements. Golden
schemas belong beside their tests. Give each fact one home; link instead of
copying. Extend existing subject files unless a topic has a distinct
responsibility, and link new topics from the domain index or testing guide.
No milestone reports, retrospectives, audit journals or duplicate plans. Test
counts, timings, hashes and session paths belong in external logs or commit
messages. Git owns history.

Act on authorized reversible work within scope. Questions alone are not
implementation requests. Ask before irreversible, external or costly actions.
Finish requested work; name genuine blockers. Save durable findings in their
owning topic before reporting.

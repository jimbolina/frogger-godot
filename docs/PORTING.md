# Porting plan and status

The game is rebuilt in phases. Each phase is independently demonstrable and has a stated exit check. Sizes are relative: S, M, L, XL.

The original is roughly 80,000 lines of C game code. About 24,000 lines of GDScript under `src/` cover the data formats, rendering, terrain movement and a bounded part of the entity system. The C still to port (entities, script interpreter, HUD, game flow, front end, saves, sound, effects) is about 53,000 lines, so the finished port is estimated at 45,000 to 60,000 lines. The first milestone that matters is one complete playable level, at the end of P8c.

## Status

P8 is split into exit-sized pieces, and P10 (level loop and HUD) runs before P9 because a level is not playable without checkpoints, a timer, lives and level-complete flow. Cross-cutting work has its own rows (X1–X3).

| # | Phase | Size | Checked against | Status |
|---|---|---|---|---|
| P0 | Project, test runner, data locator, FrogLord config parser, build detection | S | Unit tests | Done, `d4f3920` |
| P1 | MWI index, MWD archive, PP20, WADs | M | SHA-256 of every file and WAD child from an independent Python reader | Done, `37533f2` |
| P2 | Every table in the executable | M | Independent Python reader; byte and value comparison with the reference engine's extracted tables | Done, `0f03972` |
| P3 | Texture banks (VLO) and a texture viewer | S | Per-image hashes; screenshots inspected | Done, `bf6d356` |
| P4 | Static models (MOF) and a model viewer | L | Counts and digests of every part from an independent Python reader; measured screen colours; screenshots inspected | Done, `b3188cd` |
| P5 | Animated models, flipbooks, texture animation | L | Independent animation facts, every retail action, C matrix hashes and inspected animation sequences; optional presentation smoothing | Done, `957b9a0` |
| P6 | Map parsing and rendering, camera | L | The reference engine's map pictures, with tolerance. Includes a first load of a FrogLord-saved map. | Done |
| P7 | Grid, frog movement, camera, collision, deaths | XL | Independent grid facts and per-tick traces; calibrated visual comparisons | Done; frozen C port at 30 Hz |
| P8a | Behaviour catalog and typed tick outbox | M | Every existing golden unchanged; architecture scanner rejects entity-name string dispatch in `src/game` | Next |
| P8b | Demo playback harness | S–M | This project's per-tick trace in the reference CSV layout compared with the reference engine's attract-demo traces | |
| P8c | ORG1 complete: every original-theme and general form, all script opcodes and callbacks, per-build FORM callbacks, all death types, checkpoints, pink frog delivery, tongue, whole-map visibility and zones | L | The ORG1 attract demo replays to the reference end state; ORG1 is playable by keyboard through five checkpoints | Bounded corridors only: 9 of 121 entity types, 16 of 49 opcodes, 15 of 125 scripts, 4 of 24 script callbacks, 2 of 8 death types, no FORM callbacks |
| P8d | Inspection module split: guards, presets, scenario options and manifests leave the gameplay and setup layers | S | Scanner and both test modes | |
| P10 | Level loop and HUD: shared gameplay host, game scene, HUD/score/timer/lives/font, checkpoint flow, level complete, game over, selective reset, generic camera zones | L | ORG1–ORG5 and SUB1 playable start to finish; SUB1 and ORG1 attract demos run to completion with the same end state | |
| P9 | The remaining seven themes, one sub-phase each: FOR and VOL (attract demos exist), then CAV, DES, JUN, SWP, SKY | XL | A checklist per level; demo or reference-engine trace per theme | |
| P11 | Effects and particles | L | By eye against reference pictures | |
| P12 | Sound banks and music: PC sound-bank reader with an independent golden, then playback of the typed sound events | M | Reader golden; by ear | |
| P13 | Front end, level select, options, saves, high scores | XL | A flow checklist; reference pictures of the options pages | Largest remaining block, about 17,000 lines of C |
| P14 | FrogLord round trip and reload on change, with a report of unmapped forms, scripts and callbacks | M | An edited map, script, remap and demo all load; a repointed behaviour loads without code | Loading half exists |
| P15 | Split-screen for two to four players | L | By eye | |
| P16 | Videos, credits, ending | M–L | By eye | Blocked on the FMV codec decision below |
| P17 | Export for Windows, Linux and macOS; hosted asset-free CI pinned to Godot 4.5.1 | S–M | A run on a clean machine; one verified CI runner with retained logs and named skips | Mac source setup and isolated verification available; packaged exports and CI pending |
| X1 | Performance acceptance gate | S each | Measured on an idle system at each playable milestone (P8c, P10, end of P9); see [inspection](reference/testing/terrain-inspection.md) | Launcher and profiling exist; 200+ FPS at 1440p on the owner's machine is the target |
| X2 | [Animated per-part lighting](reference/rendering/gameplay-projection.md) | M | Independent colour samples after each part's animation transform | Any time after P8a |
| X3 | Owner decisions | | | See below |

Network play is deferred. Multiplayer levels belong to P15.

## Needed from the owner

| What | Needed by | Why |
|---|---|---|
| A licence for this project's own code | Before the repository is made public | |
| A repository host | Before P17's CI | CI needs a runner and retained logs |
| A decision on the FMV videos | Before P16 | The videos are ARMovie `.RPL` files with the Escape codec; Godot has no decoder. Either a decoder is written (GDScript or GDExtension) or the videos are skipped with a documented stub. |

## Next: DDD refactor, then P8b and P8c

Complete the DDD refactor before feature expansion: ownership/copy contracts,
named constants and typed events, behavior resolution, source/application/inspection
boundaries, composed gameplay state, frog extraction, reusable host and reference
cleanup. Each part has a separate commit and full verification gate.
The entity candidate API, discovered value-copy contracts, named source
constants and typed tick events are implemented; the remaining parts are pending. P8d moves into this refactor rather than waiting
for ORG1 completion.

P8a resolves each entity to one behaviour value in setup, from FrogLord names,
with a documented fallback and diagnostic for unknown names; the game layer
dispatches on that value instead of name strings. Tick requests and events
become typed values with a text projection so existing goldens stay identical.
Named mode and flag catalogs replace raw bit tests. `EntityRun` gets a
candidate/commit API and one test checks every state copy is complete.
This is behaviour-preserving and is what makes "mods repoint behaviours"
possible.

P8b parses the demo input files already located by the demo table, feeds them
as tick commands and compares this project's trace with the reference engine's
attract-demo traces on end state and path. It is the acceptance test for P8c,
P10 and every theme in P9.

P8c completes ORG1 as listed in the table. The guarded JUN1 and ORG1 corridor
presets and their admission manifests are scaffolding: they proved the
transaction, ordering and visibility rules on bounded routes, and they retire
when ORG1 plays whole. Route facts stay in the
[entity contract](reference/gameplay/entities.md) and the golden specifications.

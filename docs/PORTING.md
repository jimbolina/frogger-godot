# Porting plan and status

The game is rebuilt in phases. Each phase is independently demonstrable and has a stated way of checking it. Sizes are relative: S, M, L, XL.

The original is roughly 80,000 lines of C game code. The estimate for this project is 35,000 to 45,000 lines of GDScript. The entity, frog and front-end phases dominate. The first milestone that matters is one playable level, at the end of P8.

## Status

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
| P8 | Entity framework, paths, zones, script interpreter, the general theme plus the original and suburbia themes | XL | First levels of those themes playable | In progress: paths, STATIC/MOVING transforms, bounded POP/SAFE, guarded JUN1 bank/log exploration, decoded zone queries and opt-in script-free visibility lifecycle |
| P9 | The remaining seven themes | XL | A checklist per level | |
| P10 | HUD, score, timer, game flow, checkpoints, demo playback | L | Attract demos run to completion with the same end state | |
| P11 | Effects and particles | L | By eye | |
| P12 | Sound banks and music | M | By ear | |
| P13 | Front end, level select, options, saves, high scores | XL | A flow checklist | |
| P14 | FrogLord round trip and reload on change | M | An edited map, script, remap and demo all load | |
| P15 | Split-screen for two to four players | L | By eye | |
| P16 | Videos, credits, ending | M | | |
| P17 | Export for Windows, Linux and macOS | S | A run on a clean machine | |

Network play is deferred.

The graphics follow-up for [animated per-part lighting](reference/rendering/gameplay-projection.md)
needs source light/color matrices applied after each part's animation transform,
with independent color samples. Existing static-probe prelighting does not
provide this. P7's declared foreground checks cover geometry and silhouette;
the visible color difference remains explicit.

## Needed from the owner

| What | Needed by | Why |
|---|---|---|
| A licence for this project's own code | Before the repository is made public | |

## Next: entities and the first playable level

The [bounded entity reactions](reference/gameplay/entities.md) include POP,
platform landing, centring, carrying, local hops, departure and camera attachment.
Other lethal reactions, entity-specific sliding/bouncing and primitive collision
remain unimplemented. P8 remains in progress; complete level play is unfinished.
Live keyboard terrain exploration is available through the [terrain viewer](../README.md).
Opt-in visibility lifecycle now covers script-free generic entities on zero-zone
maps within its selected-group budget guard; the demonstrated camera sequence
is synthetic. Guarded JUN1 exploration connects safe terrain to a moving log
and back, with all-attached lifetime and transactional world/zone restrictions.
Complete level collision still needs scripts, active zones, custom and
immortal behaviors, selective game-flow reset and broader visibility workloads.
FOR1's automatic retail lifecycle sequence remains unverified.
The ORG1 bank/turtle/log proof now closes the animated frog-probe and
excluded-neighbor obligations for a narrower rectangle. Independent traces
cover the normal round trip, full dive/rise cycles and an attached-diver death.
The [entity contract](reference/gameplay/entities.md#org1-admission) owns
bounds, routes and the expanded script/background closure. Next are bounded
script components, source-ordered atomic integration and guarded live
exploration, with independent goldens and rendered/keyboard acceptance.
A complete playable level is still required.
Resolve callbacks through verified names and supported implementations;
preserve source ordering and test unknown mappings. Per-build form callback
address mappings still need investigation.
Mods may repoint supported behaviors but never load new code.

Extend current entity diagnostics and inspection as behaviors are added. Use the first additional behavior
to check that the registry and setup adapters stay small, then reassess at the
first playable level.

Measure tick/load/conversion costs and resource counts as real level workloads
arrive. Keep captures outside the repository; do not impose limits from
uncalibrated shared runners. Add progression, save and reload boundaries with
their owning features.

## Infrastructure

When a repository host is selected, add asset-free CI pinned to Godot 4.5.1,
starting with one verified desktop runner. Retain logs, enforce named skips,
and keep legally held retail data in local/private gates.

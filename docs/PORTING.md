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
| P6 | Map parsing and rendering, camera | L | The reference engine's map pictures, with tolerance. Includes a first load of a FrogLord-saved map. | Done; [validation](validation/p6.md) |
| P7 | Grid, frog movement, camera, collision, deaths | XL | Side by side; the reference engine's per-tick traces within tolerance | |
| P8 | Entity framework, paths, zones, script interpreter, the general theme plus the original and suburbia themes | XL | First levels of those themes playable | |
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

## Needed from the owner

| What | Needed by | Why |
|---|---|---|
| A licence for this project's own code | Before the repository is made public | |

## Planning the next phase

Start with [the current checkpoint](CURRENT.md). P6 is complete, including
the owner's saved JUN1 terrain edit; see the [validation report](validation/p6.md).
Plan P7 against current code and frozen per-tick traces. P7 settles retail
timing, grid movement, gameplay camera, collision and deaths; P8 adds entity
placement and is the first playable-level milestone.

## Completed-phase evidence

Read these only when checking a historical result or reproducing a comparison:
[archives (P1)](validation/p1.md), [textures (P3)](validation/p3.md),
[models (P4)](validation/p4.md), [animation (P5)](validation/p5.md),
[maps (P6)](validation/p6.md).
P0/P2 checks and generator cross-checks are documented in the
[testing guide](reference/testing.md) and [golden specifications](../tests/golden/README.md).
Current technical contracts are routed from [AGENTS.md](../AGENTS.md).

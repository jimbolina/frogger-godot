# Porting plan and status

The game is rebuilt in phases. Each phase is independently demonstrable and has a stated exit check. Sizes are relative: S, M, L, XL.

The dedicated game scene opens ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4 and DES1–DES5 with the original-style HUD.
Remaining work expands theme coverage and completes the systems listed below.

## Status

P8 is split into exit-sized pieces. P8c includes the minimum playable level loop; P10 adds the dedicated game scene, original-style HUD and broader level coverage before P9. Cross-cutting work has its own rows (X1–X4).

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
| P8a | Behaviour catalog and typed tick outbox | M | Every existing golden unchanged; architecture scanner rejects entity-name string dispatch in `src/game` | Done |
| P8b | Demo playback harness | S–M | Recorded input decoding, atomic playback and reference-layout comparison reporting, including incomplete runs against native reference traces | Done; complete ORG1 acceptance belongs to P8c |
| P8c | ORG1 complete: single-player original-theme and general forms, all script opcodes and callbacks, v3.0e FORM callbacks, all death types, checkpoints, pink frog delivery, tongue, whole-map visibility and zones | L | The ORG1 attract demo replays to the reference end state; ORG1 is playable by keyboard through five checkpoints | Done; native attract, keyboard completion/collections, schedule parity and both test modes pass |
| P8d | Inspection module split: guards, presets, scenario options and manifests leave gameplay | S | Scanner and both test modes | Done before P8b |
| P10 | Dedicated game scene, original-style HUD and broader level setup | L | ORG1–ORG5 and SUB1 playable start to finish; SUB1 and ORG1 attract demos run to completion with the same end state | Done; six keyboard completions, native attract comparisons, schedule parity and both test modes pass |
| P9 | The remaining seven themes, one sub-phase each: FOR and VOL (attract demos exist), then CAV, DES, JUN, SWP, SKY | XL | A checklist per level; demo or reference-engine trace per theme | In progress; P9a Forest, P9b Volcano, P9c Cave and P9d Desert complete |
| P11 | Effects and particles | L | By eye against reference pictures | |
| P12 | Sound banks and music: PC sound-bank reader with an independent golden, then playback of the typed sound events | M | Reader golden; by ear | Metadata and logical voice timing implemented; audio playback pending |
| P13 | Front end, level select, options, saves, high scores | XL | A flow checklist; reference pictures of the options pages | Largest remaining block, about 17,000 lines of C |
| P14 | FrogLord round trip and reload on change, with a report of unmapped forms, scripts and callbacks | M | An edited map, script, remap and demo all load; a repointed behaviour loads without code | Loading half exists |
| P15 | Split-screen for two to four players | L | By eye | |
| P16 | Videos, credits, ending | M–L | By eye | Blocked on the FMV codec decision below |
| P17 | Export for Windows, Linux and macOS; hosted asset-free CI pinned to Godot 4.5.1 | S–M | A run on a clean machine; one verified CI runner with retained logs and named skips | Mac source setup and isolated verification available; packaged exports and CI pending |
| X1 | Performance acceptance gate | S each | Measured on an idle system at each playable milestone (P8c, P10, end of P9); see [inspection](reference/testing/terrain-inspection.md) | Original-hardware target remains unverified; further tuning deferred at the owner’s request |
| X2 | [Animated per-part lighting](reference/rendering/gameplay-projection.md) | M | Independent colour samples after each part's animation transform | Any time after P8a |
| X3 | Owner decisions | | | See below |
| X4 | [Sandbox](reference/architecture.md#sandbox): flat zone arena with entity spawning, presets, teleport and real models without a map | M | Asset-free and retail unit tests; owner play check | Done; a play-check tool, not level acceptance |

Network play is deferred. Multiplayer levels belong to P15.

## Needed from the owner

| What | Needed by | Why |
|---|---|---|
| A licence for this project's own code | Before the repository is made public | |
| A repository host | Before P17's CI | CI needs a runner and retained logs |
| A decision on the FMV videos | Before P16 | The videos are ARMovie `.RPL` files with the Escape codec; Godot has no decoder. Either a decoder is written (GDScript or GDExtension) or the videos are skipped with a documented stub. |

## P9 theme coverage

P9a Forest is complete: FOR1 and FOR2 have normal-start keyboard completion
checks, FOR1 matches its native attract trace across rendering schedules, and
independent behavior goldens cover the Forest custom entities. Visible bee
swarms are included because they are gameplay hazards. FOR3–FOR5 are dummy
entries; FORM remains in multiplayer scope.

P9b Volcano is complete: VOL1–VOL3 have normal-start keyboard completion
checks, VOL1 matches its native attract trace across rendering schedules, and
independent facts cover switches, controlled/falling platforms and source
visibility allocation. VOL4/VOL5 have no playable maps; VOLM remains multiplayer.

P9c Cave is complete: CAV1 and CAV4 have normal-start keyboard completion
checks, CAV3 is accepted by the owner's play check,
the CAV1 and CAV4 demos complete with schedule parity, and independent facts cover
the frogger light, entity fade, the firefly callback and the fat fire fly. Cave has no native attract baseline because the fresh-boot native export
never unlocks it. Pickups and fireflies draw as source sprites. CAV2/CAVM are
dummy rows and CAV5 has no map; the player croak light swell is deferred.

P9d Desert is complete: DES1–DES5 admit through whole-map setup with typed
falling rocks, rolling rocks, tumbleweeds, snakes, vultures, croc heads and
cracks, the per-level explosion flipbook overlay, and the generic movers,
cacti and butterflies. Independent facts cover every behavior and the retail
payloads; all five demos complete with schedule parity and no native baseline.
DESM has no map. Rock and tumbleweed shadows are tracked but not drawn until
the effects phase.

Next are JUN, SWP and SKY. Each level is accepted when the owner plays
it in the game scene and confirms it looks and plays well; recorded replays are
not required. Retain the thirteen existing keyboard completion checks
and the ORG1, SUB1, FOR1 and VOL1 native attract comparisons; see
[demo verification](reference/testing/README.md#demo-playback-and-comparison).

Normal play and demos use whole-map dependency validation. The guarded JUN1
and ORG1 corridor fixtures remain separate regression coverage.

Audio playback, other particles/splashes, animated per-part lighting, multiplayer,
packaged exports and hosted CI retain their separate phases above. Performance
work remains open: the original-hardware target is unverified, and further
tuning is deferred at the owner’s request.

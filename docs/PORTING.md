# Porting plan and status

The game is rebuilt in phases. Each phase is independently demonstrable and has a stated exit check. Sizes are relative: S, M, L, XL.

The dedicated game scene opens ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and SKY1–SKY4 with the original-style HUD.
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
| P9 | The remaining seven themes, one sub-phase each: FOR and VOL (attract demos exist), then CAV, DES, JUN, SWP, SKY | XL | A checklist per level; demo or reference-engine trace per theme | Done; P9a Forest, P9b Volcano, P9c Cave, P9d Desert, P9e Jungle, P9f Swamp and P9g Sky complete; every playable level accepted by the owner |
| P11 | Effects and particles | L | By eye against reference pictures | Done; P11a effect signals and resources, P11b frog effects and P11c entity effects complete and accepted by the owner's play check |
| P12 | Sound banks and music: PC sound-bank reader with an independent golden, then playback of the typed sound events | M | Reader golden; by ear | Done; sound effects and disc music play from committed voices (owner's by-ear check pending) |
| P13a | Front-end flow, unlock progression, saves, plain main menu and level list, score and lives carried between levels | M | Independent unlock and flow goldens; owner play check | Done; accepted by the owner's play check |
| P13b | 3D level-select stack | L | Independent layout and motion goldens; owner play check | Done; accepted by the owner's play check |
| P13g | Front-end water background: the options water surface and river bed behind the menu and stack pages, a prerequisite of P13c and P13d | S–M | Independent wave and mesh goldens; owner play check | Done; accepted by the owner's play check |
| P13c | Options page, volumes, controller page, languages | L | Independent options, controller-page and language goldens; reference pictures of the options pages; owner play check | Implemented; awaits the owner's play check |
| P13d | High scores: table view and name entry | L | Flow checklist | |
| P13e | Attract cycle from the main menu | S | Owner play check | |
| P13f | Multiplayer and network front-end pages | L | With P15 | |
| P14 | FrogLord round trip and reload on change, with a report of unmapped forms, scripts and callbacks | M | An edited map, script, remap and demo all load; a repointed behaviour loads without code | Loading half exists |
| P15 | Split-screen for two to four players | L | By eye | |
| P16 | Videos, credits, ending, including the JUN2 ending stage and the JUN1 end-of-game sequence | M–L | By eye | Blocked on the FMV codec decision below |
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

P9d Desert is complete and DES1–DES5 are accepted by the owner's play check.
They admit through whole-map setup with typed
falling rocks, rolling rocks, tumbleweeds, snakes, vultures, croc heads and
cracks, the per-level explosion flipbook overlay, and the generic movers,
cacti and butterflies. Independent facts cover every behavior and the retail
payloads; all five demos complete with schedule parity and no native baseline.
DESM has no map.

P9e Jungle is complete and JUN1 is accepted by the owner's play check. It
admits through whole-map setup with typed plants,
rope bridges, hippos, scorpions, the bouncy mushroom and the outro set loaded
as statics, animated-model collision primitives, the FORM bounce reaction and
the crusher door callback. Independent facts cover every behavior and the
retail payloads; the executable enables no Jungle demo. JUN2 is the ending
stage with no checkpoints and stays with P16 together with the end-of-game
sequence frozen C runs after JUN1; the port shows the level-complete flow
there. JUN3–JUN5 have no maps and JUNM is multiplayer.

P9f Swamp is complete and SWP1–SWP5 are accepted by the owner's play check.
They admit through whole-map setup with typed acid squirts, wall crushers, presses,
rats, slugs, nuclear barrels and the weir, the Swamp branch of the crusher
callback, register payloads for the nuclear and bobbing waste barrels, and
frozen `LOCAL_ALIGN` path alignment for the generic movers that carry it.
Independent facts cover every behavior and the retail payloads; all five demos
complete with schedule parity, and SWP1 and SWP5 match native traces per tick
(the native run needs a scratch store with every level selectable). Fixing
them also corrected the post-reset start timer, the landing cell kept by a
slip reaction and the freefall reference height for every level. SWPM has no map.

P9g Sky is complete and SKY1–SKY4 are accepted by the owner's play check. They admit
through whole-map setup with the generic `TRIGGER` entity (the SKY3 magical
popping balloon that releases the squadron through `TriggerEntityCallback`),
the 12-byte `MOVING_PLATFORM` payload, and the sky backdrop drift stepped from
the shared RNG on a modelled `Game_timer`. The script-driven balloons,
helicopters, hawk, birds, jets and clouds run on existing machinery. Independent
facts cover every Sky-specific rule and the retail payloads; all four demos
complete with schedule parity and match native traces per tick, obtained from a
scratch store that unlocks SKY1. Fixing SKY3 also made freefall entry clear the
whole frozen entity landing mask. SKY5 and SKYM are dummy rows.

## P11 effects and particles

Effects are presentation work: the port draws them from committed state and
events and never reproduces the frozen generators' shared random draws (see
[simulation](reference/gameplay/simulation.md#effects-and-the-random-stream)).
P11a is complete: gameplay commits the frog's edge-fade, drowning and Volcano
tints and the croak light swell, emits splash and croak signals, and resolves
particle hilites per entity model, the executable's particle generator
records, splash animation lists, pop colours and effect images, with the
synthetic and retail families in the [effects specification](../tests/golden/specs/effects.md).
P11b is complete: the frog's shadow, hop trail, slide, bubble and fire
particles, death ring, splash ripple, tints and score popups draw from
committed state and events through the rule classes in `src/convert/effects/`
and the views in `src/presentation/effects/`, matched to the synthetic
families. P11c is complete: Desert rock and tumbleweed shadows, poly-piece
pops for checkpoints, gold frogs, balloons, the nuclear barrel and the
breaking branch, the gold-frog glow, turtle, hippo and rat splashes,
exhaust, cloud, smoke and fire sprites from the resolved hilites, the croak
key (C) with the throat scale, and a sandbox effects preset. The ORG gold
baby frog is carried rather than popped and the outro stone frog belongs to
P16. See the [effects reference](reference/rendering/effects.md).

Each level is accepted when the owner plays it in the game scene and confirms it
looks and plays well; recorded replays are not required. The thirteen keyboard
completion replays and the native attract comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison),
not phase deliverables or acceptance evidence (owner decision, 2026-10-30); the
sandbox and the owner's play checks are the system checks, and the commit gate
is unchanged.

Normal play and demos use whole-map dependency validation. The guarded JUN1
and ORG1 corridor fixtures remain separate regression coverage.

Audio playback, other particles/splashes, animated per-part lighting, multiplayer,
packaged exports and hosted CI retain their separate phases above. Performance
work remains open: the original-hardware target is unverified, and further
tuning is deferred at the owner’s request.

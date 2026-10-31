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
| P13c | Options page, volumes, controller page, languages | L | Independent options, controller-page and language goldens; reference pictures of the options pages; owner play check | Done; accepted by the owner's play check |
| P13d | High scores: table view and name entry | L | Independent default-table, insertion, name-entry and view goldens; owner play check | Done; accepted by the owner's play check |
| S1a | [Boundaries and archive staging](#s1-and-s2-native-asset-and-modern-rendering-spikes): Git LFS, the `archive/` folder with the retail goldens, two test suites with no skips, scanner isolation and `src/data` rules | S | Game suite with zero skips; archive suite with `FROGGER_DATA_DIR`; strict compilation and the architecture check | Done |
| S1b | Typed `Resource` schema in `src/data/` and the abstract `AssetCatalog`; readers split out in `src/source/` | M | Every retail golden passes through the Resource-typed records; both suites green; no behaviour change | Done |
| S1c | Importer and committed assets: PNG textures, baked pages, model meshes and scenes, map resources, WAV effects, Ogg music, tables, demos; import goldens with independent oracles | L | Second import leaves `assets/` unchanged; import goldens and deliberate-break checks pass | Done; shaders moved to files |
| S1d | Runtime switch: every scene opens `ImportedAssets`; `--data-dir`, `FROGGER_DATA_DIR` and `--disc` leave the game; readers and FrogLord configs move to `archive/` | L | Both suites green; every accepted level, the front end and the sandbox play from imported resources (owner play check); captures compared with pre-S1 captures | Done; owner's play check pending |
| S1e | Layout audit, domain model documentation and cleanup of runtime-decoding code | M | The audit and documentation are reviewed by the owner; both suites green | Done; [audit](#s1e-layout-audit) and [domain model](reference/domain-model.md) await the owner's review |
| S2a | Upscaled texture set: `images_x4/` committed, a per-launch `TextureSet` (`--texture-set=x4`), scale-aware 2D draws, pages and sky at scale, mipmapped linear sampling for the set, locally baked `pages_x4/` with an independent golden | M | Both suites green with the retail set unchanged; x4 page goldens and deliberate breaks pass; owner play check at x4 | Done; play check 2026-10-31 accepted the mechanics and rejected the ML upscale's look, so the owner will recreate the x4 images by hand over time |
| S2b | [Native text](#s2b-native-text): a bitmap `FontFile` generated from the `newfont` glyph grid (retail and x4) replaces the hand-rolled glyph draws in the HUD, its ink layer and the level-stack score lines; the vector font is the owner's decision | S | Retail glyph placement pinned by the HUD and stack tests; the committed font matches its generator; both suites green; owner play check | Done; accepted by the owner's play check |
| S2c | [Modern rendering profile](#s2-modern-rendering-profile): `--rendering=modern` on Forward+ beside the retail look; scene lights and shadows from the map light records, lit model materials with the committed tints, lit terrain sampling per-image textures | L | Both suites green with no retail expectation changed; scene-lighting golden with a deliberate break; modern smoke tests; windowed probes and captures on Forward+ and Compatibility; owner play check | Done; owner play check pending |
| S2d | Cave omni light instead of the grey ramp, sky tile array, water as a partial reflection, `vertex_tint` as a blend, the map viewer under modern, the map UV ranges premise golden | M | Cave-light, modern-UV and UV-ranges goldens with breaks; modern smoke tests for CAV1, SKY1 and SWP1; sky levels load no page set; owner play check | Done; owner play check pending |
| S2e | Front end, sandbox and viewers under modern; blob shadows replaced by real shadows (`--effect-shadows=`), `--shadows=off` for comparison, water glint and shadow constants checked | M | Modern smoke tests for the front end, sandbox and viewers; owner play check and acceptance decision | Done; owner play check and acceptance pending |
| S2f | Cleanup after acceptance: retire or keep the retail profile, default profile, golden re-scope, `src/convert/` renamed `src/rendering/` | M/S | Both suites green; no `src/convert` reference left; owner launches ORG1 on the default profile | Next, gated on the owner's acceptance |
| P13e | Attract cycle from the main menu | S | Owner play check | |
| P13f | Multiplayer and network front-end pages | L | With P15 | |
| P14 | FrogLord round trip and reload on change, with a report of unmapped forms, scripts and callbacks | M | An edited map, script, remap and demo all load; a repointed behaviour loads without code | Loading half exists |
| P15 | Split-screen for two to four players | L | By eye | |
| P16 | Videos, credits, ending, including the JUN2 ending stage and the JUN1 end-of-game sequence | M–L | By eye | Blocked on the FMV codec decision below |
| P17 | Export for Windows, Linux and macOS; hosted CI pinned to Godot 4.5.1 | S–M | A run on a clean machine; one verified CI runner with retained logs | Mac source setup and isolated verification available; packaged exports and CI pending |
| X1 | Performance acceptance gate | S each | Measured on an idle system at each playable milestone (P8c, P10, end of P9); see [inspection](reference/testing/terrain-inspection.md) | Original-hardware target remains unverified; further tuning deferred at the owner’s request |
| X2 | [Animated per-part lighting](reference/rendering/gameplay-projection.md#animated-part-lighting) | M | Independent colour samples after each part's animation transform ([animated lighting golden](../tests/golden/specs/animation.md#animated-part-lighting)); owner play check | Done; the gameplay frog takes the map's lights, custom ambient and colour scale like every entity model (owner's play check pending) |
| X3 | Owner decisions | | | See below |
| X4 | [Sandbox](reference/architecture.md#sandbox): flat zone arena with entity spawning, presets, teleport and real models without a map | M | Asset-free and retail unit tests; owner play check | Done; a play-check tool, not level acceptance |

Network play is deferred. Multiplayer levels belong to P15.

## S1 and S2: native asset and modern rendering spikes

The owner has set two spikes ahead of P13e. They deliberately leave the
compatibility mantra: FrogLord-saved files, runtime loading of the player's
archive and executable, and the stored-colour fidelity checks stop being
requirements. That compatibility is deferred, not discarded; P14 and the
`pc-retail-v3.0e` target return to the plan later if the owner wants them.

S1 imports every asset once into `assets/` as committed Godot resources:
models and animations as meshes, scenes and animation libraries (the XAR
transforms stay authoritative for gameplay inside the model resource), textures
as PNG images with baked texture pages, sound effects as WAV and the CD music
as Ogg Vorbis, maps and the executable's tables as typed `Resource` records in
`src/data/`. Binary assets go through Git LFS. The readers, the importer, the
retail-format goldens and FrogLord's configuration live in `archive/`, which
the game never depends on; the assets are then edited directly. S1 then audits
the project layout, class boundaries and naming against Godot's project
organisation practice and domain-driven design, and writes the domain model
documentation (bounded contexts, aggregates and their invariants). The audit
proposes the reorganisation; the owner decides. Sub-phases S1a–S1e are in the
status table.

Test suites: the game suite under `tests/` is asset-free and allows no skips;
the archive suite under `archive/tests/` runs only with `FROGGER_DATA_DIR`
set. The former exit 3 and the reviewed-skip manifest are retired.

S2 replaces the C lighting recipe, its per-vertex stored-colour shaders and the
map's light records with Godot's lights, shadows and material pipeline, and
replaces texture-page reconstruction and colour keys with ordinary imported
textures and materials. Goldens that assert C colours are retired or re-scoped
to what still holds (geometry, animation, gameplay).

### S2: modern rendering profile

Owner decisions of 2026-10-31: the modern pipeline is a per-launch profile
beside the retail look (`--rendering=modern`, retail default and byte-exact),
it runs on Forward+ while retail stays on Compatibility, and the stored-colour
goldens, `probe_model_shader.gd` and the page bake stand until the owner
accepts the modern look by eye. Sub-phases S2c–S2f are in the status table;
S2f also renames `src/convert/` to `src/rendering/`. The rules live in the
[modern profile](reference/rendering/modern-profile.md) reference.

### S2b: native text

All in-game text is drawn by hand from one bitmap glyph grid, texture
`newfont`: 96 ASCII glyphs in 8x8 cells, 32 per row, monospace, coloured by
modulate, at three sites (the gameplay HUD, its ink layer and the
level-stack score lines). S2b generates a Godot bitmap font from that grid
with a small generator under `tools/` (a BMFont `.fnt` or `FontFile`, one
for the retail texture and one for the x4 texture with 32-pixel cells drawn
at size 8, chosen by the texture set) and draws the three sites with
`draw_string` or `Label` nodes, pixel-identical at retail. Text then takes
theme colours, outlines, authored scenes and later localisation without new
draw code. Done: `tools/make_font_newfont.py` writes `assets/fonts/retail/newfont.fnt`
and `assets/fonts/x4/newfont.fnt`, Godot imports them as `FontFile`s, the
catalog serves the set's font, and the HUD ink layer and stack panel draw with
`draw_string` through `NewfontText` ([assets](reference/assets.md#fonts)).
A vector recreation of the Frogger font is the only way text stays
crisp at any window size; it is a design task (automatic vectorising of 8x8
glyphs gives blobs), so it waits for the owner's decision after the x4 play
check and would supersede the x4 font image.

### S1e layout audit

The project was checked against Godot's project-organisation practice and the
[domain model](reference/domain-model.md). S1e itself renamed the inspection
vocabulary from admitted/admission to supported scenarios, presets and
provenance, moved the DES2 capture literals into preset data, and deleted the
code that only served runtime decoding of the retail files.

| Item | Verdict |
|---|---|
| Naming: snake_case files and folders, PascalCase `class_name`s | Pass |
| `.uid` and `.import` sidecars committed, `.godot/` ignored | Pass |
| `.gdignore` on raw data folders | Only `tests/golden/synthetic/` (CSV facts) has one. `docs/`, `archive/docs/` and `archive/third_party/` hold nothing Godot imports; `archive/`, `tests/` and `tools/` hold scripts the suites and scanner load, so they stay visible. |
| Layer-first split under `src/` rather than feature-first | Kept deliberately: the architecture scanner enforces the layers by path prefix. Features are folders inside a layer (`game/entities/`, `game/frontend/`, `presentation/frontend/`, `presentation/sandbox/`). |
| Scenes beside their scripts | Deferred. The eight scenes in `scenes/` are entry points launched by literal path from `project.godot`, the play and capture wrappers and tests (28 files); views build their nodes in code. Revisit when S2 adds authored scenes. |
| `tools/` (219 tracked files) | Owner decision. Proposed split: `tools/golden/` (the `make_*` generators), `tools/oracles/` (C oracles, headers and `build_*_oracle.ps1`), `tools/inspection/` (scenario runners, schedule verifiers, captures, comparisons and probes) and `tools/test/` (`check_*.gd`, `support/`, `godot_project.py`, `godot_profile.py`). Each Python test goes beside the tool it tests; `play.*`, `run_tests.*` and `launch_macos.command` stay at the root as entry points. About 100 files name tool paths, so the move is one mechanical commit with a link check. |
| `src/convert/` renamed `src/rendering/` | Planned for S2f, the cleanup after the owner accepts the modern profile. |
| Per-corridor inspection presets (`Org1ExplorationSetup`, `Jun1ExplorationSetup`, `Jun1ZoneLifecycleSetup` and five JSON manifests) | Owner decision. Proposed: one preset reader over data keyed by level code, so a new supported scenario is a data file rather than a class. Until then they stay. |
| `reference/gameplay/entities.md` (1,086 lines) | Deferred documentation work: move route narrative (tick numbers, index ranges) beside the golden specifications and keep the rules. |
| Viewer sizes | `map_viewer.gd` is 1,319 lines after `MapScenarioRun` took the rendered path and entity scenario runs; `gameplay_world_view.gd` 970, `model_viewer.gd` 907, `terrain_viewer.gd` 646. Deferred: split the map viewer's capture and overlay code when it next changes; S2 reworks the world view's drawing. |

Findings for later work: `CameraZoneInspection` uses `TerrainTrace` from
`src/presentation/tools/`, the one inspection-to-presentation dependency, and
the scanner does not check inspection's direction.

The domain-driven design review at `60cd252` is applied: inspection module and
single `TickGuard` hook, `EntityBehavior` catalog with the scanner rule against
name dispatch, `GameplayRun`/`Frog`/`FrogContacts` and the `GameplayState`
split, flag catalogs, typed `TickEvent`s, the copy-contract test, the
application layer, `GameplayHost`, and the renames. Still open from it:

- the per-corridor presets and manifests (owner decision above);
- route narrative in `entities.md`, and "admit" prose in the topic references,
  the golden specifications and the `*_admission.py` tool names;
- the size of `map_viewer.gd`;
- the historical `fixture_lives` key in the terrain trace schema.

## Needed from the owner

| What | Needed by | Why |
|---|---|---|
| A licence for this project's own code | Decided 2026-10-31 | The repository is permanently private, so no public licence is needed; third-party material keeps its own licences. |
| A repository host | Decided 2026-10-31 | `https://github.com/jimbolina/frogger-godot.git`, private; pushes happen only when the owner asks. GitHub's free Git LFS allowance (1 GB storage and bandwidth) bounds how often the assets can be re-imported or replaced before a data pack is needed. |
| Where imported assets live | Decided 2026-10-30 | Imported models, textures, sounds, music and maps are committed as project resources through Git LFS; the repository stays private and the licence decision covers them. |
| Git LFS on every machine that clones | Before S1c | Binary assets are LFS objects; a clone without `git lfs install` holds pointer files, which the test wrapper rejects. |
| Licence position on retail-derived assets | Decided 2026-10-31 | `assets/` is derived from Frogger (1997); the repository stays private permanently, so the assets are never distributed. |
| Python dependency management | When the tooling grows beyond the standard library | The generators and wrappers are stdlib-only; `compare_map_captures.py`, `bake_pages_x4.py` and `make_golden_texture_pages_x4.py` need Pillow. If upscaling or other tooling adds numpy, torch or more, switch to a `pyproject.toml` managed by uv with a lock file, and name `uv run` in the testing guide. |
| S1e proposals: split `tools/` into four folders, and replace the per-corridor inspection presets with data keyed by level code | After S2 (decided 2026-10-31) | Both moves touch many files; the [audit](#s1e-layout-audit) recommends them and leaves the choice to the owner. |
| Hand-made x4 textures | On hold from 2026-10-31 | The ML upscale is the placeholder and the `x4` set stays optional; when the owner resumes, they replace `images_x4/tNNNN.png` by hand, one texture at a time, keeping the layout rules (exact 4x padded size, alpha the nearest 4x of the retail mask, zero RGB under it, no opaque pixel the 5-bit key cuts). Each batch reruns the page bake and `make_golden_texture_pages_x4.py`; a batch that touches `t0310.png` (`newfont`) also reruns `tools/make_font_newfont.py`, which refreshes the font's page copy under `assets/fonts/x4/`; the wrappers stop until it does. |
| Acceptance of the modern rendering profile | After the S2e play check | Decides S2f: keep the retail profile beside modern (recommended; it costs nothing while green and compatibility is deferred, not discarded) or retire it with its shaders, page sets, bake and probes; and whether modern becomes the default profile and Forward+ the project renderer. |
| Modern look choices | At the S2 play check | `vertex_tint` for baked terrain shading under real light; the cave light curve (exact edge or fitted range), height and ambient; the water glint (`set_water_look`); `frogger/rendering/effect_shadows` (blob shadows off by default under modern); linear or AgX tone mapping; mipmaps on the retail images and `fix_alpha_border` on `images_x4` (both change the pinned import policy). |
| A vector recreation of the Frogger font | After the x4 play check, before S2 | A pixel-square TTF equals nearest upscaling (sharp, blocky); a smoothed redraw changes the look and needs the owner's eye. Either is retail-derived like `assets/`, which the private-repository decision covers. Until then the x4 bitmap font serves large windows ([S2b](#s2b-native-text)). |
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
They play through whole-map setup with typed
falling rocks, rolling rocks, tumbleweeds, snakes, vultures, croc heads and
cracks, the per-level explosion flipbook overlay, and the generic movers,
cacti and butterflies. Independent facts cover every behavior and the retail
payloads; all five demos complete with schedule parity and no native baseline.
DESM has no map.

P9e Jungle is complete and JUN1 is accepted by the owner's play check. It
plays through whole-map setup with typed plants,
rope bridges, hippos, scorpions, the bouncy mushroom and the outro set loaded
as statics, animated-model collision primitives, the FORM bounce reaction and
the crusher door callback. Independent facts cover every behavior and the
retail payloads; the executable enables no Jungle demo. JUN2 is the ending
stage with no checkpoints and stays with P16 together with the end-of-game
sequence frozen C runs after JUN1; the port shows the level-complete flow
there. JUN3–JUN5 have no maps and JUNM is multiplayer.

P9f Swamp is complete and SWP1–SWP5 are accepted by the owner's play check.
They play through whole-map setup with typed acid squirts, wall crushers, presses,
rats, slugs, nuclear barrels and the weir, the Swamp branch of the crusher
callback, register payloads for the nuclear and bobbing waste barrels, and
frozen `LOCAL_ALIGN` path alignment for the generic movers that carry it.
Independent facts cover every behavior and the retail payloads; all five demos
complete with schedule parity, and SWP1 and SWP5 match native traces per tick
(the native run needs a scratch store with every level selectable). Fixing
them also corrected the post-reset start timer, the landing cell kept by a
slip reaction and the freefall reference height for every level. SWPM has no map.

P9g Sky is complete and SKY1–SKY4 are accepted by the owner's play check. They play
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

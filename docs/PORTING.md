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
| P5 | Animated models, flipbooks, texture animation | L | Independent animation facts, every retail action, C matrix hashes and inspected animation sequences; optional presentation smoothing | Done |
| P6 | Map parsing and rendering, camera | L | The reference engine's map pictures, with tolerance. Includes a first load of a FrogLord-saved map. | Next |
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

P5 closed on 2026-10-01: 99 scripts compiled, 240 retail tests passed,
and 198 asset-free tests passed with 42 named retail skips. All 187 XAR
actions and safe flipbook actions were sampled, all texture targets were
checked through wrap, and the 19 unsafe authored flipbook records remain
diagnosed and unavailable. The C driver passed 10 checks; visual evidence,
timing measurements and the six deliberate-break checks are recorded in
`FINDINGS.md` and `tests/golden/README.md`. Maps, lighting, gameplay-driven
actions, animation events, particles and sound remain later phases.

## Needed from the owner

| What | Needed by | Why |
|---|---|---|
| A FrogLord-saved mod: the folder holding the three `modded_*` files after any small level edit | P6 | FrogLord has no command line for this, and the round trip is the project's main compatibility claim |
| A licence for this project's own code | Before the repository is made public | |

## Layout

```
third_party/froglord_cfg/   FrogLord's config files, unmodified
src/legacy/                 Pure data: readers for the original formats. No nodes.
  io/                       ByteReader, FixedPoint, Crc32, Pp20
  config/                   FrogLord config parsers, GameVersionConfig, name lists
  source/                   Where the game files are: retail folder, FrogLord mod folder, locator
  exe/                      The executable and the tables inside it
  formats/                  MWI, MWD, WAD, VLO, MOF; later MAP, sound banks, demos
  game_data.gd              One facade over all of the above
src/convert/                Builds Godot resources from legacy data: textures, meshes, animations, audio
src/game/                   The game: world, entities, scripts, frog, camera, collision, effects
src/presentation/           HUD, front end, options, saves, audio, tools
src/mod/                    Watching mod files and reporting what could not be mapped
tests/unit/                 Need no game files
tests/golden/               Need the retail files; compared with committed facts
tools/                      Test runner and the independent golden generators
```

Directories are created when a phase puts real files in them.

## Simulation

- Game logic runs in `_physics_process` at the original tick rate, with at most 3 steps per rendered frame. Rendering is interpolated. Godot's physics engine is not used; collision is the game's own.
- The tick rate is an open question to settle in P7: the reference engine runs 30 ticks per second, while FrogLord's editor treats the PC release as 25. See `docs/FINDINGS.md`.
- The model viewer uses that existing 30 Hz clock. Its optional smoothing changes only presentation and defaults off; textures and animation state stay tick-driven.
- Entities update in the original list order, because random-number use depends on it.
- These keep integer behaviour: the random number generator, script timers and counters, path distance stepping, grid coordinates and form heights, the game timer, score, entity delay counters, and radius-squared collision tests.
- Frog hops last a whole number of ticks and snap to the grid on landing, so recorded demos replay approximately. Demo checks compare completion and end state, not the path.
- Floats are fine for camera easing, particles, animation blending and interpolation.

## Space

- Fixed in P4: a game position `(x, y, z)` is drawn at Godot `(x, -y, -z) / 256`. One grid square is one Godot unit. The game's y points down; this is a half turn about the x axis, not a mirror image, so polygons keep their stored corner order and Godot's back-face culling works as the original's did. `GameSpace` is the only place that converts.
- Game logic keeps the original whole units. Only what is drawn is converted.

## Rendering

- Renderer: Compatibility (OpenGL), no environment, no tone mapping, no fog, no MSAA. It was chosen because it mixes translucent polygons on stored colour values, as the original did.
- Depth buffer. A texture pixel made transparent by the black-is-transparent rule is discarded. Semi-transparent polygons go in separate surfaces that do not write depth, in four blend variants: average, add, subtract, add a quarter.
- One family of unshaded shaders written out from one template (`ModelShaders`). A textured pixel is texture colour times lit colour times 2, the lit colour stopping at full brightness. An untextured pixel is the lit colour as it is, not doubled. All of it is computed on stored colour values.
- The lit colour is the polygon's colour lit by the map's lights, which the game works out while it runs. Until maps are read (P6) the polygon's own colour is used.
- The renderer converts a shader's colour to linear light and back with two approximations that darken dark colours. The shaders undo this beforehand. `tools/probe_model_shader.gd` measures what reaches the screen; run it after changing the Godot version, the renderer or the environment.
- The black-is-transparent rule is a colour key over a whole 256x256 texture page in the original, not per image.
- One texture per VLO image, clamped, no mipmaps. Filtering is a user option; the font is always nearest.
- One mesh per map group, split by material. Polygons with animated textures get their own surfaces.
- HUD on a 640x480 canvas layer. The camera's field of view is derived in P6 against the reference pictures.

## Open risks

- Form callbacks are addresses in the executable; the address-to-name table has to be measured per supported build.
- Demo replay under floats may drift. The fallback is an integer-only frog and path core.
- GDScript speed on large map builds. Decompression is already fast enough (about 4 seconds for the whole archive).
- The PC camera projection constant is unverified.
- FrogLord changing its config keys or the layout of what it appends to a saved executable.

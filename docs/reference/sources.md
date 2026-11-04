# Reference sources

External material is read-only. Relative external paths below are relative to
the repository root, not this document. The verified build has an absolute path.
Read only the sources needed for the current task.

The owner explicitly selected frozen `froggy` C-port behavior, including its
30 Hz pacing. Original retail executable timing does not
override that target or block implementation. Player executables remain data
sources for recognition and tables; their data role is separate from behavioral
authority. See [simulation](gameplay/simulation.md).

## The reference engine: `../froggy`

A port of the original C game code to modern PCs, matched against the retail PC game. It is frozen and serves as the behavioural reference for this project. Its own documentation uses milestone and ruling numbers; none of that bookkeeping belongs in this repository.

| What | Where |
|---|---|
| A guide written for this project: timing, units, random numbers, trace columns, how to run the engine beside another program | `../froggy/engine/docs/REFERENCE.md` |
| The original game's C source, 242 files | `../froggy/engine/vendor/frogger-psx-src/source/` |
| The original's library layer (models, animation, viewports, sprites) | `../froggy/engine/vendor/frogger-psx-src/source/API.SRC/` |
| Short, standalone readers for MWI, MWD, VLO, MOF, MAP and PP20. The most concise description of the formats. | `../froggy/engine/asset_pipeline/src/` |
| The engine's own loaders | `../froggy/engine/mr_stub/src/loaders/` |
| Tables transcribed from the retail executable: demos, cheats, languages, options pages | `../froggy/engine/asset_pipeline/include/frogger_*.h` |
| Measured facts about how the PC game behaves, many of them differences from the PlayStation game | `../froggy/engine/docs/KEY_FACTS.md`; the index at the end of `REFERENCE.md` says which entries matter |
| Reference pictures: 148 PNGs of maps, the frog and options pages | `../froggy/engine/tests/baselines/` |

### Where to look in the C source

| Subject | Files |
|---|---|
| Entities | `ENTITY.C`, `ENTLIB.C`, `formlib.C`, `form.C` |
| Entity behaviour per theme | `ent_gen.c`, `ent_org.c`, `ent_sub.c`, `ent_cav.c`, `ent_des.c`, `ent_for.c`, `ent_jun.c`, `ent_swp.c`, `ent_sky.c`, `ent_vol.c` |
| Script interpreter | `scripter.c`, `scripts.c` |
| Frog | `FROG.C`, `froguser.C`, `froganim.c` |
| Map, grid, collision | `mapload.C`, `mapdisp.c`, `MAPVIEW.C`, `GRID.C`, `COLLIDE.C`, `WATER.C` |
| Camera, paths, zones | `CAMERA.C`, `PATH.C`, `ZONE.C` |
| Game loop | `gamesys.C`, `MAIN.C` |
| HUD, score, font | `HUD.C`, `score.C`, `GAMEFONT.C` |
| Front end | `tempopt.c`, `OPTIONS.C`, `SELECT.C`, `pause.c`, `credits.c`, `HSView.c`, `hsinput.c` |
| Saves | `LoadSave.c` |
| Sound | `sound.c`, `xalist.c` |
| Effects, particles | `EFFECTS.C`, `PARTICLE.C` |

File names in that folder are mixed case. Use the exact spelling; it matters on Linux.

### The retail executable

The vendored source is a PlayStation decompilation; retail PC's `FROGGER.EXE`
(`FROGGER_DATA_DIR`, image base `0x00400000`, `.text` at `0x00401000`) compiles
bodies that the source leaves empty, disabled or different. Where behaviour is
retail-only, read the executable instead of guessing:
`llvm-objdump -d --x86-asm-syntax=intel --start-address=<va> --stop-address=<va> FROGGER.EXE`
(Xcode's Command Line Tools) disassembles it. froggy's
`engine/docs/evidence/m38_step0_ground_truth.txt` (from line 671) maps retail's
options-page rows to their startup, update and shutdown addresses; retail numbers
the pages differently from the vendored enum (row 18 is GAME_OVER, 16 LEVEL_SELECT).
`KEY_FACTS.md` names other recovered addresses (`PlayCD` `0x004300a0`,
`MRSNDPlaySound` `0x0044c290`, `Option_page_request` `0x00498500`, `GameEnd`
`0x00430560`); the CD layer is `StopCD` `0x004300e0`, `PauseCD` `0x00430110` (a
stop that remembers the track), `ResumeCD` `0x00430140` (a fresh looping `PlayCD`
of it), `PlayLevelMusic` `0x0043e5a0`, `PlayOptionsMusic` `0x00446450`,
`ShutdownOptionsMusic` `0x00446470` and `PlayZoneComplete` `0x0043e580`, with
`Game_xa_tunes` at `0x00481400` and `Game_map_theme` at `0x00495118`. Pin executable facts to their bytes in a golden, as the cheats and
the [game-over page](../../tests/golden/specs/frontend.md#game-over) do.

### Exporting reference material from the engine

The verified native macOS arm64 binary is
`<reference-build>/build/mr_stub/frogger` on the owner's machine, where
`<reference-build>` is a copy of `../froggy` built outside the frozen source tree.
Its build directory is the parent `build/` folder, outside the frozen source
tree. Its sibling `../verification.json` (relative to the build directory)
records a clean source HEAD of
`fbf8351925b84816b1d8ab67025dd43c9bc0950f`, native execution without
Rosetta, allocations above 4 GB and passing driver checks. Reuse this build;
do not modify or rebuild the frozen sources. Keep exports outside repositories.

| Want | How |
|---|---|
| A screenshot of every map | `python3 ../froggy/engine/tools/reference_export.py screens --build-dir <reference-build>/build --out <external-folder>` |
| Per-tick traces of the attract demos | `python3 ../froggy/engine/tools/reference_export.py traces --build-dir <reference-build>/build --out <external-folder>` |
| A trace of any run | Start the `frogger` driver with `--trace-csv=<file>` |
| Attract demos the fresh boot never reaches (Cave, Desert, Swamp, Sky) | Run the driver with a scratch store whose "Selectable Levels" value opens the wanted arcade rows (row 18 is SKY1, which gates all four Sky demos), then let the attract route cycle to the wanted demo with a `--smoke` script of repeated `waitstatus:DEMO_MAIN;waitstatus:DEMO_FINISH;` steps; with every row open SWP1 is the thirteenth demo (the fourteenth table row, counting the first -2 row), and with only Sky added SKY1 is the sixteenth, inside the sound-journal cap. Keep the store and traces outside repositories. |

A trace has one row per frog per call: `call,page,map,frog,grid_x,grid_z,x,y,z,mode,flags,input`. A second file, `<file>.entities.csv`, has one row per live entity. Positions are whole world units; a grid square is 256 units. One call is one logic tick, except the call after a level ends or starts (the demo start included), which covers up to three: the engine caps catch-up logic at three loops per frame. The verified native export covers four attract demos and four map screenshots. SUB1 traces match the retained pre-port Windows baseline byte for byte; older full Windows baselines for the other three demos are unavailable, so their cross-platform parity is unverified.

## FrogLord: `../froggy/resources/FrogLord`

The community editor, MIT licensed, at commit `5416ae4f`. Its Java source is the authority on how the data formats are read and written.

| What | Where, under `src/net/highwayfrogs/editor/` |
|---|---|
| Archive formats | `games/sony/shared/mwd/` |
| Decompression | `games/sony/shared/pp20/` |
| Textures | `games/sony/shared/vlo2/` |
| Models | `games/sony/shared/mof2/` |
| Sound banks | `games/sony/shared/sound/` |
| Maps | `games/sony/frogger/map/` |
| Entity data per type | `games/sony/frogger/map/data/entity/data/` |
| Tables in the executable | `games/sony/frogger/FroggerGameInstance.java`, `games/sony/frogger/data/` |
| What is written on save | `games/sony/shared/ui/SCMainMenuUIController.java`, `saveMainGameData()` |
| The block appended to a saved executable | `utils/FileUtils.java`, around lines 965 to 1070 |

Its config files are under `resources/games/frogger/`. This repository ships unmodified copies in `archive/third_party/froglord_cfg/`.

## The pre-recode alpha and the letter SVGs

The owner's PlayStation disc image of a pre-recode build (MWD created 19 March
1997) is kept outside every repository; FrogLord's old-format MWI entries
in its `PSX.EXE` index `FROGGER.MWD`, whose `FRONT_0.WAD` holds the flat letter
models `A.XMR`–`Z.XMR` and `0.XMR`–`9.XMR`. Nothing reads it; it is reference
only. The 36 SVGs in `content/fonts/angular/svg/` are a trace of those
models by StarmanUltra, received by the owner on 2026-11-01; they are tracked
in the repository, and the font, lettering images and tile masks built from
them carry that credit in the README and in packaged builds. No licence terms
are recorded. They match the models to 98–99% of
their area ([lettering](assets.md#lettering)).

## The retail game files

`../froggy/resources/pc-version/extracted/FROGGER/` holds `FROGGER.EXE` and `FROGPSX.MWD`; the videos are in `../froggy/resources/pc-version/extracted/VIDEO/`. These are the owner's own copy. The importer and the archive test suite read the first folder through `FROGGER_DATA_DIR`; the game plays from an import of it, the developer's local `assets/` or a player's import under `user://`.

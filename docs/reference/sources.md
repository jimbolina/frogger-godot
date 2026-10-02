# Reference sources

External material is read-only. All external paths below are relative to the repository root, not this document. Read only the sources needed for the current task.

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

### Exporting reference material from the engine

The engine is built in `../froggy/engine/build/`. Do not rebuild or modify that tree.

| Want | How |
|---|---|
| A screenshot of every map | `python3 ../froggy/engine/tools/reference_export.py screens --out <folder outside any repository>` |
| Per-tick traces of the attract demos | `python3 ../froggy/engine/tools/reference_export.py traces --out <folder>` |
| A trace of any run | Start the `frogger` driver with `--trace-csv=<file>` |

A trace has one row per frog per call: `call,page,map,frog,grid_x,grid_z,x,y,z,mode,flags,input`. A second file, `<file>.entities.csv`, has one row per live entity. Positions are whole world units; a grid square is 256 units. One call is one logic tick, except the call after a level ends, which covers up to three. Output is identical on Windows and Linux.

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

Its config files are under `resources/games/frogger/`. This repository ships unmodified copies in `third_party/froglord_cfg/`.

## The retail game files

`../froggy/resources/pc-version/extracted/FROGGER/` holds `FROGGER.EXE` and `FROGPSX.MWD`; the videos are in `../froggy/resources/pc-version/extracted/VIDEO/`. These are the owner's own copy. Point `FROGGER_DATA_DIR` at the first folder. Never copy any of it into a repository.

# Front end: flow, progression and saves

The single-player front end is a main menu and the 3D level-select stack in front
of the game scene. Menu text, the logo and level names are the player's own images,
resolved by FrogLord name ([menu assets](#menu-assets)). The options page, high
scores, attract demos, multiplayer pages, videos and languages other than English
are not built; see the [roadmap](../../PORTING.md).

## Page flow

`FrontEndFlow` (`src/game/frontend/`) is a pure `(page, event) -> page` table:
boot, main menu, level select, game, level complete, game over, continue and
ending. An unknown pair keeps the page and reports. Retail page order wins over
the vendored source, which the [specification](../../../tests/golden/specs/frontend.md)
lists with each row's C line. The port skips the logo, language and intro pages
and opens on the main menu. Choosing a level from the list may go back only until
the first level of a game is chosen (`Sel_first_time`).

`FrontEndScreen` shows the menu and list, `GameplayScreen` ends each level with the
flow's next page, and `FrontEndSession` holds the game across scene changes.

## Level-select stack

`StackLayout` and `StackSelector` (`src/game/frontend/`) hold the frozen
`SELECT.C` geometry and the 30 Hz page machine: camera slide with chained travel
over selectable rows, box slide-out, glow, the spin to the level picture and the
32-tick fade into the game. `LevelStackView` draws the 33 arcade boxes from
`StackMeshBuilder` with the source camera (perspective 1000 on 640×480) and
`StackPanel` draws the title, prompt, level name and loading images. The
[specification](../../../tests/golden/specs/frontend.md#level-select-stack) lists
the facts and their C lines. Up/Down are held, Enter or Space is Fire, Escape is
Triangle.

Retail PC runs the glow pulse that the vendored source builds only for PSX, so
the port does. Not built: the high-score lines beside the picture (P13d), race
rows and mouse picking. Gold-frog quads draw slightly in front of the boxes
rather than on top, and the glow is unverified against retail pictures.

## Water background

Every front-end page sits on the options water: a 14×16 mesh of the sky texture
over a 14×16 river bed of the bed texture (`opt_env_sky` and `opt_bank3`, read
from `OPT_VRAM.VLO`). `MenuWater` (`src/game/frontend/`) holds the grids, the wave
heights from `HSUpdateWater` and the per-tick counter; `MenuWaterMesh` and
`MenuWaterView` draw it. Retail PC blends the water additively with its colours
doubled, so the port does, and the bed is opaque behind it. The stack page draws
it through the stack camera; the main menu uses the options camera at its static
`MAIN` preset. The [specification](../../../tests/golden/specs/frontend.md#front-end-water)
records the C facts, including that retail's main-menu camera follows the
scrolling high-score frog, which the port does not yet (P13d).

## Progression

`LevelProgress` holds a COMPLETED / SELECTABLE / ZONEACCESSIBLE word per arcade
row, the gold-frog bits and the shipped level of each row. A fresh game opens
ORG1, SUB1, FOR1 and VOL1 and makes the rest of those worlds zone-accessible.
Completing a level opens the next in its world when the player leaves the
complete page. A gold frog opens the first level of the first closed world.
Retail never runs the level-complete JUN1 rewrite: the jungle statue sets its
gold bit and the end of the game rewrites the row, which the port follows.
Each rule has an independent golden.

Score, lives and the extra-life threshold carry between levels of one game
(`GameInitialise` is the only reset); `RunStart` carries them into the next level.
Replay with R restarts with the values the level began with.

## Saves

Progress is saved to `user://progress.cfg` (`ProgressStore`) after each finished
level: the arcade flag words, the gold-frog bits, music and sound volume (defaults
3 and 5 of 8) and key bindings (unused until the options page). Retail uses a
registry key, which the port does not read or write. A missing file means a fresh
game; a corrupt or foreign-version file is reported in the menu and ignored.
Volumes and bindings are stored but not yet applied.

## Menu assets

`FrontEndAssets` reads `STARTNTSC.VLO`, `FIXE_VRAM.VLO`, `OPTE_RAM.VLO` and
`LS_ALL.VLO`. The English names are `opt_start`, `opt_options`, `opt_exit`,
`opt_race`, `select_level`, `zone_complete`, `press_fire`, `sel_loading`,
`opt_big_continue`, `opt_yes`, `opt_no`, `opt_paused`, `froglogo` and `newfont`;
each arcade row also resolves its world, screenshot and stack-name images.
Race rows keep their images in `LS_ALLM.VLO` and belong to the multiplayer pages.

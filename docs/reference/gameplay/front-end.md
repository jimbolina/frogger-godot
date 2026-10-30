# Front end: flow, progression and saves

The single-player front end is a main menu and a level list in front of the game
scene. Menu text, the logo and level names are the player's own images, resolved
by FrogLord name ([menu assets](#menu-assets)). The 3D level-select stack,
options page, high scores, attract demos, multiplayer pages, videos and
languages other than English are not built; see the [roadmap](../../PORTING.md).

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

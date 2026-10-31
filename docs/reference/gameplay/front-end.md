# Front end: flow, progression and saves

The single-player front end is a main menu and the 3D level-select stack in front
of the game scene. Menu text, the logo and level names are the player's own images,
resolved by FrogLord name ([menu assets](#menu-assets)). Attract demos,
multiplayer pages and videos are not built; see the [roadmap](../../PORTING.md).

## Page flow

`FrontEndFlow` (`src/game/frontend/`) is a pure `(page, event) -> page` table:
boot, main menu, level select, game, level complete, game over, continue, ending,
options, controls, high-score input and high-score view. An unknown pair keeps the page and reports. Retail page order wins over
the vendored source, which the [specification](../../../tests/golden/specs/frontend.md)
lists with each row's C line. The port skips the logo, language and intro pages
and opens on the main menu. Choosing a level from the list may go back only until
the first level of a game is chosen (`Sel_first_time`).

`FrontEndScreen` shows the menu and list, `GameplayScreen` ends each level with the
flow's next page, and `FrontEndSession` holds the game across scene changes. The
main menu is retail's: the scrolling high-score table fills the screen and the
Start, Options and Exit sprites sit on 16-pixel rows 80 above the bottom over the
translucent `opt_menu_cloud` poly, sliding up 8 a tick during the table's fly-on
(`tempopt.c:1209-1290`, `:1486`). Up and Down hop between the rows and wrap, and
fire croaks (`:1712-1744`, `:1820`). Retail's rows are Start, Race and Options; the
port's Exit takes the race row until P15.

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
the port does. The [high-score view](#high-scores) reuses the stack with the
score lines beside the picture. Not built: race rows and mouse picking. Gold-frog quads draw slightly in front of the boxes
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
scrolling high-score frog, which the port's main menu does ([high scores](#high-scores)).

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
3 and 5 of 8), the key bindings and the language setting. Retail uses a
registry key, which the port does not read or write. A missing file means a fresh
game; a corrupt or foreign-version file is reported in the menu and ignored.
The options page also saves on leaving, which retail does not.

## Options page

Options on the main menu opens `OptionsMenu` (`src/game/frontend/`), the 30 Hz
state machine of retail's four-lily page: exit, controller configuration and the
volume logs. The port shows two logs, music then effects, where retail has one
(its effects log: the effects model stands beside it); the high-score row opens
the [high-score view](#high-scores).
Left/Right step a volume by one, clamped 0..8; both levels are `127·step/8`
(`AudioLevels`), the music on the Music bus and the effects through
`SoundVoiceView.effect_volume`. Menu keys are fixed and the bindings do not apply.

`OptionsScene` places the page as the C does each tick: every model, title and
the frog sit on the front-end water's wave surface for the frame being drawn,
drop onto it during the fly-on and slide away from x 0 during the fly-off.
`OptionsModels` (`src/convert/`) loads the models by FrogLord name from
`OPTIONSH.WAD`: `OPT_LILLYPAD_BLANK` lilies, `HI_LOG` volume logs whose 64
animated polygons show each stage blank, full or half, the spinning `OPT_MUSIC`
and `OPT_SFX` volume models beside them (glowing `(frame & 7) << 5` while selected,
0x20 otherwise) and the `OPT_STAT_BULLRUSH`/`OPT_STAT_LILLY` extras, plus the
`GEN_FROG` frog. The frog hops with `GEN_FROG_HOP`, lands into `WAIT1`, dances
(`DANCE`) on the music row and pants (`PANT2`) on the effects row while the volume
is above 0, and croaks `OUCH` on fire; a ripple splash marks each landing and its
jump shadow lies on the water. The titles are 3D sprites over their lilies with
flat subtracted reflections; models and sprites take the options viewport's
lights. The unselected glow is 0x20 as the C sets it, not the 0x60 the retail
pictures might suggest. The
[specification](../../../tests/golden/specs/frontend.md) lists the facts and their C lines.

## Controller page

`ControlsPage` is retail's page 25: four player records of nine actions (left, right,
up, down, super-hop, tongue, croak, camera clockwise and anticlockwise) as DirectInput
scancodes, with the retail capture rules (named keys only, none bound twice). Gameplay
and the level stack read player 1 through `BindingInput`. The retail defaults apply:
arrows, Return, right Ctrl, right Shift, `'` and `;`. Space, R and Escape stay fixed
unless a binding claims the key; the sandbox and inspection tools keep their own keys.
Key names and labels are English in the default font and no joystick can be chosen.
The bindings are saved as 44 integers (`device, valid, nine scancodes` per player).

## High scores

`HighScoreBoard` (`src/game/frontend/`) holds the main table of ten rows and three
rows per level (`HighScoreRow`: three initials, a score and five checkpoint seconds).
The defaults are read from the executable's `Game_high_score` and `Level_high_scores`
(`HighScoreTable`, `src/source/exe/`); retail's tables differ from the vendored
source in two Volcano rows, which the [specification](../../../tests/golden/specs/frontend.md#default-high-scores)
records. Achieved scores persist in `user://high_scores.cfg` (`HighScoreStore`),
written after name entry and at the end of a game; retail writes registry blobs,
which the port does not read.

Completing a level records player one's score gained in that level and its five
checkpoint times in whole seconds (rounded up, 99 from 2971 ticks); a better run of
the same level in the same game replaces it; the JUN2 statue's zero-time record
belongs to the P16 outro. A game that ends by losing every life (after Continue) or by the ending opens
the name-entry page when the final score beats a main row or a recorded level beats
one of its rows; leaving a level with Escape skips it. A new score enters above the
first lower row (ties go below), the main shift keeps rows' times, the level shift
moves them, and each table given a row is flagged for the tour.

`HighScoreEntry` and `HighScoreEntryScene` run the name-entry page (`hsinput.c`),
drawn by `HighScoreEntryView`: 30 lilies (A–Z, dot, space, BACK, END) over the water
under the static camera, six extras and three initials pads. The frog starts on O;
held arrows hop every seventh tick, Enter or Space picks the pad, BACK rubs the last
letter, END pops the frog and enters the initials 31 ticks later. The pad flips over
eight ticks and swaps its model at the half-turn. Retail PC plays the PSX sound ids
(croak, fly gulp, explode). There is no cancel and no timeout. The frog is the GENM
flipbook frog; its explosion particles are not drawn.

`HighScoreTour` runs the view page (`HSView.c`) with `HighScoreScene` holding the
scrolling table: ten turtles numbered by rank, the initials on letter lilies, the
scores on eight-digit logs with leading zeros blank, five extras and the frog that
hops from turtle to turtle (18 ticks' wait, 12 ticks' hop) with hop and splash sounds.
`HighScoreTableView` draws it; `LevelStackView` and `StackPanel` draw the stack mode
with the checker background and the three score lines (`HighScoreText`) in `newfont`
beside the spun-out picture. After name entry the tour spins out ORG1 first, then every
level with a new row (camera creeping 20 a tick, a ten-tick wait, a 90-tick hold), then
the main table with the static camera when it has a new row, and times out to the main
menu after 120 ticks; Escape leaves at once. From Options the view opens on the stack:
Up/Down travel, Enter spins a level out, Left shows the main table, Right returns to
the stack and Escape returns to Options. The main menu runs the scrolling table behind
its buttons with the camera following the frog; the attract alternation with demos
belongs to P13e. The score lines centre in retail's 192-wide text box (KF-407) while
the stack keeps the vendored panel end 400, title y 300 and line pitch 16, where
retail measures 364, 280 and 20 (sanitize T35); the stack geometry was accepted with
P13b and the change is deferred. The arrow glow is capped at the neutral colour where
retail ramps past it, the tour's first wait always starts from zero where the C
keeps the counter between visits, and the main-menu camera follows the frog only once
its sweep has ended. Race tables and multiplayer frogs stay with P15. The
[specification](../../../tests/golden/specs/frontend.md#high-score-tables) lists the
rules, the entry and view traces and their C lines.

## Languages

Retail has no language screen: the OS locale picks English, Italian, German, French or
Spanish. `GameLanguage` does the same (`OS.get_locale()`), `--language=en|it|de|fr|es`
overrides it for one session and the saved setting can pin one. `FrontEndAssets` loads
the language's `OPT` and `FIX` banks after the English ones and resolves each menu image
by its localized FrogLord name, falling back to English with a recorded diagnostic. The
logo, font, arrows and gold frog have no localized variants. Level names, the water and
the in-game HUD stay English.

## Menu assets

`FrontEndAssets` reads `STARTNTSC.VLO`, `FIXE_VRAM.VLO`, `OPTE_RAM.VLO` and
`LS_ALL.VLO`. The English names are `opt_start`, `opt_options`, `opt_exit`,
`opt_race`, `select_level`, `zone_complete`, `press_fire`, `sel_loading`,
`opt_big_continue`, `opt_yes`, `opt_no`, `opt_paused`, `froglogo` and `newfont`;
each arcade row also resolves its world, screenshot and stack-name images.
Race rows keep their images in `LS_ALLM.VLO` and belong to the multiplayer pages.

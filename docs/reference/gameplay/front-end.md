# Front end: flow, progression and saves

The single-player front end is a main menu and the 3D level-select stack in front
of the game scene. Menu text, the logo and level names are the player's own images,
resolved by FrogLord name ([menu assets](#menu-assets)). The main menu
alternates with the [attract demos](#attract-cycle); multiplayer pages and videos
are not built; see the [roadmap](../../PORTING.md).

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

## Attract cycle

`MainMenuView` (`src/presentation/frontend/`) draws the three sprites and the cloud,
which follows the first sprite's row as the C recomputes it each tick (`tempopt.c:1700`).
`AttractTimer` and `AttractCycle` (`src/game/frontend/`) hold the counters and the
demo order; `FrontEndSession` keeps the cycle and the demo request across scenes.

- Each main-menu startup places the sprites below their rows and flies them on 8 a
  tick with the scrolling table, then counts `SCORE_TIME` (810 ticks, 27 s)
  while no fly counter runs (`:1629-1685`). Up and Down hop at any time and never
  reset the count (`:1713-1746`); fire is read only while no fly counter runs and no
  demo is loading (`:1811-1817`).
- When the count ends the table and the water go, the options music stops, and over
  10 ticks the sprites slide 8 down a tick while the centred LOADING sprite brightens
  16 a tick from black (`:1336-1426`). The demo then plays in the game scene with no
  HUD, the sprites flying back on over it and staying live; Start opens the level
  select and Options the options page (`:1824-1977`).
- At 30 ticks before the demo's end the sprites fly off, LOADING brightens again and
  the screen fades to black over 30 ticks (`:1481-1557`). The main menu returns with
  the camera snapped to MAIN, the row kept, the table flying on, the options music and
  a fresh count; the next demo is the next row whose unlock level is selectable
  (`:1560-1626`).

Port differences: retail plays the INTRO video at each `-2` row and when the list
wraps; the port restarts the main menu instead, cursor on Start, camera snapped and a
fresh count (owner decision 2026-11-02). The LOADING sprite's colour maps 0x80 to full
brightness, as the stack page's does. Retail places the rows 90 below and moves
them nine times, so its menu rests 18 lower than the accepted port rows, which slide
from 80 below over 10 ticks. The menu is a scene of its own, so each return
from a demo reloads it. Options on the main menu opens at once, as before, where retail
flies the sprites off first through its delayed request; the count therefore never
waits for one. A demo whose resource is missing or whose tick fails returns to the
menu with a note in the menu's diagnostics. Deaths never end a demo: the level restarts
at the demo spawn with the input stream carried on and ten lives, since the HUD is hidden
([simulation](simulation.md#recorded-demo-control)). `--attract` ends the first count at once.

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
the port does. A level spun out shows the first three rows of its table beside
the picture (`SELECT.C:2017-2031`); the lines slide with the panel and stay
until the next spin-out. A level's rows change only when initials are entered
at the end of a game, so a level completed in the current game shows its new
score after name entry. The [high-score view](#high-scores) reuses the stack
with the same score lines. Not built: race rows and mouse picking. Gold-frog quads draw slightly in front of the boxes
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

## Level complete

After the fifth frog's bonus, `GameplayScreen` opens `LevelCompletePage`
(`src/game/frontend/`), the 30 Hz page of `LevelCompleteStartup` and
`LevelCompleteUpdate` (`tempopt.c:5792-6067`), drawn by `LevelCompleteView` from the
positions in `LevelCompleteLayout`. Retail has run `LevelEnd` by then, so the page
sits on the map alone: the HUD, frog, entities and effects hide, the map's animated
polygons keep moving, and a grey 0x60 poly covers the screen. PC draws that poly with
tpage 0, the PSX average blend, so the port mixes it at half strength where the stack
page's fade subtracts. The five frog icons animate at (215, 170 + 20·j) with each
frog's whole seconds (`Frog_time_data`, the run's rounded-up seconds, 99 cap) in two
`med` digits and SEC; TOTAL TIME sums them in three digits; TOTAL SCORE shows the level
score the high-score run recorded (`Frog_score_data[map].he_score`, the better of two
runs of the level in one game), not the running total. When the next arcade row is in
the same world the page shows NEXT, the next level's name image, PRESS FIRE and the
`select4` prompt ("[ESC] SELECT LEVEL"), plays the level-complete sting and pauses the
music; at a world's end it shows ZONE COMPLETE and PRESS FIRE with the music playing
(the zone music is PSX-only). The gold frog icon shows at (215, 270) when a gold frog
was found on the level or, at a world's end, anywhere in the zone.

The count-down starts at 20 units of 31 ticks and the units stop at 17, so the page
never times out: fire is read once the units pass below 19 (tick 62), when PRESS FIRE
starts blinking 16 ticks on and off; it croaks and either starts the next level,
opened in the stack, or returns to the stack. Escape (PC's triangle) works at once,
opens a closed next level and focuses the stack on it; at a world's end the focus
stays on the completed level. Fire is the bound super-hop key, Enter or Space. The
labels are localised (`next`, `total_time`, `total_score`, `select4`, `opt_sec`);
level names stay English. The [specification](../../../tests/golden/specs/frontend.md#level-complete)
lists the facts and their C lines.

Port differences: the page opens on the COMPLETE transition rather than after the
frog's last animation cel; PRESS FIRE blinks from the page's own counter rather than
`MRFrame_number`; the cave light and the sky drift stay where the level ended; a direct
`--level=` launch shows the statistics alone (no prompt, R restarts, Escape leaves);
the sandbox restarts instead; JUN1 shows the zone-complete variant as a stand-in for
the P16 ending, whose fire follows the ending flow to name entry. The game-over page
is still the placeholder label.

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
`OptionsModels` (`src/rendering/`) loads the models by FrogLord name from
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
(`HighScoreTable`, `src/data/tables/`); retail's tables differ from the vendored
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
with the checker background and the three score lines (`HighScoreText`) beside the
spun-out picture, drawn white with `draw_string` from the texture set's `newfont`
[bitmap font](../assets.md#fonts), centred in the score box by `NewfontText.width` and
nearest filtered. After name entry the tour spins out ORG1 first, then every
level with a new row (camera creeping 20 a tick, a ten-tick wait, a 90-tick hold), then
the main table with the static camera when it has a new row, and times out to the main
menu after 120 ticks; Escape leaves at once. From Options the view opens on the stack:
Up/Down travel, Enter spins a level out, Left shows the main table, Right returns to
the stack and Escape returns to Options. The main menu runs the scrolling table behind
its buttons with the camera following the frog and alternates with the
[attract demos](#attract-cycle). The score lines centre in retail's 192-wide text box (KF-407) while
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
the in-game HUD stay English; the level-complete labels are localized.

## Menu assets

`FrontEndAssets` reads `STARTNTSC.VLO`, `FIXE_VRAM.VLO`, `OPTE_RAM.VLO` and
`LS_ALL.VLO`. The English names are `opt_start`, `opt_options`, `opt_exit`,
`opt_race`, `select_level`, `zone_complete`, `press_fire`, `sel_loading`,
`opt_big_continue`, `opt_yes`, `opt_no`, `opt_paused`, `froglogo`, `newfont` and the
level-complete labels `next`, `total_time`, `total_score`, `select4` and `opt_sec`;
each arcade row also resolves its world, screenshot, stack-name and in-game name images.
Race rows keep their images in `LS_ALLM.VLO` and belong to the multiplayer pages.
The words in the angular face, the level names and the high-score lilies, rank
turtles and score logs draw their [vector lettering](../assets.md#lettering)
images instead of the retail pixels, at the retail sizes.

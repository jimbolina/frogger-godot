# Front-end progression and page flow

The families below describe the single-player front end. Progression and page flow
come from `make_golden_frontend.py`; the [level-select stack](#level-select-stack)
and the [front-end water](#front-end-water) have their own generators. The independent Python generator
replays the frozen C rules over the committed retail level-select rows and
transcribes the page requests. Every rule and request is checked against the C
source. It never reads Godot output.

```sh
python3 tools/make_golden_frontend.py           # write both files
python3 tools/make_golden_frontend.py --check   # diff against the committed files, exit 1 on change
```

The generator needs Python 3's standard library only. It reads
`pc-retail-v3.0e/exe_level_select.tsv` as the level stack and `exe_music.tsv`
for level codes. `--c-reference <dir>` names the frozen C `source/` folder.
The default is `../froggy/engine/vendor/frogger-psx-src/source`; when that
folder is missing, the generator skips the cross-checks. The cross-checks
compare the transcribed `LIBRARY.H` level enum, `gamesys.H` theme enum,
`SELECT.H` `SEL_LF_*` bits, `ent_gen.h` gold-frog bits and the
`SelectLevelInit` flag calls with the C. They also compare the source
`Sel_arcade_levels` order, themes and stack positions with the retail rows (no
differences), and check that each flow row's cited line requests the stated
page.

## Progression (`pc-retail-v3.0e/frontend_progress.tsv`)

The first column gives the row kind. Flags use `SEL_LF_COMPLETED` 1,
`SEL_LF_SELECTABLE` 2 and `SEL_LF_ZONEACCESSIBLE` 4. `levels` and `flags` are
comma-joined values for the 33 arcade rows in stack order.

| Kind | Columns | Meaning |
|---|---|---|
| `constant` | name, value | flag bits and `GEN_ALL_GOLD_FROGS` (1982) |
| `initial` | list (`arcade`/`race`), position, level, code, flags | `SelectLevelInit` (`SELECT.C:599-684`) |
| `complete` | step, level, code, next_level, levels, flags | completes each arcade row in stack order, cumulatively from a fresh stack |
| `replay` | arm, level, next_level, flags | completes the whole first world, then completes its first level again |
| `lookup` | level, flags | `SelectGetLevelFlags` for JUN1 and JUN2 after every `complete` step |
| `gold_frog` | step, theme, gold_frogs, opened_level, flags | collects one gold frog per stack theme from a fresh stack, then the first again |

Rules replayed:

- **Completion** (`LevelCompleteStartup`, arcade arm from `tempopt.c:5849`): the level is
  set to 7. The next arcade row is `next_level` when it has the same
  `li_world_id`; otherwise it is -1. When the last row is JUN1, its
  `li_library_id` becomes JUN2 (`levels` shows 19 at step 32).
- **Opening the next level** (`LevelCompleteUpdate`, `tempopt.c:6029-6063`): the
  `complete` rows use the TRIANGLE arm, which writes 6 only when the next level
  is not selectable. `replay` records both arms. The count-down arm writes 6
  unconditionally, so a replay clears the next level's COMPLETED bit (ORG2 7 to 6).
- **Lookup**: a missing JUN1 or JUN2 falls back to the arcade row that holds
  either (`SELECT.C:790-801`).
- **Gold frog** (`FrogCollectGoldFrog`, `FROG.C:2909-2919`, then
  `SelectLevelCollectGoldFrog`, `SELECT.C:2858-2914`): an already-set theme bit
  changes nothing (opened -1). Otherwise the bit `1 << theme` is set. The first
  run of consecutive same-theme rows with no selectable level has every row of
  that theme set to 4 and its first row set to 6. The `theme` argument is
  `li_theme_no`/`Game_map_theme`, not `li_world_id`. The C walks
  `Sel_level_ptr`, which is the arcade list in arcade play.

Asymmetries replayed as written: completion writes flags on a level even when
it is closed. Race levels are routed by id to the race list.

## Page flow (`synthetic/frontend_flow.json`)

The JSON has `start_page` (retail's seeded page), `p13a_start_page`, `pages`,
`transitions` and `differences`. Each transition has `page`, `event`, `next`,
`phase` (the roadmap slice that implements it) and `source` (the cited
`file:line` request). A retail-overridden row also has `source_next`, the page
the vendored line requests, and `retail`, a KEY_FACTS citation. Page names are
the vendored `OPTIONS_PAGE_*` suffixes. Events describe the condition in the
cited arm.

Global quits (`OPTIONS.C:189`, retail Alt+F4), PSX select+start reset
(`pause.c:118`) and the network pages are not rows. Attract demos (P13e) are
not rows either: they run inside MAIN_OPTIONS, and fire during a demo reuses
the MAIN_MENU rows ([attract cycle](#attract-cycle)).

The P13d rows cover the high-score pages. CONTINUE `arcade`
(`tempopt.c:3993`) and CREDITS `finished` (`credits.c:882`, retagged from P16:
the port folds the outro and credits into its ending page) lead to
HIGH_SCORE_INPUT. HIGH_SCORE_INPUT leaves for MAIN_OPTIONS on `game_quit`
(`hsinput.c:191`) and `no_high_score` (`:224`), both inside its startup, and
for HIGH_SCORE_VIEW on `entered` (`:538`). HIGH_SCORE_VIEW after name entry
returns to MAIN_OPTIONS on `back` (`HSView.c:868`, triangle), `timeout`
(`:928`, the scrolly count-down) and `levels_shown` (`:1072`, the automatic
level tables done without a main score). Opened from the options page it
returns to OPTIONS on `back_to_options` (`:1463`, triangle or start on the
level tables) and `back_to_options_from_scores` (`:912`, triangle on the
scrolly table). OPTIONS `view_high_scores` requests HIGH_SCORE_VIEW
(`tempopt.c:4801`). The view's internal mode switches (`HSView.c:894`, `:1066`,
`:1392`, `:1622`, each requesting HIGH_SCORE_VIEW again) are not page rows.
The port maps `timeout` and `levels_shown` onto one TIMEOUT event and both
options back-outs onto BACK_TO_OPTIONS.

### Retail differences

`differences` records each one. The flow follows retail where it differs:

- **Start and boot order:** retail seeds ANTI_PIRACY. HASBRO_LOGO then requests
  the language page, which silently requests MAIN_OPTIONS. CHECK is never
  entered. INTRO is never entered at boot; the attract loop enters it at the
  -2 rows and wraps, which the port replaces by a main-menu restart (KEY_FACTS
  KF-288, KF-294, KF-343, KF-351). The vendored line
  is kept as `source`/`source_next`.
- **Page numbers:** retail numbers pages +1 through the boot range and +2 from
  LEVEL_SELECT (KF-147, KF-254, KF-288). The files use names only.
- **Escape:** the vendored ESC requests EXIT. In retail, ESC is a pressed-edge
  back key ORed into the TRIANGLE back-outs, and Alt+F4 quits (KF-250, KF-368).
- **Level-select back-out:** KF-250 says `Sel_first_time` is never written
  TRUE, which would make the back-out dead. Vendored `MainOptionsShutdown`
  sets it TRUE (`tempopt.c:2006`), and the generator checks that line. The flow
  follows the frozen C: `back_before_first_play` works until the first level
  after the main menu is chosen.

## Level-select stack

A second generator replays the `SELECT.C` stack for the 3D level select:

```sh
python3 tools/make_golden_stack.py           # write both files
python3 tools/make_golden_stack.py --check   # diff against the committed files, exit 1 on change
```

It reads the arcade rows (with `local_level` and `levels_in_world`) from
`pc-retail-v3.0e/exe_level_select.tsv` and the fresh flags from
`make_golden_frontend.py`. Fixed-point helpers are the project's shared ones
from `make_golden_paths.py`: `rsin`/`rcos` round `sin·4096` half away from
zero, `MRNormaliseVEC` rounds `x·4096/|v|`, and `MROuterProduct12`,
`MRApplyMatrixVEC`/`SVEC` shift sums right by 12. Divisions the C writes
with `/` truncate toward zero. `--c-reference` works as above. The
cross-checks compare every `SELECT.H` define used, the PC (`#else`) panel and
640x480 display defines, the glow defines, `Level_table`, the
`SelectCreateMOF` vertex sign, face index and normal tables, and each
transcribed statement (tiling, camera, lights, slice UVs, gold-frog points,
slide, find-target, camera motion, glow and tint, spin, interpolation, fade,
background) with the squashed C text. They also check that only `HSView.c`
creates the checker background.

### Layout (`synthetic/frontend_stack_layout.json`)

Units are PSX world units, Y down. Keys:

- `constants`: box half sizes 240, `stack_origin` (-2560, 0, -2560),
  `camera_matrix` (rows of `MR_MAT.m`, column 2 is the view axis),
  `camera_translation` (-4864, -3840, -6912), `camera_y_offset` -3840,
  `perspective` 1000, `display` 640x480, slide, camera, spin, glow, panel and
  fade constants, `spin_dest_vec_y` and `spin_dest_vec_roll` (camera-only).
- `lights`: ambient `[32,32,32]`, then three parallels with `rotation_y`
  (4096 per turn), colour and `direction` (the light frame's Z column,
  `[rsin(a), 0, rcos(a)]`).
- `vertex_signs`: per vertex `[x, y, z]` signs of `[240, y_size, 240]`.
- `faces`: `mof_vertices` is `mp_p0..p3`; `gpu_vertices` is the `POLY_FT4`
  corner order (`x0..x3`: top-left, top-right, bottom-left, bottom-right of
  the texture), because `MR_P_FT4.C` stores `p0, p1, p3, p2`. `normal` is
  the C's literal normal, which points into the box. `uv` is
  `world_slice` for faces 0-3 and `world_full` for faces 4-5.
- `spin_image_face`: on the spin box, face 5 shows the level picture with
  image corners `[2, 0, 3, 1]` per GPU corner and tint 128; faces 0-4 copy
  the stack box.
- `rows` (33, stack order): `position`, `level`, `world`, `theme`,
  `local_level`, `levels_in_world`, `y_size` (`240 // levels_in_world`),
  `y_position` (tiled edge to edge, then shifted so the last row is 0),
  `camera_target_y` (`y_position + camera_y_offset`), `slice_v_index`,
  `slice_divisions`, `vertices` (eight `[x, y, z]` at `current_z` 0, stack
  local), `spin_start` and `spin_end` (world positions for a fully extended
  box with the camera on it).
- `gold_frogs`: `level_table`, `themes` (`theme`, its `Gold_frogs` bit and the
  world `slot` it draws on) and `slots` (`corners` in GPU order, world space,
  fixed at startup: the world's first box top edge at z+240 and z-240, then
  the next world's top edge, or the last box's bottom edge for slot 8).
- `high_score_background`: tile count and size, colour, texture pairs (one
  pair chosen by `rand() & 3`), the counter sequence and the offsets for
  each direction.

Slice UVs use integer texels: `h = te_h // levels_in_world`,
`v = te_v0 + local_level·h`, side corners `(u, v)`, `(u+w, v)`, `(u, v+h)`,
`(u+w, v+h)` with `w = te_w`. The texture is `world_selectable_image` when the
row is zone-accessible, otherwise `world_not_tried_image`.

### Motion (`synthetic/frontend_stack_motion.json`)

`tick_order` names the per-tick order. Each scenario has `name`,
`description`, `rows` (`world`, `theme`, `local`, `levels_in_world`,
`flags`), `y_size`, `y_position`, `start_row` (`Sel_arcade_level_ptr`),
`first_time`, `name_width` (the level-name texture width used for panel
positions), `inputs` (`[count, [inputs]]` runs; `up`/`down` are held,
`go`/`back` are pressed on that tick) and `trace`.

Trace row 0 is the state after `SelectLevelStartup`; each later row is the
state after that tick. Keys: `tick`, `input`, `mode` (`SELECTING`,
`SHOW_LEVEL_INFO`, `START_FADE`, `UPDATE_FADE`), `camera_y`, `camera_vel`,
`camera_acc`, `camera_flags` (UP 1, DOWN 2, STATIONARY 4, STOPPING 8),
`target_y`, `work_row`, `glowy_row`, `glow`, `glow_dir`, `current_z` and
`tint` (per row), `first_time`, `events`, `spin` and `fade`. Events are `hop`,
`croak`, `show_info`, `hide_info`, `play`, `back` and `enter_game`; a
scenario ends at `back` or `enter_game`. `spin` is null outside the info view
and otherwise holds `mode` (`OUT`, `IN`, `HOLD`), `time`, `pos`, `vec_y`,
`vec_roll`, `axes` (spin-frame matrix columns X, Y, Z), `status_x` and
`title_x`. `fade` holds `count`, `screen`, `loading`, `title_y`, `prompt_y`
and `name_x`.

| Scenario | Covers |
|---|---|
| `retail_fresh_chain_down_then_up` | fresh retail flags; held DOWN chains ORIGINAL1, SUBURBIA1, FOREST1, VOLCANO1 and stops; one-tick UP stops on FOREST1 |
| `small_glow_cycle_and_tints` | glow cycle while idle, every tint branch, BACK ignored after the first play |
| `small_down_wins_and_release` | DOWN beats UP, release sets STOPPING, re-press while stopping is ignored, locked rows skipped both ways |
| `small_info_back_play_fade` | GO rejected until `current_z` is -480, spin out, GO ignored while spinning, BACK spins in, second GO croaks and fades |
| `small_back_first_time` | BACK ignored while moving, accepted when stationary on the first visit |

Rules replayed (`SELECT.C`):

- **Tick order** (`SelectLevelUpdate`, 1303-1430): slide every tick; in
  SELECTING and SHOW_LEVEL_INFO the glow update runs before the mode update.
  Retail PC calls the glow at the head of both arms. The vendored `#else`
  does not (froggy `MILESTONE51.md` F51-74); the files follow retail.
- **Slide** (2152-2186): rows whose `[y_position - y_size, y_position + y_size]`
  contains the previous tick's camera Y minus the offset move -64 to -480;
  others return +64 to 0. `glowy_row` starts as the work row, and becomes the
  last row whose new `current_z` is below the work row's value from before
  the slide.
- **Camera** (1898-2095): velocity += acceleration, clamped to ±56, then
  added. A move is reached when the old and new Y straddle the target, which
  also sets glow to 64. While stationary, held DOWN, else held UP, else GO,
  else first-visit BACK is read; a failed DOWN search blocks the others. In
  plain GOING_DOWN or GOING_UP, releasing sets STOPPING; a reached target
  chains to the next selectable row or sets STOPPING. STOPPING plus reached
  snaps to the target and zeros velocity and acceleration.
- **Glow and tint** (1486-1535): direction is forced down while the camera is
  not stationary or the value exceeds 160, and up below 96. The step applies
  only at 64 or above. The value therefore cycles 80 to 176 while idle and
  sinks to 48 while moving. Selectable, uncompleted rows of the glowy row's
  theme take the value; completed or inaccessible rows take 128; the rest 64.
  `flags & COMPLETED | !(flags & ZONEACCESSIBLE)` parses as a bitwise OR of
  two truth values and matches a logical OR. Before the first tick,
  `SelectCreateMOF` tints completed rows 128 and the rest 64.
- **Spin** (2284-2647): GO needs `current_z == -480`. The interpolation runs
  before the timer changes, so spin-out uses times 0-10 over 11 ticks and
  HOLD follows. Spin-in runs 10 down to 0 and returns to SELECTING on the
  next decrement. The ease is `(0x1000 + s)/0x2000`, `s = -rsin((5-t)·0x800/10)`
  below 5, else `rsin((t-5)·0x800/10)`. `status_x` eases 672 to 400 and
  `title_x = status_x + 80 - name_width/2`. BACK and GO are read only at HOLD.
- **Fade** (1346-1425): the tick after GO enters UPDATE_FADE with count 1.
  For counts 1-32, screen `count·8-1`, loading `count·4`, title -8, prompt
  +8, and `name_x -= (name_x - (320 - name_width/2)) / (33 - count)`. Count 33
  sets screen 255 and requests GAME.

### Ambiguities and differences

- The checker background (`SelectLevelCreateBG`) is created only by
  `HSView.c` for the high-score stack. The level-select page draws the
  options water and river bed through `HSUpdateWater`. The
  [high-score view](#high-score-view) draws the background from these facts.
- Slice UVs end at `u + w` and `v + h`, one texel past the image, in
  `MR_UBYTE`. Fractions `0..1` of the image are the faithful equivalent.
- Gold-frog slot 0 serves both ORG (bit 5) and ARN (bit 6, never set).
- Spin end positions depend on the shared rounding of `MRNormaliseVEC` and
  `rsin`; the GTE may differ by a unit.
- Retail ORs a pressed-edge ESC into the BACK reads (KF-250); `back` covers
  both.

## Tests and deliberate break

`tests/golden/test_frontend_flow_golden.gd` (asset-free) maps the port's
`FrontEndFlow.table_names()` onto these rows. Port pages that collapse
vendored pages are aliased in the test. Every port row must agree with the
golden rows, and every `P13a`, `P13c` and `P13d` row must be covered. `archive/tests/golden/test_retail_frontend_progress.gd`
builds the stack from the supplied executable and replays every progression
row.

To run the deliberate-break check, change one fact in either file, run
`--check` (exit 1, one-line diff) or the matching test, then restore the file
and rerun. For the stack files, change `camera_y_offset` in the layout or one
fade `screen` value in the motion trace and run `make_golden_stack.py
--check`. For the C cross-checks, copy the C files to a scratch folder,
change one define and pass the copy as `--c-reference`.

## Front-end water

A third generator transcribes the options water and riverbed that most
front-end pages draw behind their menus (`HSInitialiseWater`,
`HSUpdateWater`, `HSView.c:1972-2237`) and the options camera presets:

```sh
python3 tools/make_golden_water.py           # write synthetic/frontend_water.json
python3 tools/make_golden_water.py --check   # diff against the committed file, exit 1 on change
```

It needs Python 3's standard library only and reads no retail data; texture
sizes stay retail, so UVs are fractions. `rsin`, `MRNormaliseVEC` and
`MROuterProduct12` are the shared helpers [above](#level-select-stack).
`--c-reference` works as for the other generators. The cross-checks compare
every `HSView.h` water, wave and perspective define, the `tempopt.h` and
`hsinput.h` camera offsets and sweep times, `vp_frame_count`'s `MR_USHORT`
type, its reset and increment in `MR_VIEW.C`, the prim colours, mesh, UV,
riverbed corner, wave, OT-slot and camera statements, and that each page row's
cited line calls `HSUpdateWater` inside the named update function.

### Water file (`synthetic/frontend_water.json`)

Units are PSX world units, Y down. Keys:

- `constants`: `water_num` and `riverbed_num` `[14, 16]` quads, `*_len` 576
  (0x240), `wave_amp` `[64, 80]`, `wave_freq` `[96, 128]`, `wave_period`
  `[8192, 8192]`, `perspective` 256 (`HIGH_SCORE_VIEW_PERSPECTIVE` 0x100) and
  `clear_colour` black.
- `grid`: 15x17 vertices, row-major with `j` (z) outer. `x` is
  `-(576·14)/2 + i·576` and `z` is `(576·16)/2 - j·576`, so `j` 0 is the far
  edge at +4608. Both meshes rest at y 0; the riverbed's y is never changed,
  so the wave rises above and sinks below it. `corner_steps` gives the
  `[di, dj]` of GPU corners 0-3: quad `(i, j)` uses vertices `(i, j)`,
  `(i+1, j)`, `(i, j+1)` and `(i+1, j+1)`.
- `water`: texture `im_opt_env_sky`, `colour_word` 0x00406060, stored by
  `MR_COPY32` into `r0`, so RGB `[96, 96, 64]`. It is semi-transparent with
  ABR 1. One texture spans the whole mesh: corner `(di, dj)` of quad `(i, j)`
  takes `u = te_u0 + te_w·(i+di)/14` and `v = te_v0 + te_h·(j+dj)/16` with C
  truncation, so the fractions are `(i+di)/14` and `(j+dj)/16`.
- `riverbed`: texture `im_opt_bank3`, RGB `[48, 48, 48]`, opaque. Every quad
  holds the whole texture. `texture_corners` names the texture corner (0
  top-left, 1 top-right, 2 bottom-left, 3 bottom-right, the `te_u0..te_u3`
  pairs) per GPU corner. Odd rows (`j & 1`) copy them in order; even rows
  flip the texture vertically.
- `draw_order`: the riverbed goes into OT slot `vp_ot_size - 1` and the water
  into `vp_ot_size - 3` (`ot_slot_from_back` 0 and 2), so both lie behind every
  depth-sorted primitive and the riverbed draws first. `addPrim` prepends, so
  within one slot the last quad submitted draws first. The flat opaque bed and
  additive water make that order invisible.
- `wave`: `counter` is the options viewport's `vp_frame_count`, 16 bits.
  `period_frames` 128 is the smallest step after which both phases repeat,
  and it divides 65536, so the wrap is seamless. `height_min`/`height_max`
  cover one period. Each `frames` row has `t`, `sin_x` (15 values of
  `rsin(i·8192/14 + t·96)`), `sin_z` (17 values of
  `rsin(j·8192/16 + t·128)`), `heights` (17 rows of 15
  `(sin_x·64 + sin_z·80) >> 12`, arithmetic shift) and `digest`, the
  [list digest](../README.md#digest-convention) of `heights` in vertex order.
  Frames 0, 1, 2, 30, 127, 128, 255, 1000 and 65535 are listed; the generator
  also checks every listed frame against `t + 128`.
- `cameras.options`: `Cameras[0]` with origin `Null_vector` and roll vector
  world Y. `presets` hold `source` and `target` offsets and the resulting
  `MRPointMatrixAtVector` `matrix` (rows of `MR_MAT.m`, column 2 is the view
  axis) and `translation` (the source): `MAIN`, `OPTIONS` and `HS_STATIC`
  from `tempopt.h`, `HS_INPUT` from `hsinput.h`. `sweep_*` replay
  `HSUpdateScrollyCamera` from one preset to the other with
  `OPTIONS_CAMERA_MOVE_TIME` 20: each tick sets the timer to `MAX(1, timer)`
  and decrements it; while it is non-zero each offset moves by
  `(next - current) / timer`, truncated. Tick 19 lands exactly and tick 20
  holds. `scrolly_z_bias` 1152 is the scrolly high-score tracking term below.
- `cameras.level_select`: the stack camera of the
  [layout file](#layout-syntheticfrontend_stack_layoutjson) at perspective 1000.
- `pages`: each page that draws the water, its update function, camera, cited
  `HSUpdateWater` line and a note.

### Rules and retail notes

- **Frame counter.** `HSUpdateWater` reads `vp_frame_count` before the
  options loop renders the viewport, so the first update after creation sees
  0, and the counter rises by 1 per rendered frame (KEY_FACTS KF-074).
  `MRCreateViewport` zeroes it. The options viewport is created by
  `CreateOptionsAfterStream`: at `OptionStart` and again after each FMV
  (`HasbroLogoUpdate`, `IntroStartup`, `OutroUpdate`, `CreditsStartup`). It is
  rendered on every options-loop frame, including pages that hide the water.
  **The wave does not restart when a page opens**; it continues across pages.
  Within one period, only the phase matters.
- **Blend.** The water is semi-transparent with ABR 1. `HSInitialiseWater`
  ORs bit 8 into the PC tpage, which is already set in the retail
  `im_opt_env_sky` data (KF-064). Retail's driver draws rate 1 as
  `ONE`/`ONE`, `F + B` saturating, ignoring packet alpha (KF-175 B1); black
  texels are colour-keyed out (B4). KF-064's "draws opaque" describes the
  froggy engine's rasterizer of that time, not retail. The riverbed is
  opaque.
- **Colour.** Prim colours modulate the texture with 128 as 1.0. Retail's
  driver doubles three colour bytes and clamps at 255 (KF-177), giving
  192, 192, 128 and 96 out of 255.
- **Cameras by page.** `InitialiseOptionsCamera` (`tempopt.c:6353`) points the
  options viewport at `Option_camera_ptr`, sets perspective 256, makes
  `Cameras[0]` the options camera and snaps to `MAIN`. Pages then sweep
  between presets with `OptionsCameraMoveTo*` (timer 20) or main-menu fly-on
  (timer 10). The level select switches the viewport to `Sel_camera_frame`
  and perspective 1000 (`SELECT.C:949`, `:1588`). Its shutdown calls
  `InitialiseOptionsCamera` again, then snaps to `OPTIONS` when the next page
  is OPTIONS.

### Ambiguities

- **Main-menu camera.** The main menu draws the water only inside its
  high-score view (`HSUpdateScrollyHighScores`). With no fly-off or fly-on
  pending, that view sets both offsets' z to
  `frog_z + 1152 + MAIN_*_OFS_Z` each tick, so the menu camera follows the
  scrolling high-score frog and is not static. `MAIN` is the snap value and
  the other axes. The frog's path is the [high-score view](#high-score-view)'s;
  the port's main menu follows it the same way.
- **Settled sweep.** The C leaves `ca_mode` at `CAMERA_MODE_FOLLOW_FROG` when
  a sweep ends, but `HSUpdateScrollyCamera` sets it back to
  `CAMERA_MODE_FIXED_SWEEP` before every call, so the camera holds.
- **`rsin`.** The shared helper rounds `sin·4096`. The PSX table may differ by
  a unit at some angles, which can move one height by 1.
- **UV texels.** Water UVs truncate integer texels; the fractions are the
  faithful equivalent at any texture size. Riverbed corners are the texture's
  own corner pairs.
- **Related.** `HSGetWaterSurfaceInfoFromXZ` (`HSView.c:2697`) samples the
  same wave at arbitrary x, z for floating models; it is not part of this
  file.

### Deliberate break

Change `period_frames` to 64 and run `make_golden_water.py --check` (exit 1,
one-line diff), then restore it. For the C cross-checks, copy the C folder,
change `HIGH_SCORE_VIEW_WAVE_AMP_Z` in `HSView.h` and pass the copy as
`--c-reference`.

## Languages

`make_golden_language.py` writes the language facts for `GameLanguage` and
the localized `FrontEndAssets` lookup:

```sh
python3 tools/make_golden_language.py           # write both files
python3 tools/make_golden_language.py --check   # diff against the committed files, exit 1 on change
```

It reads FrogLord's retail image list and VLO configuration, and the committed
`vlo_files.tsv`/`vlo_images.tsv` for which bank holds each texture id. The
retail locale arithmetic is transcribed from retail page 5 (`0x00444CE0`);
`--map-header` compares it with froggy's pinned `frogger_language_map.h`.
`--c-reference` checks the `tempopt.h` enum order and the `Opt_resource_files`
and `Language_res` bank order in `tempopt.c`. Missing sources skip their check.

### Language file (`synthetic/frontend_language.json`)

| Key | Facts |
|---|---|
| `languages` | Game_language id, key, name, bank letter, ISO code, `FIX?_VRAM.VLO`, `OPT?_RAM.VLO` and the front-end bank upload order |
| `lcid` | `& 0x3FF`, bias 7, bound 9, the ten map bytes and the language each jump-table arm stores |
| `exe` | File offsets of the routine prologue, the map and the five arm stores, with the prologue and store opcode bytes |
| `locale_primary_ids` | ISO 639-1 code to Windows primary language id for the ten ids the map spans |
| `lcid_cases`, `locale_cases` | Locale ids and names with the language they select |
| `name_rule` | Variant order (I, G, F, S), first words taking the prefix form, and variants with no English name |
| `families` | Every English name with localized variants, then its I, G, F and S names |
| `front_end_images` | Each `FrontEndAssets.NAMES` entry, its I, G, F and S names (null when the list has none) and whether every language shares it |

### Retail images (`pc-retail-v3.0e/frontend_language.tsv`)

One row per language and front-end name: `language`, `english_name`,
`source_name`, `texture_id` and the last front-end bank in upload order
holding that id. The retail test loads `FrontEndAssets` for each language,
expects no diagnostics, compares the drawn name and the pixels with that bank's
image, and reads the map and arm stores from the supplied executable.

### Rules and retail notes

- **Detection.** Primary ids 0x07 German, 0x0A Spanish, 0x0C French and 0x10
  Italian select their language; every other id, including the five the map
  spans that ship no language, is English. A locale name maps through its ISO
  code's primary id.
- **Names.** Names whose first word is `opt` or `sel` put the letter after
  that word (`optg_start`, `self_loading`); others append `_<letter>`
  (`select1_g`). A name without variants is shared. `hi_f`/`_g`/`_i`/`_s`
  have no English name.
- **Banks.** Localized texture ids sit in their language's `FIX`/`OPT` bank.
  Ids shared across the five banks have identical pixels, so the port loads
  the language banks after the English ones and English fills any gap.
- **Not covered.** Retail's `Options_text_textures` pointer table is not read;
  level-stack names, the water and the HUD stay English.
- **Level complete.** `next`, `total_time`, `total_score`, `select4` and
  `opt_sec` close the list for the [level-complete page](#level-complete);
  `opt_sec`'s variants take the prefix form and every language finds them in
  `LS_ALL.VLO`.

### Deliberate break

Change the German result of `de_DE` in `locale_cases` to 0 and run
`make_golden_language.py --check` (exit 1), then restore it (exit 0).

## Options page

A generator transcribes the options page (`OptionsStartup`, `OptionsUpdate`,
`OptionsUpdateFrog` and `OptionsSetupVolumeLogAnimatedPolys`,
`tempopt.c:4295-5067`; `HSUpdateFlying` and `HSProjectMatricesOntoWaterSurface`,
`HSView.c:2760-2993`) with the retail PC layout, and replays scripted input
over the port's rows:

```sh
python3 tools/make_golden_options.py           # write synthetic/frontend_options.json
python3 tools/make_golden_options.py --check   # diff against the committed file, exit 1 on change
```

It needs Python 3's standard library only and reads no retail data.
`--c-reference` works as for the other generators. The cross-checks compare
the `tempopt.h` sound, start-volume, row-count, fly and move-time defines and
the option-row enum, `HIGH_SCORE_VIEW_FROG_JUMP_TIME`, and each transcribed
statement (lily, log and title placement, scales, fly-on reset, update order,
back and fire guards, Right/Left edges and clamps, volume commits, glow,
held Up/Down hops, jump parabola, test croak, log cels, fly-off and fly-on
motion) with the squashed C text. The generator also checks that the vendored
z formula with retail's row count and pitch gives KF-110's measured
positions. [Page flow](#page-flow-syntheticfrontend_flowjson) holds the page
rows: OPTIONS backs out to MAIN_OPTIONS by the back key (`tempopt.c:4662`) or
the exit row (`:4782`), goes to CHOOSE_WIN_CONTROLLER on the controller row
(`:4833`) and to HIGH_SCORE_VIEW on the high-score row (`:4801`); the
controller page returns to OPTIONS (`:5744`) and the high-score view does so
through its own back-outs (`HSView.c:1463`, `:912`).

### Options file (`synthetic/frontend_options.json`)

Units are PSX world units, Y down. Keys:

- `constants`: `sound_stages` 8, start volumes 3 (music) and 5 (sound),
  `volume_scale` 127, `frog_jump_time` 12, fly-on and fly-off 10 ticks at
  speeds 0xa0 and 0x100, `fly_on_height` -1600, `camera_move_time` 20,
  `prompt_step` 10, `glow_idle` 0x20, the glow rule and the log cels.
- `volume_levels`: `127 * step / 8` for steps 0-8, the level both
  `MRSND_FX_VOLUME` and `MRSND_CD_VOLUME` take.
- `volume_log_cels`: the cel of the eight log stages per step: stages below the
  step 11 (full), the step's own stage 12 (half), the rest 10 (blank); step 0
  is all blank, so a full log never shows.
- `jump_lift`: `-8 * (36 - (count - 6)^2)` for counts 12 down to 1, the
  parabola above the straight hop line; the landing tick snaps to the lily.
- `cameras`: the controller-page sweep (source 1500, -2400, -1000, target 0)
  and the MAIN and OPTIONS presets of the [water file](#water-file-syntheticfrontend_waterjson).
- `retail`: four lilies at x -0x380 and z `-7*0xc0 + (4 - i)*0x200`
  (0x2c0, 0xc0, -0x140, -0x340), three titles on the first three, one drawn
  log at x 0 on the fourth (two allocated), six extras, the vendored title x
  rule and the scales (KEY_FACTS KF-110).
- `vendored`: the seven-row source layout at pitch 0x180 with two logs.
- `undecoded`: the port's choices where retail is not decoded (below).
- `events`: the event names in order.
- `scenarios`: `name`, `description`, `scores_available`, start volumes,
  `start_row`, `frame_start` (the options viewport frame count seen on tick
  1, rising by one per tick), `inputs` (`[count, [inputs]]` runs; `up`/`down`
  are held, `left`, `right`, `fire` and `back` are pressed on that tick) and
  `trace`.

Trace row 0 is the state after `OptionsStartup`; each later row is the state
after that tick: `row` (the frog's lily), `frog` (`STATIONARY`/`JUMPING`),
`count`, `lift`, `music`, `effects`, `glow` (music and effects model
ambient), `fly_on`, `fly_off`, `camera` (`OPTIONS`, `MAIN`, `CONTROLS`),
`camera_timer`, `test_sound`, `request` (`MAIN_MENU`, `CONTROLS`,
`VIEW_SCORES` or null) and `events`: `hop`, `splash`, `volume_step` (with the
hop sound), `croak`, `volume_test_sound` (the repeating croak),
`stop_test_sound`, `back`, `controls`, `view_scores` and `leave` (the page
request). A scenario ends at `leave`.

| Scenario | Covers |
|---|---|
| `walk_volumes_and_controls` | fire ignored during fly-on, held DOWN hopping every 13 ticks, a step on the landing tick, clamp at 8, Right over Left, fire on a volume row, the test croak, controls fly-off |
| `back_during_fly_and_hop_during_fly_off` | back ignored during fly-on while Right is not, back fly-off, Right ignored while leaving, a hop during fly-off |
| `exit_row_and_low_clamp` | Left at 0, the exit row |
| `scores_row_available` | the high-score row shown and requested at once |

Rules replayed (`tempopt.c`, `HSView.c`):

- **Tick order** (4551-4672): camera timer `MAX(1, t) - 1`, `HSUpdateFlying`
  (fly-on down by one; fly-off down by one and the page request at 0), the
  volume models' ambient reset to 0x20, the frog, then an early return while a
  request is pending. Back is read next, then the stationary frog's row.
- **Frog** (4878-5028): read only while stationary, held Up before Down,
  clamped to the end lilies; the fly counters do not gate it. A hop sets the
  count to 12; landing takes 12 ticks, so a held key hops every 13. Leaving the
  effects row kills the test croak; landing on it starts it.
- **Back and fire** (4650-4672, 4772-4842): back (triangle, start, retail
  Escape) and fire need both fly counters at 0. Back and the exit row set
  fly-off 10 and sweep to MAIN in 20; the controller row sweeps to the
  controls camera; the high-score row requests its page with no fly-off. Fire
  on a volume row only croaks.
- **Volume** (4687-4767): on a stationary volume row the model glows
  `(vp_frame_count & 7) << 5`; Right (pressed) steps up below 8, else Left
  steps down above 0, without wrap. Neither waits for the fly counters.
- **Fly motion** (`HSView.c:2772-2793`, `tempopt.c:4625-4629`, `:5030-5034`):
  while fly-on is non-zero after its decrement, models fall 0xa0 from
  `fly_on_height`, clamped to the water, then sit on it. While fly-off is
  non-zero, models slide 0x100 away from x 0 (positive at x 0) and the frog
  0x100 toward -x. The prompt rises 10 per fly-on tick and falls 10 per
  fly-off tick.

### Retail differences and undecoded choices

- Retail's page has four lilies at pitch 0x200, not seven at 0x180; load and
  save are removed (KF-110, KF-139).
- Retail's `OptionsUpdate` switch was not disassembled, so the row identities
  are undecoded. The port puts exit, view high scores and controller config
  on the titled lilies top to bottom, the vendored order without load/save.
- Retail draws one log, with the effects model beside it
  ([model retail notes](#model-retail-notes)), so its volume row is the
  effects volume. The port shows two volume rows, music then effects, at
  `0x2c0 - row * 0x200`.
  With the high-score row shown the port has five rows where retail's four
  lilies hold exit, view high scores, controller configuration and one volume.
- The idle ambient is 0x20 (`tempopt.c:4617-4622`); no retail measurement
  gives another value.

### Deliberate break

Change `volume_levels[3]` to 48 or `fly_on_height` to -1500 and run
`make_golden_options.py --check` (exit 1, one-line diff), then restore it.
For the C cross-checks, copy the C folder, change `OPTIONS_SOUND_STAGES` in
`tempopt.h` and pass the copy as `--c-reference`. For the flow rows, change
the controller row's `next` in `frontend_flow.json`, or its cited line in a
copied `tempopt.c`, and run `make_golden_frontend.py --check`.

## Options page models

A second generator transcribes where the options page draws its models
(`OptionsStartup`, `OptionsUpdate` and `OptionsUpdateFrog`, `tempopt.c:4295-5067`;
`HSGetWaterSurfaceInfoFromXZ` and `HSProjectMatricesOntoWaterSurface`,
`HSView.c:2697-2800`; the frog jump shadow tables, `FROG.C:136-179`; the
options viewport lights, `options.c:446-454`) and replays scripted input
through the [options page](#options-page) model over the port's rows:

```sh
python3 tools/make_golden_options_models.py           # write synthetic/frontend_options_models.json
python3 tools/make_golden_options_models.py --check   # diff against the committed file, exit 1 on change
```

It needs Python 3's standard library only and reads no retail data.
`--c-reference` works as for the other generators. The cross-checks compare
`Options_extras_coords` and `Options_extras_resource_id`, the shadow-texture
ABR, title and reflection sprite settings, the frog's start action, update
period and croak-sack scale, the prompt start, each model transform and
projection call, the volume-model spin, the shadow projection, every frog
action change, the hop and landing statements, the splash sprite, the fly-off
frog shift, the shadow phase, `High_score_splash_animlist`,
`High_score_log_animated_poly_indices`, the surface and projection statements,
the `HIGH_SCORE_VIEW_WAVE_*`/`WATER_*` defines, the three shadow tables,
the light creation and FrogLord's `GEN_FROG` action list with the C text.

### Models file (`synthetic/frontend_options_models.json`)

Units are PSX world units, Y down; a matrix is nine row-major 4.12 rotation
values and the translation. Keys:

- `constants`: model scales (lilies 0x1600, logs 0x1300 after the half turn
  about X, titles 0x1000/0x1400/0x1000, extras 0x1800, frog 0x1400 on its
  lily's matrix), the volume-model tilt 0x400 and spin `vp_frame_count << 8`,
  the title x rule, the volume-model offset from its log (x 0x400, z -0xc0),
  the 3D sprite scale 10 << 16, the title raise -0x40, the reflection offset
  0x48, colour 0x40, ABR 2 and OT offset 0x10, the splash OT offset -8, the
  prompt start 76 (y = 480 - te_h + offset), the slope step 0x100, the frog's
  update period 2, start action and croak-sack scale 0x200, and the log's
  animated-poly indices.
- `extras`: the vendored seven extras, retail's six (the effects model then
  five statics, measured from the retail executable's extras tables) with
  retail's log z, and the five statics the port draws.
- `lights`: ambient 0x606060 and the parallel light 0xa0a0c0 (red in the
  low byte) whose frame at (0x800, -0x1000, -0x1000) points at the origin.
- `shadow`: the four corner tables, the phase-to-table map and the phase
  images.
- `splash_list`: the landing splash animation list.
- `actions`: FrogLord's `GEN_FROG` action names in index order.
- `log_poly_cels`: the cel of the log's 64 animated polys for steps 0-8.
- `surface`: water heights and normalised x and z slopes at sample points
  and frame counts.
- `scenarios`: `name`, `description`, the [options page](#options-page)
  scenario fields, `title_widths` (te_w by row) and `trace`. Trace row 0 is
  `OptionsStartup`; each later row is the state after that tick with the
  viewport `frame`: the `lilies`, `titles`, `logs`, `volume_models` and
  `extras` matrices, the `frog` matrix and 16.16 `frog_position`, the
  `frog_direction`, the frog `action`, whether the tick set it
  (`action_set`), `looping` (one-shot cleared), the lilies given a splash,
  `prompt_offset`, and the `shadow`'s visibility, phase, whether its corners
  were set onto the water, and its four corners.

| Scenario | Covers |
|---|---|
| `fly_on_hop_and_music` | fly-on, hops with their lift and splashes, DANCE on Right from 0 and on landing on music above 0, one-shot at 0, PANT2 on effects, OUCH on fire, the back fly-off |
| `scores_row_and_controls_fly_off` | three titles with the logs below at the same pitch, a hop each way, the controls fly-off sliding models away from x 0 and the frog left |

Rules replayed (`tempopt.c`, `HSView.c`):

- **Surface** (`HSView.c:2697-2737`): from the water's first vertex,
  `tx = dx * 0x2000 / (14 * 0x240) + t * 0x60` and `tz` likewise with 16 and
  0x80; the height is the summed sines at amplitudes 0x40 and 0x50 shifted by
  12; each slope samples 0x100 further and is normalised.
- **Projection** (`HSView.c:2760-2800`): while fly-on runs (after
  `HSUpdateFlying`) y falls 0xa0, stopping at the water, and sits on it once
  fly-on ends; while fly-off runs x moves 0x100 away from 0 (positive at 0).
  The axes are the x slope, the normalised `z slope x x slope` and
  `x x y`, written as columns, then the model transform times them.
- **Frog** (`tempopt.c:4878-5060`): stationary, it takes its lily's y and its
  rotation times 0x1400, turned half about Y when facing south (the start).
  A hop aims at the new lily's position after this tick's projection, with
  velocities `(target << 16 - position) / 12`; each hop tick moves the line
  y toward the lily, adds the lift and steps x and z; landing snaps to the
  lily, sets WAIT1 and a splash. The fly-off moves it 0x100 left. The matrix
  translation is the 16.16 position shifted by 16.
- **Actions**: WAIT2 one-shot at start; HOP on a hop; WAIT1 on landing, then
  DANCE looping on music above 0; Right from 0 starts PANT2 (effects) or DANCE
  (music) looping; Left to 0 sets one-shot; fire croaks with OUCH, back does
  not (`tempopt.c:4646`).
- **Shadow**: hidden while fly-on runs; phase `((12 - count) * 6) / 12`
  clamped to 0-5 while hopping, else 0; corners are the frog matrix applied to
  the phase's offsets, set onto the water unless a page request was pending
  before the tick.

### Model retail notes

- Retail draws one log and one volume model; its extras tables (high and low
  resource ids, then coordinates) hold `OPT_SFX` at (0x400, -0x400) and the
  five statics, so retail's volume row is the effects volume. The port keeps
  both rows; each volume model sits 0xc0 nearer than its log, which puts the
  effects model on retail's position in the four-row layout.
- Retail picks the high or `_WIN95` twin by the `0x0049476C` flag (KF-096,
  KF-110); the port draws the high-poly `OPTIONSH.WAD` models.

### Deliberate break

Change one `lilies` value in a trace row, or `log_poly_cels[3][0]`, and run
`make_golden_options_models.py --check` (exit 1, one-line diff), then restore
it. For the C cross-checks, copy the C folder, change
`High_score_log_animated_poly_indices` in `HSView.c` and pass the copy as
`--c-reference`.

## Controller page

Retail PC replaces the vendored `ChooseWINController*` stub (`tempopt.c:5711-5770`)
with page 25, a keyboard-redefinition page for four controller records. The
vendored C has no body for it, so the generator transcribes froggy's decoded
retail tables and page (`engine/asset_pipeline/include/frogger_page25_tables.h`,
`engine/mr_stub/src/glue/mr_stub_page25.c`):

```sh
python3 tools/make_golden_controls.py           # write synthetic/frontend_controls.json
python3 tools/make_golden_controls.py --check   # diff against the committed file, exit 1 on change
```

It needs Python 3's standard library only and reads no retail data.
`--froggy-reference <dir>` names froggy's `engine` folder (default
`../froggy/engine`); when it is missing the cross-checks are skipped. They compare
the action list, the four default records, the 83 bindable scancodes with their
English names and `PAGE25_BINDABLE_KEY_COUNT` with the tables header, and
`P25_SLIDE_FRAMES`, the seven `P25_DIK_*` page keys and the six `P25_SFX_*`
sounds with the page. The FrogLord sound names are always checked by index
against `third_party/froglord_cfg/sounds/1997-11-19-pc-retail.cfg`.

### Controls file (`synthetic/frontend_controls.json`)

- `layout`: 4 records of 11 integers, `device, valid, key0..key8`, 44 in all.
  This is `KeyBindings`' serialised form and `ProgressStore.key_bindings`.
  Retail's 0x84-byte record also holds a joystick index and a projected
  15-slot key map, which the port derives instead of storing.
- `devices`: 0 none, 1 keyboard, 2 upwards joysticks.
- `actions`: the nine slots in retail order with their vendored
  `FRInput_default_map` indices (`CAMERA_CLOCKWISE` 10, `CAMERA_ANTICLOCKWISE` 11).
- `defaults` and `default_array`: the shipped records, all valid keyboards. P1
  binds the arrows, Return, R-Ctrl, R-Shift, `'` and `;`; P2 `E R 2 W 1 T Tab 3 4`;
  P3 `N M G B F , Space H J`; P4 `O P 8 I 7 [ Y 9 0`.
- `scancodes`: every DirectInput scancode the port translates, with its `DIK_`
  name, whether it is bindable, its English retail name, and the Godot physical
  `godot_key` and `location` constant names. Left and right modifiers differ
  only by location. Keys outside the table translate to `unknown_scancode` 0.
- `page_keys`, `rules`, `events`: the page's key reads, slide length (16 ticks a
  phase), the `shown` codes (-2 blank, -1 the `_` prompt), capture and validity
  rules, and each event's vendored sound, id and FrogLord name.
- `scenarios`: `joysticks`, `initial` (44 values), `inputs` (`[count, [scancodes]]`
  runs: the scancodes are newly pressed on each of the `count` ticks) and `trace`.
  Row 0 is the state after Startup; each later row is after one Update. Rows give
  `state` (retail's 0-9), `helper_a`/`helper_b`/`helper_c` (chooser, key list and
  capture sub-states), `phase`, `counter`, `record`, `cursor`, `action`,
  `finished` and `events`. `bindings` and `shown` appear when they change.

| Scenario | Covers |
|---|---|
| `enter_and_exit` | 0 -> 4 -> 1, ESC slides out and exits |
| `device_carousel` | LEFT/RIGHT with clamps, RETURN commits none and keyboard, F3 needs the keyboard |
| `record_paging` | F1/F2 clamps, the two-phase record turn, valid re-derived, an unattached joystick dropped to none, ESC refused while invalid |
| `rebind_all_with_refusals` | unnamed and duplicate refusals, a slot's own key accepted, lowest scancode wins, nine captures |
| `capture_escape_undo` | ESC in the capture restores the record; the key list redraws it |
| `exit_refused_until_valid` | a repeated key keeps a record invalid until it is recaptured |
| `joystick_choice` | one attached joystick reached and committed; no key list for it |

### Rules

- **Entry and exit.** State 0 seeds, state 4 slides in for 16 ticks, the
  chooser's first tick reads no keys. ESC on the chooser enters state 9 only when
  every record's valid flag is set, otherwise it croaks; state 9 slides for 16
  ticks and requests OPTIONS.
- **Chooser keys** are tested in retail order on one tick and fall through: ESC,
  RETURN (store the cursor as the device and, for the keyboard, set valid from
  whether the nine keys are distinct), F3 (keyboard only, to the key list), LEFT,
  RIGHT, F1, F2. Paging clamps to records 0-3. LEFT/RIGHT slide 16 ticks; a
  non-free joystick at the end steps the cursor on and slides again. The record
  turn is 16 ticks, a turn that reads the new record's device into the cursor,
  re-derives valid for a keyboard and drops a non-free joystick to none, then 16
  more.
- **Key list.** Its first tick draws the record's nine names. ESC goes back to the
  chooser and F1 starts a capture; both blank the names. States 5-8 run 16 ticks
  per phase.
- **Capture.** The first tick copies the nine keys and shows the prompt in slot 0.
  ESC restores the copy. Otherwise the lowest pressed scancode is refused when it
  has no name or is bound in another record or in this record below the slot.
  An accepted key is drawn, then 16 ticks pass, the prompt moves to the next slot,
  and 16 more pass. After slot 8 valid is re-derived and the page returns to the
  key list.
- **Free devices.** None and keyboard are always free. Joystick `d` is free when
  `d - 2` is an attached joystick that no other record holds. The cursor's upper
  bound is the highest free device for record 0 at startup.

### Retail differences and undecoded choices

- Retail stores records in the registry (`keyboard 0`..`keyboard 3`); the port
  keeps the 44 values in `user://progress.cfg`.
- Retail's bindable test is a filled row in its 256-entry key-name table. The
  port carries the 83 scancodes and English names; localised names come from the
  executable's name rows (`PAGE25_KEY_NAME_LIST` in the tables header).
- Joystick enumeration (`Page25_HighestFreeDevice` with attached devices) is not
  decoded for more than zero devices; the cursor bound rule is the port's.
- The capture scan order and the port's single unknown scancode (0) mean a
  key with no retail identity is refused like an unnamed key.

### Deliberate break

Change `slide_frames` to 15 and run `make_golden_controls.py --check` (exit 1,
one-line diff), then restore it. For the froggy cross-checks, copy the tables
header and page into a scratch `engine` layout, change one default key and pass
the copy as `--froggy-reference`.

## Default high scores

The default main table (`Game_high_score[10]`) and per-level tables
(`Level_high_scores[60][3]`) are read from the player's executable, not
compiled in. A generator reads both from `FROGGER.EXE` independently of the
Godot reader (`HighScoreTable`) and cross-checks them with the
`HSView.c:153-610` initialisers:

```sh
python3 tools/make_golden_high_scores.py "$FROGGER_DATA_DIR"           # write pc-retail-v3.0e/exe_high_scores.tsv
python3 tools/make_golden_high_scores.py "$FROGGER_DATA_DIR" --check   # diff against the committed file, exit 1 on change
```

It needs Python 3's standard library only. It takes `Exe`, `parse_cfg` and
the level codes from `make_golden_exe_tables.py`, and turns addresses into
file offsets with the build's `ramOffset`. `--c-reference DIR` (default
`../froggy/engine/vendor/frogger-psx-src/source`) parses `HSView.c`: it
keeps the non-`DEBUG` branches, evaluates character literals (`'Z'+1` is
`[`), C octal (`00100` is 64) and `(60*12)+34`, and zero-fills the main
rows' missing times. Every row is compared with the executable. The two
retail deviations below are expected, and their absence fails. Any other
difference also fails. The generator skips the check, with a message, when
the folder is missing. Without the C, the generator still checks that both
deviation levels hold the recorded retail initials. It also checks that every
initials terminator and padding pair is zero and that `Level_high_scores`
directly follows `Game_high_score`.

### High-score file (`pc-retail-v3.0e/exe_high_scores.tsv`)

Tab-separated, `#` lines are comments. The first column is the row kind:

- `entry`: `table` (`main` or `level`), `level` (-1 for main, else the
  LIBRARY.H level id 0-59), `rank` (0 best), `initials`, `score`,
  `time_0`..`time_4` (checkpoint times in whole seconds). 10 main rows, then 180
  level rows in `level * 3 + rank` order.
- `fact`: `main_pointer` 0x477400, `level_pointer` 0x4774C8, `main_count`
  10, `level_count` 60, `level_ranks` 3, `entry_size` 20 and
  `times_per_row` 5.
- `deviation`: `level`, level code, retail initials and `HSView.c` initials
  (rank order, comma-joined).

Initials are three bytes. Printable ASCII 0x21-0x7E other than backslash is
written as itself and every other byte as `\xNN` (lower-case hex). So `[`
stays `[` and a space is `\x20`, which keeps trailing spaces intact in a
TSV. The Godot test encodes the reader's strings by the same rule.

### Rules and retail notes

- Records are `HIGH_SCORE_ENTRY` (`HSView.h:73-81`): `he_initials[4]`
  (three letters, then zero), `he_score` (u32), `he_time_to_checkpoint[5]`
  (u16), then two bytes of padding, 20 bytes in all.
- Level ids follow LIBRARY.H. The `HSView.c` comments name SWAMP "SEWER" and
  VOLCANO "INDUSTRIAL"; array order is what counts.
- The main rows have no times (all 0). `'Z'+1` gives `[` in four main-table
  initials (`M[B`, `MK[`, `B[S`, `AL[`). The reader keeps the bytes, and
  the drawing code decides how `[` looks.
- JUNGLE 2 (level 19) has scores 64, 11111, 64: the source's `00100` is
  octal. Initials `NE `, `OS ` and `IL ` end in a space.
- Unused slots hold `BUG`, 9999, time 754 (`(60*12)+34`) then zeros. Used
  slots hold 4000/2000/1000 with all five times 60.
- Retail and `HSView.c` differ in exactly two rows of initials. Scores and
  times are identical:

  | Level | Code | Retail | `HSView.c` |
  |---|---|---|---|
  | 54 | VOL1 | SEC, ORG, SKY | STU, ORG, SKY |
  | 56 | VOL3 | STU, MAP, FOR | FOR, MAP, SEC |

  The port uses retail's values because it reads them from the executable.
- The reader is guarded to `pc-retail-v3.0e`, like `ScoreTable`. Other
  builds report "high-score tables are unverified for this build" in
  `ExeTables.errors()`.
- A zero initials byte, which only an edited executable could hold, becomes
  a space in the Godot reader because Godot strings cannot hold NUL. The
  generator would write `\x00`.

### Saved high scores (`HighScoreStore`)

The port keeps achieved scores in `user://high_scores.cfg` (format version 1).
The file holds the same flat fields as the table: `[main]` and `[levels]`
`initials` (PackedStringArray), `scores` and `times` (PackedInt32Array). It
holds no defaults. When it is absent or unusable, the caller fills the
tables from the executable. A missing file is not an error. A corrupt,
other-version or badly formed file is rejected whole, and the error names the
path and ends "using defaults". Lengths must be 10/50 (main) and 180/900
(levels), initials 3 characters, scores ≥ 0 and times 0-65535. Saving
validates first, then writes `path.tmp` and renames it. Unit tests
(`tests/unit/application/test_high_score_store.gd`) cover this file; no golden
does.

### Deliberate break

Change `fact level_pointer 0x4774C8` to `0x4774C9` (or one entry's score)
and run `make_golden_high_scores.py "$FROGGER_DATA_DIR" --check`. It exits 1
with a one-line diff; then restore the file. For the C cross-check, copy
`HSView.c` to a scratch folder and change JUNGLE 2's `11111` to `11112`. Run
`--check --c-reference <scratch>` and expect exit 1 naming level 19 rank 1.
`tests/golden/test_retail_high_scores.gd` compares every reader row, the
layout facts and the deviation levels with the file.

## High-score tables

A generator transcribes the high-score rules: `HighScoreInitialiseData`,
`HighScoreInputStartup`'s bails and qualification, `HighScoreCheckScore`,
`HighScoreCheckArcadeTime`, `HighScoreCheckAllArcadeTimes`,
`HighScoreEnterScore`, `HighScoreEnterArcadeTime` and
`HighScoreAddAllArcadeTimes` (`hsinput.c:129-1214`), the level-completion and
jungle-statue recording (`gamesys.C:2733-2766`, `:3493-3513`), the checkpoint
seconds (`FROG.C:2833-2842`) and `HighScoreBuildArcadeTimeTable`
(`HSView.c:1662-1773`) over the `SELECT.C:138-144` score-line templates. It
replays the rules over small synthetic tables:

```sh
python3 tools/make_golden_high_score_tables.py           # write synthetic/frontend_high_score_tables.json
python3 tools/make_golden_high_score_tables.py --check   # diff against the committed file, exit 1 on change
```

It needs Python 3's standard library only and reads no retail data; the
default tables come from the player's executable and are covered elsewhere.
`--c-reference` works as for the other generators. The cross-checks compare
the LIBRARY.H ids of JUNGLE1, JUNGLE2 and ORIGINAL1, the `HIGH_SCORE_ENTRY`
fields and table declarations (`HSView.h`), the three templates parsed from
`Sel_hiscore_text`, the `tempopt.c:1801` run reset and each transcribed
statement with the squashed C text: the reset values, the quit and
no-qualifier bails, the flag reset, the entry order (main score, then arcade
times), both strict `<` comparisons, the JUNGLE2 redirects, the 10-row and
3-row do-while shifts (the main shift must not move times), the new row's run
score and times, both new-score flags, the 'Z' tests, the recording and
statue arms, the timer's rounding loop and the 2971 constant, and the line
builder's blanking, columns, 99:59 cap and zero blanking.
[Page flow](#page-flow-syntheticfrontend_flowjson) holds the page rows.

### Tables file (`synthetic/frontend_high_score_tables.json`)

Keys:

- `constants`: 10 main rows, 60 levels, 3 ranks, 5 checkpoints, 4 run players
  (player 0 only is ported), marker `Z`, reset initials `AAA`, 30 ticks per
  second, `seconds_limit_ticks` 2971 giving `seconds_limit` 99, JUNGLE1 18 and
  JUNGLE2 19, 8 score digits with 7 blankable, the 99:59 cap and the
  `level * 3 + rank` and `level * 5 + checkpoint` indexing.
- `rules`: one prose line per rule with its C lines.
- `templates`: the three `Sel_hiscore_text` strings verbatim.
- `display`: the dropped `%jc` prefix (MRBuildText centre justification), the
  22-character line length and JUNGLE2's table.
- `checkpoint_seconds`: `[ticks, seconds]` pairs.
- `score_text` and `time_text`: `[value, text]` pairs.
- `lines`: `name`, `rows` (`[initials, score, [five seconds]]`) and the
  built `lines`.
- `scenarios`: `name`, `description`, `main` (ten rows, or empty when the
  scenario does not use the main table), `levels` (level id to its three
  rows; unlisted levels hold three empty rows of score 0) and `steps`. Each
  step has `op`, `args`, `result` and `state` after it: `main` (when used),
  the listed `levels`, `recorded` (level ids carrying the marker), `run`
  (level id to `[score, [seconds]]` for recorded levels), `new_main` and
  `new_levels`.

Operations: `qualifies [score]`, `qualifies_arcade []`, `qualifies_any
[score]`, `enter [initials, score]` (rank or -1), `enter_arcade_times
[initials]` (table level of each insertion), `record_level [level, score,
[five ticks]]`, `record_jungle_statue [score]`, `reset_run []` and
`input_startup [score, game_quit]` (`ENTRY`, `NO_HIGH_SCORE` or
`GAME_QUIT`).

| Scenario | Covers |
|---|---|
| `main_strict_and_tie_below` | an equal score not qualifying, a tie entering below the equal row, the 10-row shift moving initials and score only and dropping the last row |
| `main_top_bottom_and_miss` | a miss leaving the flag clear, top, bottom (no shift) and middle insertion |
| `level_record_and_better_overwrite` | the first record, lower and equal scores kept, a higher score replacing score and seconds, out-of-range levels ignored, the run reset |
| `level_shift_moves_times` | arcade qualification, a tie below, a 3-row shift moving times, a top insertion, flags and the levels in level order |
| `jungle_redirect` | a JUNGLE2 record checked and entered against JUNGLE1's table, the new row taking JUNGLE1's (unrecorded) run data |
| `jungle_statue` | the statue's zero-time record and keep-the-better rule, two insertions into JUNGLE1's table both taking JUNGLE1's run data |
| `startup_outcomes` | the quit bail, the no-qualifier bail leaving flags, a main and an arcade qualifier opening the entry and clearing flags |

Rules replayed:

- **Recording** (`gamesys.C:2733-2766`): at level completion player 0's run
  row for `Game_map` is written if it lacks the 'Z' initial (marking it) or
  if its score is below the new level score `fr_score - fr_prev_score`; score
  and the five `Frog_time_data` seconds are stored together. The statue
  (`gamesys.C:3493-3513`, only with `Game_map == LEVEL_JUNGLE2`) applies the
  same rule to JUNGLE1's row with zero times.
- **Seconds** (`FROG.C:2833-2842`): at checkpoint collection in arcade mode
  the count-up timer `Game_map_timer_decimalised` (30 Hz ticks, reset to 0 at
  level start, `gamesys.C:823`, advanced by `Game_map_timer_speed >> 16` per
  tick, `:1677`) is rounded up to a multiple of 30; 2971 or more gives 99,
  otherwise the value / 30. The port's `checkpoint_times` keep the pre-round
  ticks (`cp_time`, `FROG.C:2827`), so the board applies the same rounding.
- **Qualification** (`hsinput.c:178-226`): a pause-menu quit bails first; the
  game score qualifies when some main row's score is below it; in arcade mode
  every level with the 'Z' initial is compared with its table (JUNGLE2 read as
  JUNGLE1) the same way. Nothing qualifying bails to MAIN_OPTIONS. Otherwise
  `New_high_scores` and `New_high_score` are cleared (`:384-390`).
- **Entry** (`hsinput.c:509-545`): the main score is entered first, then every
  marked level in id order. `HighScoreEnterScore` (`:792-844`) takes the first
  row whose score is below; a do-while from row 9 moves rows down with
  initials and score only. `HighScoreEnterArcadeTime` (`:871-955`) does the
  same over three rows, moving times too; the new row takes the entered
  initials and the run score and times of the redirected level.
- **Lines** (`HSView.c:1690-1757`): columns 3-23 of the template are blanked;
  column 3 is the rank digit, 4 a dot, 5-7 the initials verbatim, 9-16 the
  score's low eight digits with leading zeros blanked up to column 15, and
  18-23 `MM:SSs` from the sum of the five times, with minutes above 99 shown
  as 99:59. Column 24 keeps the template's space.

### Differences and notes

- Race tables (`HighScoreCheckAllRaceScores`, `HighScoreAddAllRaceScores`,
  `HighScoreBuildRaceScoreTable`) are not covered; race play is P15.
- The `%jc` prefix is a text-area control code, so the port's lines are the
  22 characters after it and the renderer centres them. Initials are copied
  verbatim: the default tables' '[' ('Z' + 1) stays '[' and draws as that
  newfont cell (`GAMEFONT.C` puts '[' at 216, 8); no text transform makes it
  a dot.
- A JUNGLE2 insertion takes JUNGLE1's run row, not JUNGLE2's
  (`hsinput.c:884-885` redirects before `:943-950` read
  `Frog_score_data[level_number][0]`). With JUNGLE1 unrecorded the new row
  scores 0 with zero times; with both recorded one game can insert twice
  into JUNGLE1's table. The port keeps this.
- `record_level` ignores levels outside 0-59 (the C indexes unchecked).
- Comparisons in the C are unsigned 32-bit; scores here are never negative.

### Deliberate break

Change `checkpoint_seconds`' `[2971, 99]` to `[2971, 100]` and run
`make_golden_high_score_tables.py --check` (exit 1, one-line diff), then
restore it. For the C cross-checks, copy the C folder, change `2971` in
`FROG.C`, a `total_time < time` in `hsinput.c` to `<=`, or one template in
`SELECT.C`, and pass the copy as `--c-reference` (exit 1 naming the
statement). For the flow rows, change `credits.c:882` or `HSView.c:1463` in
the copy and run `make_golden_frontend.py --check --c-reference`.

## High-score entry

A generator transcribes the name-entry page (`HighScoreInputStartup`,
`HighScoreInputUpdate`, `HSInputInitialiseCamera` and `HSInputUpdateFrog`,
`hsinput.c:178-545` and `:1267-1608`; the `HSINPUT.H` defines; the poly-piece
pop timer, `FROG.C` `FrogStartPolyPiecePop` and `EFFECTS.C`
`UpdatePolyPiecePop`) and replays scripted input for player 0:

```sh
python3 tools/make_golden_high_score_entry.py           # write synthetic/frontend_high_score_entry.json
python3 tools/make_golden_high_score_entry.py --check   # diff against the committed file, exit 1 on change
```

It needs Python 3's standard library only and reads no retail data.
`--c-reference` works as for the other generators. The cross-checks compare
the `HSINPUT.H` extras, initials, jump-time, RUB/END and camera defines,
`HIGH_SCORE_VIEW_PERSPECTIVE`, `FROG_POLY_PIECE_POP_DURATION`, the
`FROG_DIRECTION_*` order, the `sound.h` enumerators at ids 3, 5, 6, 15 and 17,
the `gnm_frog.h` actions, `FR_GO`, the letter and extra resource tables and
extra coordinates (parsed from the C arrays), the three WIN95
`SFX_SEL_HI_SCORE_COUNT` arms ruling R11 replaces, and each transcribed
statement (both bails, pad and initials-pad placement, start cell and facing,
blank initials, scales and projections, the flip rotation, update order, the
shadow loop, completion test and view request, the held-direction chain, the
fire guard, RUB, END, letter, dot and space writes, the occupied-pad refusal,
hop start, parabola, landing, splash sprite, shadow phase, pop update and flip
steps) with the squashed C text. Every run also checks FrogLord's retail sound
list (`GEN_FROG_CROAK`, `GEN_FROG_FLY_GULP`, `GEN_FROG_HOP`, `GEN_SPLASH01`,
`GEN_FROG_EXPLODE` at those ids) and its `GENM_FROG` flipbook actions.

### Entry file (`synthetic/frontend_high_score_entry.json`)

Units are PSX world units, Y down. Keys:

- `constants`: the 10 by 3 grid, 3 initials, 6 extras, pads 26 (dot), 27
  (space), 28 (RUB/BACK) and 29 (END), `frog_jump_time` 6, flip step 0x100,
  swap angle 0x500 resumed at -0x300 (8 ticks), `pop_duration` 32, pad scale
  0x1300, frog scale 0x1400, the blank model, the sounds (id, FrogLord name,
  C enumerator), the frog flipbook actions and update period 2, and the view
  request (HIGH_SCORE_VIEW, automatic, LEVEL_SELECT, STATIC, `From_options`
  FALSE).
- `jump_lift`: `-8 * (9 - (count - 3)^2)` for counts 6 down to 1; the landing
  tick snaps to the pad, so the drawn arc is 0, -40, -64, -72, -64, landed.
- `layout`: the 30 pads `[x, z, model, character]` at
  `x = (i % 10) * 0x100 - 0x480`, `z = (3 - i / 10) * 0x100`; the 12
  initials pads (three per player) at `x = i * 0x100 - 0x100`,
  `z = j * -0x100 - 0x80`; the six extras `[x, z, model]`; the static camera
  (perspective 0x100, source 0, -2400, -256, target 0, 1024, 0, no move); and
  each player's start cell and facing.
- `events`: the event names in order.
- `scenarios`: `name`, `description`, `qualifies`, `quit`, `blocked_cells`
  (pads other active frogs hold), `inputs` (`[count, [inputs]]` runs; `up`,
  `down`, `left` and `right` are held, `fire` is pressed on that tick) and
  `trace`.

Trace row 0 is the state after `HighScoreInputStartup` with its events; each
later row is the state after that tick: `cell` (`grid_z * 10 + grid_x`, the
pad it stands on or hops to), `facing` (`N`, `E`, `S`, `W`), `mode`
(`ACTIVE`, `JUMPING`, `STUNNED`), `count`, `lift`, `position` (initials
entered), `initials`, `pad_angle` (`hs_angle` after the tick), `pad_turn` (the
Z rotation drawn this tick), `pad_letter` (the pad model shown, -1 blank),
`pop_timer`, `request` (`VIEW`, `MAIN_MENU` or null) and `events`: `hop`,
`splash`, `letter` (croak), `rub` (fly gulp), `end` (explode), `entered`,
`no_high_score` and `game_quit`. A scenario stops at its request.

| Scenario | Covers |
|---|---|
| `hop_timing_and_held_repeat` | held hops every 7 ticks, directions ignored mid-hop, Up over Down |
| `blocked_edges_and_fall_through` | all four grid edges, fire read past a blocked Up, Down past a blocked Up, END after one letter, completion 31 ticks after END |
| `three_letters_with_flips` | three flips with the swap at 0x500, the dot, a fourth letter ignored silently, END with three letters |
| `back_at_zero_and_after_letters` | BACK at 0, a space letter, BACK flipping to blank, fire during that flip, END with no letters |
| `end_with_two_letters_and_fire_during_flip` | fire ignored during a flip while hops are not, END with two letters |
| `occupied_pad_refused` | a hop onto player 1's pad refused: the frog turns, stays, and fire is not read |
| `no_high_score`, `game_quit` | MAIN_MENU requested by startup; the update never runs |

Rules replayed (`hsinput.c`):

- **Startup** (186-226, 302-304, 350-355, 392-402): the quit test precedes
  the score tests; either bail requests MAIN_OPTIONS from startup, so the page
  gets no update (`OPTIONS.C` tests the request before the first one). Otherwise player `i` starts on cell
  `(1 + (i >> 1)) * 10 + 4 + (i & 1)` ('O' for player 0) facing
  `(i & 2) + 1` (east); non-qualifiers start STUNNED; initials are spaces.
- **Tick order** (445-518): project the letters at scale 0x1300, set the
  initials pads at the surface height under the bare scale, turn each
  flipping one by its `hs_angle` from the previous tick, project the extras,
  update each frog, then test completion.
- **Frog** (1326-1511): only a stationary frog reads input, as one chain:
  held Up (row > 0), else Down (row < 2), else Left (column > 0), else Right
  (column < 9), else pressed FR_GO when no flip is pending. A direction
  blocked by its edge falls through to the next test. A direction sets the
  facing and grid at once; a hop onto a pad a non-stunned frog holds restores
  the grid, keeps the new facing and skips fire. A hop lasts 6 ticks and a
  held direction hops again on the tick after landing (every 7).
- **Fire** (1381-1456): BACK with letters entered steps back, writes a space
  and flips that pad to the blank model (fly gulp); with none it does nothing.
  END explodes the frog (explode, `FrogStartPolyPiecePop`, pop particles,
  shadow hidden) and stuns it with 0-3 letters. Any other pad with fewer than
  three letters writes `letter + 'A'`, '.' or ' ', flips the next initials pad
  to that pad's model and advances (croak); a fourth is ignored silently.
- **Flip** (1585-1607): after the frog, a pending flip adds 0x100; at 0x500
  the model swaps and the angle becomes -0x300; at 0 the flip ends. Fire
  waits 8 ticks including its own; the drawn turn lags `hs_angle` by a tick.
- **Completion** (509-544, 1575-1583): the pop timer is set to 32 and updated
  once on the END tick; when every frog is stunned with its timer at 0 the
  scores are entered and HIGH_SCORE_VIEW is requested, 31 ticks after END.

### Retail differences and undecoded choices

- Retail PC plays the PSX arm's sounds, 3, 5 and 17, at the letter, RUB and
  END sites (KEY_FACTS R11); `SFX_SEL_HI_SCORE_COUNT` does not exist.
- Retail selects the RUB model, `OPT_LILLYPAD_BLANK.XMR` or its `_WIN95`
  twin, by its runtime map-quality flag (KEY_FACTS KF-096); the port uses the
  high-poly names throughout.
- The header comment says END is chosen automatically when the initials are
  full; the code does not, and neither does the port.
- The shadow projection loop (498-507) reuses `i`, so with more than one
  player only the first frog with a shadow is set onto the water. The port
  places every shadow.
- The fly counters are not run on this page; the port assumes both are 0, as
  every earlier page leaves them.
- The port replays player 0 only; the occupied-pad rule takes the other
  frogs' cells from the caller.

### Deliberate break

Change `flip_swap_angle` to 1024 or one trace row's `initials`, run
`make_golden_high_score_entry.py --check` (exit 1, one-line diff) and the
golden test (fails at that tick), then restore. For the C cross-checks, copy
the C folder, change `HIGH_SCORE_INPUT_FROG_JUMP_TIME` in `HSINPUT.H` or the
`-0x300` resume angle in `hsinput.c`, and pass the copy as `--c-reference`.

## High-score view

`make_golden_high_score_view.py` replays the high-score view page and the scrolly
high-score set from the frozen C. It reuses the level-stack model of
`make_golden_stack.py` (`Selector`, `find_target`, `enable_spin`,
`interpolate`, `slide`) and the water projection of
`make_golden_options_models.py` (`water_info`, `project`, `Mat`). It never reads
Godot output.

```sh
python3 tools/make_golden_high_score_view.py           # write the file
python3 tools/make_golden_high_score_view.py --check   # diff against the committed file, exit 1 on change
```

Standard library only. `--c-reference <dir>` names the frozen C `source/`
folder (default `../froggy/engine/vendor/frogger-psx-src/source`); without it the
cross-checks are skipped. The cross-checks compare the `HSView.h` durations,
frog times, extras count and mode enums; the `tempopt.h` MAIN and HS_STATIC
camera offsets and fly defines; `FROG.H` `FROG_CROAK_MIN_SCALE`; the release
`Game_high_score` defaults; the extras coordinates and models, the log poly
indices and about sixty squashed `HSView.c` statements (startup, shutdown, every
update arm, the scrolly set, `HSUpdateFrog`, `HSUpdateFlying`, the arrows and
prompts); the turtle rotation, main-menu scrolly start and the snap/fly-off
counter writes in `tempopt.c`; `High_score_input_letters_resource_id` and the
automatic entry in `hsinput.c`; and the `LIBRARY.H` positions of ORIGINAL1,
ORIGINAL_MULTI_PLAYER, JUNGLE1 and JUNGLE2.

`test_frontend_high_score_view.gd` replays every scenario through
`HighScoreTour` and `HighScoreScene`, asset-free.

### View file (`synthetic/frontend_high_score_view.json`)

| Key | Content |
|---|---|
| `constants` | durations 120/90, frog wait 18 and jump 12, fly 10/0xa0/0x100 and height -1600, model scale 0x1300, log X scale 0x1200 and tilt 0x500, frog scale 0x1400 and raise -64, throat 0x200, turtle model rotation 0xc00, 12 turtle polys, log poly indices, 8 digits and blank cel 10, splash scale 10<<16 and OT -8, follow offset 1152, creep 20, tour wait 10, the STATIC and MAIN camera offsets, arrow and prompt positions, the frog's start action |
| `models` | FrogLord names of the turtle, log, 30 letter pads and 5 extras |
| `default_table` | the release `Game_high_score` (`HSView.c:156-173`), used by the scene and the layout |
| `layout` | turtles (rank, x, z, cel), pads (rank, column, x, z), logs, extras and `pad_letters` for the default table |
| `log_cels` | `digits` and the 64 `polys` for 250000, 25000, 7, 0, 99999999 and 123456789 |
| `letter_indices`, `port_fallback_letters` | `[character, model index]` |
| `frog_motion` | the hop offset per remaining count 12..1 |
| `arrow_glow` | `[frame, colour byte]` |
| `events` | event names in `HighScoreTour.EventKind` order |
| `tour_stack`, `tour_name_width` | the synthetic eight-row stack (levels 24 25 26 / 48 49 / 12 / 19 20) and name width 96 |
| `tour_scenarios` | page runs: options, `new_levels` pairs, `frame_start`, `inputs`, `ticks` and `trace` |
| `scene_scenarios` | scrolly-set runs: `scrolly` camera, `frame_start`, `inputs` (`fly_off` starts a fly-off after that tick), `model_ticks`, `ticks` and `trace` |

Traces are sampled: tick 0, the first 40 ticks, every eighth tick and every
tick with events or a change of operation, request, pick, prompt, shown level,
arrows, fly counters, stack mode, spin mode or frog jump. The replay runs every
tick and compares the sampled ones. A tour record holds the page fields and,
in the stack view, the selector camera, row, slides and spin (mode, time,
position, panel x); in the table view the fly counters. A scene record holds
the fly counters, the camera follow, the frog, and on `model_ticks` the frog
matrix and every model matrix.

| Scenario | Shows |
|---|---|
| `automatic_tour_then_scrolly` | ORIGINAL1 spun first for its multiplayer flag; locked row 49 skipped; FOR1 by creep, wait, spin, 91-check hold, spin in; new main score restarts as the table, which times out on its 121st tick |
| `automatic_tour_jungle_flag_no_main` | the JUN2 row found by the JUNGLE1 flag; FIRE, LEFT, RIGHT ignored; ends at the main menu |
| `automatic_tour_back` | TRIANGLE during the creep leaves at once |
| `scrolly_after_entry_back` | TRIANGLE on the table stops the fly-on and leaves |
| `manual_from_options` | held DOWN/UP travel with HOP and HOP+CROAK at the ends, FIRE only when out, spin out/in, LEFT to the table, RIGHT back, LEFT while shown, BACK to options |
| `manual_back_while_moving` | TRIANGLE ignored while the camera moves |
| `frog_ping_pong` | 600 ticks with the scrolly camera: fly-on, hops 0→9→0→2, follow offsets |
| `fly_on_then_fly_off` | fly-on, a hop, then fly-off sliding models and frog, LEAVE on its tenth tick |
| `static_camera` | the frog hidden and still |

### Rules replayed

- **Startup** (`HSView.c:633-767`): table view = `HSInitialiseScrollyHighScore`;
  prompt `select3` from options else `skip_hi_score` at x
  `400 + 160 - te_w - 16`, y 400. Stack view = `SelectLevelStartup` at
  ORIGINAL1 (`Sel_arcade_level_ptr`, :718), prompt `select1`/`select5` by
  `Sel_first_time` (`SELECT.C:993-1000`), title hidden while touring
  (`SELECT.C:989`). From options: left arrow (32, 224) flipped, right arrow
  (576, 224); the left hides in the table, the right in the stack (:741-760).
  `HSView_counter = 120` (:766).
- **Restart** (`HSViewShutdown` :837-838): a request for the high-score view
  shuts the page down and starts it in `New_high_score_operation_mode` with
  `HSView_automatic_flag` cleared; the port restarts at the end of that tick.
- **After entry** (:862-873): TRIANGLE requests the main menu on any tick
  (`OptionsCameraSnapToMain` zeroes both fly counters); the update still runs.
- **Table** (:880-933): from options RIGHT = HOP and the stack, TRIANGLE =
  CROAK and options (snap to options zeroes the fly counters); otherwise
  `if (!HSView_counter--)` requests the main menu: unsigned post-decrement, so
  it fires on the 121st tick and leaves 0xffffffff (KEY_FACTS R31-8).
- **Manual stack** (:942-962, 1295-1634): slide; camera as `SELECT.C` without
  the glow; when stationary DOWN/UP held = HOP then travel or CROAK; LEFT = HOP
  and the table; CROSS when fully out = CROAK and spin out (prompt `select3`);
  TRIANGLE|START = CROAK and options. Shown: TRIANGLE spins in (CROAK), LEFT =
  HOP and the table; the spin-in end restores `select1`.
- **Automatic stack** (:1027-1273): ORIGINAL1 or ORIGINAL_MULTI_PLAYER flagged
  = clear both and spin out at once; else, unpicked, `SelectFindTarget(NEXT)`
  until a flagged row (JUN2 reads JUNGLE1, :1081-1084); none left: new main
  score = table with the static camera, else main menu. Picked: camera += 20
  while below the target, then `++HSView_automatic_counter == 10` spins out.
  Spin-out sets the row fully out, croaks and sets the counter to 90; held, the
  counter's 91st check spins in with CROAK. Background counter fixed at 12.
- **Scrolly set** (:2283-2499): turtle i at (-0x480, -0x480 + i*0x100) with
  cel 9 - i on 12 polys, model pre-rotated 0xc00 about Y (`tempopt.c:6292-6298`);
  pad i at (-0x300 + (i%3)*0x100, -0x480 + (9 - i/3)*0x100); log i at
  (0x280, -0x480 + (9 - i)*0x100); digits blank (cel 10) while leading zeros,
  last always shown; five extras; frog on turtle 0 facing north, waiting 18,
  `GEN_FROG_WAIT2`; fly-on 10 from y -1600.
- **Update** (:2563-2641): with the scrolly camera and neither counter set,
  camera source/target z = frog z + 1152 - 1280/-800; `HSUpdateFlying`; pads,
  turtles and extras projected with scale 0x1300, logs with
  diag(0x1200, 0x1300, 0x1300) x rotX(0x500); the frog only with the scrolly camera.
- **Frog** (:2819-2966): waits 18, turns south at 9 and north at 0, hops 12 with
  `(-8<<16) * (36 - (count-6)^2)`, HOP on take-off, SPLASH1 and a splash sprite on
  the landing turtle; rotation 0x1400 x turtle (flipped facing south); y
  raised 64; fly-off slides it 0x100 a tick.
- **Fly-off** (:2983-2993): the counter's tenth decrement raises LEAVE
  (`Option_page_request = High_score_view_delayed_request`).

### Retail differences and undecoded choices

- `HSView.c:2439` initialises `High_score_view_initials_matrix_ptr[i]` in the
  log loop instead of the log matrix: the logs' rotation is unset until the
  first projection. The port starts them as the identity.
- The frog's `fr_lwtrans` translation is unset until the first `HSUpdateFrog`;
  the port starts it at the frog's position. It matters only for a camera
  follow before any frog update, which the C never reaches.
- The page itself never starts a fly-off: its exits are immediate. Only the
  main menu and the load/save pages set `High_score_view_flyoff_counter`;
  `HighScoreScene.start_fly_off` serves them (P13e).
- The arrow colour `(vp_frame_count & 0xff) << 4` is stored in a byte, so it
  ramps 0..0xf0 every 16 frames.
- Letters past `^` (or lower case) would index past the 30-entry resource
  table; the port shows the blank pad.
- A score of 10^8 or more puts its quotient (for example 12) in the first cel.
- The view never runs `SelectUpdateGlowyColours`: tints keep
  `SelectCreateMOF`'s values and arrivals do not darken the glow.
- The camera sweep (`CAMERA_MODE_FIXED_SWEEP`) and the checker background's
  random direction belong to the renderer.
- `HSView_automatic_counter` is a file static reset only at `:1104`, so a tour
  left mid-wait shortens the next tour's first wait in the C; the port starts
  every tour's wait at 0.
- The main menu's `HSUpdateScrollyHighScores` writes the follow z whenever both
  fly counters are 0, and the fixed sweep then blends from it (`CAMERA.C:306-322`);
  the port's menu follows the frog only after its sweep has ended.
- The arrow colour ramps 0..0xf0 past the neutral 0x80; the port caps the
  modulation at neutral.
- The score lines centre in retail's 192-wide text box (KEY_FACTS KF-407, the
  only write of `at_box_w` is 0xc0, sanitize T19); the stack's panel end, title y
  and line pitch keep the vendored values (retail 364, 280 and 20, sanitize T35)
  until the accepted P13b layout is revisited.

### Deliberate break

Changing `"after_input_duration": 120` to 121, the first `["croak", "spin_out"]`
to `["croak"]`, or one frog lift in the JSON makes `--check` exit 1 and the
Godot test fail; restoring passes. A copied C folder with
`HIGH_SCORE_VIEW_FROG_WAIT_TIME` 17, or the turtle x -0x400, fails the
cross-check (exit 1).

## Level complete

`make_golden_level_complete.py` replays the level-complete page from the
frozen C at the PC's 640x480 display. It never reads Godot output.

```sh
python3 tools/make_golden_level_complete.py           # write the file
python3 tools/make_golden_level_complete.py --check   # diff against the committed file, exit 1 on change
```

Standard library only. It checks the two sound ids against FrogLord's retail
sound list. `--c-reference <dir>` names the frozen C `source/` folder (default
`../froggy/engine/vendor/frogger-psx-src/source`); a missing folder skips the
cross-checks. They compare `NUM_OPTION_TICKS`/`NUM_GAME_OVER_TICKS`
(`tempopt.h`), `GEN_MAX_CHECKPOINTS` (`ent_gen.h`), every startup sprite
statement and the count-down, fire and triangle statements built from the
generator's offsets (`tempopt.c`, comments stripped), the gold-frog and five
checkpoint animlists, `HUDGetDigits` (`HUD.C`), the seconds rounding
(`FROG.C`), the overlay polygon (`gamesys.C`) and the `sound.h` generic enum.

`test_frontend_level_complete.gd` replays the file through
`LevelCompletePage`, `LevelCompleteLayout` and
`HighScoreBoard.checkpoint_seconds`, asset-free.

### Level-complete file (`synthetic/frontend_level_complete.json`)

| Key | Content |
|---|---|
| `constants` | start units 20, unit ticks 31, last units 17, fire units 19, blink bit 16, sounds 8 and 3, overlay RGB 0x60 at alpha 0.5, checkpoint cel ticks 2, gold cel ticks 1, 7 cels |
| `seconds` | checkpoint ticks and the whole seconds shown |
| `centring` | image width and the centred left edge |
| `digits` | value, digit count and the shown text |
| `frames` | frame, checkpoint, checkpoint image and gold image |
| `scenes` | page runs, below |

A scene has the `LevelCompletePage.create` arguments (`variant`,
`next_level`, `checkpoint_ticks`, `level_score`, `show_gold_frog`), the
expected `checkpoint_seconds`, `total_seconds`, `startup_sounds`,
`pauses_music` and `shows_prompt`, `inputs` (1-based tick to `fire`/`back`),
`ticks`, an optional `no_exit_after`, `trace` and `sprites_at`. A trace row
is `[frame, units, ticks, accepts_fire, press_fire_visible, sounds, exit]`
after that tick, with the exit as a `FrontEndFlow.Event` name or null. A
trace stops at its exit tick; the test then ticks five more times with fire
and back and expects nothing to change. `sprites_at` gives, after `frame`
ticks of a fresh page, the image widths used for centring and the sprites in
order (`image`, `x`, `y`, top-left corners).

| Scene | Shows |
|---|---|
| `next_level_idle` | the full count-down; no exit within 10000 ticks |
| `fire_at_61_then_62` | fire ignored at units 19, then croak and NEXT_LEVEL |
| `back_at_1` | BACK before fire is read |
| `fire_and_back_at_70` | croak and BACK on one tick |
| `zone_fire_at_100` | ZONE_COMPLETE layout and exit |
| `statistics_ignores_keys` | no prompt, sounds or exit |
| `next_level_idle_wraps` | ticks 0 at tick 124, then 4294967295 |

### Rules replayed

- **Count-down** (`tempopt.c:5803-5804`, :5995-6008): units 20 and ticks 31
  at startup. Each update decrements the `MR_ULONG` ticks (:64-65); at 0 with
  units above 17 the units fall and ticks reload to 31. Units stop at 17, so
  ticks reach 0 on tick 124 and then wrap: the page never times out.
- **Fire** (:6011-6026): once units are below 19, fire zeroes units and ticks
  and croaks (`SFX_GEN_FROG_CROAK` 3); press fire shows while bit 16 of the
  frame count is clear. Startup hides it (:5961).
- **Exit** (:6029-6069): triangle leaves for the level select first; else
  units and ticks both 0 leave for the next level when there is one, else the
  level select.
- **Startup** (:5807-5953): five checkpoint frogs at (215, 170 + 20j), their
  tens and units digits at x 236 and 252 and `opt_sec` at 268; `total_time` at
  (304, 180), three digits at x 330/346/362, y 200, `opt_sec` at (378, 200);
  `total_score` at (298, 225), six digits at x 310..390 step 16, y 245; gold
  frog at (215, 270). Next level: `next`, the level name, press fire and
  `select4` centred at y 390, 410, 430 and 450, `SFX_MUSIC_LEVEL_COMPLETE` (8)
  and the music paused. Zone complete: `zone_complete` and press fire centred
  at y 430 and 448, no sound on PC.
- **Digits** (`HUD.C:2522`): `HUDGetDigits` fills ten digits; the page shows
  the last two, three or six.
- **Seconds** (`FROG.C:2833-2842`): the checkpoint time rounds up to a whole
  second; 2971 ticks or more shows 99.
- **Cels**: checkpoint frogs advance every 2 frames (`HUD.C:641-660`), the gold
  frog every frame (`tempopt.c:668`), over 7 cels.

### Port differences

- Press fire blinks from the page's own update count where retail reads
  `MRFrame_number`.
- The 0x60 overlay is drawn with the PC's average blend (tpage 0,
  `gamesys.C:4459-4491`) at alpha 0.5; PlayStation subtracts it. The overlay
  is documented only; the test does not replay it.
- `STATISTICS` is a port variant with no bottom block; it reads no keys and
  never exits by itself.

### Deliberate break

Set `UNIT_TICKS = 31` to 30 in the generator: `--check` exits 1 (the C
cross-check reports the define; with `--c-reference` pointing nowhere the
diff shows the traces) and the Godot test fails. Restore it (exit 0).

## Attract cycle

`make_golden_attract.py` replays the main menu's attract loop from the frozen
C: the high-score dwell, the demo load, play and fade-out, and the
`Demo_level_table` search. It never reads Godot output.

```sh
python3 tools/make_golden_attract.py           # write the file
python3 tools/make_golden_attract.py --check   # diff against the committed file, exit 1 on change
```

Standard library only. It keeps its own copy of `Demo_level_table` and checks
it against the high-poly list of `pc-retail-v3.0e/exe_demos.tsv` (`level` and
`unlock_level`); the selectable sets come from `exe_level_select.tsv`. A
model of `MainOptionsUpdate` runs one pass call by call and must give the
status run lengths the native engine measured (`4x1 5x819 6x1 0x15`, KEY_FACTS
KF-093, KF-274). `--c-reference <dir>` names the frozen C `source/` folder
(default `../froggy/engine/vendor/frogger-psx-src/source`); a missing folder
skips the cross-checks. They compare `SCORE_TIME` under `PSX_RELEASE`
(`tempopt.h`) and the `PSX_RELEASE` define (`PC/winsys.h`), both fly times,
the `Demo_time == 30` test, the fade units and grey, the slide and brighten
steps, the VIEW_INIT rows and its fall-through, the dwell exit and fire
conjunctions, the DEMO_FINISH loop and both intro arms (`tempopt.c`, comments
stripped), every `Demo_level_table` row and its resource name,
`HSUpdateFlying` (`HSView.c`) and the `Demo_time` count-down (`gamesys.C`).

`test_frontend_attract.gd` replays the file through `AttractCycle` and
`AttractTimer` over the retail-shaped stack of `test_stack_layout.gd`,
asset-free; `test_attract_cycle.gd` and `test_attract_timer.gd` cover the
edge cases.

### Attract file (`synthetic/frontend_attract.json`)

| Key | Content |
|---|---|
| `constants` | score time 810, fly time 10, fade units 30, demo end 30, brighten 16, slide 8, and `view_main_calls` 819 derived from the model |
| `table`, `table_codes` | the 34 rows as `[level, gate]`, -2 for the play-intro rows, and their codes |
| `cycles` | per selectable set (`fresh_boot`, `fresh_boot_and_sky1`, `world_firsts`, `all_open`): `selectable` levels, `codes`, the `first` demo (row 0) and 24 `steps` of `[result, seen, next demo]` after each DEMO_FINISH |
| `dwell_trace` | one pass, below |
| `fire_gate` | `[fly_on, fly_off, loading, delayed, accepted]` |

`dwell_trace` holds `c_status_rle` (`[status, calls]`), `start` (after
`start_dwell`), `view_init` (after the INIT call's fall-through),
`view_main_calls`, `view_main_phases` (phase after each call, run-length),
`view_main_samples` (`[call, phase, fly_on, score_time, menu_slide,
c_sprite_offset]` for calls 1-12 and 817-819), `loading` (`[fly_off,
brightness, done, menu_slide, c_sprite_offset]` per call), `demo_frames` 100,
`playing_first` (`[demo_time, fly_on, menu_slide, c_sprite_offset]` for 12
calls), `playing_phases`, `switch_demo_time` and `fade` (`[phase, fly_off,
brightness, grey, menu_slide, c_sprite_offset]` per call). `menu_slide` is the
port's offset below its rest rows; `c_sprite_offset` is the C's offset below
`Game_display_height - MAIN_MENU_Y_OFFSET` and `c_rest_offset` its rest (18).
The test does not replay the C offsets.

### Rules replayed

- **Dwell** (`tempopt.c:1629-1685`): VIEW_INIT sets `score_time` to
  `SCORE_TIME`, `30*27` under `PSX_RELEASE`, which `PC/winsys.h:29` defines;
  `HSInitialiseScrollyHighScore` seeds the fly-on with 10 (`HSView.c:2492`).
  VIEW_INIT has no `break`, so its call also runs VIEW_MAIN.
  `HSUpdateFlying` (`HSView.c:2983-2993`) decrements the fly counters before
  the slide test, so the fly-on reaches 0 on the ninth VIEW_MAIN call; from
  then `!score_time--` counts 810 down and the call that finds 0 ends the
  dwell: 9 + 810 = 819 VIEW_MAIN calls, then one VIEW_FINISH call.
- **Loading** (:1337-1478): DEMO_LOADING_INIT sets the fly-off to 10 and the
  LOADING sprite black; each DEMO_LOADING call with the counter positive
  slides the menu 8 down and brightens the sprite 16. The load completes on
  the call that reaches 0; GAME_START takes three calls and LEVEL_START one,
  15 DEMO_INIT calls in all. LEVEL_START sets `Demo_time` and flies the menu on.
- **Demo** (:1481-1514): each call slides the menu 8 up while the fly-on runs;
  `GameMainloop` decrements `Demo_time` once per logic tick, clamped at 0
  (`gamesys.C:1357-1363`). `Demo_time == 30` starts the fade with 30 units,
  the fly-off 10 and the LOADING sprite black: a demo of N frames has N - 30
  DEMO_MAIN calls.
- **Fade-out** (:1517-1557): the menu flies off and the sprite brightens while
  the fly-off runs; units fall by one and the subtractive grey is
  `min(255, (30 - units) * 255 / 30)`; units 0 is DEMO_FINISH.
- **Demo order** (:1578-1614): `Num_demo_levels_seen` is session-long and
  starts at 0; row 0 plays first without its gate. DEMO_FINISH steps to the
  next row, wrapping at the -1 terminator, until a -2 row or a row whose gate
  is selectable; row 0 is checked after a wrap. A wrap to row 0 requests the
  intro; a -2 row requests it and steps past, so the following row plays next
  without its gate. Gates are each world's first level, so `world_firsts` and
  `all_open` give one order. From a fresh boot the order is SUB1, FOR1, VOL1,
  intro, ORG1 (the native measurement); with every row open SWP1 is the
  thirteenth demo, and with only SKY1 added SKY1 is the sixteenth.
- **Fire** (:1811-1817): fire is read only with both fly counters 0, no demo
  loading and no delayed request. Up and Down (:1713-1746) never touch
  `score_time`.

### Port differences

- The intro the loop requests at a wrap or a -2 row is replaced by a restart
  of the main menu; `seen` is already positioned for the next demo.
- The port loads a demo synchronously, so LOADING lasts exactly the 10-call
  fly-off; VIEW_FINISH, DEMO_LOADING_INIT, GAME_START and LEVEL_START are
  folded into the transitions.
- The demo ends at `Demo_time <= 30`, latched, where the C tests `== 30` and
  would never end a demo shorter than 30 frames.
- The port's `score_time` does not wrap after the exit.
- The menu rests at `MAIN_MENU_Y_OFFSET` above the bottom with a
  `fly_on * 8` slide; the C places the rows 90 below at VIEW_INIT and moves
  them nine times, so retail's rows rest 18 lower (`c_rest_offset`).
- No row qualifying and a final -2 row would hang or overrun the C; the port
  returns no demo or wraps to row 0.
- Lives stay `DemoSetup.DEMO_LIVES` because the HUD is hidden. Effects never
  reproduce the C's random draws, so a demo's route may differ from native.

### Deliberate break

Set `SCORE_TIME = 30 * 27` to 811 in the generator: `--check` exits 1 (the C
cross-check reports the define; with `--c-reference` pointing nowhere the diff
shows `score_time` 811 and `view_main_calls` 820), and after writing with the
cross-check skipped the Godot test fails. Restore it and rewrite (exit 0).

[Golden data index and shared rules](../README.md).

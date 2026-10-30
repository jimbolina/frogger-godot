# Front-end progression and page flow

Four families describe the single-player front end. Progression and page flow
come from `make_golden_frontend.py`; the [level-select stack](#level-select-stack)
has its own generator. The independent Python generator
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

Global quits (`OPTIONS.C:189`, retail Alt+F4), attract demos (P13e), PSX
select+start reset (`pause.c:118`) and the network pages are not rows.

### Retail differences

`differences` records each one. The flow follows retail where it differs:

- **Start and boot order:** retail seeds ANTI_PIRACY. HASBRO_LOGO then requests
  the language page, which silently requests MAIN_OPTIONS. INTRO and CHECK are
  never entered (KEY_FACTS KF-288, KF-294, KF-343, KF-351). The vendored line
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
  options water and river bed through `HSUpdateWater`. Its facts are kept
  for P13d.
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
vendored pages are aliased in the test. The port skips HIGH_SCORE_INPUT by its
`no_high_score` exit. Every port row must agree with the golden rows, and
every `P13a` row must be covered. `tests/golden/test_retail_frontend_progress.gd`
builds the stack from the supplied executable and replays every progression
row.

To run the deliberate-break check, change one fact in either file, run
`--check` (exit 1, one-line diff) or the matching test, then restore the file
and rerun. For the stack files, change `camera_y_offset` in the layout or one
fade `screen` value in the motion trace and run `make_golden_stack.py
--check`. For the C cross-checks, copy the C files to a scratch folder,
change one define and pass the copy as `--c-reference`.

[Golden data index and shared rules](../README.md).

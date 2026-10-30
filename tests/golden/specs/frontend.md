# Front-end progression and page flow

Five families describe the single-player front end. Progression and page flow
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
  the other axes. The frog's path belongs to the high-score view (P13d).
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
(`:4833`) and to HIGH_SCORE_VIEW on the high-score row (`:4801`, P13d), and the
controller page returns to OPTIONS (`:5744`).

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
  With the high-score row hidden (until P13d) the four rows sit exactly on
  retail's lilies.
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

[Golden data index and shared rules](../README.md).

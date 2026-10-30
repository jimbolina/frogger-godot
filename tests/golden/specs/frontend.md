# Front-end progression and page flow

Two families describe the single-player front end. The independent Python generator
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
and rerun.

[Golden data index and shared rules](../README.md).

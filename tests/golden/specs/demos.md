# Recorded demo facts

`pc-retail-v3.0e/demos.tsv` contains facts for every usable row of both demo
lists, in list order. The independent Python reader follows FrogLord's
`FroggerDemoFile`, reads the executable's table, resolves archive records and
summarizes their decoded inputs. It shares the independent EXE/archive Python
readers, never Godot output. Only text facts are committed.

```sh
python3 tools/golden/make_golden_demos.py <player-data-directory> tests/golden/pc-retail-v3.0e
```

Columns are detail (`low` or `high`), level, resource id, duration, starting
X/Z, stored input count, input list digest, skip count, four directional counts
(up/right/down/left), unused-bit count, super-hop count, tongue count and two
camera-bit counts (counter-clockwise/clockwise). The digest follows the index's
comma-separated decimal convention. Directions count only records with skip
clear. Additive bits count independently, including skip records. These counts
summarize the entire stored buffer, which is independent of elapsed duration.
The header begins with `#` and is excluded from comparison.

The retail test compares every row and every column. Synthetic decoder tests
cover short headers, signed invalid values, independent duration/input lengths,
all raw action bits, exhausted cursors and detached buffer ownership. For the
required deliberate-break check, change one duration fact, run the focused
`test_retail_demos` wrapper and confirm its row mismatch, then restore the file
and rerun successfully. Do not change raw player files.

# Archive: retail readers, importer and retail goldens

Everything here reads the owner's retail Frogger files or verifies that
reading. The game never depends on it: the architecture check rejects any
script, scene or resource under `src/`, `scenes/`, `assets/`, `tests/` or
`tools/` that references `res://archive/`.

| Path | What |
|---|---|
| `tests/golden/` | Tests against the retail files (`test_retail_*.gd`), comparing decoded values with the text facts in `tests/golden/pc-retail-v3.0e/`. |
| `tests/support/` | `RetailTest`, the base class that opens `FROGGER_DATA_DIR`. |
| `tests/.gutconfig.json` | The archive suite; `tools/run_tests.*` runs it only when `FROGGER_DATA_DIR` is set. |

Later S1 sub-phases add `source/` (the readers, moved from `src/source/`),
`import/` (the one-time importer that writes `assets/`), `tools/` and
`third_party/froglord_cfg/`. See the [roadmap](../docs/PORTING.md#s1-and-s2-native-asset-and-modern-rendering-spikes).

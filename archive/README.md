# Archive: retail readers, importer and retail goldens

Everything here reads the owner's retail Frogger files or verifies that
reading. The game never depends on it: the architecture check rejects any
script, scene or resource under `src/`, `scenes/`, `assets/`, `tests/` or
`tools/` that references `res://archive/`.

| Path | What |
|---|---|
| `source/` | The readers that decode `FROGGER.EXE` and `FROGPSX.MWD` into the `src/data` records (`io/`, `config/`, `source/`, `formats/`, `exe/`, `sound/`), and `GameData`, the retail-backed `AssetCatalog`. |
| `import/` | The importer: `import_assets.sh` runs the raw and resource phases of `import_assets.gd` with Godot's import between them and `encode_music.sh` for the CD tracks; `ImportRun` runs the steps of one phase; `steps/` holds one step per asset kind; `ImportContext` fixes the path conventions. It reads the retail files or FrogLord's `modded_FROGGER.EXE` and `modded_FROGPSX.MWD` when their trailer names `pc-retail-v3.0e`. |
| `tests/golden/` | The archive suite's retail goldens (`test_retail_*.gd`), comparing decoded values with `tests/golden/pc-retail-v3.0e/`. |
| `tests/unit/` | Reader unit tests and the synthetic byte builders. |
| `tests/support/` | `RetailTest`, the base class that opens `FROGGER_DATA_DIR`. |
| `tests/.gutconfig.json` | The archive suite; `tools/run_tests.*` runs it only when `FROGGER_DATA_DIR` is set. |
| `docs/formats/` | The retail format references (archives, executable tables, textures, models, animation, maps, build detection). |
| `third_party/froglord_cfg/` | FrogLord's configuration files, unmodified (`third_party/README.md`). |

## Regenerating the assets

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot FROGGER_DATA_DIR=<game-folder> FROGGER_DISC=<FROGGER.mds> archive/import/import_assets.sh
```

`--only=<step,...>` limits the run to named steps and `--force-music`
re-encodes existing Ogg files. The run is idempotent: a second run leaves
`assets/` byte-identical. Hand-edited assets are overwritten by a full run, so
record them as [golden overrides](../tests/golden/specs/imported-assets.md)
and re-import only the steps you mean to.

The data folder may hold the retail pair or a FrogLord save of it
(`modded_FROGGER.EXE` and `modded_FROGPSX.MWD`); the index records which, with
the trailer's build and FrogLord version. `--assets-root=<folder>` (default
`res://assets`) writes elsewhere; it must lie inside the project when the run
writes images or sounds, since Godot imports them there.
`--fallback-root=<folder>` makes the run an overlay: the index records, for
every resource the run did not write, the file under the fallback root, so it
is complete although the folder is not. Open it with
`ImportedAssets.open("res://assets", "", <folder>)`. The music step checks for
Ogg files under the assets root and `encode_music.sh` writes to `assets/`, so
leave `music` out of an overlay's `--only` list.

A complete run without a fallback root prints `import: note stale <path>` for
every file under `textures/banks`, `textures/images`, `maps`, `demos`,
`tables`, `models` and `audio/sfx` that it neither wrote nor found unchanged;
it deletes nothing. Godot's `.import` files are not listed.

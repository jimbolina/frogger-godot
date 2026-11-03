# Archive: retail readers, importer and retail goldens

Everything here reads the owner's retail Frogger files or verifies that
reading. The game depends on it in one place only:
`AssetImporterFactory` (`src/application/setup/asset_importer_factory.gd`),
used by the setup screen and the in-game FrogLord watcher, loads
`import/runtime_import.gd`, which implements the `AssetImporter` interface
([runtime import](#runtime-import)). The architecture check allows
that one dependency and rejects any other script, scene or resource under
`src/`, `scenes/`, `assets/`, `tests/` or `tools/` that references
`res://archive/`.

| Path | What |
|---|---|
| `source/` | The readers that decode `FROGGER.EXE` and `FROGPSX.MWD` into the `src/data` records (`io/`, `config/`, `source/`, `formats/`, `exe/`, `sound/`), and `GameData`, the retail-backed `AssetCatalog`. |
| `import/` | The importer: `import_assets.sh` runs the raw and resource phases of `import_assets.gd` with Godot's import between them and `encode_music.sh` for the CD tracks; `RuntimeImport` runs both phases in-process without the editor import; `ImportRun` runs the steps of one phase; `steps/` holds one step per asset kind; `ImportContext` fixes the path conventions; `disc_tracks.tsv` holds the disc's audio-track facts the music step checks. It reads the retail files or FrogLord's `modded_FROGGER.EXE` and `modded_FROGPSX.MWD` when their trailer names `pc-retail-v3.0e`. |
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

`froglord_watch.gd` (run by `archive/import/froglord_watch.sh --data-dir=<folder>
[--once] [--interval=1.0] [--steps=...]`) imports the folder's pair once, then
again whenever its files change and stay unchanged for one more interval. Each
cycle (`FrogLordWatchCycle`) is an overlay run of `names,tables,demos,maps,catalog`
into `user://froglord/<key>/`, keyed by the first 16 hex digits of the source
fingerprint, with `support_report.tsv` beside its index; earlier folders stay,
since a running game loads maps lazily. Last, it rewrites the pointer
`user://froglord/current.cfg` (`FrogLordPointer`), recording the save folder,
the fallback root and the files' state, which a game launched with
`--froglord` opens and reloads. Files FrogLord has not finished writing are
retried on the next poll; `--once` exits 1 when the cycle was not clean.

The cycle's fallback root defaults to `res://assets`, which the developer
watch keeps; it must hold an index. `RuntimeImport.import_overlay` runs the
same cycle over the base root the game plays from, such as a runtime import
under `user://assets/<fingerprint>/`, into the folder
`AssetImporter.overlay_parent_for` gives that root, and reports the step
labels as progress and honours cancel between steps and items. With FrogLord
on in the setup, the game runs it itself
([FrogLord while playing](../docs/reference/setup.md#froglord-while-playing)).
The cycle saves only records, never meshes or materials, so the game runs it
on a worker thread; a windowed run imported a save on one while the front end
and a level kept drawing.

A complete run without a fallback root prints `import: note stale <path>` for
every file under `textures/banks`, `textures/images`, `maps`, `demos`,
`tables`, `models` and `audio/sfx` that it neither wrote nor found unchanged;
it deletes nothing. Godot's `.import` files are not listed.

## Runtime import

A packaged build ships no retail content, and Godot's editor import (the
`--import` step, `.import` sidecars and `.godot/imported`) does not exist in
it. `RuntimeImport` (`import/runtime_import.gd`) imports the player's copy
into `user://assets/<fingerprint>/` in one in-process pass of every step in
`ImportContext.runtime` mode, which writes the
[runtime layout](../docs/reference/assets.md#runtime-import): textures,
sound effects and music as resources Godot loads directly. Music is read
from the `.mds`/`.mdf` image only when one is given, each track checked
against `import/disc_tracks.tsv`; without a disc the run notes that it has
no music and still succeeds. No `oggenc` is involved.

The run writes into `<root>.partial`. Every saved resource takes over its
path under the final root, so references and the index name that root, and
the folder is renamed to it only when the run had no problems; an earlier
root is moved to `<root>.old` and removed after the rename. A failed or
cancelled run removes its folder. Steps touch no scene tree, and textures
are saved as `PortableCompressedTexture2D` because an `ImageTexture` reads
its pixels back from the RenderingServer when saved. Saving meshes and
shader materials still queries the RenderingServer: a headless run on a
worker thread stalls at the first model mesh that embeds shader materials,
even with the main loop iterating, so the archive suite runs the import on
the main thread.

`AssetImporter.run` reports progress as a fraction and a label and checks
its cancel callable between items; `detect` reports the build, the
fingerprint and a summary, and `detect_froglord` also whether the pair is
FrogLord's and the trailer's FrogLord version. The archive suite's
`test_retail_froglord_overlay_import` imports the round trip's synthetic save
through the seam over a runtime import under `user://` and plays ORG1 from
it. `import/disc_tracks.tsv` is read with
`FileAccess`, so an export preset must include `*.tsv` under
`archive/import/`. The editor-import path stays the default for the committed
`assets/`. The archive suite's `test_retail_runtime_import` compares a
runtime import with them
([runtime import golden](../tests/golden/specs/imported-assets.md#runtime-import)).

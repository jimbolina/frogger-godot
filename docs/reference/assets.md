# Assets

`assets/` holds the game's content as committed Godot resources, imported
once from the owner's `pc-retail-v3.0e` copy by the importer under
`archive/import/` and edited directly afterwards. The game, sandbox, viewers
and inspection tools read only these resources; see the
[roadmap](../PORTING.md#s1-and-s2-native-asset-and-modern-rendering-spikes)
and the [domain model](domain-model.md#asset-identities) for how they are keyed.

## Storage

Binary files under `assets/` (`.png`, `.wav`, `.ogg`, `.res`) are Git LFS
objects (`.gitattributes`). Text resources (`.tres`, `.tscn`), import sidecars
(`.import`) and script ids (`.uid`) stay in plain Git so they diff. A clone
needs `git lfs install` before checkout, or `git lfs pull` afterwards; the test
wrapper refuses to run while any asset is still an LFS pointer.

Import settings are fixed in `project.godot` under `importer_defaults`:
lossless textures without mipmaps, alpha-border fixing or premultiplied alpha,
and uncompressed WAV without trimming, normalisation or baked loops. Loop modes
are applied at runtime from the sound definitions.

## Records

`src/data/` holds one statically typed `Resource` class per record kind, with
every public field exported: `archive/` (`MwiIndex`, `MwiEntry`, `WadFile`,
`WadChild`), `textures/` (`VloFile`, `VloImage` with its `texture`), `models/`
(`MofFile`, `MofStatic`, `MofPart`, `MofAnimated` and their promoted part
records), `maps/` (`MapFile` and its sections), `tables/` (`GameTables` and
every executable table), `sound/` (`SoundBankHeader`, `SoundBankEntry` with its
`stream`), `demos/` (`SourceDemoFile`) and `names/` (`GameNameLists`,
`NameBank`). Records are immutable once loaded: Godot shares loaded resources,
so nothing may mutate one. `MapFile` stores polygons, grid stacks and grid
squares as packed columns (`polygon_records`, `grid_stack_records`, ...) and
rebuilds the record arrays on first access, which keeps SUB1 under 1.7 MB as
a binary resource; compressed saving brings it under 0.4 MB.

`AssetCatalog` is the abstract provider the game is typed against.
`ImportedAssets` implements it over `assets/`; `GameData` in `archive/source/`
implements it over the retail files for the importer and the archive suite.

## Layout

| Path | Content |
|---|---|
| `catalog.tres` | `AssetIndex`: build name, SHA-256 of the retail executable and archive, the MWI index, the asset path of every resource id, WAD membership, model counterparts, page sets and the playable level codes. |
| `tables/<table>.tres`, `tables/game_tables.tres`, `tables/names.tres` | One file per executable table, linked from `game_tables.tres`; FrogLord's name lists. |
| `textures/images/tNNNN.png` | One padded RGBA8 image per texture id (1,858); exact black is alpha 0 where the image is colour-keyed. |
| `textures/banks/<BANK>.tres` | The bank's `VloFile` headers and placement; pixels live in the PNGs. |
| `textures/pages/<GENERAL>+<THEME>/page_NN.png`, `sky.png`, `page_set.tres` | The 14 VRAM pages a map set uses, baked by the importer with the page-wide colour key, plus the sky atlas. The game only loads a `TexturePageSet`; composing pages lives in the archive (`VramPages`). |
| `materials/model/tNNNN_bB[_2s].tres` | One shared `ShaderMaterial` per texture id, blend mode and sidedness. |
| `models/<NAME>/model.res`, `part_NN.res`, `mesh.res`, `model.tscn`, `preview.res` | The `MofFile` record (gameplay, collision and animation source of truth), one `ArrayMesh` per drawn part, the `ModelMesh` with cel atlases and texture tracks, a preview scene, and for animated models an `AnimationLibrary` derived for the editor. `models/options/` holds the options-page models. |
| `maps/<NAME>.res` | Each map and sky-land file as a compressed binary resource. |
| `audio/sfx/<BANK>/NNN_<name>.wav`, `audio/sfx/<BANK>.tres` | 16-bit mono 11,025 Hz effects and the bank headers that reference them. |
| `audio/music/track_NN.ogg` | The CD tracks, Ogg Vorbis quality 6, named by track number. |
| `demos/<NAME>.tres` | The recorded demos. |

Gameplay collision and hilites come from `model.res`; editing a part mesh
changes only what is drawn. Shared materials are files: a view draws a
committed mesh through `ModelMeshCopy`, which gives every surface its own
material copy (a flipbook part's morph surface shares its part's copy, so the
view's projection reaches it) and leaves geometry, cel atlases and textures
shared.

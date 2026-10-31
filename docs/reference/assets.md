# Assets

`assets/` will hold the game's content as committed Godot resources, imported
once from the owner's `pc-retail-v3.0e` copy by the importer under
`archive/import/` and edited directly afterwards. Until S1c lands the folder
does not exist and the game still decodes the retail files at runtime through
`GameData`; see the [roadmap](../PORTING.md#s1-and-s2-native-asset-and-modern-rendering-spikes).

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

## Layout

Decided in S1b and S1c: typed `Resource` records in `src/data/`, `catalog.tres`,
`tables/`, `textures/`, `materials/`, `models/`, `maps/`, `audio/` and `demos/`.
This reference is completed when the importer lands.

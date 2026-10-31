# Current checkpoint

The front end and every accepted level play from the player's retail files.
Launch `tools/play.sh --scene=res://scenes/front_end.tscn`: the main menu
scrolls the high-score table behind its buttons, Start opens the 3D level-select
stack over the animated water, Options sets volumes, rebinds keys and views the
high scores, and menu images follow the OS language or `--language=`. ORG1–ORG5,
SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and
SKY1–SKY4 are accepted by the owner's play check. See the [roadmap](PORTING.md)
and [front end](reference/gameplay/front-end.md). X2's per-part frog lighting
and P12 audio await the owner's play and by-ear checks.

S1 is in progress ([roadmap](PORTING.md#s1-and-s2-native-asset-and-modern-rendering-spikes)).
S1a and S1b are done: Git LFS covers `assets/` binaries, the retail goldens
form the archive suite under `archive/tests/`, the game suite allows no skips,
and every decoded record is a typed `Resource` in `src/data/` behind the
abstract `AssetCatalog` ([assets](reference/assets.md)); the readers in
`src/source/` fill them and `GameData` still serves the game from the retail
files until S1d. The independent oracles for the import goldens are committed
([spec](../tests/golden/specs/imported-assets.md)).

Next: S1c, the importer under `archive/import/` writing `assets/` (PNG
textures and baked pages, model meshes and scenes, map and table resources,
WAV effects, Ogg music, demos) with `ImportedAssets` and the import goldens;
then S1d (runtime switch, owner play check of every level) and S1e (layout
audit, domain model documentation, cleanup). S2 follows.

Effects never reproduce the frozen generators' random draws (owner decision).
Keyboard replays and native attract comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison);
the sandbox and the owner's play checks are the system checks.

The ORG gold baby frog is carried rather than popped; the outro stone frog
belongs to P16. Attract demos, multiplayer, exports, hosted CI and performance tuning keep
separate scope. Owner decisions (licence, repository
host, FMV videos, retail-derived assets) gate later phases. FrogLord
compatibility is deferred from S1 on. Never push.

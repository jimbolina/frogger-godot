# Current checkpoint

The front end and every accepted level play from the player's retail files.
Launch with `tools/play.sh --scene=res://scenes/front_end.tscn`: the main menu
scrolls the high-score table behind its buttons, Start opens the 3D level-select
stack over the animated water, Options sets volumes, rebinds keys and views the
high scores, and menu images follow the OS language or `--language=`. ORG1–ORG5,
SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and
SKY1–SKY4 are accepted by the owner's play check. See the [roadmap](PORTING.md),
[front end](reference/gameplay/front-end.md), [entities](reference/gameplay/entities.md)
and [effects](reference/rendering/effects.md). X2's per-part frog lighting and
P12 audio await the owner's play and by-ear checks.

S1 is in progress ([roadmap](PORTING.md#s1-and-s2-native-asset-and-modern-rendering-spikes)).
S1a is done: Git LFS is enabled for `assets/` binaries, the retail goldens
live in `archive/tests/golden/` as the archive suite, the game suite under
`tests/` is asset-free with no skips (exit 3 retired), and the architecture
check forbids any dependency on `archive/` and prepares the `src/data`
Resource layer. The game still reads the retail files at runtime until S1d.

Next: S1b, the typed `Resource` schema in `src/data/` with the abstract
`AssetCatalog`, splitting the readers into `archive/source/` with no behaviour
change; then S1c (importer, committed assets, import goldens), S1d (runtime
switch, owner play check of every accepted level) and S1e (layout audit,
domain model documentation, cleanup). S2 follows.

Effects never reproduce the frozen generators' random draws (owner decision).
Keyboard replays and native attract comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison);
the [sandbox](../README.md#sandbox) and the owner's play checks are the system
checks.

The ORG gold baby frog is carried rather than popped; the outro stone frog
belongs to P16. Attract demos, multiplayer, exports and hosted CI keep separate
scope. Performance tuning is deferred. Owner decisions (licence, repository
host, FMV videos, licence position on retail-derived assets) gate later phases.
FrogLord compatibility is deferred from S1 on. Never push.

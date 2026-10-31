# Current checkpoint

The front end and every accepted level play from the imported assets.
Launch `tools/play.sh --scene=res://scenes/front_end.tscn`: the main menu
scrolls the high-score table behind its buttons, Start opens the 3D level-select
stack over the animated water, Options sets volumes, rebinds keys and views the
high scores, and menu images follow the OS language or `--language=`. ORG1–ORG5,
SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and
SKY1–SKY4 are accepted by the owner's play check. See the [roadmap](PORTING.md)
and [front end](reference/gameplay/front-end.md). X2's per-part frog lighting
and P12 audio await the owner's play and by-ear checks.

S1 is complete pending the owner's checks
([roadmap](PORTING.md#s1-and-s2-native-asset-and-modern-rendering-spikes)).
The game, sandbox, viewers and inspection tools play from the committed
`assets/` through `ImportedAssets` ([assets](reference/assets.md)); the
retail readers, importer, retail goldens, format references and FrogLord
configs live in `archive/`, which nothing in the game may reference. Launch
`tools/play.sh --level=ORG1`; no data folder is needed. S1e added the
[domain model](reference/domain-model.md) and the
[layout audit](PORTING.md#s1e-layout-audit); the owner's review of both, the
two proposals it raises (`tools/` split, presets as data), and the play check
of every accepted level, the front end and the sandbox from imported
resources are pending.

Next: S2, the modern rendering spike; x4 upscaled textures wait for it
under `assets/textures/images_x4/` ([assets](reference/assets.md#upscaled-textures)).

Effects never reproduce the frozen generators' random draws (owner decision).
Keyboard replays and native attract comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison);
the sandbox and the owner's play checks are the system checks.

The ORG gold baby frog is carried rather than popped; the outro stone frog
belongs to P16. Attract demos, multiplayer, exports, hosted CI and performance tuning keep
separate scope. Owner decisions (licence, repository
host, FMV videos, retail-derived assets) gate later phases. FrogLord
compatibility is deferred from S1 on. Never push.

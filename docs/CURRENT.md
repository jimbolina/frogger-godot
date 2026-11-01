# Current checkpoint

The front end and every accepted level play from the imported assets.
Launch `tools/play.sh --scene=res://scenes/front_end.tscn`: the main menu,
the 3D level-select stack over the animated water, Options (volumes, keys,
high scores) and localised menu images. ORG1–ORG5,
SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and
SKY1–SKY4 are accepted by the owner's play check. See the [roadmap](PORTING.md)
and [front end](reference/gameplay/front-end.md). X2 frog lighting and P12 audio
await the owner's checks.

Everything plays from the committed `assets/` through `ImportedAssets`
([assets](reference/assets.md)); readers, importer and retail goldens live in
`archive/`. `--texture-set=x4` draws the upscaled set (S2a,
accepted; hand-made replacements on hold) and text draws from the `newfont`
bitmap fonts (S2b, accepted). The owner's review of the
[domain model](reference/domain-model.md) and
[layout audit](PORTING.md#s1e-layout-audit) is pending.

S2 is complete: the game draws on Forward+ with scene lights and real
shadows from the map light records, lit models and terrain, reflective
water, a tile-array sky, caves under an omni light and a lit front end,
sandbox and viewers ([lighting](reference/rendering/lighting.md)). The
retail stored-colour pipeline, texture pages and reference projection are
retired and `src/convert/` is now `src/rendering/`. `--shadows=off` and
`--effect-shadows=retail` compare the choices. FrogLord stays the level
editor: the importer under `archive/` remains runnable and a re-import
reproduces `assets/`. Awaiting the owner's play check and the
[look choices](reference/rendering/lighting.md#look-choices). Next: P13e; the S1e
proposals and P14 are the owner's calls ([roadmap](PORTING.md#status)).

Effects never reproduce the frozen generators' random draws. Replays and
native attract comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison);
the sandbox and the owner's play checks are the system checks.

The ORG gold baby frog is carried rather than popped; the outro stone frog
belongs to P16. Attract demos, multiplayer, exports, hosted CI and performance
tuning are separate. The FMV decision gates P16. FrogLord compatibility
is deferred from S1 on. Never push.

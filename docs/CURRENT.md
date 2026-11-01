# Current checkpoint

The front end and every accepted level play from the imported assets.
Launch `tools/play.sh --scene=res://scenes/front_end.tscn`: the main menu,
the 3D level-select stack over the animated water, Options (volumes, keys,
high scores) and localised menu images. ORG1–ORG5, SUB1–SUB5, FOR1–FOR2,
VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and SKY1–SKY4 are
accepted by the owner's play check. Audio (P12), the level-complete page
(P13h), the ORG gold baby frog and the S2g glow and graphics panel are
accepted, as are the asset switch (S1d), the modern rendering (S2c–S2e), X2
frog lighting and the level's three table rows beside a spun-out stack
picture. See the [roadmap](PORTING.md).

Everything plays from the committed `assets/` through `ImportedAssets`
([assets](reference/assets.md)); readers, importer and retail goldens live in
`archive/`. `--texture-set=x4` draws the upscaled set (hand-made replacements
on hold); text draws from the `newfont` bitmap fonts, and the angular
lettering from vector images (S2h, owner play check pending). The owner's review
of the [domain model](reference/domain-model.md) and
[layout audit](PORTING.md#s1e-layout-audit) is deferred.

S2 is complete: Forward+ with scene lights, real shadows, lit models and
terrain, reflective water, a tile-array sky, cave omni lights and a lit
front end ([lighting](reference/rendering/lighting.md)). FrogLord stays the
level editor: a re-import through `archive/` reproduces `assets/`. The
[look choices](reference/rendering/lighting.md#look-choices) keep their
defaults until the owner tunes them. Next: P13e; P14 is the owner's call ([roadmap](PORTING.md#status)).

Effects never reproduce the frozen generators' random draws. Replays and
native attract comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison);
the sandbox and the owner's play checks are the system checks.

The outro stone frog belongs to P16. Attract demos, multiplayer, exports,
hosted CI and performance tuning are separate. The FMV decision gates P16.
FrogLord compatibility is deferred from S1 on. Never push.

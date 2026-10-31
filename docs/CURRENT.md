# Current checkpoint

The front end and every accepted level play from the imported assets.
Launch `tools/play.sh --scene=res://scenes/front_end.tscn`: the main menu,
the 3D level-select stack over the animated water, Options (volumes, keys,
high scores) and menu images in the OS language or `--language=`. ORG1–ORG5,
SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and
SKY1–SKY4 are accepted by the owner's play check. See the [roadmap](PORTING.md)
and [front end](reference/gameplay/front-end.md). X2's per-part frog lighting
and P12 audio await the owner's checks.

S1 is complete pending the owner's checks
([roadmap](PORTING.md#s1-and-s2-native-asset-and-modern-rendering-spikes)).
Everything plays from the committed `assets/` through `ImportedAssets`
([assets](reference/assets.md)); readers, importer, retail goldens and FrogLord
configs live in `archive/`, which the game never references. Launch
`tools/play.sh --level=ORG1` without a data folder. Pending: the owner's review
of the [domain model](reference/domain-model.md) and
[layout audit](PORTING.md#s1e-layout-audit) with its two proposals, and the
play check of every accepted level, the front end and the sandbox.

S2a is accepted: `--texture-set=x4` draws the upscaled textures
([assets](reference/assets.md#upscaled-textures)), with the pages baked
locally by the wrappers; the retail set stays the default and is unchanged.
The ML upscale is a placeholder; hand-made replacements are on hold
([roadmap](PORTING.md#needed-from-the-owner)). S2b is accepted by the owner's
play check: the HUD and the level-stack score lines draw with `draw_string` from
the bitmap fonts under `assets/fonts/`, one per texture set, generated from
the `newfont` grid ([fonts](reference/assets.md#fonts)); the vector font stays
the owner's decision. Next: S2, the modern rendering spike
([roadmap](PORTING.md#s1-and-s2-native-asset-and-modern-rendering-spikes)).

Effects never reproduce the frozen generators' random draws. Replays and
native attract comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison);
the sandbox and the owner's play checks are the system checks.

The ORG gold baby frog is carried rather than popped; the outro stone frog
belongs to P16. Attract demos, multiplayer, exports, hosted CI and performance
tuning keep separate scope. The FMV decision gates P16. FrogLord compatibility
is deferred from S1 on. Never push.

# Current checkpoint

The front end and every accepted level play from the imported assets.
Launch `tools/play.sh --scene=res://scenes/front_end.tscn`: the main menu,
the 3D level-select stack over the animated water, Options and localised menu
images. ORG1–ORG5, SUB1–SUB5, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5,
JUN1, SWP1–SWP5 and SKY1–SKY4 are accepted by the owner's play check, as are
audio (P12), the level-complete page (P13h), the modern rendering (S2), the
S2g glow and graphics panel, X2 frog lighting and the
[attract cycle](reference/gameplay/front-end.md#attract-cycle) (P13e). See
the [roadmap](PORTING.md).

Everything plays from the committed `assets/` through `ImportedAssets`
([assets](reference/assets.md)); readers, importer and retail goldens live in
`archive/`. `--texture-set=x4` draws the upscaled set (hand-made replacements
on hold); text draws from the `newfont` bitmap fonts (accepted) and the
angular lettering from vector images (S2h, accepted). The
[look choices](reference/rendering/lighting.md#look-choices) keep their
defaults until the owner tunes them. The owner's review of the
[domain model](reference/domain-model.md) and
[layout audit](PORTING.md#s1e-layout-audit) is deferred.

FrogLord is the level editor (P14a): the importer accepts a FrogLord save and
writes it as an overlay beside `assets/` (`--assets-root`, `--fallback-root`),
`AssetIndex` records the source, and `tools/asset_report.sh` prints the
`LevelSupportReport` of what a build uses that the port cannot play (nothing,
for the committed assets). The archive suite's round trip imports a synthetic
save and loads ORG1 and CAV3 from it. Next: P14b, reload on change
(`tools/froglord_watch.sh` and `--froglord`), then the owner's call among P15,
P16 and P17 ([roadmap](PORTING.md#status)). A FrogLord save replacing the
retail `assets/` waits on the owner's facts-folder decision.

Effects never reproduce the frozen generators' random draws. Replays and
native attract comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison);
the sandbox and the owner's play checks are the system checks.

The outro stone frog belongs to P16. Multiplayer, exports, hosted CI and
tuning are separate. The FMV decision gates P16. Never push.

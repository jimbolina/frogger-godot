# Current checkpoint

The front end and every accepted level play from the imported assets.
Launch `tools/play.sh --scene=res://scenes/front_end.tscn`: the main menu,
the 3D level-select stack over the water, Options and localised menu
images. ORG1–ORG5, SUB1–SUB5, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5,
JUN1, SWP1–SWP5 and SKY1–SKY4 are accepted by the owner's play check, as are
audio (P12), the level-complete page (P13h), the modern rendering (S2), the
S2g glow and graphics panel, X2 frog lighting and the
[attract cycle](reference/gameplay/front-end.md#attract-cycle) (P13e). The
[pause page](reference/gameplay/front-end.md#pause-page) (P13i), its
[cheat phrases](reference/gameplay/front-end.md#cheats) (P13j) and the
[game-over page](reference/gameplay/front-end.md#game-over) (P13k) await the
owner's play check. See the [roadmap](PORTING.md).

Everything plays from the committed `assets/` through `ImportedAssets`
([assets](reference/assets.md)); readers and importer live in `archive/`. [Texture packs](reference/assets.md#texture-packs) replace the upscaled set; text is the `newfont` bitmap font and the vector angular lettering
(S2h), both accepted. The
[look choices](reference/rendering/lighting.md#look-choices) keep their
defaults until the owner tunes them.

FrogLord is the level editor (P14a): the importer accepts a FrogLord save and
writes it as an overlay beside `assets/` (`--assets-root`, `--fallback-root`),
`AssetIndex` records the source, and `tools/asset_report.sh` lists what a
build uses that the port cannot play (nothing, for the committed assets).
Reload on change (P14b):
`archive/import/froglord_watch.sh --data-dir=<FrogLord folder>` re-imports a
save into `user://froglord/<fingerprint>/` and `tools/play.sh --level=ORG1
--froglord` reopens the level when it does (`F5` on demand), accepted by the
owner's play check. First-run
[setup](reference/setup.md), FrogLord in play, packaged builds and texture packs
(L3–L6) await play checks. A FrogLord save replacing the retail
`assets/` waits on the owner's facts-folder decision.

Effects never replay the frozen generators' random draws. Replays and
native comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison);
the sandbox and play checks are the system checks.

Exports and hosted CI (P17) await the owner's verification on GitHub;
multiplayer and tuning are separate, and the FMV decision gates P16. Never
push.

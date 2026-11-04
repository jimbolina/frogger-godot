# Current checkpoint

The front end and every accepted level play through `ImportedAssets`
([assets](reference/assets.md)). Launch
`tools/play.sh --scene=res://scenes/front_end.tscn`. ORG1–ORG5, SUB1–SUB5,
FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and
SKY1–SKY4 are accepted by the owner's play check, as are audio, the
level-complete page, the modern rendering, glow, frog lighting, the attract
cycle and FrogLord as the level editor with reload on change (P14). See the
[roadmap](PORTING.md).

The repository holds no retail content (P-public). `assets/` is git-ignored
local importer output: `tools/setup_dev.sh --import` fills it from
`FROGGER_DATA_DIR` (and `FROGGER_DISC` for the music); without it a source
run opens the setup screen and imports into `user://` like a player.
[`content/`](reference/assets.md#content) holds the port's own files: the
angular font, 270 lettering images, 49 tile masks composited at runtime over
the player's textures, and the emissive table. `newfont` is built at runtime
from texture 310. The game suite runs asset-free on hosted CI; the imported
and archive suites run only with `FROGGER_DATA_DIR` set and an import
([testing](reference/testing/README.md)).

The pause page with its cheat phrases, the game-over page (P13i–P13k), the
retail disc music across the front end, pause, level-complete and
zone-complete pages
([front-end music](reference/gameplay/front-end.md#music)), first-run setup,
FrogLord in play, packaged builds and texture packs (L3–L6) are accepted by
the owner's play check. Next work: P15 split-screen multiplayer with the
multiplayer front-end pages (P13f); P16 videos, credits and ending once the
FMV decision is made.

Owner decisions before publishing
([needed from the owner](PORTING.md#needed-from-the-owner)): whether
`tests/golden/pc-retail-v3.0e/` stays, and the licence for the project's own
code. Also open: facts for a FrogLord
save replacing `assets/`, the
[look choices](reference/rendering/lighting.md#look-choices), the FMV
decision gating P16, and verification of hosted CI and a first release (P17).

Effects never replay the frozen generators' random draws; replays and native
comparisons are
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison).
Never push.

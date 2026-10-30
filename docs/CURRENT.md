# Current checkpoint

P11 effects and particles is complete and accepted by the owner's play check
on top of the accepted P9 levels. The dedicated game scene opens independent
ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1,
SWP1–SWP5 and SKY1–SKY4 sessions with the original-style English HUD from
player assets. See [controls](../README.md), [roadmap](PORTING.md), the
[entity contract](reference/gameplay/entities.md) and the
[effects reference](reference/rendering/effects.md).

Effects draw the frog's and entities' shadows, trails, particles, pops, splashes,
tints and score popups from committed state; the sandbox has an effects preset.

Effects are presentation-only by owner decision: the port never reproduces the
frozen generators' shared random draws, so its stream diverges from the
original's. Keyboard replays and native attract comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison);
the [sandbox](../README.md#sandbox) and the owner's play checks are the system
checks. Both test modes, strict compilation and architecture checks pass.

P13a front-end flow is complete and accepted by the owner's play check: the game opens on a
main menu and level list ([front end](reference/gameplay/front-end.md)), unlocks
and score carry between levels, and progress saves to `user://progress.cfg`.
Launch with `tools/play.sh --scene=res://scenes/front_end.tscn`.

P13b is implemented and awaits the owner's play check: Start opens the 3D
level-select stack ([front end](reference/gameplay/front-end.md#level-select-stack)),
with independent layout and motion goldens, over the P13g water background
(also awaiting the play check). Options, high scores and the attract cycle are
P13c–P13e.

P12 audio playback is implemented and awaits the owner's by-ear check: sound
effects play from committed voices and music from the disc image
(`--disc=` or `FROGGER_DISC`), see the [audio notes](../README.md#audio).
The ORG gold baby frog is carried rather than popped and the outro stone
frog belongs to P16. Animated per-part lighting, the full
front end (where attract demos may desync), multiplayer, exports and hosted
CI retain separate scope. Performance tuning remains deferred at the owner's
request; the original-hardware target is unverified. The roadmap's owner
decisions (licence, repository host, FMV videos) gate later phases.
Compatibility stays `pc-retail-v3.0e`. Never push.

# Current checkpoint

P11 effects and particles is complete and accepted by the owner's play check
on top of the accepted P9 levels. The dedicated game scene opens independent
ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1,
SWP1–SWP5 and SKY1–SKY4 sessions with the original-style English HUD from
player assets. See [controls](../README.md), [roadmap](PORTING.md), the
[entity contract](reference/gameplay/entities.md) and the
[effects reference](reference/rendering/effects.md).

Gameplay commits the frog's edge-fade, drowning and Volcano tints, the croak
light swell (key C) and splash, croak and reward events. Setup resolves
particle hilites per entity model, the executable's particle generator
records, splash animation lists, pop colours and effect images. Presentation
draws the frog's shadow, hop trail, slide, bubble and fire particles, death
ring, splash, tints, throat swell and score popups, Desert rock shadows,
poly-piece pops, the gold-frog glow, entity splashes and exhaust, cloud, smoke
and fire sprites, with a sandbox effects preset for play checks.

Effects are presentation-only by owner decision: the port never reproduces the
frozen generators' shared random draws, so its stream diverges from the
original's. Keyboard replays and native attract comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison);
the [sandbox](../README.md#sandbox) and the owner's play checks are the system
checks. Both test modes, strict compilation and architecture checks pass.

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

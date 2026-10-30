# Current checkpoint

P11a effect signals and resources are complete on top of the accepted P9
levels. The dedicated game scene opens independent ORG1–ORG5, SUB1, FOR1–FOR2,
VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and SKY1–SKY4 sessions
with the original-style English HUD from player assets. See [controls](../README.md),
[roadmap](PORTING.md) and the [entity contract](reference/gameplay/entities.md).

Gameplay now commits the frog's edge-fade, drowning and Volcano tints, the
croak light swell with its throat scale (`TickCommand.CROAK`, no key bound
yet) and splash and croak events. Setup resolves particle hilites per entity
model, the executable's particle generator records (which differ from the
frozen C in three recorded places), splash animation lists, pop colours and
effect images into `MapSceneData.effects`. Presentation reads none of it yet.

Effects are presentation-only by owner decision: the port never reproduces the
frozen generators' shared random draws, so its stream diverges from the
original after the first slide, drowning, fire death or live particle-hilite
entity. Keyboard replays and native attract comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison),
not acceptance evidence; the [sandbox](../README.md#sandbox) and the owner's
play checks are the system checks. Both test modes, strict compilation and
architecture checks pass.

Next is P11b: frog shadow, hop trail, slide, bubble and fire particle sprites,
death ring, splash ripple, tints and score popups, with the synthetic families
already generated for them. P11c then covers entity shadows, poly-piece pops,
the gold-frog glow, entity splashes, hilite particle sprites and the croak
key. Audio playback, animated per-part lighting, the full front end,
multiplayer, exports and hosted CI retain separate scope. Performance tuning
remains deferred at the owner's request; the original-hardware target is
unverified. The roadmap's owner decisions (licence, repository host, FMV
videos) gate later phases. Compatibility stays `pc-retail-v3.0e`. Never push.

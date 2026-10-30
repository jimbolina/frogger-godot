# Current checkpoint

P9g Sky is complete; SKY1–SKY4 passed the owner's play check. The dedicated
game scene opens independent ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3,
CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and SKY1–SKY4 sessions with the
original-style English HUD from player assets. See [controls](../README.md),
[roadmap](PORTING.md) and the [entity contract](reference/gameplay/entities.md).

Whole-map SKY1–SKY4 run the script-driven balloons, helicopters, hawk, birds,
jets and clouds on existing machinery, plus the generic `TRIGGER` entity and `TriggerEntityCallback` (the
SKY3 magical popping balloon releases the squadron), the 12-byte moving-platform
payload and the sky backdrop drift stepped from the shared RNG on a modelled
`Game_timer`. Freefall entry now clears the whole frozen entity landing mask.

The [sandbox](../README.md#sandbox) is a flat zone arena for the owner's play
checks of terrain and entity mechanics, with Desert, Jungle, Swamp and Sky
hazard presets; it is not acceptance evidence.

Level acceptance is the owner's play check in the game scene. Thirteen levels
keep normal-start keyboard completion replays with per-tick parity as regression
coverage. ORG1, SUB1, FOR1 and VOL1 attract demos match native terminal states;
SWP1, SWP5 and SKY1–SKY4 demos match native traces per tick; CAV1, CAV4,
DES1–DES5 and SWP2–SWP4 demos complete with schedule parity without one; Jungle
has no enabled demo. Both test modes, strict compilation and architecture checks
pass.

P9 is complete; next is the roadmap's remaining phases. Entity shadows, the statue
glow, the hippo and rat splashes, the balloon poly-piece pop, the green Swamp
drowning tint, the player croak light swell and the web wall bounce are
deferred. Audio playback, other effects, animated per-part lighting, the full
front end, multiplayer, exports and hosted CI retain separate scope.
Performance tuning remains deferred at the owner's request; the
original-hardware target is unverified. The roadmap's owner decisions (licence,
repository host, FMV videos) gate later phases. Compatibility stays
`pc-retail-v3.0e`. Never push.

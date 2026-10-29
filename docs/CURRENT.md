# Current checkpoint

P9d Desert is complete. The dedicated game scene opens independent ORG1–ORG5,
SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4 and DES1–DES5 sessions with the
original-style English HUD from player assets. See [controls](../README.md),
[roadmap](PORTING.md) and the [entity contract](reference/gameplay/entities.md).

Whole-map Desert includes falling rocks with ground-snapped bounce targets and
the per-level explosion flipbook overlay, rolling rocks, hopping tumbleweeds,
biting and rattling snakes with path-end turns, swooping vultures, timed croc
heads that bite riders, and cracks that open, drop the frog and sink. Rock and
tumbleweed shadows are tracked in state but not drawn.

The [sandbox](../README.md#sandbox) is a flat zone arena for the owner's play
checks of terrain and entity mechanics, including a Desert hazards preset; it
is not acceptance evidence.

Level acceptance is the owner's play check in the game scene. Thirteen levels
keep normal-start keyboard completion replays with per-tick parity as regression
coverage. ORG1, SUB1, FOR1 and VOL1 attract demos match native terminal states;
CAV1, CAV4 and DES1–DES5 demos complete with schedule parity but have no native
baseline. Both test modes, strict compilation and architecture checks pass.

Next is Jungle, followed by Swamp and Sky; a new mechanic can get a sandbox
preset. Entity shadows, the player croak light swell and the web wall bounce
are deferred. Audio playback, other effects, animated per-part lighting, the
full front end, multiplayer, exports and hosted CI retain separate scope.
Performance tuning remains deferred at the owner's request; the
original-hardware target is unverified. Jungle has no blocker; the roadmap's
owner decisions (licence, repository host, FMV videos) gate later phases.
Compatibility stays `pc-retail-v3.0e`. Never push.

# Current checkpoint

P9e Jungle is implemented and awaits the owner's JUN1 play check. The dedicated
game scene opens independent ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3,
CAV1/CAV3/CAV4, DES1–DES5 and JUN1 sessions with the original-style English
HUD from player assets. See [controls](../README.md), [roadmap](PORTING.md)
and the [entity contract](reference/gameplay/entities.md).

Whole-map JUN1 includes snapping plants with animated collision primitives,
rope bridges that drop after their authored hops, diving hippos, scorpions,
the bouncy mushroom (a plain safe square in retail), generic Jungle movers, and
the outro doors, plinths, gold frogs and stone frogs loaded as statics. The
doors bounce the frog back through the crusher callback. Completing JUN1 shows
the level-complete flow; frozen C's end-of-game sequence and the JUN2 ending
stage belong to P16.

The [sandbox](../README.md#sandbox) is a flat zone arena for the owner's play
checks of terrain and entity mechanics, with a Jungle hazards preset; it is not
acceptance evidence.

Level acceptance is the owner's play check in the game scene. Thirteen levels
keep normal-start keyboard completion replays with per-tick parity as regression
coverage. ORG1, SUB1, FOR1 and VOL1 attract demos match native terminal states;
CAV1, CAV4 and DES1–DES5 demos complete with schedule parity but have no native
baseline; Jungle has no enabled demo. Both test modes, strict compilation and
architecture checks pass.

Next is the JUN1 acceptance, then Swamp and Sky; a new mechanic can get a
sandbox preset. Entity shadows, the statue glow, the hippo splash, the player
croak light swell and the web wall bounce are deferred. Audio playback, other
effects, animated per-part lighting, the full front end, multiplayer, exports
and hosted CI retain separate scope. Performance tuning remains deferred at the
owner's request; the original-hardware target is unverified. Swamp has no
blocker; the roadmap's owner decisions (licence, repository host, FMV videos)
gate later phases. Compatibility stays `pc-retail-v3.0e`. Never push.

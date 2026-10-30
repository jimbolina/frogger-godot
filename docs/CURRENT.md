# Current checkpoint

P9f Swamp is implemented and awaits the owner's play check of SWP1–SWP5. The
dedicated game scene opens independent ORG1–ORG5, SUB1, FOR1–FOR2, VOL1–VOL3,
CAV1/CAV3/CAV4, DES1–DES5, JUN1 and SWP1–SWP5 sessions with the original-style
English HUD from player assets. See [controls](../README.md), [roadmap](PORTING.md)
and the [entity contract](reference/gameplay/entities.md).

Whole-map SWP1–SWP5 include acid squirts, wall crushers with the Swamp crusher
callback, presses, rats, straight and curvy slugs, nuclear barrels that eject
the frog and pop, bobbing waste barrels that drown it, the rotating weir and
the generic Swamp movers and statics. Generic path movers honour the frozen
`LOCAL_ALIGN` flag. Frozen C's end-of-game sequence after JUN1 and the JUN2
ending stage belong to P16.

The [sandbox](../README.md#sandbox) is a flat zone arena for the owner's play
checks of terrain and entity mechanics, with Desert, Jungle and Swamp hazard
presets; it is not acceptance evidence.

Level acceptance is the owner's play check in the game scene. Thirteen levels
keep normal-start keyboard completion replays with per-tick parity as regression
coverage. ORG1, SUB1, FOR1 and VOL1 attract demos match native terminal states;
SWP1 and SWP5 demos match native traces; CAV1, CAV4, DES1–DES5 and SWP2–SWP4
demos complete with schedule parity without one; Jungle has no enabled demo. Both test modes, strict
compilation and architecture checks pass.

Next is Sky; a new mechanic can get a sandbox preset. Entity shadows, the statue glow, the hippo and rat splashes,
the green Swamp drowning tint, the player croak light swell and the web wall
bounce are deferred. Audio playback, other
effects, animated per-part lighting, the full front end, multiplayer, exports
and hosted CI retain separate scope. Performance tuning remains deferred at the
owner's request; the original-hardware target is unverified. Sky has no
blocker; the roadmap's owner decisions (licence, repository host, FMV videos)
gate later phases. Compatibility stays `pc-retail-v3.0e`. Never push.

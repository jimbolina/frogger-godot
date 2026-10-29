# Current checkpoint

P9c Cave is complete. The dedicated game scene opens independent ORG1–ORG5,
SUB1, FOR1–FOR2, VOL1–VOL3 and CAV1/CAV3/CAV4 sessions with the original-style
English HUD from player assets. See [controls](../README.md), [roadmap](PORTING.md)
and the [entity contract](reference/gameplay/entities.md).

Whole-map Cave includes the frogger light with source decay, crop and pickup
growth, per-visit entity fade, firefly path sprites with their score callback,
the fat fire fly pickup and land projection for generic path followers.

The [sandbox](../README.md#sandbox) is a flat zone arena for the owner's play
checks of terrain and entity mechanics: entity spawning with path presets,
named layouts, teleport and real models without a map, falling back to
placeholders without player data. Its [design and limitations](reference/architecture.md#sandbox)
live in the architecture reference; it is not acceptance evidence.

Level acceptance is the owner's play check in the game scene. Thirteen levels
keep normal-start keyboard completion replays with per-tick parity as regression
coverage. ORG1, SUB1, FOR1 and VOL1 attract demos match native terminal states;
CAV1 and CAV4 demos complete with schedule parity but have no native baseline,
because the fresh-boot native export never unlocks Cave. Both test modes, strict
compilation and architecture checks pass.

Next is Desert, followed by Jungle, Swamp and Sky; a new mechanic can get a
sandbox preset. The player croak light swell and the web wall bounce are deferred;
CAV_SNAIL follows FrogLord's MOVING override with a recorded disagreement.
Audio playback, other effects, animated per-part lighting, the full front end,
multiplayer, exports and hosted CI retain separate scope. Performance tuning
remains deferred at the owner's request; the original-hardware target is
unverified. Desert has no blocker; the roadmap's owner decisions (licence,
repository host, FMV videos) gate later phases. Compatibility stays
`pc-retail-v3.0e`. Never push.

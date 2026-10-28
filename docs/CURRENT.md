# Current checkpoint

P9c Cave is complete. The dedicated game scene opens independent ORG1–ORG5,
SUB1, FOR1–FOR2, VOL1–VOL3 and CAV1/CAV3/CAV4 sessions with the original-style
English HUD from player assets. See [controls](../README.md), [roadmap](PORTING.md)
and the [entity contract](reference/gameplay/entities.md).

Whole-map Cave includes the frogger light with source decay, crop and pickup
growth, per-visit entity fade on models and sprites, firefly path sprites with
their score callback, the fat fire fly pickup and land projection for generic
path followers. Light radii live in the shared entity environment and commit
with each tick; presentation drives the terrain ramp from committed radii and
draws pickups and fireflies as source sprites.

Level acceptance is the owner's play check in the game scene. Thirteen levels
keep normal-start keyboard completion replays with per-tick parity as regression
coverage; CAV3 has none and needs none. ORG1, SUB1, FOR1 and VOL1 attract
demos match native terminal states; CAV1 and CAV4 demos complete with schedule
parity but have no native baseline, because the fresh-boot native export never
unlocks Cave. Independent Cave facts have deliberate-break checks. Both complete
test modes, strict compilation and architecture checks pass.

Next is Desert, followed by Jungle, Swamp and Sky. The player croak light swell
and the web wall bounce are deferred; CAV_SNAIL follows FrogLord's MOVING override
with a recorded disagreement. Guarded JUN1 and ORG1 fixtures remain separate
regression coverage. Audio playback, other effects, animated per-part lighting,
the full front end, multiplayer, exports and hosted CI retain separate scope.
Performance tuning remains deferred at the owner's request; the original-hardware
target is unverified. Compatibility stays `pc-retail-v3.0e`. Logs and captures
remain external. Never push.

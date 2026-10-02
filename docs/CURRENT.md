# Current checkpoint

Terrain movement, collision/deaths, gameplay camera and animation control are
implemented against the frozen C port's 30 Hz behavior. Typed scenarios run
the same rules in tests, headless traces and the terrain viewer. There is no
playable level yet. See the [domain index](reference/domain.md).

Final-PC PATH and FORM records decode into detached definitions. Optional
entity integration advances owned STATIC/MOVING transforms before the frog,
queries nearby map groups and applies supported POP FORM reactions. Frog,
entities, camera, animation and RNG commit atomically. The high-detail DES2
cactus inspection demonstrates an airborne entity hit. Standalone fixed-point
contact inspection remains available. See [paths](reference/gameplay/paths.md)
and [entities](reference/gameplay/entities.md) for support and exclusions.

Next is platform landing, centring, carrying, jumping off and camera attachment,
then live-entity lifecycle, scripts, zones and verified callback mappings toward
the first playable level. The [roadmap](PORTING.md) owns
remaining work; [architecture](reference/architecture.md) defines ownership.

Animated per-part lighting remains a [renderer limitation](reference/rendering/gameplay-projection.md).
Original retail runtime timing is unmeasured; the selected source-port target
is described in [simulation](reference/gameplay/simulation.md).

Hosted CI awaits a repository host. The licence remains the owner's decision
before publication. Never push.

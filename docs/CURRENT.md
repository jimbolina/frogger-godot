# Current checkpoint

Terrain movement, collision/deaths, gameplay camera and animation control are
implemented against the frozen C port's 30 Hz behavior. Typed scenarios run
the same rules in tests, headless traces and the terrain viewer. There is no
complete playable level yet. Direct retail terrain-viewer launches select live
keyboard exploration; see [controls](../README.md) and the [domain index](reference/domain.md).

Final-PC PATH and FORM records decode into detached definitions. Optional
entity integration advances owned STATIC/MOVING transforms before the frog,
queries nearby map groups and applies supported POP and SAFE FORM reactions. Frog,
entities, camera, animation and RNG commit atomically. The high-detail DES2
cactus inspection demonstrates an airborne entity hit. SAFE platforms support
landing, centring, carrying, hops along and off platforms, and camera attachment.
The high-detail JUN1 log inspection starts explicitly on water, with its first
contact verified through the ordered scan. Standalone fixed-point
contact inspection remains available. See [paths](reference/gameplay/paths.md)
and [entities](reference/gameplay/entities.md) for support and exclusions.

Opt-in visibility lifecycle now creates and retires script-free generic entities
from the source camera/group selector. Paths persist while instances are absent;
retained frog attachments protect live platforms. Selection and creation join
the atomic transaction. The demonstrated automatic-camera route is synthetic;
FOR1 is a retail-data candidate, not a verified runtime demonstration. The mode
requires zero zones and a bounded selected-group polygon budget.

Next are scripts, zones, custom behavior and verified callback mappings toward
the first playable level. The [roadmap](PORTING.md) owns
remaining work; [architecture](reference/architecture.md) defines ownership.

Animated per-part lighting remains a [renderer limitation](reference/rendering/gameplay-projection.md).
Original retail runtime timing is unmeasured; the selected source-port target
is described in [simulation](reference/gameplay/simulation.md).

Hosted CI awaits a repository host. The licence remains the owner's decision
before publication. Never push.

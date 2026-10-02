# Current checkpoint

Terrain movement, collision/deaths, gameplay camera and animation control are
implemented against the frozen C port's 30 Hz behavior. Typed scenarios run
the same rules in tests, headless traces and the terrain viewer. There is no
playable level yet. See the [domain index](reference/domain.md).

Final-PC PATH records decode into detached line, arc and spline definitions.
Source-ordered STATIC/MOVING entities now attach independently owned paths and
produce reset and tick transforms. The standalone path overlay and bounded
entity inspection exercise these components. See [paths](reference/gameplay/paths.md)
and [entities](reference/gameplay/entities.md).

Next is entity/form collision, scripts, zones and verified callback mappings,
leading to the first playable level. The [roadmap](PORTING.md) owns
remaining work; [architecture](reference/architecture.md) defines ownership.

Animated per-part lighting remains a [renderer limitation](reference/rendering/gameplay-projection.md).
Original retail runtime timing is unmeasured; the selected source-port target
is described in [simulation](reference/gameplay/simulation.md).

Hosted CI awaits a repository host. The licence remains the owner's decision
before publication. Never push.

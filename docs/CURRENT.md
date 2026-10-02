# Current checkpoint

Terrain movement, collision/deaths, gameplay camera and animation control are
implemented against the frozen C port's 30 Hz behavior. Typed scenarios run
the same rules in tests, headless traces and the terrain viewer. There is no
playable level yet. See the [domain index](reference/domain.md).

Final-PC PATH and FORM records decode into detached definitions. Source-ordered
STATIC/MOVING entities attach independently owned paths and produce reset and
tick transforms. A bounded FORM query checks one selected entity against a
fixed world point; the map viewer and traces inspect its contact cell and
flags. It does not change the frog. See [paths](reference/gameplay/paths.md)
and [entities](reference/gameplay/entities.md).

Next is lethal entity reaction and transactional frog/entity integration, then
platform riding, scripts, zones and verified callback mappings toward the first
playable level. The [roadmap](PORTING.md) owns
remaining work; [architecture](reference/architecture.md) defines ownership.

Animated per-part lighting remains a [renderer limitation](reference/rendering/gameplay-projection.md).
Original retail runtime timing is unmeasured; the selected source-port target
is described in [simulation](reference/gameplay/simulation.md).

Hosted CI awaits a repository host. The licence remains the owner's decision
before publication. Never push.

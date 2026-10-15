# Current checkpoint

Terrain movement, collision/deaths, gameplay camera and animation control
follow the frozen C port at 30 Hz. Direct retail terrain-viewer launches use
live keyboard input. There is no complete playable level yet. See
[launch and controls](../README.md) and the [domain index](reference/domain.md).

Optional POP and SAFE interactions advance detached entity/path, frog, camera,
animation and RNG state atomically. Platforms support landing, centring,
carrying, local/departing hops and camera attachment. The opt-in JUN1 bank/log
preset connects safe terrain to a moving log and back. It opens LIVE and
paused, assumes all-attached lifetime, and rejects entire ticks that leave its
audited world boundary or enter a camera zone. Its proof depends on pinned
retail inputs; changed dependencies and visibility mode are rejected. R resets
the complete inspection and presentation clocks. The earlier explicit
water-start inspection remains available. See the
[entity contract](reference/gameplay/entities.md#guarded-jun1-bank-route).

ZONE records now decode into detached, source-ordered queries with the frozen
unsigned outer/signed child interpretation. Active camera-zone behavior is
still deferred. Opt-in visibility lifecycle supports script-free generic
entities on zero-zone maps within its polygon budget. Its demonstrated route
is synthetic; FOR1 remains an unverified retail lifecycle candidate.

ORG1's [admission checker](reference/gameplay/entities.md#org1-admission-blocker)
compares traffic/fly updates and moving-sound ownership with frozen C, inventories
shared FORM writers and neighbors, and bounds retail animated frog hilites.
The candidate remains blocked: pose bounds overlap traffic in Z, without
establishing a reachable collision. Next are reachable action/transform bounds,
active-frog requests, turtle behavior and an integrated round-trip proof before
runtime integration.

[PORTING](PORTING.md) owns the other remaining P8 dependencies;
[architecture](reference/architecture.md) owns transaction boundaries.
Scoring, progression and win conditions remain unfinished.

Animated per-part lighting remains a
[renderer limitation](reference/rendering/gameplay-projection.md).
Original retail runtime timing is unmeasured; the selected source target is
explained in [simulation](reference/gameplay/simulation.md).
Hosted CI awaits a repository host. The licence remains the owner's decision
before publication. Never push.

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

ORG1's [source proof](reference/gameplay/entities.md#org1-admission)
bounds animated collision points and connects bank, turtle, small log, turtle
and bank inside X `[-512,512)`, Z `[-128,480)`. Independent Python and frozen C
agree on the normal round trip and a separate attached-diver death, retaining
all neighbors' logical updates and retail animation lengths. Bounded script
components pass independent component goldens. Atomic integration and
the guarded preset are next.

[PORTING](PORTING.md) owns the other remaining P8 dependencies;
[architecture](reference/architecture.md) owns transaction boundaries.
Scoring, progression and win conditions remain unfinished.

Animated per-part lighting remains a
[renderer limitation](reference/rendering/gameplay-projection.md).
Original retail runtime timing is unmeasured; the selected source target is
explained in [simulation](reference/gameplay/simulation.md).
Hosted CI awaits a repository host. The licence remains the owner's decision
before publication. Never push.

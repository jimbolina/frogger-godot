# Current checkpoint

Updated: 2026-10-01. Replace this checkpoint; do not append a journal.

**P7 is complete.** Terrain grid interpretation, movement/collision/deaths,
default gameplay camera and animation control follow the owner's selected
frozen `froggy` source behavior at 30 Hz. Typed scenarios feed the same pure
rules through tests, headless traces and rendered inspection. See
[terrain contracts](reference/terrain-movement.md),
[inspection](reference/terrain-inspection.md) and
[P7 validation](validation/p7.md).

Final retail: 407 passing tests, zero skips. Asset-free: 353 passing tests and
54 exact named retail skips. Both compile and architecture-check 191 scripts.
Independent source comparisons and deliberate-break restorations pass; twelve
hash-pinned headless/rendered schedule comparisons match exactly.

Foreground start, airborne and landed placement/orientation/silhouette passes
its declared bounds. Animated per-part source lighting remains a specific
renderer limitation; see [projection](reference/gameplay-projection.md) and the
[roadmap](PORTING.md). Original retail runtime timing is unmeasured and separate
from the selected source-port target;
[timing evidence](reference/pc-timing.md) records that distinction.

**Next phase: P8**, entity/form collision, paths, zones and callback mappings,
leading to the first playable level. There is no playable level yet. Follow the
[domain](reference/domain.md) and [architecture](reference/architecture.md)
ownership contracts and [remaining foundation work](plans/domain-foundation.md).
Rules receive detached definitions/commands; C files in tools are offline
validation adapters, not runtime implementations.

Hosted CI remains deferred until a repository host is selected. Never push.
The licence remains the owner's decision before publication.

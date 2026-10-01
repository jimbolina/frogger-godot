# Current checkpoint

Updated: 2026-10-01. Replace this checkpoint; do not append a journal.

**Domain foundation complete; P7 is next.**
The [domain language](reference/domain.md) and
[architecture contract](reference/architecture.md) define source identities,
layer boundaries and ownership. Viewers share argument/capture helpers and
borrow injected GameData unless ownership is explicitly transferred. Both test
wrappers now enforce architecture and exact retail-skip/result rules.

Final retail and asset-free gates, failure probes and inspected captures passed;
see the [foundation validation](validation/domain-foundation.md) for counts,
timings, logs and limitations. SUB1's reference capture is unchanged.
Hosted CI remains deferred until a repository host is selected.

**Next action:** plan P7 against the [roadmap](PORTING.md), current implementation
and frozen C per-tick traces: grid, frog movement, gameplay camera, collision
and deaths. Resolve the PC 25/30 Hz discrepancy before movement. Runtime form
callback address-to-name mappings also need source evidence. The
[remaining adoption plan](plans/domain-foundation.md) belongs to P7/P8.

P6 map parsing/rendering, inspection cameras and the owner's FrogLord-saved
JUN1 compatibility check remain complete; see [map contracts](reference/maps.md)
and [P6 validation](validation/p6.md). Entity placement/rendering remains P8,
which is the first playable-level milestone. There is no gameplay yet.

Never push. The licence remains the owner's decision before publication.

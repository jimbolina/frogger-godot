# Current checkpoint

Terrain movement, collision/deaths, gameplay camera and animation control follow
the frozen C port at 30 Hz. Retail exploration uses live input. See
[launch and controls](../README.md) and the [domain index](reference/domain.md).

POP, SAFE and SQUISHED interactions advance detached entity/path, frog, camera,
animation and RNG state atomically. Platforms support landing, centring,
carrying, local/departing hops and camera attachment. The guarded JUN1 preset
connects bank, moving log and return. Active camera zones reject whole ticks;
zone decoding and queries are implemented. Script-free visibility lifecycle
has a synthetic demonstration; FOR1 remains an unverified retail candidate.

The guarded ORG1 river preset connects bank, turtle, small log, turtle and bank.
The separate `org1-road-river` preset adds the southern road, all 24 vehicle
cuboids, stored animated frog collision points and squish deaths. Independent
Python/frozen-C facts cover a successful crossing into the river corridor and
a lorry collision with its following traffic-splat callback. Both presets keep
all 64 authored logical updates, pinned supplied inputs and all-attached lifetime.
They open LIVE and paused; boundary or unsupported-pose failures roll back the
entire tick. R resets inspection and presentation clocks. See the
[entity contract](reference/gameplay/entities.md#org1-road-and-vehicle-primitives)
and [inspection](reference/testing/terrain-inspection.md).

[PORTING](PORTING.md) owns remaining P8 work: broader behaviors/reactions,
active zones, verified FORM callbacks, selective reset and lifecycle workloads.
Complete level play remains unfinished. Audio playback, splash/particle effects
and [animated per-part lighting](reference/rendering/gameplay-projection.md)
remain deferred.

Prepared scripts, private transactions, asynchronous playback and rendering
caches are implemented. Sustained performance acceptance remains open and must
be measured on an idle system separately from correctness checks.
Hosted CI awaits a repository host. The licence remains the owner's decision
before publication. Never push.

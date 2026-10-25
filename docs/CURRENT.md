# Current checkpoint

Terrain movement, collision/deaths, gameplay camera and animation control
follow the frozen C port at 30 Hz. Retail terrain exploration uses live input. See
[launch and controls](../README.md) and the [domain index](reference/domain.md).

POP and SAFE interactions advance detached entity/path, frog, camera,
animation and RNG state atomically. Platforms support landing, centring,
carrying, local/departing hops and camera attachment. The opt-in JUN1 bank/log
preset connects bank, moving log and return. It opens LIVE and
paused, and rejects entire ticks that leave its
audited world boundary or enter a camera zone. Pinned retail inputs and
all-attached lifetime are required. R resets the inspection and presentation clocks.
See the
[entity contract](reference/gameplay/entities.md#guarded-jun1-bank-route).

ZONE records now decode into detached, source-ordered queries with the frozen
unsigned outer/signed child interpretation. Active camera-zone behavior is
still deferred. Opt-in visibility lifecycle supports script-free generic
entities on zero-zone maps within its polygon budget. Its demonstrated route
is synthetic; FOR1 remains an unverified retail lifecycle candidate.

The guarded [ORG1 preset](reference/gameplay/entities.md#org1-admission)
connects bank, turtle, small log, turtle and bank inside X `[-512,512)`,
Z `[-128,480)`. Its animated collision-point proof pins supplied inputs and
individual neighbor exclusions. All authored logical updates run, including
diving, traffic scripts and shared neighbor state. Independent Python/frozen-C
goldens cover complete dive/rise cycles and attached-diver drowning. Callbacks,
RNG, animation, colour and requests commit atomically. Audio playback and splash
rendering remain deferred. See [inspection](reference/testing/terrain-inspection.md).

[PORTING](PORTING.md) owns the other remaining P8 dependencies;
[architecture](reference/architecture.md) owns transaction boundaries.
ORG1 uses prepared scripts, private transactions and asynchronous playback.
Coherent smoothing, cached pose/morph updates and prepared lighting materials are
implemented. Next, measure sustained performance on an idle system using the
inspection procedure; acceptance remains open.

Animated per-part lighting remains a
[renderer limitation](reference/rendering/gameplay-projection.md).
Hosted CI awaits a repository host. The licence remains the owner's decision
before publication. Never push.

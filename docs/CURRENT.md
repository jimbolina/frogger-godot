# Current checkpoint

Terrain movement, collision/deaths, gameplay camera and animation control follow
the frozen C port at 30 Hz. Retail exploration uses live input. See
[launch and controls](../README.md) and the [domain index](reference/domain.md).

POP, SAFE and SQUISHED interactions advance detached entity/path, frog, camera,
animation and RNG state atomically. Guarded JUN1 bank/log and ORG1 river/road
presets support platform movement and vehicle cuboids within their audited
bounds. ORG1 keeps all 64 authored logical updates, pinned supplied inputs and
all-attached lifetime. Unsupported poses and boundary failures reject whole
ticks. Complete level play remains unfinished.

Active camera zones and script-free visibility lifecycle now share the same
transaction. Independent Python/frozen-C facts cover synthetic out-and-back
gameplay and a prescribed v3.0e JUN1 camera probe with eleven audited logs.
Checks cover creation/retirement/recreation, reset, attachment and rollback;
rendered schedules match headless state. Ordinary retail terrain's zero-zone
guard and existing exploration admission remain. The probe does not expand
playable routes. See the [combined contract](reference/gameplay/entities.md#combined-camera-zones-and-lifecycle).

[PORTING](PORTING.md) owns remaining P8 work: broader behaviors/reactions,
verified FORM callbacks, selective reset, playable zone routes and scripted
visibility workloads. Script-free visibility has a retail log probe;
FOR1 remains an unverified retail candidate. Audio playback, splash/particle
effects and [animated per-part lighting](reference/rendering/gameplay-projection.md)
remain deferred.

Prepared scripts, private transactions, asynchronous playback and rendering
caches are implemented. Sustained performance acceptance remains open and must
be measured on an idle system separately from correctness checks.
Hosted CI awaits a repository host. The licence remains the owner's decision
before publication. Never push.

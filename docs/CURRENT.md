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

Active camera zones now support retained zone/region selection, directional
offsets, forced and semiforced turns, absolute-height transitions and platform
camera composition. Independent Python/frozen-C facts cover camera transitions
and actual manual control. Synthetic gameplay checks cover selection timing,
reset and rollback. The `jun1-camera-zones` inspection demonstrates authored
v3.0e zones using prescribed probe positions; it does not expand playable routes.
Existing exploration admission and zero-zone visibility-lifecycle guards remain.
See the [camera contract](reference/gameplay/gameplay-camera.md).

[PORTING](PORTING.md) owns remaining P8 work: broader behaviors/reactions,
verified FORM callbacks, selective reset, playable zone routes and combined
zone/lifecycle workloads. Script-free visibility has a synthetic demonstration;
FOR1 remains an unverified retail candidate. Audio playback, splash/particle
effects and [animated per-part lighting](reference/rendering/gameplay-projection.md)
remain deferred.

Prepared scripts, private transactions, asynchronous playback and rendering
caches are implemented. Sustained performance acceptance remains open and must
be measured on an idle system separately from correctness checks.
Hosted CI awaits a repository host. The licence remains the owner's decision
before publication. Never push.

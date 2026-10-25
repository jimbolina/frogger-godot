# Current checkpoint

Terrain movement, collision/deaths, gameplay camera and animation control follow
the frozen C port at 30 Hz. Retail exploration uses live input. See
[launch and controls](../README.md) and the [domain index](reference/domain.md).

POP, SAFE and SQUISHED interactions advance entity/path, frog, camera,
animation and RNG state atomically. Guarded JUN1 bank/log and ORG1 river/road
presets retain their audited all-attached bounds. Complete level play remains
unfinished.

The separate ORG1 bank/turtle/log visibility preset adds scripted recreation,
source live-list updates, immortal initialization and uncollected baby-frog
parent loss/search/hops. Persistent paths outlive mortal instances; script,
animation and logical sound ownership restart per generation. Independent
Python/frozen-C facts cover the round trip and an attached-diver death.
A dynamic collection-radius guard rejects extended play when the baby invalidates
its contact exclusion. See the [scripted visibility contract](reference/gameplay/entities.md#scripted-visibility-route).

Combined active zones and script-free visibility retain synthetic gameplay and
the prescribed JUN1 log probe. Ordinary retail terrain still requires zero-zone
maps. [PORTING](PORTING.md) owns remaining P8 work: broader behaviors/reactions,
verified FORM callbacks, collection, selective reset, playable zone routes and
broader scripted visibility workloads. FOR1 remains an unverified retail candidate.
Audio playback, splash/particle effects and
[animated per-part lighting](reference/rendering/gameplay-projection.md) remain deferred.

Prepared scripts, private transactions, asynchronous playback and rendering
caches are implemented. Sustained performance acceptance remains open and must
be measured on an idle system separately from correctness checks.
Hosted CI awaits a repository host. The licence remains the owner's decision
before publication. Never push.

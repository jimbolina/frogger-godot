# Current checkpoint

Movement, collision/deaths, camera and animation follow frozen C at 30 Hz. Exploration uses live input. See
[launch and controls](../README.md) and the [domain index](reference/domain.md).

POP, SAFE and SQUISHED interactions advance entity/path, frog, camera,
animation and RNG state atomically. Guarded JUN1 bank/log and ORG1 river/road
presets retain their audited all-attached bounds. Complete level play remains
unfinished.

The separate ORG1 bank/turtle/log visibility preset adds scripted recreation,
source live-list updates, immortal initialization and pink frog
parent loss/search/hops, body-contact pickup, riding and death. Persistent paths outlive mortal instances; script,
animation and logical sound ownership restart per generation. Independent
Python/frozen-C facts cover the round trip, pickup/return and carried drowning.
Verified pink frog contact replaces her proximity exclusion within the existing
corridor. See the [scripted visibility contract](reference/gameplay/entities.md#scripted-visibility-route).

Combined zones and script-free visibility retain synthetic gameplay and the JUN1 probe. Ordinary retail terrain still requires zero-zone
maps. [PORTING](PORTING.md) owns the revised phases: next is P8a, a behaviour
catalog with typed tick events and the remaining DDD refactor before P8b
demo playback as the oracle for
completing ORG1 in P8c. The corridor presets retire there. FOR1 remains an
unverified retail candidate.
Audio playback, splash/particle effects and
[animated per-part lighting](reference/rendering/gameplay-projection.md) remain deferred.

Candidate/commit methods and discovered copy contracts protect transaction
ownership across composed state. GameplayRun coordinates Frog and contact components. Typed tick events preserve text traces. Setup
resolves entity behaviors once; gameplay uses kinds and named source constants. Inspection owns corridor guards and presets; application owns source adapters.
Prepared scripts, asynchronous playback and rendering caches are implemented. Sustained performance acceptance remains open and must
be measured on an idle system separately from correctness checks.
CI awaits a repository host. The licence remains the owner's decision
before publication. Never push.

[Mac source setup](../README.md#macos-setup) uses Godot 4.5.1 with isolated
automated profiles. Packaged exports and native C-reference builders remain open.

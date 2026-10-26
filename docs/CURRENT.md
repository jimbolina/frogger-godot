# Current checkpoint

Movement, collision/deaths, gameplay camera and animation follow frozen C at
30 Hz. Retail exploration uses live input. See [launch and controls](../README.md)
and the [domain index](reference/domain.md). Complete level play remains unfinished.

POP, SAFE and SQUISHED interactions advance frog, entity/path, camera, animation
and RNG state atomically. Supported ORG1 visibility behavior includes scripted
recreation, immortal initialization, pink frog parent loss/search/hops, pickup,
riding and death. Persistent paths outlive mortal instances; instance state
restarts per generation. Independent Python/frozen-C facts cover these behaviors.

The DDD refactor is complete. Application resolves behavior names once;
source decoding, gameplay, inspection and presentation have separate ownership.
GameplayRun coordinates Frog and contact components over composed GameplayState.
Typed events retain the existing trace format. Candidate APIs and discovered
copy contracts protect transaction ownership. GameplayHost owns pacing and worker
handoff; map inspection retains its independent seek clock and capture workflow.

[PORTING](PORTING.md) owns remaining work. P8b provides player-data demo
resolution, raw-action control, atomic duration/input counters and isolated
reference-layout traces with comparison reporting. Duration completion does
not establish complete gameplay. Native reference validation remains pending;
unsupported actions, whole-map zones and corridor admission report incomplete
playback. Next is complete ORG1 in P8c. Bounded JUN1/ORG1 presets remain
inspection scaffolding. Ordinary retail terrain still requires zero-zone maps;
combined zones/visibility retain synthetic gameplay and the prescribed JUN1
probe. FOR1 remains an unverified retail candidate.

Audio playback, splash/particle effects and [animated per-part lighting](reference/rendering/gameplay-projection.md)
remain deferred. Performance acceptance requires an idle-system measurement.
Hosted CI awaits a repository host. Packaged exports and native C-reference
builders remain open. The licence remains the owner's decision before publication.
Never push. [Mac source setup](../README.md#macos-setup) uses Godot 4.5.1 and isolated
automated profiles.

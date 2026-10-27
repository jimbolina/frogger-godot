# Current checkpoint

P9a Forest is complete. The dedicated game scene opens independent ORG1–ORG5,
SUB1 and FOR1–FOR2 sessions with the original-style English HUD from player
assets. See [controls](../README.md), [roadmap](PORTING.md) and the
[entity contract](reference/gameplay/entities.md).

Whole-map Forest setup includes hives with visible bee swarms and obstruction
queries, breaking branches, squirrels and terrain-projected hedgehogs.
Named behavior mappings support compatible FrogLord repoints; unknown mappings
retain diagnostics. FOR3–FOR5 are dummy entries and FORM belongs to multiplayer.
The guarded JUN1 and ORG1 fixtures remain separate regression coverage.

All eight playable levels have normal-start keyboard completion replays in the
dedicated scene, with per-tick parity against fresh detached runs. ORG1, SUB1
and FOR1 attract demos match the verified native terminal states, routes and
consumed inputs across headless and rendered schedules. Forest behavior goldens
are independent Python implementations, with deliberate-break checks; swarm,
branch, squirrel and hedgehog captures have been inspected.

Both complete test modes, strict compilation and architecture checks pass.
Next is P9b Volcano, followed by the remaining themes. Audio playback, other
particles/splashes, animated per-part lighting, full front end, multiplayer,
packaged exports and hosted CI retain their separate roadmap scope. Further
performance tuning is deferred at the owner's request; the original-hardware
target remains unverified. Compatibility remains `pc-retail-v3.0e`, including
compatible FrogLord-saved edits. Raw logs and captures stay external. Never push.

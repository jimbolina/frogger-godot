# Current checkpoint

P8c is complete: whole-map ORG1 is playable through five checkpoints in the
existing viewer, including tongue collection, pink-frog delivery, death/respawn,
timeout, game over and restart. See [controls](../README.md),
[roadmap](PORTING.md) and the [entity contract](reference/gameplay/entities.md).

All 49 script opcodes, 25 named callbacks and four verified v3.0e FORM callbacks
have typed implementation paths. Application setup resolves names and verified
callback identities; unknown mappings retain source-located diagnostics.
Documented unsafe operands remain rejected. MULTIPOINT remains multiplayer-only.

Rewards, level flow, tongue, entity lifecycle, selective resets, animation,
logical sound timing and RNG commit together. Full restart remains separate
from selective in-level resets; the checkpoint mask has one authoritative value.
Audio playback and rendered particles/splashes remain deferred.

The complete high-detail ORG1 attract demo matches the verified native terminal
state, route and consumed input. Committed traces and provenance match headless,
rendered 30/60/144 Hz and irregular schedules. Repeatable
[keyboard replays](reference/testing/terrain-inspection.md#whole-map-keyboard-playthrough)
cover completion, pink delivery and tongue collection with per-tick rules parity.
Manual keyboard checks cover death/respawn, timeout, game over and restart.
Both complete test modes, strict compilation and architecture checks pass.

Next is P10: a dedicated game scene, original-style HUD and broader level
coverage using the shared gameplay host. Animated per-part lighting, other
themes, multiplayer, packaged exports and hosted CI retain their roadmap scope.
Further performance tuning is deferred at the user’s request; the original-hardware
target remains unverified. Compatibility remains `pc-retail-v3.0e`, including
compatible FrogLord-saved edits. Raw logs and captures stay external. Never push.

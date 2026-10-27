# Current checkpoint

P10 is complete. The dedicated game scene opens independent ORG1–ORG5 and SUB1
sessions from a
small level picker. It shares the transactional gameplay host and world renderer
with inspection, and draws the original-style English HUD from player assets.
See [controls](../README.md), [roadmap](PORTING.md) and the
[entity contract](reference/gameplay/entities.md).

Whole-map setup includes Suburbia dogs, moving tongue collectables, dynamic
entities, complete model contact bounds and the verified butterfly reward
callback. All 49 script opcodes, 25 named script callbacks and five verified
v3.0e FORM callbacks have typed paths; unknown mappings retain diagnostics.
The guarded JUN1 and ORG1 fixtures remain separate regression coverage.

ORG1–ORG5 and SUB1 have normal-start keyboard completion replays in the dedicated scene,
with per-tick parity against fresh detached runs. Collection, timeout,
death/respawn, game over, restart and viewport scaling have inspected captures.
ORG1 and SUB1 attract demos match the verified native terminal states, routes
and consumed inputs across headless and rendered schedules.

Both complete test modes, strict compilation and architecture checks pass.
Next is P9, beginning with
FOR and VOL, which have attract demos. Audio playback, particles/splashes,
animated per-part lighting, full front end, multiplayer, packaged exports and
hosted CI retain their separate roadmap scope. Further performance tuning is
deferred at the owner's request; the original-hardware target remains unverified.
Compatibility remains `pc-retail-v3.0e`, including compatible FrogLord-saved
edits. Raw logs and captures stay external. Never push.

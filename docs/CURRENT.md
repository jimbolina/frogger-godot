# Current checkpoint

P9b Volcano is complete. The dedicated game scene opens independent ORG1–ORG5,
SUB1, FOR1–FOR2 and VOL1–VOL3 sessions with the original-style English HUD from
player assets. See [controls](../README.md), [roadmap](PORTING.md) and the
[entity contract](reference/gameplay/entities.md).

Whole-map Volcano includes colour switches, controlled immortal platforms,
falling platforms and its scripted hazards. Target changes, collision, animation
and logical sound ownership commit atomically. Source polygon allocation history
supports Volcano visibility. Shared collision bounds include model primitives,
and contact/jump reads preserve callback-modified matrix positions. Named
behavior and callback mappings support compatible FrogLord repoints with
explicit diagnostics for unsupported entries.

All eleven playable levels have normal-start keyboard completion replays with
per-tick parity against fresh detached runs. ORG1, SUB1, FOR1 and VOL1 attract
demos match native terminal states, routes and consumed inputs across headless
and rendered schedules. Independent Volcano behavior/allocation facts have
deliberate-break checks; switches, carrying, collapse and hazards were inspected.
Both complete test modes, strict compilation and architecture checks pass.

Next is Cave, followed by the remaining themes. Guarded JUN1 and ORG1 fixtures
remain separate regression coverage. VOL4/VOL5 have no playable maps; VOLM is
multiplayer. Audio playback, other effects, animated per-part lighting, the full
front end, multiplayer, exports and hosted CI retain separate scope. Further
performance tuning remains deferred at the owner's request; the original-hardware
target is unverified. Compatibility stays `pc-retail-v3.0e`. Logs and captures
remain external. Never push.

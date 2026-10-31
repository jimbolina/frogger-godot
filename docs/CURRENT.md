# Current checkpoint

The front end and every accepted level play from the player's retail files.
Launch with `tools/play.sh --scene=res://scenes/front_end.tscn`: the main menu
scrolls the high-score table behind its buttons, Start opens the 3D level-select
stack over the animated water, Options sets volumes, rebinds keys and views the
high scores, and menu images follow the OS language or `--language=`. ORG1–ORG5,
SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and
SKY1–SKY4 are accepted by the owner's play check (P9, P10, P11 effects, P13a
flow, P13b stack, P13g water, P13c options). See the [roadmap](PORTING.md),
[front end](reference/gameplay/front-end.md), [entities](reference/gameplay/entities.md)
and [effects](reference/rendering/effects.md).

P13d is implemented and awaits the owner's play check: a finished game enters
the name-entry page when its score beats a table, the view page tours the new
rows and the scrolling main table, Options offers View high scores, and scores
persist in `user://high_scores.cfg`. See
[high scores](reference/gameplay/front-end.md#high-scores). The attract cycle
(P13e) is next.

P12 audio playback awaits the owner's by-ear check: sound effects play from
committed voices and music from the disc image (`--disc=` or `FROGGER_DISC`),
see the [audio notes](../README.md#audio).

Effects are presentation-only by owner decision: the port never reproduces the
frozen generators' shared random draws. Keyboard replays and native attract
comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison);
the [sandbox](../README.md#sandbox) and the owner's play checks are the system
checks. Both test modes, strict compilation and architecture checks pass.

The ORG gold baby frog is carried rather than popped and the outro stone frog
belongs to P16. Animated per-part lighting, attract demos, multiplayer, exports
and hosted CI retain separate scope. Performance tuning remains deferred at the
owner's request; the original-hardware target is unverified. The roadmap's owner
decisions (licence, repository host, FMV videos) gate later phases.
Compatibility stays `pc-retail-v3.0e`. Never push.

# Current checkpoint

The front end and every accepted level play from the player's retail files.
Launch with `tools/play.sh --scene=res://scenes/front_end.tscn`: the main menu
scrolls the high-score table behind its buttons, Start opens the 3D level-select
stack over the animated water, Options sets volumes, rebinds keys and views the
high scores, and menu images follow the OS language or `--language=`. ORG1–ORG5,
SUB1, FOR1–FOR2, VOL1–VOL3, CAV1/CAV3/CAV4, DES1–DES5, JUN1, SWP1–SWP5 and
SKY1–SKY4 are accepted by the owner's play check (P9, P10, P11 effects, P13a
flow, P13b stack, P13g water, P13c options, P13d high scores). See the [roadmap](PORTING.md),
[front end](reference/gameplay/front-end.md), [entities](reference/gameplay/entities.md)
and [effects](reference/rendering/effects.md).

P13d is complete and accepted; scores persist in `user://high_scores.cfg`
([high scores](reference/gameplay/front-end.md#high-scores)). X2 is implemented:
the gameplay frog takes the map's lights through the per-part path every entity
model uses, with its committed custom ambient and colour scale, checked by an
independent [golden](../tests/golden/specs/animation.md#animated-part-lighting).
Owner's play check pending.
Next: the owner's spikes S1 (import every asset as project resources, audit the
layout against Godot practice and domain-driven design, document the domain
models) and S2 (Godot lights, shadows and materials replace the C recipe), set
ahead of P13e ([roadmap](PORTING.md#s1-and-s2-native-asset-and-modern-rendering-spikes)).
They defer FrogLord compatibility and runtime loading.

P12 audio awaits the owner's by-ear check: effects play from committed voices,
music from the disc image (`--disc=`/`FROGGER_DISC`); see [audio](../README.md#audio).

Effects never reproduce the frozen generators' random draws (owner decision). Keyboard replays and native attract comparisons are on-demand
[diagnostics](reference/testing/README.md#diagnostics-demo-playback-and-native-comparison);
the [sandbox](../README.md#sandbox) and the owner's play checks are the system
checks. Both test modes and strict compilation pass.

The ORG gold baby frog is carried rather than popped; the outro stone frog
belongs to P16. Attract demos, multiplayer, exports and hosted CI keep separate
scope. Performance tuning is deferred. Owner decisions
(licence, repository host, FMV videos) gate later phases.
Compatibility stays `pc-retail-v3.0e` until S1. Never push.

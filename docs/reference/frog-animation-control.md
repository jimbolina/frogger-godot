# Frog animation control

`src/game/animation/` implements the frozen frog script controller over copied
action-length metadata. The generated catalog preserves source animation IDs,
action names, request flags and program words; action indices are not inferred
from presentation events. Queue, delayed start, restore, death locking, loop
and idle selection state remain authoritative and copyable.

The caller owns `FrogAnimationContext`, including its shared `SourceRandom` and
idle-selection counter. Camera draws precede animation draws in the source
logic sequence. A new run needs a fresh context. Retail setup supplies decoded
GEN_FROG action lengths; synthetic fixtures explicitly supply authored counts.

Source `gamesys.C` calls frog/camera updates, animation scripts and then
`MRAnimUpdateEnvironments` during logic updates. The controller therefore has
separate script and pose steps. Presentation samples action, cel and one-shot
state without advancing either clock. Script evaluation captures cel/count
before queued or restored programs restart, preserving the source's behavior.

The [independent component corpus](../../tests/golden/specs/frog-animation.md)
compares 320 actual frozen-C phase records. The adapter omits LW renderer
transform construction by temporarily clearing its update flag; the flag is
restored in recorded state. It does not replace animation rules, action setters,
or random selection. Geometry pose interpolation remains presentation-owned.
Other terrain adapters omit audio, entity systems, score mutation and effect
factories as documented in their component boundaries; their omitted random
draws are not simulated. These comparisons do not claim full-engine parity.

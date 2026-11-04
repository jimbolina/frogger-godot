# Terrain height and collision component facts

`tools/oracles/terrain_collision_oracle.c` links the frozen `ControlFrog`, `MoveFrog`
and, with `--collision`, `CollideFrog`. It initializes explicit synthetic grid,
theme, fade bounds, input and frog state. No retail bytes are saved.
`tools/oracles/build_terrain_collision_oracle.ps1 -OutputDirectory <external-folder>
-Collision -Run` builds and runs hidden, awaited transport outside both repos.
Its provenance records linked inputs and wrapper boundaries.

`make_golden_terrain_d1.py` independently computes 320 control/movement rows:
super, fixture quick/auto, height boundaries and empty-cell freefall.
`make_golden_terrain_collision.py` independently computes 3,240 rows covering
safe landing, stun boundaries, fatal/soft falls, combined SAFE/DEADLY priority,
deadly/pop/water reactions, fade priority and theme-height death. Both require
an external `--c-oracle` executable and compare every generated field with its
actual frozen component output before writing text facts; `--verify` checks
the committed corpus. They never consume Godot output.

The run follows integer 16.16 movement, authored stack search order, source
landing thresholds, cached integer matrix translation and deferred dying.
Theme-height collision clamps cached matrix Y rather than position Y. SAFE
takes reaction precedence over DEADLY. A death request occurs at collision;
the next control call enters dying. Completion emits once and terminates the
run. Tests compare the supported prefix and explicitly exclude later C rows
whose intercepted main-loop request cannot perform its real setup callback.

Animation, sound and score calls are counted requests. Score mutation, lives
progression and main-loop setup belong to later game flow; fixture lives and
intercepted game mode are reference context/request diagnostics. Particle and
sprite factories return transport storage, and viewport insertion is omitted.
These factories may consume RNG in the full engine. Their omitted RNG work is
neither reproduced nor compensated, so this fixture proves represented frog
fields and request ordering, not full engine RNG or effect parity. Camera shake
executes in C, but its internal state is outside this collision schema.

This D1 family supplies authored power flags without executing modifier expiry.
Separate D2 special-mode, matrix and modifier fixtures are indexed in the
[terrain movement contract](../gameplay/terrain-movement.md). Pickup application remains
outside these component facts. Source-undefined storage accesses are diagnosed
before committing a tick; ignored authored flag bits are retained.

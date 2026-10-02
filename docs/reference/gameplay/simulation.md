# Simulation contracts

`TerrainRun` implements one ordered terrain tick. `PathRunner` separately
implements one detached PATH cursor update. Full level/entity simulation is
not implemented; no map entity consumes a path runner yet. See [paths](paths.md).

- The gameplay host schedules original-rate tick commands; the rules do not read wall time. Optional interpolation affects drawing only. Godot's physics engine is not used; collision is the game's own.
- The owner selected frozen `froggy` source-port behavior: 30 Hz steady-state logic/presentation pacing. Its actual driver defines `FROGGER_TARGET_FPS=30`, computes `perf_freq / 30`, and its timer backend asserts `LOGIC_CALLS_PER_SEC==30`. This is source evidence independent of the existing viewer clock. See [PC timing evidence](pc-timing.md).
- The model viewer uses that existing 30 Hz clock. Its optional smoothing changes only presentation and defaults off; textures and animation state stay tick-driven.
- Entities update in the original list order, because random-number use depends on it.
- These keep integer behaviour: the random number generator, script timers and counters, path distance stepping, grid coordinates and form heights, the game timer, score, entity delay counters, and radius-squared collision tests.
- Frog hops last a whole number of ticks and snap to the grid on landing, so recorded demos replay approximately. Demo checks compare completion and end state, not the path.
- Camera control uses the source's discrete integer state. Floats remain available for particles, animation blending and render interpolation; numeric conversion bounds require independent evidence.

The C source defines 30 logic calls per second and creates a 33 ms timer;
these are source facts, not the supplied retail executable's timer contract.
FrogLord converts PC entity delays using 25. The static retail audit found a
20 ms periodic callback that supplies logic budget on alternate deliveries.
Original-retail runtime delivery remains unmeasured. The selected behavior
target is the C port. The [terrain contract](terrain-movement.md) uses signed 16.16 frog state,
with rendering interpolation separate from authoritative ticks.

The source port arms one virtual timer tick per presented frame and delivers
it at the next ordering-table clear. Its human-session driver uses an
accumulating 30 Hz deadline, resetting the deadline after a large overrun so
stalls do not bank a burst. Smoke/component comparisons have no wall-clock
pacing. The original C loop caps accumulated virtual ticks at three; source
reset/render-flush paths can supply several ticks to one driver call. A driver
trace row therefore is not universally one logic tick. The terrain rule API always
performs exactly one tick per accepted command; host pacing and reset policy
remain outside rules.

Live debug input samples collected button state at the command boundary.
Pressed edges are `held & ~previous_held`, matching `MR_INPUT.C`'s
`in_pad_new & (in_pad_new ^ in_pad_old)`. A press released before sampling is
absent. Scripted scenarios supply both masks explicitly. Direction precedence,
camera mapping and the one-entry flight buffer remain rule responsibilities;
the host does not consume or arbitrate them.

`src/game/` owns detached terrain and path definitions and state, grid queries,
movement/collision, gameplay camera, animation control and source RNG. Entity
and script systems are not implemented. `src/mod/` remains future work
for watching files and reporting unmapped behavior. See the
[README layout](../../../README.md#layout) and [path contract](paths.md).

# Simulation contracts

`GameplayRun` implements one ordered frog tick and optional atomic entity
advancement/reaction. `PathRunner` implements one detached PATH cursor update;
moving entities own independent cursors. Full level simulation is not
implemented. See [paths](paths.md) and [entities](entities.md).

- The gameplay host schedules original-rate tick commands; the rules do not read wall time. Optional interpolation affects drawing only. Godot's physics engine is not used; collision is the game's own.
- The owner selected frozen `froggy` source-port behavior: 30 Hz steady-state logic/presentation pacing. Its actual driver defines `FROGGER_TARGET_FPS=30`, computes `perf_freq / 30`, and its timer backend asserts `LOGIC_CALLS_PER_SEC==30`. This is source evidence independent of the existing viewer clock. See [PC timing evidence](pc-timing.md).
- The model viewer uses that existing 30 Hz clock. Its optional smoothing changes only presentation and defaults off; textures and animation state stay tick-driven.
- Entities update in the original list order, because random-number use depends on it.
- These keep integer behaviour: the random number generator, script timers and counters, path distance stepping, grid coordinates and form heights, the game timer, score, entity delay counters, and radius-squared collision tests.
- Frog hops last a whole number of ticks and snap to the grid on landing, so recorded demos replay approximately. Demo acceptance compares completion and end state; route and input differences are reported as diagnostics.
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

`src/game/` owns detached terrain, path and bounded entity definitions/state,
grid and FORM queries, movement/reactions, gameplay camera, animation control
and source RNG. Supported entity scripts run in the same transaction. `src/mod/` remains future work
for watching files and reporting unmapped behavior. See the
[README layout](../../../README.md#layout) and [path contract](paths.md).

## Tick notifications and named source values

`TickEvent` carries a kind and typed parameters for sound, moving sound, sprite,
entity generation and death-animation notifications. Entity requests and
lifecycle notifications use the same value type. Candidate outboxes preserve
source order and are discarded on failure; copied observations detach events.
Consumers inspect kinds and parameters. `to_trace_line()` and `trace_lines()`
are external text projections and preserve the existing golden spellings.

`FrogMode`, `FrogFlags`, `GridSquareFlags`, `EntityLiveFlags` and `PowerupFlags`
name the source integer values. Movement callback flags belong to
`TerrainCallbackResult`. Their names do not alter serialized numeric values
or extend supported gameplay.

## Recorded demo control

`DemoSetup` resolves the enabled executable demo row and chosen detail through
`GameData`, then supplies the recorded starting cell and `FAST_RESET` start with the source 30-tick
fast-start timer. The session supplies its countdown only after accepted ticks.
Normal map, zone, entity and corridor validation still applies. Demo setup does
not establish whole-map gameplay support.

`TickCommand.recorded_input_byte` carries the raw byte separately from live
masks (`-1` means absent). Mixing live masks and recorded input is rejected.
The stationary C override boundary consumes the byte after input selection and
before camera, tongue and jump handling; jumping and camera waits do not consume
or buffer demo input. Raw camera bits are `0x40` clockwise and `0x20`
anticlockwise, while existing live logical masks retain their public values.
Camera handling precedes tongue and super-hop. Unsupported tongue and unsafe
reserved directional actions fail atomically. The recorded byte is preserved
in `TickResult.consumed_demo_byte`, or `-1` when the tick reads no input.

`DemoPlaybackSession` owns detached bytes, elapsed successful logic ticks and
consumed-input count. It offers one command at a time and accepts its matching
committed result; a failed tick advances neither counter and marks playback
incomplete with its diagnostic. An exhausted stream may continue non-consuming
ticks through `recorded_input_exhausted`; the next read fails safely. Reset the
session only after resetting the run succeeds. Worker consumers accept a result
only once after host handoff. Pause offers no commands and advances no counters.
Duration completion means the authored tick count elapsed, not that missing
level flow or reference agreement has been established. Reference global driver
call numbers are separate from local logic tick numbers.

## Logical sound clock

Whole-map ORG1 resolves [supplied sound tables](../data/executable-tables.md#sound-metadata)
and [Windows bank durations](../data/archives.md#windows-sound-bank-metadata)
into detached definitions. The logical clock advances before entity updates,
with moving objects visited newest first and voices allocated from the first
free slot in their source group. A successful allocation consumes pitch RNG
only when no explicit pitch offset was supplied. Single samples release their
voice after the source initialization guard, repeat samples re-key without a
new allocation draw, and looped samples wrap. Source moving pointers use the
same current transform for both position arguments, including the resulting
zero-doppler bend behavior.

Script sound, death and ejection operations execute on private candidates at
their source positions among RNG consumers. The runtime bridge is a private
transaction service passed separately to owned updates; detached value contexts
never contain it. Frog, reward, tongue and HUD sounds
likewise allocate at the call site. Entity retirement releases its moving owner;
selective recreation gets a new owner generation while the shared RNG and frame
clock continue. Full restart clears voice state. Later failure rolls back voices,
sample cursors, object generations, random draws and emitted requests together.
Actual audio playback remains deferred.

Killed logical voices retain their occupied slots until the source voice-update
pass, including first-update protection. Retirement clears moving ownership and
repeat behavior immediately; allocation and pitch RNG cannot reuse the slot early.

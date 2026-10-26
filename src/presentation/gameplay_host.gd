class_name GameplayHost
extends RefCounted
## Reusable 30 Hz pacing, command sampling and single-command worker handoff.

const PERIOD: float = 1.0 / GameplayRun.TICKS_PER_SECOND
var run: GameplayRun
var elapsed: float = 0.0
var render_elapsed: float = 0.0
var sampled_held: int = 0
var last_tick_usec: int = 0
var error: String = ""
var pending_command: TickCommand
var worker: TerrainTickWorker

## Replaces the run after joining any previous worker.
func open(value: GameplayRun) -> void:
	close()
	run = value
	elapsed = 0.0
	render_elapsed = 0.0
	sampled_held = 0
	error = ""

## Advances the render clock before accepting a completed result.
func begin_frame(delta: float) -> void:
	render_elapsed += delta

## Accumulates time without admitting overlapping work or multiple catch-up ticks.
func advance(delta: float, playing: bool) -> bool:
	if playing:
		elapsed += delta
	return playing and elapsed >= PERIOD and not pending()

## Retains one fractional period, dropping an excessive host stall.
func consume_period() -> void:
	elapsed = 0.0 if elapsed > PERIOD * 2.0 else elapsed - PERIOD

## Samples source-style pressed edges only at a command boundary.
func sample(tick: int, held: int) -> TickCommand:
	var command := TickCommand.new()
	command.tick_index = tick
	command.pressed_mask = held & ~sampled_held
	command.held_mask = held
	sampled_held = held
	return command

## Executes one synchronous command after all worker work is joined.
func step(command: TickCommand, capture_phases: bool) -> TickResult:
	if run == null or pending():
		var rejected := TickResult.new()
		rejected.error = "Open a gameplay run before stepping" if run == null else "Finish the pending command before synchronous stepping"
		return rejected
	close()
	var started: int = Time.get_ticks_usec()
	var result: TickResult = run.step(command, capture_phases)
	last_tick_usec = Time.get_ticks_usec() - started
	return result

## Submits one detached command, creating the worker on first use.
func submit(command: TickCommand) -> bool:
	error = ""
	if run == null:
		error = "Open a gameplay run before submitting"
		return false
	if worker == null:
		worker = TerrainTickWorker.new()
		var issue: Error = worker.start(run)
		if issue != OK:
			error = "Cannot start terrain tick worker: %s" % error_string(issue)
			worker = null
			return false
	if not worker.submit(command):
		error = "Terrain tick worker already has a command"
		return false
	pending_command = command.copy()
	return true

## Reports whether an unaccepted worker command is outstanding.
func pending() -> bool:
	return worker != null and worker.pending

## Accepts a completed worker result without blocking the frame.
func poll() -> TickResult:
	if not pending():
		return null
	var result: TickResult = worker.poll()
	if result != null:
		last_tick_usec = worker.last_tick_usec
	return result

## Joins and accepts the outstanding command before synchronous host operations.
func finish() -> TickResult:
	if not pending():
		return null
	var result: TickResult = worker.finish()
	last_tick_usec = worker.last_tick_usec
	return result

## Joins the worker before releasing its run ownership.
func close() -> void:
	if worker != null:
		worker.close()
		worker = null

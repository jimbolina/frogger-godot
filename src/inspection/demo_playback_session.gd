class_name DemoPlaybackSession
extends RefCounted
## Owns demo duration and input cursor outside committed gameplay transactions.

var duration: int = 0
var elapsed_ticks: int = 0
var input_cursor: int = 0
var status: String = "ready"
var reason: String = ""
var _bytes: PackedByteArray = PackedByteArray()
var _start_timer: int = -1
var _pending_tick: int = -1
var _pending_byte: int = -1

## Detaches recorded data; duration counts logic ticks rather than input bytes.
func configure(ticks: int, inputs: PackedByteArray, start_timer: int = -1) -> String:
	if ticks < 0 or start_timer < -1:
		return "Demo duration must be nonnegative and start timer at least -1"
	_start_timer = start_timer
	duration = ticks
	_bytes = inputs.duplicate()
	reset()
	return ""

## Restores playback counters after the caller successfully resets its gameplay run.
func reset() -> void:
	elapsed_ticks = 0
	input_cursor = 0
	status = "complete" if duration == 0 else "ready"
	reason = "duration elapsed" if duration == 0 else ""
	_pending_tick = -1
	_pending_byte = -1

## Offers exactly one detached command; exhaustion stops before an unsafe read.
func command(tick: int) -> TickCommand:
	if status in ["complete", "incomplete"] or _pending_tick >= 0:
		return null
	var result := TickCommand.new()
	result.tick_index = tick
	if _start_timer >= 0:
		result.start_timer_context = maxi(0, _start_timer - elapsed_ticks)
	result.recorded_input_exhausted = input_cursor >= _bytes.size()
	result.recorded_input_byte = -1 if result.recorded_input_exhausted else _bytes[input_cursor]
	_pending_tick = tick
	_pending_byte = result.recorded_input_byte
	return result

## Accepts one matching transaction; failures preserve both counters.
func accept(result: TickResult) -> String:
	if result == null or _pending_tick < 0:
		return "Demo playback has no matching pending command"
	if result.tick_index != _pending_tick:
		return "Demo playback result does not match the pending tick"
	if not result.error.is_empty():
		_pending_tick = -1
		_pending_byte = -1
		stop(result.error)
		return result.error
	if result.final_snapshot == null or result.consumed_demo_byte not in [-1, _pending_byte]:
		return "Demo playback result has invalid committed input metadata"
	elapsed_ticks += 1
	if result.consumed_demo_byte >= 0:
		input_cursor += 1
	_pending_tick = -1
	_pending_byte = -1
	status = "complete" if elapsed_ticks >= duration else "running"
	reason = "duration elapsed" if status == "complete" else ""
	return ""

## Marks a capability or admission boundary without claiming demo completion.
func stop(issue: String) -> void:
	status = "incomplete"
	reason = issue

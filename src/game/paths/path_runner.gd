class_name PathRunner
extends RefCounted
## Owns one detached path runner and applies one frozen-source update per call.

var error: String = ""
var _definition: PathDefinition = null
var _state: PathSnapshot = null

## Checks a path for geometry the source evaluator can safely sample.
static func validate_definition(definition: PathDefinition) -> String:
	if definition == null or definition.segments.is_empty():
		return "Path requires at least one segment"
	var total: int = 0
	for segment: PathSegmentDefinition in definition.segments:
		var issue: String = PathEvaluator.validate_segment(segment)
		if not issue.is_empty():
			return issue
		total += segment.length
		if total > 2147483647:
			return "Path total length exceeds source signed32"
	return ""

## Copies a path definition and creates an inspected component start.
static func create(definition: PathDefinition, start: PathStart = null) -> PathRunner:
	var result := PathRunner.new()
	result.error = validate_definition(definition)
	if not result.error.is_empty():
		return result
	result._definition = definition.copy()
	result.error = result.reset(start)
	return result

## Applies start flags and speed before evaluating the first position.
func reset(start: PathStart = null) -> String:
	if _definition == null:
		return "Path runner has no validated definition"
	var start_copy: PathStart = start.copy() if start != null else PathStart.new()
	if start_copy.segment_index < 0 or start_copy.segment_index >= _definition.segments.size():
		return "Path start segment index is outside the path"
	if start_copy.speed < 0 or start_copy.speed > 2147483647:
		return "Path speed must be nonnegative signed32"
	if start_copy.flags & ~PathStart.ALL_FLAGS:
		return "Path start has unsupported flags"
	var segment: PathSegmentDefinition = _definition.segments[start_copy.segment_index]
	if start_copy.distance < 0 or start_copy.distance > segment.length:
		return "Path start distance is outside the segment"
	var candidate := PathSnapshot.new()
	candidate.tick_index = 0
	candidate.segment_index = start_copy.segment_index
	candidate.segment_type = segment.segment_type
	candidate.segment_distance = start_copy.distance
	candidate.segment_length = segment.length
	candidate.speed = start_copy.speed
	candidate.flags = start_copy.flags
	candidate.total_distance = _total_distance(candidate.segment_index, candidate.segment_distance)
	var sample_result: PathSample = PathEvaluator.sample(segment, candidate.segment_distance, bool(candidate.flags & PathStart.BACKWARDS))
	if not sample_result.error.is_empty():
		return sample_result.error
	_apply_sample(candidate, sample_result)
	_state = candidate
	return ""

## Resets authored motion while preserving the enclosing simulation tick sequence.
func reset_motion(start: PathStart) -> String:
	var tick: int = _state.tick_index if _state != null else 0
	var issue: String = reset(start)
	if issue.is_empty():
		_state.tick_index = tick
	return issue

## Advances exactly one source path update; errors leave the prior snapshot intact.
func step(tick_index: int) -> String:
	if _state == null:
		return "Path runner has no valid start"
	if tick_index < 0 or tick_index != _state.tick_index:
		return "Path ticks must be consecutive from zero"
	var candidate: PathSnapshot = _state.copy()
	candidate.tick_index = tick_index + 1
	candidate.flags &= ~PathStart.JUST_CLEAR_MASK
	if candidate.flags & PathStart.ACTIVE:
		if candidate.flags & PathStart.BACKWARDS:
			_advance_backwards(candidate)
		else:
			_advance_forwards(candidate)
		if candidate.segment_index < 0 or candidate.segment_index >= _definition.segments.size():
			return "Path update crossed outside the path"
		var segment: PathSegmentDefinition = _definition.segments[candidate.segment_index]
		candidate.segment_type = segment.segment_type
		candidate.segment_length = segment.length
		if candidate.segment_distance < 0:
			candidate.segment_distance = _signed32(candidate.segment_distance + candidate.segment_length)
		if candidate.total_distance < 0:
			candidate.total_distance = _total_distance(candidate.segment_index, candidate.segment_distance)
		var sample_result: PathSample = PathEvaluator.sample(segment, candidate.segment_distance, bool(candidate.flags & PathStart.BACKWARDS))
		if not sample_result.error.is_empty():
			return sample_result.error
		_apply_sample(candidate, sample_result)
	_state = candidate
	return ""

## Builds a next-tick fork without copying the input cursor twice.
func advanced_copy(tick_index: int) -> PathRunner:
	var result := PathRunner.new()
	result._definition = _definition
	result._state = _state
	result.error = result.step(tick_index)
	if not result.error.is_empty():
		result._state = null
	return result

## Changes only the active bit after a script visit; the current sample is retained.
func set_active(active: bool) -> void:
	_state.flags = (_state.flags | PathStart.ACTIVE) if active else (_state.flags & ~PathStart.ACTIVE)

## Changes direction without resampling the source cursor.
func set_backwards(backwards: bool) -> void:
	_state.flags = (_state.flags | PathStart.BACKWARDS) if backwards else (_state.flags & ~PathStart.BACKWARDS)

## Changes the source path speed without resampling its current position.
func set_speed(speed: int) -> void:
	_state.speed = speed

## Returns a detached snapshot of the current runner state.
func snapshot() -> PathSnapshot:
	return _state.copy() if _state != null else null

## Returns an independent cursor sharing the private read-only validated definition.
func copy() -> PathRunner:
	var result := PathRunner.new()
	result.error = error
	result._definition = _definition
	result._state = _state.copy() if _state != null else null
	return result

func _advance_backwards(candidate: PathSnapshot) -> void:
	candidate.segment_distance = _signed32(candidate.segment_distance - candidate.speed)
	candidate.total_distance = _signed32(candidate.total_distance - candidate.speed)
	if candidate.segment_distance >= 0:
		return
	candidate.segment_index -= 1
	if candidate.segment_index >= 0:
		return
	if candidate.flags & PathStart.ONE_SHOT:
		candidate.flags |= PathStart.AT_END | PathStart.JUST_HIT_START
		candidate.segment_index = 0
		candidate.segment_distance = 0
		candidate.total_distance = 0
	elif candidate.flags & PathStart.REPEAT:
		candidate.segment_index = _definition.segments.size() - 1
		candidate.flags |= PathStart.JUST_REPEATED_START
	else:
		candidate.flags &= ~PathStart.BACKWARDS
		candidate.flags |= PathStart.JUST_BOUNCED_START
		candidate.segment_index = 0
		candidate.segment_distance = _signed32(-candidate.segment_distance)
		candidate.total_distance = candidate.segment_distance

func _advance_forwards(candidate: PathSnapshot) -> void:
	candidate.segment_distance = _signed32(candidate.segment_distance + candidate.speed)
	candidate.total_distance = _signed32(candidate.total_distance + candidate.speed)
	if candidate.segment_distance < candidate.segment_length:
		return
	candidate.segment_index += 1
	if candidate.segment_index < _definition.segments.size():
		candidate.segment_distance = _signed32(candidate.segment_distance - candidate.segment_length)
		return
	candidate.segment_index = _definition.segments.size() - 1
	if candidate.flags & PathStart.ONE_SHOT:
		candidate.flags |= PathStart.AT_END | PathStart.JUST_HIT_END
		candidate.total_distance = _signed32(candidate.total_distance - _signed32(candidate.segment_distance - candidate.segment_length))
		candidate.segment_distance = candidate.segment_length
	elif candidate.flags & PathStart.REPEAT:
		candidate.segment_index = 0
		candidate.segment_distance = _signed32(candidate.segment_distance - candidate.segment_length)
		candidate.total_distance = candidate.segment_distance
		candidate.flags |= PathStart.JUST_REPEATED_END
	else:
		candidate.flags |= PathStart.BACKWARDS | PathStart.JUST_BOUNCED_END
		candidate.total_distance = _signed32(candidate.total_distance - _signed32((candidate.segment_distance - candidate.segment_length) << 1))
		candidate.segment_distance = _signed32(_signed32(candidate.segment_length << 1) - candidate.segment_distance)

func _total_distance(index: int, distance: int) -> int:
	var total: int = distance
	for i: int in index:
		total = _signed32(total + _definition.segments[i].length)
	return total

func _signed32(value: int) -> int:
	var low: int = value & 0xffffffff
	return low - 0x100000000 if low >= 0x80000000 else low

func _apply_sample(candidate: PathSnapshot, evaluated: PathSample) -> void:
	candidate.position = evaluated.position
	candidate.tangent = evaluated.tangent
	candidate.segment_param = evaluated.segment_param

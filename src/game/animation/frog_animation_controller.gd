class_name FrogAnimationController
extends RefCounted
## Frozen high-poly froganim script control and MR_ANIM virtual-cel stepping.
## Setup supplies copied action lengths; the run owns phase order and shared RNG.

const COMMAND_LENGTHS: Array[int] = [4, 1, 1, 1, 1, 1, 8, 2, 2]

var error: String = ""
var state: FrogAnimationState = FrogAnimationState.new()
var context: FrogAnimationContext
var _action_lengths := PackedInt32Array()

## Starts the authored source PANT script and initial model action zero at cel zero.
static func create(action_lengths: PackedInt32Array, animation_context: FrogAnimationContext) -> FrogAnimationController:
	var result := FrogAnimationController.new()
	if action_lengths.size() < FrogAnimationCatalog.ACTION_NAMES.size():
		result.error = "High-poly frog metadata is missing source actions"
		return result
	for length: int in action_lengths:
		if length <= 0 or length > 32767:
			result.error = "Frog action virtual-cel count is outside source bounds"
			return result
	if animation_context == null or animation_context.random == null:
		result.error = "Frog animation requires a run-owned source random stream"
		return result
	result._action_lengths = action_lengths.duplicate()
	result.context = animation_context
	result.state.total_cels = action_lengths[0]
	return result

## Clones authoritative state while borrowing the copied run's context.
func copy(animation_context: FrogAnimationContext) -> FrogAnimationController:
	var result: FrogAnimationController = create(_action_lengths, animation_context)
	if not result.error.is_empty():
		return result
	result.state = state.copy()
	result.error = error
	return result

## Reinitializes source script/queue/restore state, including clearing a death lock.
func initialise(animation_id: int) -> bool:
	if not _valid(animation_id):
		return false
	_set_script(animation_id, FrogAnimationCatalog.FLAGS[animation_id])
	_clear_queue()
	state.previous_type = -1
	state.previous_flags = 0
	state.previous_program = -1
	state.previous_offset = -1
	return true

## Applies the source queue, delay interruption, bin, override and death-lock rules.
func request(animation_id: int) -> bool:
	if not _valid(animation_id):
		return false
	var flags: int = FrogAnimationCatalog.FLAGS[animation_id]
	if state.flags & 32:
		return true
	if state.flags & 16:
		state.previous_type = state.script_type
		state.previous_flags = state.flags
		state.previous_program = state.program_id
		state.previous_offset = state.word_offset
	if flags & 2:
		if state.delay_timer != 0:
			_set_script(animation_id, flags)
		else:
			state.queued_type = animation_id
			state.queued_flags = flags
			state.queue_program = animation_id
			state.queue_offset = 0
		state.delay_timer = 0
	elif flags & 4:
		if state.script_type == FrogAnimationCatalog.PANT:
			state.queued_type = animation_id
			state.queued_flags = flags
			state.queue_program = animation_id
			state.queue_offset = 0
			state.delay_timer = 0
	elif flags & 8:
		_set_script(animation_id, flags)
		_clear_queue()
		state.delay_timer = 0
	return true

## Runs script control before pose stepping; returns the source no-input timer.
func update_scripts(no_input_timer: int) -> int:
	if not error.is_empty():
		return no_input_timer
	state.no_input_timer = no_input_timer
	var captured_cel: int = state.cel
	var captured_total: int = state.total_cels
	# C captures these once, even when queue/restore immediately reruns a script.
	for _rerun: int in 128:
		var result: int = 0
		var commands: int = 0
		while result == 0:
			commands += 1
			if commands > 128:
				error = "Frog animation script did not yield"
				return state.no_input_timer
			result = _command()
		if state.queued_type != -1 and captured_cel >= captured_total - 1:
			_set_script(state.queued_type, state.queued_flags)
			_clear_queue()
			continue
		if result == 2 and state.previous_type != -1:
			_set_script(state.previous_type, state.previous_flags)
			state.previous_type = -1
			state.previous_flags = 0
			state.previous_program = -1
			state.previous_offset = -1
			continue
		state.script_timer += 1
		return state.no_input_timer
	error = "Frog animation queue/restore did not yield"
	return state.no_input_timer

## Advances one source logic-call virtual cel; presentation must only sample it.
func advance_pose() -> void:
	if not error.is_empty() or (state.environment_flags & 1024) == 0:
		return
	state.update_count += 1
	if state.update_count >= 1 or state.cel == -1:
		state.update_count = 0
		state.cel += 1
		if state.cel >= state.total_cels:
			state.cel = state.total_cels - 1 if state.is_one_shot() else 0

func _valid(animation_id: int) -> bool:
	if animation_id < 0 or animation_id >= FrogAnimationCatalog.NAMES.size():
		error = "Unknown source frog animation ID"
		return false
	return error.is_empty()

func _set_script(animation_id: int, flags: int) -> void:
	state.script_type = animation_id
	state.program_id = animation_id
	state.word_offset = 0
	state.flags = flags

func _clear_queue() -> void:
	state.queued_type = -1
	state.queued_flags = 0
	state.queue_program = -1
	state.queue_offset = -1

func _command() -> int:
	var program: int = state.program_id
	var at: int = state.word_offset
	var words: PackedInt32Array = FrogAnimationCatalog.program(program)
	var token: int = words[at]
	match token:
		0:
			var playback: int = words[at + 1]
			var delay: int = words[at + 2]
			if delay != 0 and state.delay_timer == 0:
				state.delay_timer = delay
				return 1
			if delay != 0:
				state.delay_timer -= 1
				if state.delay_timer != 0:
					return 1
			state.action = words[at + 3]
			state.cel = -1
			state.total_cels = _action_lengths[state.action]
			state.environment_flags |= 7168
			if playback == 0:
				state.environment_flags |= 256
			else:
				state.environment_flags &= ~256
			state.delay_timer = 0
			state.word_offset = at + 4
		1:
			state.loop_start_program = program
			state.loop_start_offset = at + 1
			var end: int = at + 1
			while words[end] != 2:
				end += COMMAND_LENGTHS[words[end]]
			state.loop_end_program = program
			state.loop_end_offset = end
			state.word_offset = at + 1
		2:
			state.program_id = state.loop_start_program
			state.word_offset = state.loop_start_offset
			return 1
		3:
			return 2
		4:
			return 1
		5:
			if state.cel < state.total_cels - 1:
				return 1
			state.word_offset = at + 1
		6:
			if state.no_input_timer >= words[at + 2]:
				var draw: int = context.random.next_value("animation_idle")
				var animation_id: int = words[at + 4 + (draw & 3)]
				if context.theme in [&"JUN", &"VOL"]:
					var previous: int = context.if_counter
					context.if_counter += 1
					if previous == 4:
						animation_id = FrogAnimationCatalog.PHEW
						context.if_counter = 0
				request(animation_id)
				state.no_input_timer = 0
			state.program_id = program
			state.word_offset = at + 8
		7:
			state.script_timer = words[at + 1]
			state.word_offset = at + 2
		8:
			if state.script_timer < words[at + 1]:
				return 1
			state.word_offset = at + 2
		_:
			error = "Unknown frozen frog animation command"
			return 1
	return 0

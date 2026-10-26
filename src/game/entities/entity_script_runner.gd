class_name EntityScriptRunner
extends RefCounted
## Bounded source interpreter; failures publish no state, requests or RNG draws.

## Executes instructions, deviation, callbacks and timer on private copies.
static func update(definition: EntityScriptDefinition, state: EntityScriptState, animation: EntityAnimationState, context: EntityUpdateContext, random: SourceRandom) -> EntityUpdateResult:
	var result := EntityUpdateResult.new()
	if definition == null or state == null or animation == null or context == null or random == null:
		result.error = "Script update requires complete detached inputs"
		return result
	result.error = definition.validate(animation.lengths, context.form_id, context.has_path)
	if not result.error.is_empty():
		return result
	return _update_validated(definition, state, animation, context, random)

## Uses run-owned validation, checking dependencies and runtime cursors on every update.
static func update_prepared(prepared: PreparedEntityScript, state: EntityScriptState, animation: EntityAnimationState, context: EntityUpdateContext, random: SourceRandom) -> EntityUpdateResult:
	if prepared == null or not prepared.error.is_empty() or state == null or animation == null or context == null or random == null:
		var failed := EntityUpdateResult.new()
		failed.error = "Prepared script update requires valid complete inputs"
		return failed
	if not prepared.matches(animation, context):
		return update(prepared._definition, state, animation, context, random)
	return _update_validated(prepared._definition, state, animation, context, random, prepared)

static func _update_validated(definition: EntityScriptDefinition, state: EntityScriptState, animation: EntityAnimationState, context: EntityUpdateContext, random: SourceRandom, prepared: PreparedEntityScript = null, owned: bool = false) -> EntityUpdateResult:
	var result := EntityUpdateResult.new()
	if context.base_matrix.size() != 12 or context.fade_bounds.size() not in [0, 4]:
		result.error = "Invalid script transform or fade bounds"
		return result
	result.script_state = state if owned else state.copy()
	result.animation = animation if owned else animation.copy()
	result.random = random if owned else random.copy()
	result.matrix12 = context.base_matrix.duplicate()
	if not result.script_state.active:
		return result
	result.error = _execute(definition, context, result, prepared)
	if not result.error.is_empty():
		var failed := EntityUpdateResult.new()
		failed.error = result.error
		return failed
	_advance_deviation(result.script_state)
	result.matrix12[10] = _signed32(result.matrix12[10] + result.script_state.deviation)
	EntityScriptCallbacks.apply(definition, context, result)
	result.script_state.timer = (result.script_state.timer + 1) & 65535
	if result.script_ended:
		var next: EntityScriptState = result.script_state
		if next.return_program >= 0:
			next.program_id = next.return_program
			next.cursor = next.return_cursor
			next.loop_start = next.return_loop_start
			next.loop_end = next.return_loop_end
			next.return_program = -1
		else:
			next.active = false
	return result

static func _execute(definition: EntityScriptDefinition, context: EntityUpdateContext, result: EntityUpdateResult, prepared: PreparedEntityScript = null) -> String:
	var state: EntityScriptState = result.script_state
	for instruction: int in 4096:
		if not definition.programs.has(state.program_id):
			return "Unknown current script program"
		var words: PackedInt32Array = definition.programs[state.program_id]
		if (prepared.following(state.program_id, state.cursor) < 0) if prepared != null else not _instruction_boundary(words, state.cursor):
			return "Invalid current script cursor"
		var opcode: int = words[state.cursor]
		var following: int = state.cursor + EntityScriptDefinition.WIDTHS[opcode]
		var a: PackedInt32Array = words.slice(state.cursor + 1, following)
		var yielded: bool = false
		match opcode:
			1:
				if result.animation.action < 0 or result.animation.action >= result.animation.lengths.size():
					return "Invalid action while waiting for animation"
				if result.animation.cel < result.animation.lengths[result.animation.action] - 1:
					following = state.cursor
					yielded = true
			2:
				if not _path_ended(context):
					following = state.cursor
					yielded = true
			4:
				if context.sound_allocation_enabled:
					result.requests.append(TickEvent.sound(_short(a[0])))
			6:
				following = state.cursor
				yielded = true
				result.script_ended = true
			10:
				if context.sound_allocation_enabled and result.random.next_value("entity:%d:script" % context.entity_index) % absi(_short(a[1])) == 1:
					result.requests.append(TickEvent.sound(_short(a[0])))
			14:
				if state.loop_start < 0 or state.loop_end < 0:
					return "Timer break without active loop"
				if state.timer >= _value(state, a[0], a[1]):
					following = state.loop_end
					state.loop_start = -1
					state.loop_end = -1
			15, 16:
				result.path_active_request = 1 if opcode == 16 else 0
			20:
				if a[0] != 8 and _condition(a[0], 0, context, result):
					following = state.cursor
					yielded = true
					result.script_ended = true
			30:
				state.remaining = 0
			32:
				state.remaining = 0
				state.deviation = 0
				state.delta = 0
				state.destination = 0
			31:
				for register: int in definition.payload_registers.size():
					state.registers[register] = definition.payload_registers[register]
			35:
				pass
			34:
				state.callbacks[a[0]] = PackedInt32Array([a[1], a[2], a[3], 2])
			11:
				state.loop_start = following
				if prepared != null:
					state.loop_end = prepared.loop_end(state.program_id, state.cursor)
				else:
					var end: int = following
					while words[end] != 12:
						end += EntityScriptDefinition.WIDTHS[words[end]]
					state.loop_end = end + 1
			12:
				if state.loop_start < 0 or ((prepared.following(state.program_id, state.loop_start) < 0) if prepared != null else not _instruction_boundary(words, state.loop_start)):
					return "Invalid active script loop"
				following = state.loop_start
				yielded = true
			5:
				state.program_id = state.root_id
				following = 0
			38:
				following = state.cursor
				yielded = true
			3:
				result.animation.select(a[0])
			7:
				state.timer = _value(state, a[0], a[1]) & 65535
			0:
				if state.timer < _value(state, a[0], a[1]):
					following = state.cursor
					yielded = true
			8:
				state.destination = _short(a[2])
				state.delta = _short(a[3])
				state.remaining = _short(a[4])
			9:
				if state.remaining != 0:
					following = state.cursor
					yielded = true
			13:
				if _condition(a[1], a[3], context, result):
					if a[0] == 1:
						state.return_program = state.program_id
						state.return_cursor = following
						state.return_loop_start = state.loop_start
						state.return_loop_end = state.loop_end
					state.program_id = a[2]
					following = 0
					state.loop_start = -1
					state.loop_end = -1
			37:
				if state.moving_sound.is_empty() and context.sound_allocation_enabled:
					state.moving_sound = PackedInt32Array([a[0], _value(state, a[1], a[2]), _value(state, a[1], a[3])])
					result.requests.append(TickEvent.moving_sound(state.moving_sound[0], state.moving_sound[1], state.moving_sound[2]))
			36:
				_distance_sound(state, a, context, result)
			44:
				for splash: int in context.form_id - 18:
					result.requests.append(TickEvent.sprite(Vector3i(0, -64, -(context.form_id - 19) * 128 + splash * 256), Vector2i(1, -16)))
		state.cursor = following
		if yielded:
			return ""
	return "Non-yielding script exceeds instruction budget"

static func _instruction_boundary(words: PackedInt32Array, wanted: int) -> bool:
	var cursor: int = 0
	while cursor < words.size():
		if cursor == wanted:
			return true
		cursor += EntityScriptDefinition.WIDTHS[words[cursor]]
	return false

static func _value(state: EntityScriptState, mode: int, operand: int) -> int:
	return state.registers[operand] if mode == EntityScriptDefinition.OperandMode.REGISTER else operand

static func _advance_deviation(state: EntityScriptState) -> void:
	if state.remaining == 0:
		return
	state.deviation = _short(state.deviation + (state.delta >> 8))
	if state.remaining < 0:
		if (state.delta > 0 and state.deviation >= state.destination) or (state.delta < 0 and state.deviation <= state.destination):
			state.deviation = state.destination
			state.delta = 0
			state.remaining = 0
	else:
		state.remaining = _short(state.remaining - 1)
		if state.remaining == 0:
			state.delta = 0

static func _distance_sound(state: EntityScriptState, args: PackedInt32Array, context: EntityUpdateContext, result: EntityUpdateResult) -> void:
	if not context.sound_allocation_enabled:
		return
	var squared: int = 0
	for axis: int in 3:
		var local: int = _short(_signed32((context.base_matrix[axis * 3 + args[3]] * _short(args[4])) >> 12))
		var point: int = _short(local + context.base_matrix[9 + axis])
		var difference: int = _short(context.frog_position[axis] - point)
		squared += difference * difference
	var distance: int = _isqrt(_isqrt(squared))
	var threshold: int = _value(state, args[0], args[1])
	if (args[0] == 1 and threshold < distance) or (args[0] == 0 and threshold > distance):
		result.requests.append(TickEvent.sound(_short(_value(state, args[0], args[2]))))

static func _isqrt(value: int) -> int:
	var root: int = int(sqrt(float(value)))
	while (root + 1) * (root + 1) <= value:
		root += 1
	while root * root > value:
		root -= 1
	return root

static func _short(value: int) -> int:
	var low: int = value & 65535
	return low - 65536 if low >= 32768 else low

static func _signed32(value: int) -> int:
	var low: int = value & 0xffffffff
	return low - 0x100000000 if low >= 0x80000000 else low

static func _path_ended(context: EntityUpdateContext) -> bool:
	return bool(context.path_flags & (PathStart.JUST_BOUNCED_START | PathStart.JUST_BOUNCED_END | PathStart.JUST_REPEATED_START | PathStart.JUST_REPEATED_END))

static func _condition(condition: int, operand: int, context: EntityUpdateContext, result: EntityUpdateResult) -> bool:
	match condition:
		0:
			return context.previous_hit
		1:
			return not context.previous_hit
		2:
			return result.script_state.remaining == 0
		3:
			return true
		4:
			return context.previous_carry
		5:
			return not context.previous_carry
		6:
			return result.random.next_value("entity:%d:script" % context.entity_index) % operand == 1
		8:
			return _path_ended(context)
		9:
			return true
	return false

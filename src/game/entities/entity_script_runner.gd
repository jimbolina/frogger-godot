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

static func _update_validated(definition: EntityScriptDefinition, state: EntityScriptState, animation: EntityAnimationState, context: EntityUpdateContext, random: SourceRandom, prepared: PreparedEntityScript = null, owned: bool = false, runtime: EntityScriptRuntime = null) -> EntityUpdateResult:
	var result := EntityUpdateResult.new()
	if context.base_matrix.size() != 12 or context.authored_matrix.size() != 12 or context.fade_bounds.size() not in [0, 4]:
		result.error = "Invalid script transform or fade bounds"
		return result
	result.script_state = state if owned else state.copy()
	result.animation = animation if owned else animation.copy()
	result.random = random if owned else random.copy()
	if runtime != null and not owned:
		result.error = "Runtime script effects require a private owned candidate"
		return result
	result.runtime = runtime
	result.matrix12 = context.base_matrix.duplicate()
	result.entity_flags = context.entity_flags
	result.environment = context.environment.copy() if context.environment != null else null
	if not result.script_state.active:
		return result
	result.error = _execute(definition, context, result, prepared)
	if not result.error.is_empty():
		var failed := EntityUpdateResult.new()
		failed.error = result.error
		return failed
	EntityScriptMotion.advance(result.script_state)
	result.matrix12 = EntityScriptMotion.transform(result.script_state, result.matrix12, context.authored_matrix)
	EntityScriptCallbacks.apply(definition, context, result)
	if not result.runtime_error.is_empty():
		result.error = result.runtime_error
		return result
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
			21:
				if context.previous_carry:
					result.add_ejection(_value(state, a[0], a[1]), _value(state, a[0], a[2]))
			45:
				var speed: int = _value(state, a[0], a[3])
				var shift: int = _value(state, a[0], a[4])
				if speed < 0 or speed > 31 or shift < 0 or shift > 31:
					return "Unsafe pitch-bend shift operand"
				if not state.moving_sound.is_empty() and context.moving_voice_active:
					var angle: int = (state.timer << speed) & 4095
					var wave: int = roundi(sin(float(angle) * TAU / 4096.0) * 4096.0) >> shift
					var pitch: int = PlatformMath.s32(_value(state, a[0], a[4] if a[0] == 1 else a[5]) - wave)
					var minimum: int = _value(state, a[0], a[1])
					var maximum: int = _value(state, a[0], a[2])
					pitch = minimum if pitch < minimum else maximum if pitch > maximum else pitch
					result.add_request(TickEvent.pitch_bend(pitch))
			46:
				if not context.pop_allocated and not result.pop_started:
					result.pop_started = true
					result.add_request(TickEvent.make(TickEvent.Kind.ENTITY_POP_EXPLOSION_REQUEST))
			42:
				if context.previous_carry:
					result.add_death(a[0])
					if a[1] != 0:
						result.add_request(TickEvent.sound(_short(a[1])))
			19:
				EntityScriptHoming.apply(result.matrix12, context.frog_position, context.frog_mode, _value(state, a[0], a[1]), _value(state, a[0], a[2]), a[2])
			22:
				if result.environment == null or not result.environment.validate().is_empty():
					return "Checkpoint selection requires a valid environment"
				state.position = Vector3i(0, -20000, 0)
				if result.random.next_value("entity:%d:checkpoint" % context.entity_index) % 5 < 2:
					var checkpoint: int = result.random.next_value("entity:%d:checkpoint" % context.entity_index) % 5
					for attempt: int in 5:
						var index: int = (checkpoint + attempt) % 5
						if not result.environment.collected & (1 << index):
							result.environment.collision_disabled |= 1 << index
							result.checkpoint_collision_changed = true
							state.position = result.environment.checkpoint_positions[index]
							state.user_data = index
							break
			23:
				for axis: int in 3:
					result.matrix12[9 + axis] = state.position[axis]
				result.entity_flags &= ~(EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION)
			24:
				result.entity_flags |= EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION
			47:
				result.entity_flags |= EntityDefinition.NO_COLLISION
			48:
				result.entity_flags &= ~EntityDefinition.NO_COLLISION
			40, 41:
				if result.environment == null or not result.environment.validate().is_empty() or state.user_data < 0 or state.user_data >= 5:
					return "Checkpoint collision requires a valid environment and selection"
				if opcode == 40:
					result.environment.collision_disabled |= 1 << state.user_data
				else:
					result.environment.collision_disabled = 0
				result.checkpoint_collision_changed = true
			25:
				state.root_id = a[0]
			26, 27, 28:
				pass
			39:
				if not context.no_display:
					var height: int = mini(0, result.matrix12[10])
					state.colours = Vector3i((16 + ((height * -16) >> 9)) & 255, (64 + ((height * -32) >> 9)) & 255, (96 + ((height * -32) >> 9)) & 255)
					state.ambient = Vector3i(64, 128, 192)
			43:
				if not context.no_display and not result.animation.lengths.is_empty():
					result.animation.select(_short(a[0]))
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
					result.add_request(TickEvent.sound(_short(a[0])))
			6:
				following = state.cursor
				yielded = true
				result.script_ended = true
			10:
				if context.sound_allocation_enabled and result.random.next_value("entity:%d:script" % context.entity_index) % absi(_short(a[1])) == 1:
					result.add_request(TickEvent.sound(_short(a[0])))
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
			17:
				state.angular_destinations[a[0]] = _short(a[1])
				state.angular_deltas[a[0]] = _short(a[2])
				state.angular_counts[a[0]] = _short(a[3])
			18:
				if state.angular_counts != Vector3i.ZERO:
					following = state.cursor
					yielded = true
			29:
				state.angular_counts = Vector3i.ZERO
			30:
				state.counts = Vector3i.ZERO
			32:
				state.counts = Vector3i.ZERO
				state.offsets = Vector3i.ZERO
				state.deltas = Vector3i.ZERO
				state.destinations = Vector3i.ZERO
			31:
				for register: int in definition.payload_registers.size():
					state.registers[register] = definition.payload_registers[register]
			35:
				state.entity_type = a[0]
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
			8, 33:
				var axis: int = a[1] % 3
				var direction: int = -1 if a[1] > 2 else 1
				state.destinations[axis] = _short(_value(state, a[0], a[2])) if opcode == 8 else 0
				state.deltas[axis] = _short(direction * _value(state, a[0], a[3] if opcode == 8 else a[2]))
				state.counts[axis] = _short(a[4]) if opcode == 8 else -1
			9:
				if state.counts != Vector3i.ZERO:
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
				if state.moving_sound.is_empty() and context.sound_allocation_enabled and context.moving_allocation_enabled:
					state.moving_sound = PackedInt32Array([a[0], _value(state, a[1], a[2]), _value(state, a[1], a[3])])
					result.add_request(TickEvent.moving_sound(state.moving_sound[0], state.moving_sound[1], state.moving_sound[2]))
			36:
				_distance_sound(state, a, context, result)
			44:
				if definition.original_turtle_splashes:
					for splash: int in context.form_id - 18:
						result.add_request(TickEvent.sprite(Vector3i(0, -64, -(context.form_id - 19) * 128 + splash * 256), Vector2i(1, -16)))
				else:
					result.add_request(TickEvent.sprite(Vector3i.ZERO, Vector2i(1, -16)))
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
		result.add_request(TickEvent.sound(_short(_value(state, args[0], args[2]))))

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
			return result.script_state.counts == Vector3i.ZERO
		3:
			return result.script_state.angular_counts == Vector3i.ZERO
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

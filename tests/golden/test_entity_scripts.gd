extends GutTest
## Independent Python/frozen-C script facts, using invented asset-free programs.

func test_complete_script_updates_match_independent_frozen_c_facts() -> void:
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/fixtures/entity_scripts.json"))
	var text: String = FileAccess.get_file_as_string("res://tests/golden/synthetic/entity_scripts.tsv")
	var lines: PackedStringArray = text.strip_edges().split("\n")
	var header: PackedStringArray = lines[0].split("\t")
	var row_index: int = 1
	for fixture: Dictionary in cases:
		var definition := EntityScriptDefinition.new()
		definition.root_id = fixture.root
		definition.payload_offset = fixture.payload_offset
		definition.payload_registers = _integers(fixture.registers)
		var programs: Dictionary = fixture.programs
		var names: Dictionary = fixture.names
		for key: String in programs:
			definition.programs[int(key)] = _integers(programs[key])
			definition.names[int(key)] = names[key]
		definition.callbacks = {0: EntityScriptDefinition.CallbackKind.FROG_TRAFFIC_SPLAT, 1: EntityScriptDefinition.CallbackKind.LOG_SPLASH, 2: EntityScriptDefinition.CallbackKind.DIVE_COLOUR_CHANGE, 8: EntityScriptDefinition.CallbackKind.HIT_TURTLE}
		var state: EntityScriptState = EntityScriptState.create(definition.root_id)
		state.timer = fixture.timer
		state.deviation = fixture.deviation
		var animation: EntityAnimationState = EntityAnimationState.create(_integers(fixture.actions))
		var seed: int = fixture.seed
		var rng: SourceRandom = SourceRandom.create(seed)
		var inputs: Array = fixture.inputs
		for tick: int in inputs.size():
			var input := _integers(inputs[tick])
			var context := EntityUpdateContext.new()
			context.has_path = true
			context.form_id = fixture.form_id
			context.previous_hit = bool(input[0])
			context.previous_carry = bool(input[1])
			context.no_display = bool(input[2])
			if bool(input[3]):
				context.fade_bounds = PackedInt32Array([1, 32767, -32767, 32767])
			context.sound_allocation_enabled = bool(input[4])
			if bool(input[5]):
				state.moving_sound.clear()
			var result: EntityUpdateResult = EntityScriptRunner.update(definition, state, animation, context, rng)
			assert_eq(result.error, "", "%s tick %d" % [fixture.name, tick])
			if not result.error.is_empty():
				return
			state = result.script_state
			animation = result.animation
			rng = result.random
			animation.advance()
			var fields: Dictionary = {"case": fixture.name, "tick": tick, "program": state.program_id, "cursor": state.cursor, "loop_start": state.loop_start, "loop_end": state.loop_end, "timer": state.timer, "deviation": state.deviation, "delta": state.delta, "destination": state.destination, "remaining": state.remaining, "action": animation.action, "cel": animation.cel, "rng": rng.state, "red": state.colours.x, "green": state.colours.y, "blue": state.colours.z, "ambient_red": state.ambient.x, "ambient_green": state.ambient.y, "ambient_blue": state.ambient.z, "no_fade": int(state.no_screen_fade), "drown": int(result.drown), "requests": ";".join(TickEvent.trace_lines(result.requests)) if not result.requests.is_empty() else "-"}
			for slot: int in 2:
				var values := PackedStringArray()
				for value: int in state.callbacks[slot]:
					values.append(str(value))
				fields["callback%d" % slot] = ":".join(values)
			fields["sound_id"] = state.moving_sound[0] if not state.moving_sound.is_empty() else -1
			fields["sound_min"] = state.moving_sound[1] if not state.moving_sound.is_empty() else -1
			fields["sound_max"] = state.moving_sound[2] if not state.moving_sound.is_empty() else -1
			var actual := PackedStringArray()
			for field: String in header:
				actual.append(str(fields[field]))
			assert_lt(row_index, lines.size(), "Complete golden required")
			if row_index >= lines.size():
				return
			assert_eq(actual, lines[row_index].split("\t"), "%s tick %d" % [fixture.name, tick])
			row_index += 1
	assert_eq(row_index, lines.size())

func _integers(value: Variant) -> PackedInt32Array:
	var values: Array = value
	return PackedInt32Array(values)

func test_named_callbacks_match_independent_source_facts() -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/script_callbacks.json"))
	for fixture: Dictionary in fixtures:
		var definition := EntityScriptDefinition.new()
		definition.root_id = 1
		definition.programs[1] = PackedInt32Array([34, 0, 7, 0, 1, 38])
		definition.names[1] = "synthetic_callbacks"
		definition.callbacks[7] = EntityScriptSetup.CALLBACK_KINDS[fixture.name]
		if fixture.name == "SCRIPT_CB_SKY_HELIUM_BALLOON":
			definition.callback_programs[7] = 2
			definition.programs[2] = PackedInt32Array([38])
			definition.names[2] = "SCRIPT_SKY_HELIUM_BALLOON_RISING"
		var context := EntityUpdateContext.new()
		context.has_path = fixture.get("has_path", true)
		context.previous_hit = fixture.hit
		context.previous_carry = fixture.get("carry", false)
		context.no_display = fixture.no_display
		context.base_matrix[10] = fixture.path_y
		var state: EntityScriptState = EntityScriptState.create(1)
		state.offsets.y = fixture.get("deviation", 0)
		var result: EntityUpdateResult = EntityScriptRunner.update(definition, state, EntityAnimationState.create([]), context, SourceRandom.create(1))
		assert_eq(result.error, "", str(fixture.name))
		if not result.error.is_empty():
			return
		var sounds := PackedInt32Array()
		for request: TickEvent in result.requests:
			assert_eq(request.kind, TickEvent.Kind.SOUND)
			sounds.append(request.sound_id)
		assert_eq(sounds, _integers(fixture.sounds), str(fixture.name))
		var colours: PackedInt32Array = _integers(fixture.colours)
		var ambient: PackedInt32Array = _integers(fixture.ambient)
		assert_eq(result.script_state.colours, Vector3i(colours[0], colours[1], colours[2]), str(fixture.name))
		assert_eq(result.script_state.ambient, Vector3i(ambient[0], ambient[1], ambient[2]), str(fixture.name))
		assert_eq(result.random.draw_count, 0, str(fixture.name))
		assert_eq(result.frog_deaths, _integers(fixture.get("deaths", [])), str(fixture.name))
		var no_fade: bool = fixture.get("no_fade", false)
		var program: int = fixture.get("program", 1)
		assert_eq(result.script_state.no_screen_fade, no_fade, str(fixture.name))
		assert_eq(result.script_state.program_id, program, str(fixture.name))

func test_control_flow_matches_independent_source_model() -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/script_control.json"))
	for fixture: Dictionary in fixtures:
		var definition := EntityScriptDefinition.new()
		definition.root_id = 1
		for key: String in fixture.programs:
			definition.programs[int(key)] = _integers(fixture.programs[key])
			definition.names[int(key)] = "SCRIPT_TURTLE"
		definition.callbacks = {1: EntityScriptDefinition.CallbackKind.LOG_SPLASH}
		definition.payload_registers = _integers(fixture.get("registers", []))
		definition.payload_offset = 12 if not definition.payload_registers.is_empty() else 0
		for prepared_mode: bool in [false, true]:
			var state: EntityScriptState = EntityScriptState.create(1)
			var animation: EntityAnimationState = EntityAnimationState.create(PackedInt32Array([3, 4]))
			var random: SourceRandom = SourceRandom.create(1)
			var prepared: PreparedEntityScript = PreparedEntityScript.create(definition, animation.lengths, 21, true)
			assert_eq(prepared.error, "", str(fixture.name))
			var inputs: Array = fixture.inputs
			for tick: int in inputs.size():
				var input: Dictionary = fixture.inputs[tick]
				var context := EntityUpdateContext.new()
				context.has_path = true
				context.form_id = 21
				context.previous_hit = input.get("hit", false)
				context.previous_carry = input.get("carry", false)
				var path_flags: float = input.get("path_flags", 0)
				context.path_flags = int(path_flags)
				context.sound_allocation_enabled = input.get("allocation", true)
				var result: EntityUpdateResult = EntityScriptRunner.update_prepared(prepared, state, animation, context, random) if prepared_mode else EntityScriptRunner.update(definition, state, animation, context, random)
				assert_eq(result.error, "", "%s tick %d" % [fixture.name, tick])
				if not result.error.is_empty():
					return
				state = result.script_state
				animation = result.animation
				random = result.random
				animation.advance()
				var returning: Array = []
				if state.return_program >= 0:
					returning = [state.return_program, state.return_cursor, state.return_loop_start, state.return_loop_end]
				var actual: Dictionary = {"active": state.active, "program": state.program_id, "cursor": state.cursor, "loop_start": state.loop_start, "loop_end": state.loop_end, "timer": state.timer, "deviation": state.deviation, "delta": state.delta, "destination": state.destination, "remaining": state.remaining, "action": animation.action, "cel": animation.cel, "rng": random.state, "return_frame": returning, "path_active_request": result.path_active_request, "requests": Array(TickEvent.trace_lines(result.requests))}
				assert_eq(JSON.stringify(JSON.parse_string(JSON.stringify(actual))), JSON.stringify(fixture.expected[tick]), "%s tick %d prepared=%s" % [fixture.name, tick, prepared_mode])

func test_three_axis_motion_matches_independent_source_facts() -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/script_motion.json"))
	assert_eq(fixtures.size(), 8)
	for fixture: Dictionary in fixtures:
		var state: EntityScriptState = EntityScriptState.create(1)
		state.entity_type = fixture.get("entity_type", 0)
		var base: PackedInt32Array = _integers(fixture.base)
		var current: PackedInt32Array = base.duplicate()
		var initial: Dictionary = fixture.initial
		for key: String in initial:
			var vector: PackedInt32Array = _integers(initial[key])
			state.set(key, Vector3i(vector[0], vector[1], vector[2]))
		var tick: int = 0
		for expected: Dictionary in fixture.expected:
			EntityScriptMotion.advance(state)
			for key: String in expected.state:
				var vector: PackedInt32Array = _integers(expected.state[key])
				var actual: Vector3i = state.get(key)
				assert_eq(actual, Vector3i(vector[0], vector[1], vector[2]), "%s tick %d %s" % [fixture.name, tick, key])
			current = EntityScriptMotion.transform(state, current if state.entity_type == 1 else base, base)
			assert_eq(current, _integers(expected.matrix), "%s tick %d matrix" % [fixture.name, tick])
			tick += 1

func test_script_effects_match_independent_source_facts() -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/script_effects.json"))
	for fixture: Dictionary in fixtures:
		var definition := EntityScriptDefinition.new()
		definition.root_id = 1
		definition.names[1] = "synthetic_effects"
		var context := EntityUpdateContext.new()
		var random: SourceRandom = SourceRandom.create(1)
		match fixture.kind:
			"pitch":
				definition.programs[1] = PackedInt32Array([45, 0, 32, 96, 5, 7, 64, 38])
				var initial: EntityScriptState = EntityScriptState.create(1)
				initial.timer = fixture.timer
				initial.moving_sound = PackedInt32Array([1, 0, 1024])
				if fixture.registers:
					definition.payload_registers = PackedInt32Array([32, 96, 5, 7, 64])
					definition.programs[1] = PackedInt32Array([45, 1, 0, 1, 2, 3, 4, 38])
					for index: int in 5:
						initial.registers[index] = definition.payload_registers[index]
				var output: EntityUpdateResult = EntityScriptRunner.update(definition, initial, EntityAnimationState.create([]), context, random)
				assert_eq(output.error, "")
				var expected: int = fixture.expected
				assert_eq(output.requests[0].pitch, expected)
				continue
			"eject":
				var delta: int = fixture.delta
				var duration: int = fixture.duration
				definition.programs[1] = PackedInt32Array([21, 0, delta, duration, 38])
				context.previous_carry = fixture.carry
				var output: EntityUpdateResult = EntityScriptRunner.update(definition, EntityScriptState.create(1), EntityAnimationState.create([]), context, random)
				assert_eq(output.error, "")
				var actual := PackedInt32Array()
				if not output.effects.is_empty():
					actual.append_array([output.effects[0].grid_delta, output.effects[0].jump_duration])
				assert_eq(actual, _integers(fixture.expected))
				continue
			"pop":
				definition.programs[1] = PackedInt32Array([46, 46, 38])
				context.pop_allocated = fixture.allocated
				var output: EntityUpdateResult = EntityScriptRunner.update(definition, EntityScriptState.create(1), EntityAnimationState.create([]), context, random)
				assert_eq(output.error, "")
				var expected: bool = fixture.started
				assert_eq(output.pop_started, expected)
				assert_eq(output.random.draw_count, 0)
				continue
			"checkpoint_croak":
				var entity := EntityDefinition.new()
				var candidate := EntityCustomResult.new()
				candidate.entity = EntitySnapshot.new()
				candidate.entity.animation = EntityAnimationState.create([4, 3, 5])
				candidate.entity.animation.action = fixture.action
				candidate.entity.animation.cel = fixture.cel
				candidate.environment = EntityEnvironmentState.new()
				for index: int in 5:
					candidate.environment.checkpoint_positions.append(Vector3i.ZERO)
				candidate.environment.croak_modes[0] = fixture.mode
				var seed: int = fixture.seed
				candidate.random = SourceRandom.create(seed)
				var distance: int = fixture.distance
				assert_eq(EntityCheckpoint.update(entity, candidate, Vector3i(0, distance, 0)), "")
				var action: int = fixture.next_action
				var cel: int = fixture.next_cel
				var mode: int = fixture.next_mode
				var rng: int = fixture.rng
				var draws: int = fixture.draws
				assert_eq(candidate.entity.animation.action, action)
				assert_eq(candidate.entity.animation.cel, cel)
				assert_eq(candidate.environment.croak_modes[0], mode)
				assert_eq(candidate.random.state, rng)
				assert_eq(candidate.random.draw_count, draws)
				continue
			"homing":
				var matrix: PackedInt32Array = EntityTransform.IDENTITY.duplicate()
				var target: PackedInt32Array = _integers(fixture.target)
				var mode: int = fixture.mode
				var speed: int = fixture.speed
				var limit: int = fixture.limit
				var literal: int = fixture.literal
				EntityScriptHoming.apply(matrix, Vector3i(target[0], target[1], target[2]), mode, speed, limit, literal)
				assert_eq(matrix, _integers(fixture.expected), JSON.stringify(fixture))
				continue
			"checkpoint":
				definition.programs[1] = PackedInt32Array([22, 23, 38])
				context.environment = EntityEnvironmentState.new()
				context.environment.collected = fixture.collected
				for index: int in 5:
					context.environment.checkpoint_positions.append(Vector3i(index * 100, 20, 30))
				var seed: int = fixture.seed
				random = SourceRandom.create(seed)
			"colour":
				definition.programs[1] = PackedInt32Array([39, 38])
				context.base_matrix[10] = fixture.height
		var result: EntityUpdateResult = EntityScriptRunner.update(definition, EntityScriptState.create(1), EntityAnimationState.create([]), context, random)
		assert_eq(result.error, "", JSON.stringify(fixture))
		if not result.error.is_empty():
			return
		if fixture.kind == "checkpoint":
			var position: PackedInt32Array = _integers(fixture.position)
			var selected: int = fixture.selected
			var disabled: int = fixture.disabled
			var rng: int = fixture.rng
			var draws: int = fixture.draws
			assert_eq(result.script_state.position, Vector3i(position[0], position[1], position[2]))
			assert_eq(result.script_state.user_data, selected)
			assert_eq(result.environment.collision_disabled, disabled)
			assert_eq(result.random.state, rng)
			assert_eq(result.random.draw_count, draws)
		else:
			var colours: PackedInt32Array = _integers(fixture.colours)
			assert_eq(result.script_state.colours, Vector3i(colours[0], colours[1], colours[2]))

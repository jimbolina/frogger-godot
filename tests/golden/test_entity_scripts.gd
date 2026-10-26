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
		definition.callbacks = {0: "SCRIPT_CB_FROG_TRAFFIC_SPLAT", 1: "SCRIPT_CB_LOG_SPLASH", 2: "SCRIPT_CB_DIVE_COLOUR_CHANGE", 8: "SCRIPT_CB_HIT_TURTLE"}
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

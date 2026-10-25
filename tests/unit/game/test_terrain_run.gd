extends GutTest
## Full ordered component fields checked against independent frozen-C synthetic facts.

func _level(blocked: bool = false) -> LevelDefinition:
	var level := LevelDefinition.new()
	level.grid = GridDefinition.new()
	level.grid.dimensions = Vector2i(4, 4)
	level.grid.base = Vector2i(-512, -512)
	level.spawn_cell = Vector2i(1, 1)
	for i: int in 16:
		var stack := GridStackDefinition.new()
		stack.first_square_index = i
		stack.square_count = 1
		level.grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		square.flags = 0 if blocked and i == 9 else 3
		var x: int = -512 + (i % 4) * 256
		@warning_ignore("integer_division")
		var z: int = -512 + (i / 4) * 256
		square.vertices.assign([Vector3i(x, 0, z + 256), Vector3i(x + 256, 0, z + 256), Vector3i(x, 0, z), Vector3i(x + 256, 0, z)])
		level.grid.squares.append(square)
	return level

func _fields(state: RunSnapshot) -> Array[int]:
	return [state.position_16.x, state.position_16.y, state.position_16.z, state.velocity_16.x, state.velocity_16.y, state.velocity_16.z, state.cell.x, state.cell.y, state.remaining_ticks, state.flags, state.mode, state.current_input, state.direction, state.animation_requests, state.sound_requests, state.score_requests, state.buffered_keys, state.buffered_input_count]

func _empty_target(level: LevelDefinition) -> void:
	level.grid.stacks[9].square_count = 0
	level.grid.squares.remove_at(9)
	for i: int in range(10, 16):
		level.grid.stacks[i].first_square_index -= 1

func test_control_and_move_match_independent_corpus() -> void:
	var lines: PackedStringArray = FileAccess.get_file_as_string("res://tests/golden/synthetic/terrain_components.csv").strip_edges().split("\n")
	assert_eq(lines.size(), 97)
	var row: int = 1
	for scenario: int in 3:
		var run: TerrainRun = TerrainRun.create(_level(scenario == 1))
		assert_eq(run.error, "")
		for tick: int in 16:
			var command := TickCommand.new()
			command.tick_index = tick
			command.pressed_mask = TickCommand.NORTH if tick == 0 else 0
			command.held_mask = command.pressed_mask
			if scenario == 2 and tick >= 2 and tick <= 8:
				command.pressed_mask = TickCommand.EAST if tick == 2 else 0
				command.held_mask = TickCommand.EAST
			var result: TickResult = run.step(command)
			assert_eq(result.error, "")
			for phase: String in ["control", "move"]:
				var expected: PackedStringArray = lines[row].strip_edges().split(",")
				assert_eq(expected[0].to_int(), scenario)
				assert_eq(expected[1].to_int(), tick)
				assert_eq(expected[2], phase)
				var state: RunSnapshot = result.control_snapshot if phase == "control" else result.move_snapshot
				var values: Array[int] = _fields(state)
				for i: int in values.size():
					assert_eq(values[i], expected[i + 3].to_int(), "scenario %d tick %d %s field %d" % [scenario, tick, phase, i])
				assert_eq(command.pressed_mask, expected[21].to_int())
				assert_eq(command.held_mask, expected[22].to_int())
				row += 1

func test_tick_validation_snapshot_ownership_and_reset() -> void:
	var level: LevelDefinition = _level()
	var run: TerrainRun = TerrainRun.create(level)
	var snapshot: RunSnapshot = run.snapshot()
	snapshot.position_16 = Vector3i.ZERO
	level.grid.squares[9].flags = 0
	var command := TickCommand.new()
	command.tick_index = 1
	command.pressed_mask = TickCommand.NORTH
	assert_false(run.step(command).error.is_empty())
	assert_eq(run.snapshot().tick_index, 0)
	command.tick_index = 0
	command.pressed_mask = 32
	assert_false(run.step(command).error.is_empty())
	command.pressed_mask = TickCommand.NORTH
	var result: TickResult = run.step(command)
	assert_eq(result.error, "")
	assert_eq(result.move_snapshot.remaining_ticks, 5)
	result.move_snapshot.position_16 = Vector3i.ZERO
	assert_eq(run.snapshot().position_16, Vector3i(-8388608, -2621440, -5592406))
	var invalid := RunStart.new()
	invalid.spawn_cell = Vector2i(-2, -2)
	assert_false(run.reset(invalid).is_empty())
	assert_eq(run.snapshot().tick_index, 1)
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().tick_index, 0)
	assert_eq(run.snapshot().animation_requests, 0)
	assert_eq(run.snapshot().position_16, Vector3i(-8388608, 0, -8388608))
	assert_eq(run.step(command).error, "")

func test_unknown_flag_data_is_retained_and_source_ignored() -> void:
	var level: LevelDefinition = _level()
	level.grid.squares[9].flags = 8195
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	var command := TickCommand.new()
	command.pressed_mask = TickCommand.NORTH
	var result: TickResult = run.step(command)
	assert_eq(result.error, "")
	for tick: int in range(1, 6):
		command.tick_index = tick
		command.pressed_mask = 0
		result = run.step(command)
		assert_eq(result.error, "")
	assert_true(result.events.has("unknown_terrain_flags_ignored"))
	assert_eq(result.final_snapshot.square_flags, 8195)
	assert_eq(result.final_snapshot.mode, 0)
	assert_eq(result.final_snapshot.position_16, Vector3i(-128 * 65536, 0, 128 * 65536))

func test_source_shape_ranges_are_validated_before_state() -> void:
	var level: LevelDefinition = _level()
	level.grid.stacks[6].first_square_index = 5
	assert_string_contains(TerrainRun.create(level).error, "layer ranges")
	level = _level()
	level.grid.stacks[0].cliff_height_byte = 256
	assert_string_contains(TerrainRun.create(level).error, "layer ranges")
	level = _level()
	level.grid.squares[0].flags = -1
	assert_string_contains(TerrainRun.create(level).error, "unsigned32")
	level = _level()
	level.collision_bounds = Rect2i(-32768, -32768, 65536, 65536)
	assert_string_contains(TerrainRun.create(level).error, "signed16")
	level = _level()
	level.theme_death_height = 2147483648
	assert_string_contains(TerrainRun.create(level).error, "signed32")
	var initial := RunStart.new()
	initial.quick_jump_timer = 65536
	assert_string_contains(TerrainRun.create(_level(), initial).error, "unsigned16")

func test_source_undefined_final_lookup_rejects_without_partial_tick() -> void:
	var level: LevelDefinition = _level()
	level.spawn_cell = Vector2i(1, 3)
	var run: TerrainRun = TerrainRun.create(level)
	var command := TickCommand.new()
	command.pressed_mask = TickCommand.NORTH
	for tick: int in range(5):
		command.tick_index = tick
		assert_eq(run.step(command).error, "")
		command.pressed_mask = 0
	var before: RunSnapshot = run.snapshot()
	command.tick_index = 5
	var result: TickResult = run.step(command)
	assert_string_contains(result.error, "outside authored storage")
	assert_eq(run.snapshot().tick_index, before.tick_index)
	assert_eq(run.snapshot().position_16, before.position_16)
	assert_eq(run.snapshot().matrix12, before.matrix12)
	assert_eq(run.snapshot().rng_state, before.rng_state)
	assert_eq(run.snapshot().rng_draw_count, before.rng_draw_count)

func test_start_context_completion_and_scalar_identity_ownership() -> void:
	var level: LevelDefinition = _level()
	level.source_id = "synthetic-source"
	level.resource_id = 42
	level.grid.squares[5].source_offset = 123
	level.grid.squares[5].polygon_index = 8
	level.grid.squares[5].polygon_source_offset = 456
	var initial := RunStart.new()
	initial.start_mode = 2
	var run: TerrainRun = TerrainRun.create(level, initial)
	level.source_id = "mutated"
	level.grid.squares[5].source_offset = 999
	var state: RunSnapshot = run.snapshot()
	assert_eq(state.source_id, "synthetic-source")
	assert_eq(state.resource_id, 42)
	assert_eq(state.square_source_offset, 123)
	assert_eq(state.polygon_index, 8)
	assert_eq(state.polygon_source_offset, 456)
	assert_eq(state.initial_cell, Vector2i(1, 1))
	assert_eq(state.mode, 265)
	var command := TickCommand.new()
	command.pressed_mask = TickCommand.NORTH
	var result: TickResult = run.step(command)
	assert_eq(result.error, "")
	assert_eq(result.control_snapshot.mode, 265, "Bounce has no input controller")
	assert_eq(result.control_snapshot.sound_requests, 0)
	command.tick_index = 1
	command.start_sequence_complete = true
	command.start_timer_context = 5
	result = run.step(command)
	assert_eq(result.error, "")
	assert_eq(result.control_snapshot.mode, 3, "Explicit HUD completion enters source camera wait")
	assert_eq(result.final_snapshot.start_timer, 5, "Run does not invent global countdown")
	command.tick_index = 2
	assert_false(run.step(command).error.is_empty())
	assert_eq(run.snapshot().tick_index, 2)
	command.start_sequence_complete = false
	command.start_timer_context = -1
	result = run.step(command)
	assert_eq(result.error, "")
	assert_eq(result.final_snapshot.start_timer, 5)
	assert_eq(result.final_snapshot.sound_requests, 0)
	assert_eq(run.reset(), "")
	command.tick_index = 0
	command.start_sequence_complete = true
	assert_false(run.step(command).error.is_empty())

func test_d1_height_power_and_freefall_corpus() -> void:
	var lines: PackedStringArray = FileAccess.get_file_as_string("res://tests/golden/synthetic/terrain_d1.csv").strip_edges().split("\n")
	assert_eq(lines.size(), 321)
	var row: int = 1
	var heights: Array[int] = [0, 0, 0, -200, -201, 256, 257, 0]
	for scenario: int in 8:
		var level: LevelDefinition = _level()
		for i: int in 4:
			level.grid.squares[9].vertices[i].y = heights[scenario]
		if scenario == 7:
			_empty_target(level)
		var initial := RunStart.new()
		initial.powerup_flags = 2 if scenario == 1 else 4 if scenario == 2 else 0
		initial.quick_jump_timer = 65535
		initial.auto_hop_timer = 65535
		var run: TerrainRun = TerrainRun.create(level, initial)
		assert_eq(run.error, "")
		for tick: int in 20:
			var command := TickCommand.new()
			command.tick_index = tick
			command.pressed_mask = (TickCommand.SUPER_HOP if scenario == 0 else TickCommand.NORTH) if tick == 0 else 0
			command.held_mask = TickCommand.NORTH if scenario == 2 and tick < 7 else command.pressed_mask
			var result: TickResult = run.step(command)
			assert_eq(result.error, "")
			for phase: String in ["control", "move"]:
				var expected: PackedStringArray = lines[row].strip_edges().split(",")
				assert_eq(expected[0].to_int(), scenario)
				assert_eq(expected[1].to_int(), tick)
				assert_eq(expected[2], phase)
				var state: RunSnapshot = result.control_snapshot if phase == "control" else result.move_snapshot
				var values: Array[int] = _fields(state)
				for i: int in values.size():
					assert_eq(values[i], expected[i + 3].to_int(), "D1 scenario %d tick %d %s field %d" % [scenario, tick, phase, i])
				row += 1

func test_collision_landing_deferred_death_and_completion_corpus() -> void:
	var lines: PackedStringArray = FileAccess.get_file_as_string("res://tests/golden/synthetic/terrain_collision.csv").strip_edges().split("\n")
	assert_eq(lines.size(), 3241)
	var row: int = 1
	var heights: Array[int] = [512, 513, 1024, 1025, 1025, 0, 0, 0, 0, 0, 0, 0]
	var flags: Array[int] = [3, 3, 3, 3, 259, 7, 5, 4097, 9, 3, 3, 5]
	for scenario: int in 12:
		var level: LevelDefinition = _level()
		level.collision_enabled = true
		level.theme = 3 if scenario == 11 else 9
		level.grid.squares[9].flags = flags[scenario]
		for i: int in 4:
			level.grid.squares[9].vertices[i].y = heights[scenario]
		if scenario == 9:
			level.collision_bounds = Rect2i(Vector2i(-127, -32767), Vector2i(32894, 65534))
		if scenario == 10:
			_empty_target(level)
			level.theme_death_height = 100
		var run: TerrainRun = TerrainRun.create(level)
		assert_eq(run.error, "")
		for tick: int in 90:
			var command := TickCommand.new()
			command.tick_index = tick
			command.pressed_mask = TickCommand.NORTH if tick == 0 else 0
			command.held_mask = command.pressed_mask
			var result: TickResult = run.step(command)
			assert_eq(result.error, "")
			for phase: String in ["control", "move", "collision"]:
				var expected: PackedStringArray = lines[row].strip_edges().split(",")
				assert_eq(expected[0].to_int(), scenario)
				assert_eq(expected[1].to_int(), tick)
				assert_eq(expected[2], phase)
				var state: RunSnapshot
				if phase == "control":
					state = result.control_snapshot
				elif phase == "move":
					state = result.move_snapshot
				else:
					state = result.collision_snapshot
				var values: Array[int] = _fields(state)
				values.resize(16)
				var requested_lives: int = state.fixture_lives - (1 if state.life_decrement_requested else 0)
				var requested_game_mode: int = state.game_mode_request if state.game_mode_request >= 0 else 10
				values.append_array([state.old_y, state.target_y, requested_lives, state.death_count, state.death_equate, state.world_position.y, requested_game_mode])
				for i: int in values.size():
					assert_eq(values[i], expected[i + 3].to_int(), "Collision scenario %d tick %d %s field %d" % [scenario, tick, phase, i])
				row += 1
			if run.snapshot().completed:
				var finished: Array[int] = _fields(run.snapshot())
				var after := TickCommand.new()
				after.tick_index = tick + 1
				assert_string_contains(run.step(after).error, "completed")
				assert_eq(_fields(run.snapshot()), finished)
				row += (89 - tick) * 3
				break

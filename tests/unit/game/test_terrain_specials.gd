extends GutTest
## Exact raw source callback families; phase coupling has its own integrated corpus.

func _level() -> LevelDefinition:
	var level := LevelDefinition.new()
	level.spawn_cell = Vector2i(1, 1)
	level.grid = GridDefinition.new()
	level.grid.base = Vector2i(-512, -512)
	level.grid.dimensions = Vector2i(4, 4)
	for index: int in range(16):
		var stack := GridStackDefinition.new()
		stack.first_square_index = index
		stack.square_count = 1
		level.grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		var x: int = -512 + (index % 4) * 256
		@warning_ignore("integer_division")
		var z: int = -512 + (index / 4) * 256
		square.flags = 3
		square.vertices = [Vector3i(x, 0, z + 256), Vector3i(x + 256, 0, z + 256), Vector3i(x, 0, z), Vector3i(x + 256, 0, z)]
		level.grid.squares.append(square)
	return level

func _height(square: GridSquareDefinition, heights: PackedInt32Array) -> void:
	for index: int in range(4):
		square.vertices[index].y = heights[index]

func _empty(level: LevelDefinition, index: int) -> void:
	level.grid.stacks[index].square_count = 0
	level.grid.squares.remove_at(index)
	for after: int in range(index + 1, 16):
		level.grid.stacks[after].first_square_index -= 1

func _facts(state: RunSnapshot) -> PackedInt64Array:
	var facts: PackedInt64Array = PackedInt64Array([state.position_16.x, state.position_16.y, state.position_16.z, state.velocity_16.x, state.velocity_16.y, state.velocity_16.z, state.cell.x, state.cell.y, state.remaining_ticks, state.flags, state.mode, state.direction, state.square_index, state.target_16.x >> 16, state.target_16.y >> 16, state.target_16.z >> 16, state.animation_requests, state.sound_requests, state.score_requests])
	for value: int in state.matrix12:
		facts.append(value)
	return facts

func _assert_facts(file: FileAccess, scenario: int, tick: int, state: RunSnapshot) -> void:
	var row: PackedStringArray = file.get_csv_line()
	assert_eq(int(row[0]), scenario)
	assert_eq(int(row[1]), tick)
	var actual: PackedInt64Array = _facts(state)
	for index: int in range(actual.size()):
		assert_eq(actual[index], int(row[index + 2]), "scenario %d tick %d field %d" % [scenario, tick, index])

func test_grid_and_simple_source_callbacks() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_special.csv", FileAccess.READ)
	file.get_csv_line()
	for scenario: int in range(8):
		var level: LevelDefinition = _level()
		level.grid.squares[5].flags = 1025 if scenario >= 4 else 17
		var kind: int = scenario % 4
		if kind == 1:
			_height(level.grid.squares[5], PackedInt32Array([128, 128, -128, -128]))
		if kind == 2:
			level.grid.squares[9].flags = 0
		if kind == 3:
			_height(level.grid.squares[9], PackedInt32Array([-449, -449, -449, -449]))
		var run: TerrainRun = TerrainRun.create(level)
		assert_eq(run.error, "")
		var state: RunSnapshot = run.snapshot()
		state.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -128, 0, -128])
		var events: Array[TickEvent] = []
		run._react(state, level.grid.squares[5].flags, events)
		_assert_facts(file, scenario, -1, state)
		for tick: int in range(15):
			state.old_position_16 = state.position_16
			run._move(state, events)
			assert_eq(run._callback_error, "")
			_assert_facts(file, scenario, tick, state)

func test_bounce_and_cliff_source_callbacks() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_roll.csv", FileAccess.READ)
	file.get_csv_line()
	for scenario: int in range(5):
		var level: LevelDefinition = _level()
		level.grid.squares[5].flags = 33 if scenario == 0 else 2049
		if scenario > 1:
			_height(level.grid.squares[5], PackedInt32Array([128, 128, -128, -128]))
		if scenario == 2:
			_height(level.grid.squares[9], PackedInt32Array([128, 128, 128, 128]))
		if scenario == 3:
			_empty(level, 9)
		if scenario == 4:
			level.grid.squares[9].flags = 1
		var run: TerrainRun = TerrainRun.create(level)
		assert_eq(run.error, "")
		var state: RunSnapshot = run.snapshot()
		state.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -128, 0, -128])
		var events: Array[TickEvent] = []
		run._react(state, level.grid.squares[5].flags, events)
		_assert_facts(file, scenario, -1, state)
		for tick: int in range(24):
			state.old_position_16 = state.position_16
			run._move(state, events)
			assert_eq(run._callback_error, "")
			_assert_facts(file, scenario, tick, state)

func test_freeform_source_callbacks() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_freeform.csv", FileAccess.READ)
	file.get_csv_line()
	for scenario: int in range(5):
		var level: LevelDefinition = _level()
		level.grid.squares[5].flags = 129
		if scenario == 1:
			_height(level.grid.squares[5], PackedInt32Array([128, 128, -128, -128]))
		if scenario == 2:
			level.grid.squares[5].flags = 3
		if scenario == 3:
			_empty(level, 5)
			level.spawn_cell = Vector2i(2, 1)
		if scenario == 4:
			level.grid.squares[5].flags = 4097
		var run: TerrainRun = TerrainRun.create(level)
		assert_eq(run.error, "")
		var state: RunSnapshot = run.snapshot()
		state.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -128, 0, -128])
		if scenario == 3:
			state.position_16 = Vector3i(-128 * 65536, 0, -128 * 65536)
			state.old_position_16 = state.position_16
			state.world_position = Vector3i(-128, 0, -128)
			state.cell = Vector2i(1, 1)
			state.square_index = 5
		state.old_position_16.z -= 8 << 16
		var events: Array[TickEvent] = []
		run._apply_requests(state, TerrainFreeformSlip.setup(state), events)
		state.mode = 262
		_assert_facts(file, scenario, -1, state)
		for tick: int in range(8):
			state.old_position_16 = state.position_16
			run._move(state, events)
			assert_eq(run._callback_error, "")
			_assert_facts(file, scenario, tick, state)

func test_wall_rebound_source_callbacks() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_wall.csv", FileAccess.READ)
	file.get_csv_line()
	for scenario: int in range(5):
		var level: LevelDefinition = _level()
		if scenario == 0:
			level.grid.squares[5].flags |= 16384
		if scenario == 1:
			level.grid.squares[5].flags |= 32768
		if scenario == 2:
			level.grid.squares[1].flags |= 16384
		if scenario == 3:
			level.grid.squares[4].flags |= 32768
		if scenario == 4:
			level.grid.squares[9].flags = 2049
		var run: TerrainRun = TerrainRun.create(level)
		var state: RunSnapshot = run.snapshot()
		var events: Array[TickEvent] = []
		assert_eq(run._jump(state, 0 if scenario == 4 else scenario, events), "")
		_assert_facts(file, scenario, -1, state)
		for tick: int in range(8):
			state.old_position_16 = state.position_16
			run._move(state, events)
			_assert_facts(file, scenario, tick, state)

func test_single_start_source_callbacks() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_startup.csv", FileAccess.READ)
	file.get_csv_line()
	var initial := RunStart.new()
	initial.start_mode = 2
	var run: TerrainRun = TerrainRun.create(_level(), initial)
	var state: RunSnapshot = run.snapshot()
	var events: Array[TickEvent] = []
	_assert_facts(file, 0, -1, state)
	for tick: int in range(80):
		state.old_position_16 = state.position_16
		run._move(state, events)
		_assert_facts(file, 0, tick, state)

func test_modifier_source_expiry() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_modifiers.csv", FileAccess.READ)
	file.get_csv_line()
	for scenario: int in range(4):
		var state := RunSnapshot.new()
		state.powerup_flags = 7
		state.auto_hop_timer = scenario
		state.super_tongue_timer = scenario + 1
		state.quick_jump_timer = scenario + 2
		for tick: int in range(7):
			TerrainModifiers.update(state)
			var row: PackedStringArray = file.get_csv_line()
			var facts: PackedInt64Array = PackedInt64Array([scenario, tick, state.powerup_flags, state.auto_hop_timer, state.super_tongue_timer, state.quick_jump_timer])
			for index: int in range(6):
				assert_eq(facts[index], int(row[index]))

func test_freeform_held_steering_source_control_and_move() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_steering.csv", FileAccess.READ)
	file.get_csv_line()
	for scenario: int in range(4):
		var level: LevelDefinition = _level()
		level.grid.squares[5].flags = 129
		var run: TerrainRun = TerrainRun.create(level)
		var state: RunSnapshot = run.snapshot()
		state.old_position_16.z -= 8 << 16
		var events: Array[TickEvent] = []
		run._react(state, 129, events)
		_assert_facts(file, scenario, -1, state)
		var command := TickCommand.new()
		command.held_mask = 1 << scenario
		for tick: int in range(8):
			assert_eq(run._control(state, command, events), "")
			_assert_facts(file, scenario, tick * 2, state)
			state.old_position_16 = state.position_16
			run._move(state, events)
			_assert_facts(file, scenario, tick * 2 + 1, state)

func test_combined_flag_source_precedence() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_priority.csv", FileAccess.READ)
	file.get_csv_line()
	var authored: Array[int] = [2051, 19, 149, 4105, 25, 1201, 1185, 161, 8195, 0x80043]
	for scenario: int in range(10):
		var level: LevelDefinition = _level()
		level.grid.squares[5].flags = authored[scenario]
		var run: TerrainRun = TerrainRun.create(level)
		var state: RunSnapshot = run.snapshot()
		var events: Array[TickEvent] = []
		run._react(state, authored[scenario], events)
		_assert_facts(file, scenario, -1, state)

func test_outward_bounds_adjustment_safe_source_prefix() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_bounds.csv", FileAccess.READ)
	file.get_csv_line()
	var cells: Array[Vector2i] = [Vector2i(1, 3), Vector2i(3, 1), Vector2i(1, 0), Vector2i(0, 1)]
	for scenario: int in range(4):
		var level: LevelDefinition = _level()
		level.spawn_cell = cells[scenario]
		var run: TerrainRun = TerrainRun.create(level)
		var state: RunSnapshot = run.snapshot()
		var events: Array[TickEvent] = []
		assert_eq(run._jump(state, scenario, events), "")
		_assert_facts(file, scenario, -1, state)
		for tick: int in range(5):
			state.old_position_16 = state.position_16
			run._move(state, events)
			_assert_facts(file, scenario, tick, state)
		run._move(state, events)
		assert_string_contains(run._callback_error, "outside authored storage")

func test_random_diagnostics_copy_and_tick_boundary() -> void:
	var random: SourceRandom = SourceRandom.create(1)
	assert_eq(random.next_value("first"), 16838)
	var candidate: SourceRandom = random.copy()
	assert_eq(candidate.draw_count, 1)
	assert_eq(candidate.consumers, ["first"])
	candidate.begin_tick()
	assert_eq(candidate.consumers.size(), 0)
	assert_eq(candidate.next_value("second"), 5758)
	assert_eq(candidate.draw_count, 2)
	assert_eq(candidate.consumers, ["second"])
	assert_eq(random.draw_count, 1)
	assert_eq(random.consumers, ["first"])

func test_grid_slope_threshold_source_setup() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_slope.csv", FileAccess.READ)
	file.get_csv_line()
	var rise: Array[int] = [16, 17, -16, -17]
	for scenario: int in range(4):
		var level: LevelDefinition = _level()
		level.grid.squares[5].flags = 17
		_height(level.grid.squares[5], PackedInt32Array([rise[scenario], rise[scenario], 0, 0]))
		var run: TerrainRun = TerrainRun.create(level)
		var state: RunSnapshot = run.snapshot()
		state.position_16.y = 0
		state.world_position.y = 0
		state.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -128, 0, -128])
		var events: Array[TickEvent] = []
		run._react(state, 17, events)
		_assert_facts(file, scenario, -1, state)

func test_odd_dimensions_source_hop() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_odd.csv", FileAccess.READ)
	file.get_csv_line()
	var level := LevelDefinition.new()
	level.spawn_cell = Vector2i(1, 1)
	level.grid = GridDefinition.new()
	level.grid.base = Vector2i(-384, -384)
	level.grid.dimensions = Vector2i(3, 3)
	for index: int in range(9):
		var stack := GridStackDefinition.new()
		stack.first_square_index = index
		stack.square_count = 1
		level.grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		var x: int = -384 + (index % 3) * 256
		@warning_ignore("integer_division")
		var z: int = -384 + (index / 3) * 256
		square.flags = 3
		square.vertices = [Vector3i(x, 0, z + 256), Vector3i(x + 256, 0, z + 256), Vector3i(x, 0, z), Vector3i(x + 256, 0, z)]
		level.grid.squares.append(square)
	var run: TerrainRun = TerrainRun.create(level)
	assert_eq(run.error, "")
	var state: RunSnapshot = run.snapshot()
	var events: Array[TickEvent] = []
	assert_eq(run._jump(state, 0, events), "")
	_assert_facts(file, 0, -1, state)
	for tick: int in range(8):
		state.old_position_16 = state.position_16
		run._move(state, events)
		_assert_facts(file, 0, tick, state)

func test_source_map_freefall_dying_and_volcano_death_branches() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_map_branches.csv", FileAccess.READ)
	file.get_csv_line()
	var maps: Array[int] = [41, 42, 47, 48, 0, 2]
	for scenario: int in range(12):
		var level: LevelDefinition = _level()
		level.map_index = maps[scenario] if scenario < 6 else 48
		level.theme = 10 if scenario >= 8 and scenario < 10 else 8
		var run: TerrainRun = TerrainRun.create(level)
		var state: RunSnapshot = run.snapshot()
		var events: Array[TickEvent] = []
		if scenario < 4:
			state.mode = 1
			state.flags |= 128 | 8192
			state.remaining_ticks = 30
		elif scenario < 6:
			state.mode = 2
			state.remaining_ticks = 0
			state.death_count = 50
			state.death_equate = 2
			state.velocity_16 = Vector3i(131073, -65537, 400000001)
		elif scenario < 10:
			run._kill(state, 8 if scenario % 2 == 0 else 12, false, events)
		else:
			state.mode = 3
			run._collision_bounds.position.x = -127
			run._candidate_camera = GameplayCamera.create(GameplayCameraDefinition.new(), state.world_position)
			run._candidate_camera._state.twist_counter = scenario - 10
		for tick: int in range(3):
			if scenario < 6:
				state.old_position_16 = state.position_16
				run._move(state, events)
			if scenario >= 10:
				run._collision(state, events)
			var row: PackedStringArray = file.get_csv_line()
			var actual: PackedInt64Array = PackedInt64Array([scenario, tick, state.position_16.x, state.position_16.y, state.position_16.z, state.velocity_16.x, state.velocity_16.y, state.velocity_16.z, state.remaining_ticks, state.flags, state.mode, state.animation_requests, state.last_animation_request, state.death_equate, state.death_count])
			for index: int in range(actual.size()):
				assert_eq(actual[index], int(row[index]), "map branch %d tick %d field %d" % [scenario, tick, index])
		if scenario >= 8 and scenario < 10:
			assert_true(state.death_fire_requested)
			assert_eq(state.death_scale_colour, Vector3i(24, 0, 0))
		assert_eq(run.snapshot().map_index, level.map_index)

func test_source_hop_signed32_delta_and_forced_search_pointer_prefix() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_narrow.csv", FileAccess.READ)
	file.get_csv_line()
	for scenario: int in range(4):
		var level: LevelDefinition = _level()
		if scenario == 0:
			level.grid = GridDefinition.new()
			level.grid.base = Vector2i(-128, -32640)
			level.grid.dimensions = Vector2i(1, 255)
			level.spawn_cell = Vector2i(0, 254)
			for index: int in range(255):
				var stack := GridStackDefinition.new()
				stack.square_count = 1
				stack.first_square_index = index
				level.grid.stacks.append(stack)
				var square := GridSquareDefinition.new()
				var z: int = -32640 + index * 256
				square.flags = 3
				square.vertices = [Vector3i(-128, 0, z + 256), Vector3i(128, 0, z + 256), Vector3i(-128, 0, z), Vector3i(128, 0, z)]
				level.grid.squares.append(square)
		else:
			_height(level.grid.squares[5], PackedInt32Array([32767, 32767, 32767, 32767]))
		if scenario == 3:
			_height(level.grid.squares[5], PackedInt32Array([32767, -32768, -32768, -32768]))
			level.grid.squares[5].flags = 129
		if scenario == 1:
			_height(level.grid.squares[13], PackedInt32Array([-32768, -32768, -32768, -32768]))
		var run: TerrainRun = TerrainRun.create(level)
		assert_eq(run.error, "")
		var state: RunSnapshot = run.snapshot()
		var events: Array[TickEvent] = []
		if scenario == 3:
			state.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -128, -32768, -128])
			state.position_16.y = -32768 * 65536
			state.world_position.y = -32768
			state.matrix12[10] = -32768
			state.old_y = -32768
			state.target_y = -32768
			state.old_position_16 = state.position_16 - Vector3i(0, 0, 8 * 65536)
			run._apply_requests(state, TerrainFreeformSlip.setup(state), events)
			state.mode = 262
		elif scenario == 2:
			state.position_16.y = -32768 * 65536
			state.world_position.y = -32768
			state.matrix12[10] = -32768
			state.old_y = -32768
			state.target_y = -32768
			state.user_target_cell = Vector2i(1, 2)
			run._apply_requests(state, TerrainWallBounce.setup(state, level.grid), events)
			state.mode = 261
		else:
			assert_eq(run._jump(state, 0, events, false, scenario == 1, 2 if scenario == 1 else 1, 15 if scenario == 1 else 0), "")
		_assert_facts(file, scenario, -1, state)
		for tick: int in range(5):
			state.old_position_16 = state.position_16
			run._move(state, events)
			assert_eq(run._callback_error, "")
			_assert_facts(file, scenario, tick, state)

func test_source_forced_search_outside_global_storage_is_diagnosed() -> void:
	var level: LevelDefinition = _level()
	level.spawn_cell = Vector2i(0, 2)
	_height(level.grid.squares[8], PackedInt32Array([32767, 32767, 32767, 32767]))
	_height(level.grid.squares[0], PackedInt32Array([-32768, -32768, -32768, -32768]))
	var run: TerrainRun = TerrainRun.create(level)
	var state: RunSnapshot = run.snapshot()
	var events: Array[TickEvent] = []
	assert_string_contains(run._jump(state, 2, events, false, true, 2, 15), "outside authored global storage")
	assert_eq(state.position_16, run.snapshot().position_16)
	assert_eq(state.square_index, 8)

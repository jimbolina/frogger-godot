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

func _facts(state: GameplayState) -> PackedInt64Array:
	var facts: PackedInt64Array = PackedInt64Array([state.frog.position_16.x, state.frog.position_16.y, state.frog.position_16.z, state.frog.velocity_16.x, state.frog.velocity_16.y, state.frog.velocity_16.z, state.frog.cell.x, state.frog.cell.y, state.frog.remaining_ticks, state.frog.flags, state.frog.mode, state.frog.direction, state.frog.square_index, state.frog.target_16.x >> 16, state.frog.target_16.y >> 16, state.frog.target_16.z >> 16, state.requests.animation_requests, state.requests.sound_requests, state.requests.score_requests])
	for value: int in state.frog.matrix12:
		facts.append(value)
	return facts

func _assert_facts(file: FileAccess, scenario: int, tick: int, state: GameplayState) -> void:
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
		var run: GameplayRun = GameplayRun.create(level)
		assert_eq(run.error, "")
		var state: GameplayState = run.snapshot()
		state.frog.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -128, 0, -128])
		var events: Array[TickEvent] = []
		run._frog.react(state, level.grid.squares[5].flags, events)
		_assert_facts(file, scenario, -1, state)
		for tick: int in range(15):
			state.frog.old_position_16 = state.frog.position_16
			run._frog.move(state, events)
			assert_eq(run._frog.callback_error, "")
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
		var run: GameplayRun = GameplayRun.create(level)
		assert_eq(run.error, "")
		var state: GameplayState = run.snapshot()
		state.frog.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -128, 0, -128])
		var events: Array[TickEvent] = []
		run._frog.react(state, level.grid.squares[5].flags, events)
		_assert_facts(file, scenario, -1, state)
		for tick: int in range(24):
			state.frog.old_position_16 = state.frog.position_16
			run._frog.move(state, events)
			assert_eq(run._frog.callback_error, "")
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
		var run: GameplayRun = GameplayRun.create(level)
		assert_eq(run.error, "")
		var state: GameplayState = run.snapshot()
		state.frog.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -128, 0, -128])
		if scenario == 3:
			state.frog.position_16 = Vector3i(-128 * 65536, 0, -128 * 65536)
			state.frog.old_position_16 = state.frog.position_16
			state.frog.world_position = Vector3i(-128, 0, -128)
			state.frog.cell = Vector2i(1, 1)
			state.frog.square_index = 5
		state.frog.old_position_16.z -= 8 << 16
		var events: Array[TickEvent] = []
		run._frog.apply_requests(state, TerrainFreeformSlip.setup(state), events)
		state.frog.mode = 262
		_assert_facts(file, scenario, -1, state)
		for tick: int in range(8):
			state.frog.old_position_16 = state.frog.position_16
			run._frog.move(state, events)
			assert_eq(run._frog.callback_error, "")
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
		var run: GameplayRun = GameplayRun.create(level)
		var state: GameplayState = run.snapshot()
		var events: Array[TickEvent] = []
		assert_eq(run._frog.jump(state, 0 if scenario == 4 else scenario, events), "")
		_assert_facts(file, scenario, -1, state)
		for tick: int in range(8):
			state.frog.old_position_16 = state.frog.position_16
			run._frog.move(state, events)
			_assert_facts(file, scenario, tick, state)

func test_single_start_source_callbacks() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_startup.csv", FileAccess.READ)
	file.get_csv_line()
	var initial := RunStart.new()
	initial.start_mode = 2
	var run: GameplayRun = GameplayRun.create(_level(), initial)
	var state: GameplayState = run.snapshot()
	var events: Array[TickEvent] = []
	_assert_facts(file, 0, -1, state)
	for tick: int in range(80):
		state.frog.old_position_16 = state.frog.position_16
		run._frog.move(state, events)
		_assert_facts(file, 0, tick, state)

func test_modifier_source_expiry() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_modifiers.csv", FileAccess.READ)
	file.get_csv_line()
	for scenario: int in range(4):
		var state := GameplayState.new()
		state.frog.powerup_flags = 7
		state.frog.auto_hop_timer = scenario
		state.frog.super_tongue_timer = scenario + 1
		state.frog.quick_jump_timer = scenario + 2
		for tick: int in range(7):
			TerrainModifiers.update(state)
			var row: PackedStringArray = file.get_csv_line()
			var facts: PackedInt64Array = PackedInt64Array([scenario, tick, state.frog.powerup_flags, state.frog.auto_hop_timer, state.frog.super_tongue_timer, state.frog.quick_jump_timer])
			for index: int in range(6):
				assert_eq(facts[index], int(row[index]))

func test_freeform_held_steering_source_control_and_move() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_steering.csv", FileAccess.READ)
	file.get_csv_line()
	for scenario: int in range(4):
		var level: LevelDefinition = _level()
		level.grid.squares[5].flags = 129
		var run: GameplayRun = GameplayRun.create(level)
		var state: GameplayState = run.snapshot()
		state.frog.old_position_16.z -= 8 << 16
		var events: Array[TickEvent] = []
		run._frog.react(state, 129, events)
		_assert_facts(file, scenario, -1, state)
		var command := TickCommand.new()
		command.held_mask = 1 << scenario
		for tick: int in range(8):
			assert_eq(run._frog.control(state, command, events), "")
			_assert_facts(file, scenario, tick * 2, state)
			state.frog.old_position_16 = state.frog.position_16
			run._frog.move(state, events)
			_assert_facts(file, scenario, tick * 2 + 1, state)

func _freeform_run() -> GameplayRun:
	var level: LevelDefinition = _level()
	level.grid.squares[5].flags = 129
	var run: GameplayRun = GameplayRun.create(level)
	return run

func _freeform_state(run: GameplayRun) -> GameplayState:
	var state: GameplayState = run.snapshot()
	state.frog.old_position_16.z -= 8 << 16
	var events: Array[TickEvent] = []
	run._frog.react(state, 129, events)
	state.frog.no_input_timer = 9
	return state

func _slurps(events: Array[TickEvent]) -> int:
	var count: int = 0
	for event: TickEvent in events:
		if event.kind == TickEvent.Kind.SOUND and event.sound_id == 20:
			count += 1
	return count

func test_freeform_tongue_starts_silently_without_held_direction() -> void:
	var run: GameplayRun = _freeform_run()
	var state: GameplayState = _freeform_state(run)
	assert_eq(state.frog.mode, FrogMode.SLIPPING_LAND_NONGRID)
	var still: GameplayState = state.copy()
	var events: Array[TickEvent] = []
	var command := TickCommand.new()
	command.pressed_mask = TickCommand.TONGUE
	assert_eq(run._frog.control(state, command, events), "")
	assert_eq(run._frog.control(still, TickCommand.new(), events), "")
	assert_eq(state.tongue.mode, TongueState.Mode.OUT)
	assert_eq(state.tongue.target_index, -1)
	assert_eq(state.frog.no_input_timer, 0)
	assert_eq(_slurps(events), 0, "froguser.C freeform control plays no slurp")
	assert_eq(state.requests.sound_requests, still.requests.sound_requests)
	assert_eq(_facts(state), _facts(still), "The tongue does not change slip motion")

func test_freeform_held_direction_steers_and_suppresses_tongue() -> void:
	for direction: int in 4:
		var run: GameplayRun = _freeform_run()
		var state: GameplayState = _freeform_state(run)
		var steered: GameplayState = state.copy()
		var events: Array[TickEvent] = []
		var command := TickCommand.new()
		command.held_mask = 1 << direction
		command.pressed_mask = TickCommand.TONGUE
		var steering := TickCommand.new()
		steering.held_mask = 1 << direction
		assert_eq(run._frog.control(state, command, events), "")
		assert_eq(run._frog.control(steered, steering, events), "")
		assert_eq(state.tongue.mode, TongueState.Mode.IDLE)
		assert_eq(state.frog.no_input_timer, 9)
		assert_eq(_facts(state), _facts(steered), "direction %d" % direction)

func test_freeform_active_tongue_is_not_restarted() -> void:
	var run: GameplayRun = _freeform_run()
	var state: GameplayState = _freeform_state(run)
	state.tongue.start(-1)
	for unused: int in 3:
		state.tongue.advance()
	var events: Array[TickEvent] = []
	var command := TickCommand.new()
	command.pressed_mask = TickCommand.TONGUE
	assert_eq(run._frog.control(state, command, events), "")
	assert_eq(state.tongue.mode, TongueState.Mode.OUT)
	assert_eq(state.tongue.section, 3)
	assert_eq(state.frog.no_input_timer, 9, "An active effect skips the source timer reset")

func test_freeform_ignores_super_hop_and_pressed_directions() -> void:
	for pressed: int in [TickCommand.SUPER_HOP, TickCommand.NORTH, TickCommand.EAST, TickCommand.SOUTH, TickCommand.WEST]:
		var run: GameplayRun = _freeform_run()
		var state: GameplayState = _freeform_state(run)
		var still: GameplayState = state.copy()
		var events: Array[TickEvent] = []
		var command := TickCommand.new()
		command.pressed_mask = pressed
		assert_eq(run._frog.control(state, command, events), "")
		assert_eq(run._frog.control(still, TickCommand.new(), events), "")
		assert_eq(state.frog.mode, FrogMode.SLIPPING_LAND_NONGRID)
		assert_eq(state.frog.buffered_keys, 0)
		assert_eq(state.tongue.mode, TongueState.Mode.IDLE)
		assert_true(events.is_empty())
		assert_eq(_facts(state), _facts(still), "pressed %d" % pressed)

func test_combined_flag_source_precedence() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_priority.csv", FileAccess.READ)
	file.get_csv_line()
	var authored: Array[int] = [2051, 19, 149, 4105, 25, 1201, 1185, 161, 8195, 0x80043]
	for scenario: int in range(10):
		var level: LevelDefinition = _level()
		level.grid.squares[5].flags = authored[scenario]
		var run: GameplayRun = GameplayRun.create(level)
		var state: GameplayState = run.snapshot()
		var events: Array[TickEvent] = []
		run._frog.react(state, authored[scenario], events)
		_assert_facts(file, scenario, -1, state)

func test_outward_bounds_adjustment_safe_source_prefix() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_bounds.csv", FileAccess.READ)
	file.get_csv_line()
	var cells: Array[Vector2i] = [Vector2i(1, 3), Vector2i(3, 1), Vector2i(1, 0), Vector2i(0, 1)]
	for scenario: int in range(4):
		var level: LevelDefinition = _level()
		level.spawn_cell = cells[scenario]
		var run: GameplayRun = GameplayRun.create(level)
		var state: GameplayState = run.snapshot()
		var events: Array[TickEvent] = []
		assert_eq(run._frog.jump(state, scenario, events), "")
		_assert_facts(file, scenario, -1, state)
		for tick: int in range(5):
			state.frog.old_position_16 = state.frog.position_16
			run._frog.move(state, events)
			_assert_facts(file, scenario, tick, state)
		run._frog.move(state, events)
		assert_string_contains(run._frog.callback_error, "outside authored storage")

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
		var run: GameplayRun = GameplayRun.create(level)
		var state: GameplayState = run.snapshot()
		state.frog.position_16.y = 0
		state.frog.world_position.y = 0
		state.frog.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -128, 0, -128])
		var events: Array[TickEvent] = []
		run._frog.react(state, 17, events)
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
	var run: GameplayRun = GameplayRun.create(level)
	assert_eq(run.error, "")
	var state: GameplayState = run.snapshot()
	var events: Array[TickEvent] = []
	assert_eq(run._frog.jump(state, 0, events), "")
	_assert_facts(file, 0, -1, state)
	for tick: int in range(8):
		state.frog.old_position_16 = state.frog.position_16
		run._frog.move(state, events)
		_assert_facts(file, 0, tick, state)

func test_source_map_freefall_dying_and_volcano_death_branches() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_map_branches.csv", FileAccess.READ)
	file.get_csv_line()
	var maps: Array[int] = [41, 42, 47, 48, 0, 2]
	for scenario: int in range(12):
		var level: LevelDefinition = _level()
		level.map_index = maps[scenario] if scenario < 6 else 48
		level.theme = 10 if scenario >= 8 and scenario < 10 else 8
		var run: GameplayRun = GameplayRun.create(level)
		var state: GameplayState = run.snapshot()
		var events: Array[TickEvent] = []
		if scenario < 4:
			state.frog.mode = 1
			state.frog.flags |= 128 | 8192
			state.frog.remaining_ticks = 30
		elif scenario < 6:
			state.frog.mode = 2
			state.frog.remaining_ticks = 0
			state.frog.death_count = 50
			state.frog.death_equate = 2
			state.frog.velocity_16 = Vector3i(131073, -65537, 400000001)
		elif scenario < 10:
			run._frog.kill(state, 8 if scenario % 2 == 0 else 12, false, events)
		else:
			state.frog.mode = 3
			run._frog.collision_bounds.position.x = -127
			run._frog.camera = GameplayCamera.create(GameplayCameraDefinition.new(), state.frog.world_position)
			run._frog.camera._state.twist_counter = scenario - 10
		for tick: int in range(3):
			if scenario < 6:
				state.frog.old_position_16 = state.frog.position_16
				run._frog.move(state, events)
			if scenario >= 10:
				run._frog.collide(state, events)
			var row: PackedStringArray = file.get_csv_line()
			var actual: PackedInt64Array = PackedInt64Array([scenario, tick, state.frog.position_16.x, state.frog.position_16.y, state.frog.position_16.z, state.frog.velocity_16.x, state.frog.velocity_16.y, state.frog.velocity_16.z, state.frog.remaining_ticks, state.frog.flags, state.frog.mode, state.requests.animation_requests, state.requests.last_animation_request, state.frog.death_equate, state.frog.death_count])
			for index: int in range(actual.size()):
				assert_eq(actual[index], int(row[index]), "map branch %d tick %d field %d" % [scenario, tick, index])
		if scenario >= 8 and scenario < 10:
			assert_true(state.requests.death_fire_requested)
			assert_eq(state.requests.death_scale_colour, Vector3i(24, 0, 0))
		assert_eq(run.snapshot().diagnostics.map_index, level.map_index)

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
		var run: GameplayRun = GameplayRun.create(level)
		assert_eq(run.error, "")
		var state: GameplayState = run.snapshot()
		var events: Array[TickEvent] = []
		if scenario == 3:
			state.frog.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -128, -32768, -128])
			state.frog.position_16.y = -32768 * 65536
			state.frog.world_position.y = -32768
			state.frog.matrix12[10] = -32768
			state.frog.old_y = -32768
			state.frog.target_y = -32768
			state.frog.old_position_16 = state.frog.position_16 - Vector3i(0, 0, 8 * 65536)
			run._frog.apply_requests(state, TerrainFreeformSlip.setup(state), events)
			state.frog.mode = 262
		elif scenario == 2:
			state.frog.position_16.y = -32768 * 65536
			state.frog.world_position.y = -32768
			state.frog.matrix12[10] = -32768
			state.frog.old_y = -32768
			state.frog.target_y = -32768
			state.frog.user_target_cell = Vector2i(1, 2)
			run._frog.apply_requests(state, TerrainWallBounce.setup(state, level.grid), events)
			state.frog.mode = 261
		else:
			assert_eq(run._frog.jump(state, 0, events, false, scenario == 1, 2 if scenario == 1 else 1, 15 if scenario == 1 else 0), "")
		_assert_facts(file, scenario, -1, state)
		for tick: int in range(5):
			state.frog.old_position_16 = state.frog.position_16
			run._frog.move(state, events)
			assert_eq(run._frog.callback_error, "")
			_assert_facts(file, scenario, tick, state)

func test_source_forced_search_outside_global_storage_is_diagnosed() -> void:
	var level: LevelDefinition = _level()
	level.spawn_cell = Vector2i(0, 2)
	_height(level.grid.squares[8], PackedInt32Array([32767, 32767, 32767, 32767]))
	_height(level.grid.squares[0], PackedInt32Array([-32768, -32768, -32768, -32768]))
	var run: GameplayRun = GameplayRun.create(level)
	var state: GameplayState = run.snapshot()
	var events: Array[TickEvent] = []
	assert_string_contains(run._frog.jump(state, 2, events, false, true, 2, 15), "outside authored global storage")
	assert_eq(state.frog.position_16, run.snapshot().frog.position_16)
	assert_eq(state.frog.square_index, 8)

func test_landing_keeps_grid_slip_destination_cell_for_next_hop() -> void:
	var level: LevelDefinition = _level()
	level.grid.squares[6].flags = 17
	var run: GameplayRun = GameplayRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var landed: GameplayState = null
	for tick: int in 7:
		var command := TickCommand.new()
		command.tick_index = tick
		command.pressed_mask = TickCommand.EAST if tick == 0 else 0
		var result: TickResult = run.step(command)
		assert_eq(result.error, "")
		if not result.error.is_empty():
			return
		if result.final_snapshot.frog.mode == FrogMode.SLIPPING_LAND_GRID:
			landed = result.final_snapshot
			break
	assert_not_null(landed, "The hop lands on the slippy square")
	if landed == null:
		return
	assert_eq(landed.frog.world_position.x, 128, "The landing tick has not slid yet")
	assert_eq(landed.frog.cell, Vector2i(3, 1), "C stores the slide destination, not the landing cell")
	assert_eq(landed.frog.square_index, 7)
	var hop := TickCommand.new()
	hop.tick_index = landed.tick_index
	hop.pressed_mask = TickCommand.NORTH
	var next: TickResult = run.step(hop)
	assert_eq(next.error, "")
	assert_eq(next.final_snapshot.frog.mode, FrogMode.JUMPING)
	assert_eq(Vector2i(next.final_snapshot.frog.target_16.x >> 16, next.final_snapshot.frog.target_16.z >> 16), Vector2i(384, 128), "The next hop starts from the stored cell")

func test_terrain_freefall_entry_copies_jump_height_into_old_y() -> void:
	var level: LevelDefinition = _level()
	_empty(level, 9)
	var run: GameplayRun = GameplayRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var state: GameplayState = run.snapshot()
	state.frog.mode = FrogMode.JUMPING
	state.frog.flags &= ~FrogFlags.JUMP_TO_LAND
	state.frog.remaining_ticks = 1
	state.frog.square_index = -1
	state.frog.cell = Vector2i(1, 2)
	state.frog.target_y = -40
	state.frog.old_y = 77
	var events: Array[TickEvent] = []
	run._frog.move_jumping(state, events)
	assert_eq(run._frog.callback_error, "")
	assert_true(state.frog.flags & FrogFlags.FREEFALL != 0)
	assert_eq(state.frog.old_y, -40)

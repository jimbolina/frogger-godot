extends GutTest
## Discrete CAMERA.C contracts; independent C traces supplement these examples.

func _camera(world: Vector3i = Vector3i.ZERO, startup: bool = false) -> GameplayCamera:
	return GameplayCamera.create(GameplayCameraDefinition.new(), world, startup)

func _camera_tick(world: Vector3i = Vector3i.ZERO) -> GameplayCameraTick:
	var input := GameplayCameraTick.new()
	input.frog_world = world
	return input

func test_follow_uses_half_distance_and_twenty_four_unit_y_step() -> void:
	var camera: GameplayCamera = _camera()
	assert_eq(camera.step(_camera_tick(Vector3i(11, -100, -11))), "")
	var state: GameplayCameraSnapshot = camera.snapshot()
	assert_eq(state.tracked_world, Vector3i(5, -24, -5))
	assert_eq(state.source_world, Vector3i(5, -524, -505))
	assert_eq(state.controller_directions, PackedInt32Array([0, 1, 2, 3]))
	assert_eq(camera.step(_camera_tick(Vector3i(9, 20, -9))), "")
	assert_eq(camera.snapshot().tracked_world, Vector3i(9, 0, -9))

func test_hop_y_uses_landing_height_blend_not_ballistic_frog_y() -> void:
	var camera: GameplayCamera = _camera()
	var input: GameplayCameraTick = _camera_tick(Vector3i(0, -500, 0))
	input.frog_mode = 1
	input.remaining_ticks = 3
	input.old_y = 0
	input.target_y = -120
	assert_eq(camera.step(input), "")
	assert_eq(camera.snapshot().tracked_world.y, -24)
	input.ignore_frog_y = true
	assert_eq(camera.step(input), "")
	assert_eq(camera.snapshot().tracked_world.y, -24)

func test_start_holds_then_decrements_before_sweep_division() -> void:
	var camera: GameplayCamera = _camera(Vector3i(20, -40, 30), true)
	var input: GameplayCameraTick = _camera_tick(Vector3i(20, -40, 30))
	input.start_timer = 31
	assert_eq(camera.step(input), "")
	assert_eq(camera.snapshot().mode, GameplayCamera.START)
	assert_eq(camera.snapshot().move_timer, 30)
	input.start_timer = 30
	assert_eq(camera.step(input), "")
	assert_eq(camera.snapshot().mode, GameplayCamera.FIXED_SWEEP)
	assert_eq(camera.snapshot().source_offset, Vector3i(200, -400, 400))
	assert_eq(camera.step(input), "")
	assert_eq(camera.snapshot().move_timer, 29)
	assert_eq(camera.snapshot().source_offset, Vector3i(194, -403, 369))
	for index: int in range(29):
		assert_eq(camera.step(input), "", str(index))
	assert_eq(camera.snapshot().mode, GameplayCamera.FOLLOW)
	assert_eq(camera.snapshot().source_offset, Vector3i(0, -500, -500))
	assert_eq(camera.snapshot().tracked_world, input.frog_world)

func test_eight_tick_turn_changes_controller_quadrant_and_wait() -> void:
	var camera: GameplayCamera = _camera()
	assert_eq(camera.request_turn(1), "")
	assert_false(camera.snapshot().turn_wait_complete())
	for index: int in range(8):
		assert_eq(camera.step(_camera_tick()), "", str(index))
	assert_eq(camera.snapshot().twist_counter, 0)
	assert_eq(camera.snapshot().move_timer, 0)
	assert_true(camera.snapshot().turn_wait_complete())
	assert_eq(camera.snapshot().source_world, Vector3i(-500, -500, 0))
	assert_eq(camera.snapshot().controller_directions, PackedInt32Array([1, 2, 3, 0]))
	assert_eq(camera.request_turn(-1), "")
	for index: int in range(8):
		assert_eq(camera.step(_camera_tick()), "", str(index))
	assert_eq(camera.snapshot().source_world, Vector3i(0, -500, -500))
	assert_eq(camera.snapshot().controller_directions, PackedInt32Array([0, 1, 2, 3]))

func test_death_blends_with_c_truncation_and_completes_in_forty_five_ticks() -> void:
	var camera: GameplayCamera = _camera()
	camera.request_death()
	assert_eq(camera.step(_camera_tick()), "")
	assert_eq(camera.snapshot().source_offset, Vector3i(0, -511, -492))
	assert_eq(camera.snapshot().move_timer, 44)
	for index: int in range(44):
		assert_eq(camera.step(_camera_tick()), "", str(index))
	assert_eq(camera.snapshot().source_offset, Vector3i(0, -1000, -100))
	assert_eq(camera.snapshot().move_timer, 0)

func test_snapshot_is_detached_and_unsupported_input_preserves_camera() -> void:
	var definition := GameplayCameraDefinition.new()
	var camera: GameplayCamera = GameplayCamera.create(definition, Vector3i.ZERO)
	definition.source_offset = Vector3i.ONE
	var snapshot: GameplayCameraSnapshot = camera.snapshot()
	snapshot.source_offset = Vector3i.ONE
	snapshot.controller_directions[0] = 3
	var input: GameplayCameraTick = _camera_tick(Vector3i(100, -100, 100))
	input.has_camera_zone = true
	assert_false(camera.step(input).is_empty())
	assert_eq(camera.snapshot().source_offset, Vector3i(0, -500, -500))
	assert_eq(camera.snapshot().tracked_world, Vector3i.ZERO)
	assert_eq(camera.snapshot().controller_directions[0], 0)

func test_actual_c_camera_component_corpus() -> void:
	var lines: PackedStringArray = FileAccess.get_file_as_string("res://tests/golden/synthetic/camera_components.csv").strip_edges().split("\n")
	var camera: GameplayCamera = null
	var previous_scenario: int = -1
	var rows: int = 0
	for line: String in lines:
		if line.begins_with("scenario,"):
			continue
		var values: PackedStringArray = line.strip_edges().split(",")
		assert_eq(values.size(), 33)
		var scenario: int = int(values[0])
		var tick: int = int(values[1])
		if scenario != previous_scenario:
			camera = _camera(Vector3i.ZERO, scenario == 0)
			previous_scenario = scenario
			if scenario == 2 or scenario == 3:
				assert_eq(camera.request_turn(1 if scenario == 2 else -1), "")
			elif scenario == 4:
				camera.request_death()
			elif scenario == 5:
				assert_eq(camera.step(_camera_tick(Vector3i(10, -20, 30))), "")
				camera.request_fixed()
			elif scenario == 6 or scenario == 7:
				if scenario == 7:
					assert_eq(camera.step(_camera_tick()), "")
					camera.request_fixed()
				assert_eq(camera.request_shake(128, 45, 20480, 16838, 5758), "")
		var input: GameplayCameraTick = _camera_tick()
		input.start_timer = maxi(90 - tick, 0) if scenario == 0 else 0
		if scenario == 1:
			input.frog_world = Vector3i(100, -200, 60) if tick == 0 else Vector3i(200, -260, 100)
		assert_eq(camera.step(input), "", line)
		var state: GameplayCameraSnapshot = camera.snapshot()
		var actual: Array[int] = [scenario, tick, state.mode, state.move_timer, state.twist_counter,
			state.tracked_world.x, state.tracked_world.y, state.tracked_world.z,
			state.source_offset.x, state.source_offset.y, state.source_offset.z,
			state.target_offset.x, state.target_offset.y, state.target_offset.z,
			state.source_world.x, state.source_world.y, state.source_world.z,
			state.target_world.x, state.target_world.y, state.target_world.z,
			state.controller_directions[0]]
		for column: int in range(actual.size()):
			assert_eq(actual[column], int(values[column]), "row %d column %d" % [rows, column])
		assert_eq(state.shake_timer, int(values[25]), "shake timer row %d" % rows)
		assert_eq(state.shake_amplitude_x, int(values[26]))
		assert_eq(state.shake_amplitude_y, int(values[27]))
		assert_eq(state.shake_frequency_x, int(values[28]))
		assert_eq(state.shake_frequency_y, int(values[29]))
		rows += 1
	assert_eq(rows, 327)

func test_source_random_matches_actual_c_shake_draws_and_detaches() -> void:
	var stream: SourceRandom = SourceRandom.create(1)
	assert_eq(stream.next_value(), 16838)
	var copied: SourceRandom = stream.copy()
	assert_eq(stream.next_value(), 5758)
	assert_eq(stream.state, 2524885223)
	assert_eq(copied.state, 1103527590)
	assert_eq(copied.next_value(), 5758)

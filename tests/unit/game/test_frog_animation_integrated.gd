extends GutTest
## Actual frozen C and independent Python constrain the represented integration fields.

func _level(scenario: int) -> LevelDefinition:
	var level := LevelDefinition.new()
	level.grid = GridDefinition.new()
	level.grid.dimensions = Vector2i(4, 4)
	level.grid.base = Vector2i(-512, -512)
	level.spawn_cell = Vector2i(1, 1)
	level.collision_enabled = true
	level.camera = GameplayCameraDefinition.new()
	level.theme_name = &"JUN" if scenario == 2 else &"SUB"
	level.theme = 4 if scenario == 2 else 9
	for action: int in 34:
		level.frog_action_lengths.append(3 + action % 3)
	for index: int in 16:
		var stack := GridStackDefinition.new()
		stack.first_square_index = index
		stack.square_count = 1
		level.grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		square.flags = 9 if scenario == 3 and index == 9 else 3
		var x: int = -512 + (index % 4) * 256
		@warning_ignore("integer_division")
		var z: int = -512 + (index / 4) * 256
		var y: int = 513 if scenario == 2 and index == 9 else 0
		square.vertices.assign([Vector3i(x, y, z + 256), Vector3i(x + 256, y, z + 256), Vector3i(x, y, z), Vector3i(x + 256, y, z)])
		level.grid.squares.append(square)
	return level

func _command(scenario: int, tick: int) -> TickCommand:
	var command := TickCommand.new()
	command.tick_index = tick
	command.pressed_mask = TickCommand.NORTH if tick == 0 else 0
	command.held_mask = command.pressed_mask
	if scenario == 0 and tick == 0:
		command.pressed_mask |= TickCommand.EAST
	if scenario == 1:
		command.pressed_mask = TickCommand.CAMERA_CLOCKWISE if tick == 0 else 0
		command.held_mask = TickCommand.NORTH if tick >= 1 and tick <= 12 else command.pressed_mask
	return command

func _fields(state: GameplayState) -> Array[int]:
	var camera: GameplayCameraSnapshot = state.camera
	var animation: FrogAnimationState = state.animation
	return [state.frog.position_16.x, state.frog.position_16.y, state.frog.position_16.z, state.frog.velocity_16.x, state.frog.velocity_16.y, state.frog.velocity_16.z,
		state.frog.cell.x, state.frog.cell.y, state.frog.remaining_ticks, state.frog.flags, state.frog.mode, state.frog.current_input, state.frog.direction,
		state.frog.no_input_timer, state.frog.death_count, camera.mode, camera.move_timer, camera.twist_counter,
		camera.tracked_world.x, camera.tracked_world.y, camera.tracked_world.z, camera.source_world.x, camera.source_world.y, camera.source_world.z,
		camera.controller_directions[0], camera.shake_timer, animation.script_type, animation.script_timer, animation.flags,
		animation.environment_flags, state.rng_state, state.frog.animation_condition_counter, animation.program_id, animation.word_offset,
		animation.action, animation.cel, animation.total_cels, animation.update_count, 10 if state.requests.game_mode_request == -1 else state.requests.game_mode_request]

func test_all_represented_integration_fields_match_frozen_c() -> void:
	var lines: PackedStringArray = FileAccess.get_file_as_string("res://tests/golden/synthetic/integrated_terrain.csv").strip_edges().split("\n")
	assert_eq(lines.size(), 1465)
	var row_index: int = 1
	for scenario: int in 4:
		var run: GameplayRun = GameplayRun.create(_level(scenario))
		assert_eq(run.error, "")
		var ticks: int = 24 if scenario < 2 else 120 if scenario == 2 else 76
		for tick: int in ticks:
			var result: TickResult = run.step(_command(scenario, tick))
			assert_eq(result.error, "", "scenario %d tick %d" % [scenario, tick])
			if not result.error.is_empty():
				return
			var expected_consumers: Array[String] = []
			if scenario == 2 and tick == 12:
				expected_consumers.assign(["camera_stun_shake_x", "camera_stun_shake_y"])
			elif scenario == 2 and (tick == 87 or tick == 117):
				expected_consumers.append("animation_idle")
			assert_eq(result.rng_consumers, expected_consumers, "source consumer order scenario %d tick %d" % [scenario, tick])
			var snapshots: Array[GameplayState] = [result.control_snapshot, result.move_snapshot, result.collision_snapshot, result.camera_snapshot, null, result.final_snapshot]
			for phase: int in 6:
				var expected: PackedStringArray = lines[row_index].strip_edges().split(",")
				assert_eq(expected[0].to_int(), scenario)
				assert_eq(expected[1].to_int(), tick)
				if phase != 4:
					var values: Array[int] = _fields(snapshots[phase])
					for field: int in values.size():
						assert_eq(values[field], expected[field + 3].to_int(), "scenario %d tick %d %s field %d" % [scenario, tick, expected[2], field])
					var draws: int = 0
					if scenario == 2:
						if tick > 12 or (tick == 12 and phase >= 2):
							draws = 2
						if tick > 87 or (tick == 87 and phase == 5):
							draws = 3
						if tick > 117 or (tick == 117 and phase == 5):
							draws = 4
					assert_eq(snapshots[phase].diagnostics.rng_draw_count, draws, "source draw count scenario %d tick %d phase %d" % [scenario, tick, phase])
				row_index += 1
	assert_eq(row_index, lines.size())

func test_reset_replays_shared_rng_and_detaches_animation_camera() -> void:
	var run: GameplayRun = GameplayRun.create(_level(2))
	var expected: Array[Array] = []
	for tick: int in 120:
		var result: TickResult = run.step(_command(2, tick))
		assert_eq(result.error, "")
		expected.append(_fields(result.final_snapshot))
	var borrowed: GameplayState = run.snapshot()
	borrowed.animation.action = -1
	borrowed.camera.controller_directions[0] = 3
	borrowed.rng_state = 0
	var last_expected: Array = expected[expected.size() - 1]
	assert_eq(_fields(run.snapshot()), last_expected)
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().diagnostics.rng_draw_count, 0)
	for tick: int in 120:
		assert_eq(_fields(run.step(_command(2, tick)).final_snapshot), expected[tick], "reset tick %d" % tick)

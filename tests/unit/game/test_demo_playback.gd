extends GutTest
## Recorded controls and playback counters obey the committed control boundary.

func _level() -> LevelDefinition:
	var level := LevelDefinition.new()
	level.grid = GridDefinition.new()
	level.grid.dimensions = Vector2i(5, 5)
	level.spawn_cell = Vector2i(2, 2)
	for index: int in 25:
		var stack := GridStackDefinition.new()
		stack.first_square_index = index
		stack.square_count = 1
		level.grid.stacks.append(stack)
		var square := GridSquareDefinition.new()
		square.flags = 3
		var x: int = index % 5 * 256
		@warning_ignore("integer_division")
		var z: int = index / 5 * 256
		square.vertices.assign([Vector3i(x, 0, z + 256), Vector3i(x + 256, 0, z + 256), Vector3i(x, 0, z), Vector3i(x + 256, 0, z)])
		level.grid.squares.append(square)
	return level

func test_raw_direction_consumes_once_and_does_not_buffer_live_input_in_flight() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	var session := DemoPlaybackSession.new()
	assert_eq(session.configure(7, PackedByteArray([0, 1])), "")
	var first: TickResult = run.step(session.command(0))
	assert_eq(first.error, "")
	assert_eq(first.consumed_demo_byte, 0)
	assert_eq(session.accept(first), "")
	assert_eq(session.input_cursor, 1)
	for tick: int in range(1, 6):
		var result: TickResult = run.step(session.command(tick))
		assert_eq(result.error, "")
		assert_eq(result.consumed_demo_byte, -1)
		assert_eq(result.final_snapshot.frog.buffered_keys, 0)
		assert_eq(session.accept(result), "")
	assert_eq(session.input_cursor, 1)
	var next: TickResult = run.step(session.command(6))
	assert_eq(next.consumed_demo_byte, 1)
	assert_eq(session.accept(next), "")
	assert_eq(session.status, "complete")
	assert_eq(session.elapsed_ticks, 7)
	assert_eq(session.input_cursor, 2)

func test_exhaustion_waits_for_consuming_control_and_failure_is_atomic() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	var session := DemoPlaybackSession.new()
	session.configure(20, PackedByteArray([0]))
	for tick: int in 6:
		var result: TickResult = run.step(session.command(tick))
		assert_eq(result.error, "")
		assert_eq(session.accept(result), "")
	var failed: TickResult = run.step(session.command(6))
	assert_string_contains(failed.error, "exhausted")
	assert_eq(failed.consumed_demo_byte, -1)
	assert_null(failed.final_snapshot)
	assert_eq(run.snapshot().tick_index, 6)
	assert_ne(session.accept(failed), "")
	assert_eq(session.elapsed_ticks, 6)
	assert_eq(session.input_cursor, 1)
	assert_eq(session.status, "incomplete")
	session.reset()
	assert_eq(session.elapsed_ticks, 0)
	assert_eq(session.input_cursor, 0)

func test_camera_and_reserved_input_fail_without_consuming_or_advancing() -> void:
	for byte: int in [0xc0, 0xa0, 4]:
		var run: GameplayRun = GameplayRun.create(_level())
		var command := TickCommand.new()
		command.recorded_input_byte = byte
		var result: TickResult = run.step(command)
		assert_ne(result.error, "", str(byte))
		assert_eq(result.consumed_demo_byte, -1)
		assert_eq(run.snapshot().tick_index, 0)

func test_no_input_superhop_and_command_copy_preserve_raw_bytes() -> void:
	for byte: int in [0x80, 0x88, 0, 1, 2, 3]:
		var run: GameplayRun = GameplayRun.create(_level())
		var command := TickCommand.new()
		command.recorded_input_byte = byte
		var detached: TickCommand = command.copy()
		command.recorded_input_byte = 255
		assert_eq(detached.recorded_input_byte, byte)
		var result: TickResult = run.step(detached)
		assert_eq(result.error, "")
		assert_eq(result.consumed_demo_byte, byte)
	var exhausted := TickCommand.new()
	exhausted.recorded_input_exhausted = true
	assert_true(exhausted.copy().recorded_input_exhausted)

func test_recorded_and_live_inputs_cannot_mix() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	var command := TickCommand.new()
	command.recorded_input_byte = 0x80
	command.pressed_mask = TickCommand.NORTH
	assert_string_contains(run.step(command).error, "mixed")
	assert_eq(run.snapshot().tick_index, 0)
	command.pressed_mask = 0
	command.recorded_input_exhausted = true
	assert_string_contains(run.step(command).error, "exhaustion")

func test_session_rejects_mismatched_results_without_committing() -> void:
	var session := DemoPlaybackSession.new()
	session.configure(2, PackedByteArray([128]))
	var command: TickCommand = session.command(0)
	assert_not_null(command)
	assert_null(session.command(0))
	var result := TickResult.new()
	result.tick_index = 1
	assert_ne(session.accept(result), "")
	assert_eq(session.elapsed_ticks, 0)
	assert_eq(session.input_cursor, 0)

func test_raw_camera_precedence_and_wait_do_not_consume_next_byte() -> void:
	for byte: int in [0xc0, 0xa0, 0xf8]:
		var level: LevelDefinition = _level()
		level.camera = GameplayCameraDefinition.new()
		var run: GameplayRun = GameplayRun.create(level)
		var session := DemoPlaybackSession.new()
		session.configure(3, PackedByteArray([byte, 0]))
		var result: TickResult = run.step(session.command(0))
		assert_eq(result.error, "")
		assert_eq(result.consumed_demo_byte, byte)
		var clockwise: bool = bool(byte & 64)
		assert_eq(result.events[0].kind, TickEvent.Kind.CAMERA_CLOCKWISE if clockwise else TickEvent.Kind.CAMERA_ANTICLOCKWISE)
		assert_eq(session.accept(result), "")
		result = run.step(session.command(1))
		assert_eq(result.error, "")
		assert_eq(result.consumed_demo_byte, -1)
		assert_eq(session.accept(result), "")
		assert_eq(session.input_cursor, 1)

func test_fast_start_and_timer_gate_preserve_demo_cursor() -> void:
	var initial := RunStart.new()
	initial.spawn_cell = Vector2i(1, 2)
	initial.start_mode = RunStart.Mode.FAST_RESET
	initial.start_timer = 2
	var run: GameplayRun = GameplayRun.create(_level(), initial)
	assert_eq(run.error, "")
	assert_eq(run.snapshot().frog.cell, initial.spawn_cell)
	var command := TickCommand.new()
	command.recorded_input_byte = 0
	var result: TickResult = run.step(command)
	assert_eq(result.error, "")
	assert_eq(result.consumed_demo_byte, -1)
	command.tick_index = 1
	command.start_timer_context = 0
	result = run.step(command)
	assert_eq(result.error, "")
	assert_eq(result.consumed_demo_byte, 0)

func test_worker_result_acceptance_matches_synchronous_playback() -> void:
	var direct: GameplayRun = GameplayRun.create(_level())
	var threaded: GameplayRun = GameplayRun.create(_level())
	var worker := TerrainTickWorker.new()
	assert_eq(worker.start(threaded), OK)
	var session := DemoPlaybackSession.new()
	session.configure(8, PackedByteArray([0, 1, 128]))
	for tick: int in 8:
		var command: TickCommand = session.command(tick)
		var expected: TickResult = direct.step(command)
		assert_true(worker.submit(command))
		command.recorded_input_byte = 255
		var result: TickResult = worker.finish()
		assert_eq(result.error, expected.error)
		assert_eq(result.consumed_demo_byte, expected.consumed_demo_byte)
		assert_eq(result.final_snapshot.frog.position_16, expected.final_snapshot.frog.position_16)
		assert_eq(session.accept(result), "")
	worker.close()
	assert_eq(session.elapsed_ticks, 8)
	assert_eq(session.input_cursor, 2)

func test_session_fast_start_countdown_advances_only_after_commit() -> void:
	var session := DemoPlaybackSession.new()
	session.configure(31, PackedByteArray([128]), 30)
	var run: GameplayRun = GameplayRun.create(_level())
	for tick: int in 30:
		var command: TickCommand = session.command(tick)
		assert_eq(command.start_timer_context, 30 - tick)
		var result: TickResult = run.step(command)
		assert_eq(result.error, "")
		assert_eq(result.consumed_demo_byte, -1)
		assert_eq(session.accept(result), "")
	assert_eq(session.input_cursor, 0)
	var command: TickCommand = session.command(30)
	assert_eq(command.start_timer_context, 0)
	var result: TickResult = run.step(command)
	assert_eq(result.consumed_demo_byte, 128)
	assert_eq(session.accept(result), "")
	assert_eq(session.status, "complete")

func test_recorded_tongue_consumes_byte_and_advances_effect_atomically() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	var command := TickCommand.new()
	command.recorded_input_byte = 0x90
	var result: TickResult = run.step(command)
	assert_eq(result.error, "")
	assert_eq(result.consumed_demo_byte, 0x90)
	assert_eq(run.snapshot().frog.current_input, 0x90)
	assert_eq(run.snapshot().tongue.section, 1)
	assert_eq(run.snapshot().tongue.mode, TongueState.Mode.OUT)

func test_demo_start_uses_explicit_maximum_lives_and_keyboard_keeps_three() -> void:
	var demo := SourceDemoFile.new()
	demo.duration = 826
	demo.start_grid_x = 10
	demo.start_grid_z = 10
	demo.input_bytes = PackedByteArray([128])
	assert_true(demo.is_valid())
	var start: RunStart = DemoSetup.start_for(demo)
	assert_eq(DemoSetup.DEMO_LIVES, 10)
	assert_eq(start.lives, DemoSetup.DEMO_LIVES)
	assert_eq(RunStart.new().lives, 3)
	var level: LevelDefinition = _level()
	level.flow_enabled = true
	start.spawn_cell = Vector2i(2, 2)
	var run: GameplayRun = GameplayRun.create(level, start)
	assert_eq(run.error, "")
	if run.error.is_empty():
		assert_eq(run.snapshot().frog.lives, DemoSetup.DEMO_LIVES)

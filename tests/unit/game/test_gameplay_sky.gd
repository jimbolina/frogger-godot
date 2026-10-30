extends GutTest
## Sky drift stepped by the gameplay transaction from the shared stream and frozen Game_timer.

func _level(theme: int = SkyDriftState.THEME) -> LevelDefinition:
	var level := LevelDefinition.new()
	level.flow_enabled = true
	level.level_time = 900
	level.theme = theme
	level.grid = GridDefinition.new()
	level.grid.dimensions = Vector2i.ONE
	var stack := GridStackDefinition.new()
	stack.square_count = 1
	level.grid.stacks.append(stack)
	var square := GridSquareDefinition.new()
	square.flags = 3
	square.vertices.assign([Vector3i(0, 0, 256), Vector3i(256, 0, 256), Vector3i.ZERO, Vector3i(256, 0, 0)])
	level.grid.squares.append(square)
	return level

func _step(run: GameplayRun) -> TickResult:
	var command := TickCommand.new()
	command.tick_index = run.snapshot().tick_index
	var result: TickResult = run.step(command)
	assert_eq(result.error, "")
	return result

func _sky_draws(result: TickResult) -> int:
	var count: int = 0
	for label: String in result.rng_consumers:
		count += int(label.begins_with("sky:"))
	return count

func test_drift_exists_only_for_the_sky_theme() -> void:
	var other: GameplayRun = GameplayRun.create(_level(0))
	assert_eq(other.error, "")
	assert_null(other.snapshot().sky_drift)
	assert_eq(_sky_draws(_step(other)), 0)
	var sky: GameplayRun = GameplayRun.create(_level())
	assert_eq(sky.error, "")
	assert_not_null(sky.snapshot().sky_drift)
	assert_eq(sky.snapshot().sky_drift.position, Vector3i.ZERO)
	assert_eq(sky.snapshot().game_timer, 0)

func test_draws_x_then_z_only_when_the_timer_is_a_multiple_of_128() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	var selections := PackedInt32Array()
	var pull_backs := PackedInt32Array()
	for tick: int in 300:
		var before: int = run.snapshot().game_timer
		var drift: Vector3i = run.snapshot().sky_drift.translation()
		var far: bool = absi(drift.x) > SkyDriftState.MAX_DRIFT or absi(drift.z) > SkyDriftState.MAX_DRIFT
		var result: TickResult = _step(run)
		if not result.error.is_empty():
			return
		assert_eq(result.final_snapshot.game_timer, before + 1)
		var index: int = result.rng_consumers.find("sky:drift_x")
		assert_eq(index >= 0, before & 0x7f == 0 and not far, "tick %d timer %d" % [tick, before])
		if before & 0x7f == 0 and far:
			pull_backs.append(before)
		if index >= 0:
			selections.append(before)
			assert_eq(result.rng_consumers[index + 1], "sky:drift_z")
			assert_eq(_sky_draws(result), 2)
		else:
			assert_eq(_sky_draws(result), 0)
	assert_eq(selections, PackedInt32Array([0, 128]))
	assert_eq(pull_backs, PackedInt32Array([256]), "the drift passes 0xb00 units before timer 256")
	assert_ne(run.snapshot().sky_drift.position, Vector3i.ZERO)

func test_component_run_without_level_flow_advances_every_tick() -> void:
	var level: LevelDefinition = _level()
	level.flow_enabled = false
	var run: GameplayRun = GameplayRun.create(level)
	for tick: int in 3:
		_step(run)
	assert_eq(run.snapshot().game_timer, 3)

func test_run_start_timer_offsets_the_first_draw_and_wraps_unsigned32() -> void:
	var initial := RunStart.new()
	initial.game_timer = 126
	var run: GameplayRun = GameplayRun.create(_level(), initial)
	assert_eq(run.snapshot().game_timer, 126)
	assert_eq(_sky_draws(_step(run)), 0)
	assert_eq(_sky_draws(_step(run)), 0)
	assert_eq(_sky_draws(_step(run)), 2)
	initial.game_timer = 0xffffffff
	assert_eq(run.reset(initial), "")
	assert_eq(_sky_draws(_step(run)), 0)
	assert_eq(run.snapshot().game_timer, 0)
	assert_eq(_sky_draws(_step(run)), 2)

func test_single_start_holds_the_timer_until_after_its_last_callback() -> void:
	var initial := RunStart.new()
	initial.start_mode = RunStart.Mode.SINGLE_START
	initial.start_timer = 120
	initial.game_timer = 5
	var run: GameplayRun = GameplayRun.create(_level(), initial)
	assert_eq(run.snapshot().flow.phase, LevelFlowState.Phase.START)
	for tick: int in 4:
		_step(run)
	assert_eq(run.snapshot().game_timer, 5)
	run._state.frog.flags |= FrogFlags.JUST_BOUNCED
	run._state.flow.start_hud_ticks = LevelStartSequence.SCATTER_FINISH
	run._state.flow.start_timer_finished = true
	var result: TickResult = _step(run)
	assert_eq(result.final_snapshot.flow.phase, LevelFlowState.Phase.PLAY)
	assert_eq(result.final_snapshot.game_timer, 5, "the start callback switches to play after this frame's update")
	_step(run)
	assert_eq(run.snapshot().game_timer, 6)

func test_single_start_at_a_selection_timer_draws_every_start_frame() -> void:
	var initial := RunStart.new()
	initial.start_mode = RunStart.Mode.SINGLE_START
	initial.start_timer = 120
	var run: GameplayRun = GameplayRun.create(_level(), initial)
	for tick: int in 3:
		assert_eq(_sky_draws(_step(run)), 2)
	assert_eq(run.snapshot().game_timer, 0)

func test_death_frames_advance_and_reset_clears_drift_then_holds_for_the_catch_up_frame() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	run._state.game_timer = 10
	run._state.frog.mode = FrogMode.DYING
	run._state.frog.death_count = 3
	run._state.frog.lives = 2
	run._state.sky_drift.position = Vector3i(1 << 20, 0, -(1 << 20))
	run._state.sky_drift.velocity = Vector3i(5, 0, 5)
	run._state.sky_drift.acceleration = Vector3i(7, 0, 7)
	var timers := PackedInt32Array()
	var reset_tick: int = -1
	for tick: int in 8:
		var result: TickResult = _step(run)
		if not result.error.is_empty():
			return
		timers.append(result.final_snapshot.game_timer)
		if reset_tick < 0 and result.final_snapshot.frog.start_timer_hold == 2:
			reset_tick = tick
			assert_eq(result.final_snapshot.sky_drift.position, Vector3i.ZERO)
			assert_eq(result.final_snapshot.sky_drift.velocity, Vector3i.ZERO)
			assert_eq(result.final_snapshot.sky_drift.acceleration, Vector3i.ZERO)
	assert_gt(reset_tick, 0)
	if reset_tick <= 0 or reset_tick + 4 >= timers.size():
		return
	for tick: int in reset_tick:
		assert_eq(timers[tick], 11 + tick, "dying frame %d is a level-play frame" % tick)
	var held: int = timers[reset_tick - 1]
	assert_eq(timers.slice(reset_tick, reset_tick + 5), PackedInt32Array([held, held, held, held + 1, held + 2]), "reset frame, then one catch-up frame of three logic ticks")

func test_checkpoint_frames_do_not_advance_the_timer() -> void:
	var level: LevelDefinition = _level()
	level.level_time = 30
	level.collision_enabled = true
	var collision := EntityCollisionDefinition.new()
	collision.group_dimensions = Vector2i.ONE
	collision.group_size = Vector2i(1024, 1024)
	collision.environment = EntityEnvironmentState.new()
	collision.environment.checkpoint_positions.resize(5)
	for index: int in 2:
		var entity := EntityDefinition.new()
		entity.entity_index = index
		entity.unique_id = index
		entity.form_id = index
		entity.form_flags = 8 | 16
		entity.behavior = EntityBehaviorCatalog.resolve("CHECKPOINT")
		entity.behavior.execution = EntityBehavior.Execution.CONTACT
		entity.action_lengths = PackedInt32Array([4, 4, 4])
		var contact := FormContactDefinition.new()
		contact.entity_index = index
		contact.form_grid_id = 0
		contact.unique_id = index
		contact.form_id = index
		contact.has_form_data = false
		collision.entities.append(entity)
		collision.contacts.append(contact)
	level.entity_collision = collision
	var run: GameplayRun = GameplayRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	_step(run)
	assert_eq(run.snapshot().game_timer, 1)
	run._state.frog.mode = FrogMode.STATIONARY
	run._state.sky_drift.velocity = Vector3i(9, 0, 9)
	var events: Array[TickEvent] = []
	assert_eq(CheckpointCollection.collect(run._frog, run._state, collision.entities[0], events), "")
	for tick: int in 140:
		var result: TickResult = _step(run)
		if not result.error.is_empty():
			return
		assert_eq(result.final_snapshot.game_timer, 1, "tick %d" % tick)
		if result.final_snapshot.flow.phase != LevelFlowState.Phase.CHECKPOINT:
			assert_eq(result.final_snapshot.frog.start_timer_hold, 2)
			assert_eq(result.final_snapshot.sky_drift.velocity, Vector3i.ZERO)
			break
	assert_eq(run.snapshot().flow.phase, LevelFlowState.Phase.PLAY)
	for tick: int in 3:
		_step(run)
	assert_eq(run.snapshot().game_timer, 2)

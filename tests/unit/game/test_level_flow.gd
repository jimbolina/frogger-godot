extends GutTest
## Committed death/reset clocks and source timer progression without presentation.

class RejectFinal extends TickGuard:
	func check(phase: Phase, _candidate: TickGuardCandidate) -> String:
		return "reset commit rejected" if phase == Phase.FINAL else ""

func _level() -> LevelDefinition:
	var level := LevelDefinition.new()
	level.flow_enabled = true
	level.level_time = 900
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

func test_death_reset_preserves_progress_rng_and_tick_then_restarts_local_timer() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	run._state.frog.mode = FrogMode.DYING
	run._state.frog.death_count = 1
	run._state.frog.lives = 2
	run._state.flow.score = 1234
	run._state.flow.remaining_time = 42
	run._random.state = 98765
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_false(result.final_snapshot.completed)
	assert_eq(result.final_snapshot.tick_index, 1)
	assert_eq(result.final_snapshot.frog.lives, 2)
	assert_eq(result.final_snapshot.frog.start_timer, 30)
	assert_eq(result.final_snapshot.frog.mode, FrogMode.WAIT_FOR_CAMERA)
	assert_eq(result.final_snapshot.flow.score, 1234)
	assert_eq(result.final_snapshot.flow.remaining_time, 900)
	assert_eq(result.final_snapshot.rng_state, 98765)
	assert_eq(result.final_snapshot.frog.start_timer_hold, 2)
	var next := TickCommand.new()
	next.tick_index = 1
	assert_eq(run.step(next).error, "")
	assert_eq(run.snapshot().frog.start_timer, 30)
	assert_eq(run.snapshot().flow.remaining_time, 899)

func test_reset_catch_up_frame_holds_start_timer_for_three_logic_ticks() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	run._state.frog.mode = FrogMode.DYING
	run._state.frog.death_count = 1
	run._state.frog.lives = 2
	var command := TickCommand.new()
	assert_eq(run.step(command).error, "")
	var seen := PackedInt32Array()
	for tick: int in 34:
		command = TickCommand.new()
		command.tick_index = run.snapshot().tick_index
		var result: TickResult = run.step(command)
		assert_eq(result.error, "")
		if not result.error.is_empty():
			return
		seen.append(result.final_snapshot.frog.start_timer)
	assert_eq(seen.slice(0, 4), PackedInt32Array([30, 30, 29, 28]))
	assert_eq(seen.find(0), 31, "C reads zero on the 33rd logic tick after the reset")
	assert_eq(run.snapshot().frog.start_timer_hold, 0)

func test_initial_fast_start_does_not_hold_start_timer() -> void:
	var initial := RunStart.new()
	initial.start_mode = RunStart.Mode.FAST_RESET
	initial.start_timer = 30
	var run: GameplayRun = GameplayRun.create(_level(), initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(run.snapshot().frog.start_timer_hold, 0)
	assert_eq(run.step(TickCommand.new()).error, "")
	assert_eq(run.snapshot().frog.start_timer, 29)

func test_late_reset_failure_preserves_prior_death_state_and_can_retry() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	run._state.frog.mode = FrogMode.DYING
	run._state.frog.death_count = 1
	run._state.frog.lives = 2
	run._state.flow.score = 777
	run._state.flow.remaining_time = 42
	run._tick_guard = RejectFinal.new()
	var failed: TickResult = run.step(TickCommand.new())
	assert_eq(failed.error, "reset commit rejected")
	assert_true(failed.events.is_empty())
	assert_eq(run.snapshot().tick_index, 0)
	assert_eq(run.snapshot().frog.death_count, 1)
	assert_eq(run.snapshot().flow.remaining_time, 42)
	assert_eq(run.snapshot().flow.score, 777)
	run._tick_guard = null
	assert_eq(run.step(TickCommand.new()).error, "")
	assert_eq(run.snapshot().flow.remaining_time, 900)

func test_death_decrements_once_and_checkpoint_mode_rejects_death() -> void:
	var frog := Frog.new()
	frog.flow_enabled = true
	var state := GameplayState.new()
	var events: Array[TickEvent] = []
	frog.kill(state, FrogAnimationCatalog.SQUISHED, false, events)
	frog.kill(state, FrogAnimationCatalog.SQUISHED, false, events)
	assert_eq(state.frog.lives, 2)
	state.frog.flags &= ~FrogFlags.MUST_DIE
	state.frog.mode = FrogMode.HIT_CHECKPOINT
	frog.kill(state, FrogAnimationCatalog.SQUISHED, false, events)
	assert_eq(state.frog.lives, 2)

func test_timeout_waits_until_jump_finishes_and_kills_on_second_message_tick() -> void:
	var frog := Frog.new()
	frog.flow_enabled = true
	var state := GameplayState.new()
	state.flow.remaining_time = 1
	state.frog.mode = FrogMode.JUMPING
	var events: Array[TickEvent] = []
	LevelFlow.advance(frog, state, null, events, false)
	assert_eq(state.flow.remaining_time, 0)
	assert_eq(state.flow.timeout_ticks, 60)
	assert_eq(state.frog.flags & FrogFlags.CONTROL_ACTIVE, 0)
	state.frog.mode = FrogMode.STATIONARY
	LevelFlow.advance(frog, state, null, events, false)
	assert_eq(state.flow.timeout_ticks, 59)
	assert_eq(state.frog.lives, 3)
	LevelFlow.advance(frog, state, null, events, false)
	assert_eq(state.frog.lives, 2)
	assert_ne(state.frog.flags & FrogFlags.MUST_DIE, 0)

func test_demo_timer_does_not_trigger_timeout_and_full_restart_clears_progress() -> void:
	var level: LevelDefinition = _level()
	level.demo_playback = true
	level.level_time = 1
	var run: GameplayRun = GameplayRun.create(level)
	assert_eq(run.step(TickCommand.new()).error, "")
	assert_eq(run.snapshot().flow.remaining_time, 0)
	assert_eq(run.snapshot().frog.lives, 3)
	assert_eq(run.snapshot().flow.phase, LevelFlowState.Phase.PLAY)
	run._state.flow.score = 900
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().flow.score, 0)
	assert_eq(run.snapshot().tick_index, 0)
	assert_eq(run.snapshot().flow.remaining_time, 1)

func test_start_phrase_rng_and_hud_clock_roll_back_with_late_failure() -> void:
	var initial := RunStart.new()
	initial.start_mode = RunStart.Mode.SINGLE_START
	initial.start_timer = 120
	var run: GameplayRun = GameplayRun.create(_level(), initial)
	assert_eq(run.error, "")
	assert_eq(run.snapshot().flow.phase, LevelFlowState.Phase.START)
	run._state.frog.flags |= FrogFlags.JUST_BOUNCED
	var before: GameplayState = run.snapshot()
	run._tick_guard = RejectFinal.new()
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "reset commit rejected")
	assert_eq(run.snapshot().rng_state, before.rng_state)
	assert_eq(run.snapshot().flow.start_hud_ticks, 0)
	assert_eq(run.snapshot().flow.remaining_time, 900)
	assert_true(result.events.is_empty())
	run._tick_guard = null
	result = run.step(TickCommand.new())
	assert_eq(result.error, "")
	assert_eq(run.snapshot().flow.start_hud_ticks, 1)
	assert_eq(run.snapshot().flow.remaining_time, 180)
	var expected: SourceRandom = SourceRandom.create(before.rng_state)
	var phrase: int = expected.next_value("level:start_phrase") % 6
	assert_eq(run.snapshot().flow.start_phrase, phrase)
	assert_eq(run.snapshot().rng_state, expected.state)
	var next := TickCommand.new()
	next.tick_index = 1
	assert_eq(run.step(next).error, "")
	assert_eq(run.snapshot().rng_state, expected.state)

func test_five_checkpoint_transitions_preserve_progress_and_complete_after_bonus() -> void:
	var level: LevelDefinition = _level()
	level.level_time = 30
	level.collision_enabled = true
	var collision := EntityCollisionDefinition.new()
	collision.group_dimensions = Vector2i.ONE
	collision.group_size = Vector2i(1024, 1024)
	collision.environment = EntityEnvironmentState.new()
	collision.environment.checkpoint_positions.resize(5)
	for index: int in 5:
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
	for checkpoint: int in 5:
		run._state.frog.mode = FrogMode.STATIONARY
		var events: Array[TickEvent] = []
		assert_eq(CheckpointCollection.collect(run._frog, run._state, collision.entities[checkpoint], events), "")
		assert_eq(run.snapshot().flow.score, checkpoint * 600 + 500)
		assert_eq(run.snapshot().entity_environment.collected, (1 << (checkpoint + 1)) - 1)
		for tick: int in 140:
			var command := TickCommand.new()
			command.tick_index = run.snapshot().tick_index
			var result: TickResult = run.step(command)
			assert_eq(result.error, "", "checkpoint %d transition tick %d" % [checkpoint, tick])
			if not result.error.is_empty():
				return
			if result.final_snapshot.flow.phase != LevelFlowState.Phase.CHECKPOINT:
				break
		assert_eq(run.snapshot().flow.score, (checkpoint + 1) * 600)
		if checkpoint < 4:
			assert_eq(run.snapshot().flow.phase, LevelFlowState.Phase.PLAY)
			assert_false(run.snapshot().completed)
			assert_eq(run.snapshot().flow.remaining_time, 30)
			assert_eq(run.snapshot().frog.start_timer_hold, 2, "checkpoint LevelEnd/LevelStart has the catch-up frame")
			assert_null(run.snapshot().entities.entities[checkpoint].animation)
		else:
			assert_eq(run.snapshot().flow.phase, LevelFlowState.Phase.COMPLETE)
			assert_true(run.snapshot().completed)
	assert_eq(run.snapshot().frog.lives, 3)
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().flow.score, 0)
	assert_eq(run.snapshot().entity_environment.collected, 0)
	assert_false(run.snapshot().completed)

func test_selective_reset_preserves_source_residue_and_clears_active_modifiers() -> void:
	var level: LevelDefinition = _level()
	level.grid.squares[0].vertices.assign([Vector3i(0, 64, 256), Vector3i(256, 64, 256), Vector3i.ZERO, Vector3i(256, 0, 0)])
	var run: GameplayRun = GameplayRun.create(level)
	var state: GameplayState = run.snapshot()
	state.frog.target_16 = Vector3i(123, -456, 789)
	state.frog.user_target_cell = Vector2i(9, 11)
	state.frog.buffered_direction = 3
	state.frog.buffered_keys = 4
	state.frog.buffered_input_count = 2
	state.frog.animation_condition_counter = 7
	state.frog.velocity_16 = Vector3i(99, 88, 77)
	state.frog.current_input = 16
	state.frog.scale = 5000
	state.frog.scale_timer = 3
	state.frog.powerup_flags = PowerupFlags.QUICK_JUMP | PowerupFlags.AUTO_HOP
	state.frog.quick_jump_timer = 20
	state.frog.auto_hop_timer = 30
	state.flow.gold_collected = true
	state.flow.life_bonus_score = 20000
	var events: Array[TickEvent] = []
	assert_eq(run._reset_in_level(state, false, events), "")
	assert_eq(state.frog.target_16, Vector3i(123, -456, 789))
	assert_eq(state.frog.user_target_cell, Vector2i(9, 11))
	assert_eq(state.frog.buffered_direction, 3)
	assert_eq(state.frog.animation_condition_counter, 7)
	assert_eq(state.frog.velocity_16, Vector3i(99, 88, 77))
	assert_eq(state.frog.current_input, 16)
	assert_eq(state.frog.scale, 5000)
	assert_eq(state.frog.scale_timer, 3)
	assert_eq(state.frog.square_flags, 3)
	assert_eq(state.frog.buffered_keys, 0)
	assert_eq(state.frog.buffered_input_count, 0)
	assert_eq(state.frog.powerup_flags, 0)
	assert_eq(state.frog.quick_jump_timer, 0)
	assert_eq(state.frog.auto_hop_timer, 0)
	assert_true(state.flow.gold_collected)
	assert_eq(state.flow.life_bonus_score, 20000)
	assert_eq(state.frog.matrix12.slice(0, 9), PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096]))

func test_checkpoint_skip_reward_and_reset_roll_back_then_commit_once() -> void:
	var level: LevelDefinition = _level()
	level.collision_enabled = true
	var collision := EntityCollisionDefinition.new()
	collision.group_dimensions = Vector2i.ONE
	collision.group_size = Vector2i(1024, 1024)
	collision.environment = EntityEnvironmentState.new()
	collision.environment.checkpoint_positions.resize(5)
	var entity := EntityDefinition.new()
	entity.entity_index = 0
	entity.unique_id = 0
	entity.form_id = 0
	entity.behavior = EntityBehaviorCatalog.resolve("CHECKPOINT")
	entity.behavior.execution = EntityBehavior.Execution.CONTACT
	entity.action_lengths = PackedInt32Array([4, 4, 4])
	collision.entities.append(entity)
	var contact := FormContactDefinition.new()
	contact.entity_index = 0
	contact.unique_id = 0
	contact.form_id = 0
	contact.form_grid_id = 0
	contact.has_form_data = false
	collision.contacts.append(contact)
	level.entity_collision = collision
	var run: GameplayRun = GameplayRun.create(level)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	run._state.flow.phase = LevelFlowState.Phase.CHECKPOINT
	run._state.flow.checkpoint_entity_index = 0
	run._state.flow.bonus_stage = 2
	run._state.flow.remaining_time = 80
	run._state.flow.bonus_score = 100
	run._state.frog.mode = FrogMode.HIT_CHECKPOINT
	run._entities._state.entities[0].pop_allocated = true
	run._entities._state.entities[0].pop_remaining = 0
	var before: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
	var command := TickCommand.new()
	command.pressed_mask = TickCommand.SUPER_HOP
	run._tick_guard = RejectFinal.new()
	assert_eq(run.step(command).error, "reset commit rejected")
	assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), before)
	run._tick_guard = null
	var result: TickResult = run.step(command)
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.final_snapshot.flow.score, 300)
	assert_eq(result.final_snapshot.flow.remaining_time, 0)
	assert_eq(result.final_snapshot.flow.bonus_stage, 4)
	assert_eq(result.final_snapshot.flow.transition_ticks, 30)
	assert_true(TickEvent.trace_lines(result.events).has("sound:3:0:0:0"))
	command.tick_index = 1
	run._tick_guard = RejectFinal.new()
	assert_eq(run.step(command).error, "reset commit rejected")
	assert_eq(run.snapshot().flow.score, 300)
	assert_eq(run.snapshot().flow.phase, LevelFlowState.Phase.CHECKPOINT)
	run._tick_guard = null
	result = run.step(command)
	assert_eq(result.error, "")
	assert_eq(run.snapshot().flow.score, 300)
	assert_eq(run.snapshot().flow.phase, LevelFlowState.Phase.PLAY)

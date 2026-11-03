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

func _checkpoint_level() -> LevelDefinition:
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
	return level

func test_five_checkpoint_transitions_preserve_progress_and_complete_after_bonus() -> void:
	var level: LevelDefinition = _checkpoint_level()
	var collision: EntityCollisionDefinition = level.entity_collision
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

func test_run_start_carries_score_lives_and_life_bonus_into_a_new_level() -> void:
	var initial := RunStart.new()
	initial.start_mode = RunStart.Mode.SINGLE_START
	initial.start_timer = 120
	initial.lives = 5
	initial.score = 4200
	initial.old_score = 4000
	initial.life_bonus_score = 20000
	var run: GameplayRun = GameplayRun.create(_level(), initial)
	assert_eq(run.error, "")
	assert_eq(run.snapshot().frog.lives, 5)
	assert_eq(run.snapshot().flow.score, 4200)
	assert_eq(run.snapshot().flow.old_score, 4000)
	assert_eq(run.snapshot().flow.life_bonus_score, 20000)

func test_kill_deactivation_before_decrement_matches_the_post_decrement_rule() -> void:
	for flow_enabled: bool in [false, true]:
		for lives: int in range(-1, 5):
			var after: int = lives - 1 if flow_enabled and lives > 0 else lives
			var previous: bool = after <= (0 if flow_enabled else 1)
			assert_eq(Frog.kill_deactivates(lives, false), previous, "flow %s lives %d" % [flow_enabled, lives])
	assert_false(Frog.kill_deactivates(1, true))
	assert_true(Frog.kill_deactivates(0, true))

func test_infinite_lives_kill_keeps_lives_and_skips_the_decrement_request() -> void:
	var frog := Frog.new()
	frog.flow_enabled = true
	for lives: int in [0, 1, 3]:
		var state := GameplayState.new()
		state.cheats.infinite_lives = true
		state.frog.lives = lives
		var events: Array[TickEvent] = []
		frog.kill(state, FrogAnimationCatalog.SQUISHED, false, events)
		assert_eq(state.frog.lives, lives)
		assert_false(state.requests.life_decrement_requested)
		assert_ne(state.frog.flags & FrogFlags.MUST_DIE, 0)
		assert_eq(state.frog.flags & FrogFlags.CONTROL_ACTIVE, 0)
		assert_eq(bool(state.frog.flags & FrogFlags.ACTIVE), lives > 0, "lives %d" % lives)

func test_kill_without_cheat_decrements_and_deactivates_on_the_last_life() -> void:
	for flow_enabled: bool in [false, true]:
		var frog := Frog.new()
		frog.flow_enabled = flow_enabled
		for lives: int in [0, 1, 2]:
			var state := GameplayState.new()
			state.frog.lives = lives
			var events: Array[TickEvent] = []
			frog.kill(state, FrogAnimationCatalog.SQUISHED, false, events)
			assert_eq(state.frog.lives, lives - 1 if flow_enabled and lives > 0 else lives)
			assert_eq(state.requests.life_decrement_requested, lives > 0)
			assert_eq(bool(state.frog.flags & FrogFlags.ACTIVE), lives > 1, "flow %s lives %d" % [flow_enabled, lives])

func test_no_death_on_timeout_skips_the_whole_timeout_block() -> void:
	var frog := Frog.new()
	frog.flow_enabled = true
	var state := GameplayState.new()
	state.cheats.no_death_on_timeout = true
	state.flow.remaining_time = 1
	var events: Array[TickEvent] = []
	for tick: int in 70:
		var result: LevelFlow = LevelFlow.advance(frog, state, null, events, false)
		assert_eq(result.error, "")
		assert_eq(result.reset, LevelFlow.Reset.NONE)
	assert_eq(state.flow.remaining_time, 0)
	assert_eq(state.flow.timeout_ticks, 60)
	assert_ne(state.frog.flags & FrogFlags.CONTROL_ACTIVE, 0)
	assert_ne(state.frog.flags & FrogFlags.ACTIVE, 0)
	assert_eq(state.frog.flags & FrogFlags.MUST_DIE, 0)
	assert_eq(state.frog.lives, 3)
	assert_eq(state.flow.phase, LevelFlowState.Phase.PLAY)
	assert_false(state.completed)
	for event: TickEvent in events:
		assert_ne(event.kind, TickEvent.Kind.DEATH_ANIMATION)

func test_cheats_survive_death_and_checkpoint_resets() -> void:
	var initial := RunStart.new()
	initial.cheats = CheatState.new()
	initial.cheats.infinite_lives = true
	initial.cheats.no_death_on_timeout = true
	var run: GameplayRun = GameplayRun.create(_level(), initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	run._state.frog.mode = FrogMode.DYING
	run._state.frog.death_count = 1
	var result: TickResult = run.step(TickCommand.new())
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.final_snapshot.frog.start_timer_hold, 2, "the death reset ran")
	assert_true(result.final_snapshot.cheats.infinite_lives)
	assert_true(result.final_snapshot.cheats.no_death_on_timeout)
	var level: LevelDefinition = _checkpoint_level()
	run = GameplayRun.create(level, initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var events: Array[TickEvent] = []
	assert_eq(CheckpointCollection.collect(run._frog, run._state, level.entity_collision.entities[0], events), "")
	for tick: int in 140:
		var command := TickCommand.new()
		command.tick_index = run.snapshot().tick_index
		result = run.step(command)
		assert_eq(result.error, "")
		if not result.error.is_empty() or result.final_snapshot.flow.phase != LevelFlowState.Phase.CHECKPOINT:
			break
	assert_eq(run.snapshot().flow.phase, LevelFlowState.Phase.PLAY)
	assert_eq(run.snapshot().frog.start_timer_hold, 2, "the checkpoint reset ran")
	assert_true(run.snapshot().cheats.infinite_lives)
	assert_true(run.snapshot().cheats.no_death_on_timeout)

func _transitions(events: Array[TickEvent], phase: LevelFlowState.Phase) -> int:
	var count: int = 0
	for event: TickEvent in events:
		if event.kind == TickEvent.Kind.LEVEL_TRANSITION and event.flow_phase == phase:
			count += 1
	return count

func test_last_life_kill_enters_game_over_on_that_tick_without_completing() -> void:
	var frog := Frog.new()
	frog.flow_enabled = true
	var state := GameplayState.new()
	state.frog.lives = 1
	var events: Array[TickEvent] = []
	frog.kill(state, FrogAnimationCatalog.SQUISHED, false, events)
	assert_eq(state.frog.flags & FrogFlags.ACTIVE, 0)
	var result: LevelFlow = LevelFlow.advance(frog, state, null, events, false)
	assert_eq(result.error, "")
	assert_eq(result.reset, LevelFlow.Reset.NONE)
	assert_eq(state.flow.phase, LevelFlowState.Phase.GAME_OVER)
	assert_false(state.completed)
	assert_eq(_transitions(events, LevelFlowState.Phase.GAME_OVER), 1)

func test_game_over_phase_clears_death_completion_and_stops_the_timer() -> void:
	var frog := Frog.new()
	frog.flow_enabled = true
	var state := GameplayState.new()
	state.frog.lives = 0
	state.frog.flags &= ~FrogFlags.ACTIVE
	state.flow.phase = LevelFlowState.Phase.GAME_OVER
	state.flow.remaining_time = 1
	state.completed = true
	var events: Array[TickEvent] = [TickEvent.make(TickEvent.Kind.DEATH_COMPLETE)]
	var result: LevelFlow = LevelFlow.advance(frog, state, null, events, false)
	assert_eq(result.error, "")
	assert_eq(result.reset, LevelFlow.Reset.NONE)
	assert_false(state.completed)
	assert_eq(state.flow.phase, LevelFlowState.Phase.GAME_OVER)
	assert_eq(state.flow.remaining_time, 1)
	assert_eq(_transitions(events, LevelFlowState.Phase.GAME_OVER), 0)

func test_death_complete_on_the_last_life_enters_game_over_without_completing() -> void:
	var frog := Frog.new()
	frog.flow_enabled = true
	var state := GameplayState.new()
	state.frog.lives = 0
	state.completed = true
	var events: Array[TickEvent] = [TickEvent.make(TickEvent.Kind.DEATH_COMPLETE)]
	var result: LevelFlow = LevelFlow.advance(frog, state, null, events, false)
	assert_eq(result.reset, LevelFlow.Reset.NONE)
	assert_eq(state.flow.phase, LevelFlowState.Phase.GAME_OVER)
	assert_false(state.completed)
	assert_eq(_transitions(events, LevelFlowState.Phase.GAME_OVER), 1)

func test_run_keeps_stepping_through_the_last_life_death() -> void:
	var initial := RunStart.new()
	initial.lives = 1
	var run: GameplayRun = GameplayRun.create(_level(), initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	run._state.flow.remaining_time = 1
	var entered: int = -1
	var death_completed: bool = false
	for tick: int in 200:
		var command := TickCommand.new()
		command.tick_index = run.snapshot().tick_index
		var result: TickResult = run.step(command)
		assert_eq(result.error, "", "tick %d" % tick)
		if not result.error.is_empty():
			return
		assert_false(result.final_snapshot.completed, "tick %d" % tick)
		if entered < 0 and result.final_snapshot.flow.phase == LevelFlowState.Phase.GAME_OVER:
			entered = tick
			assert_eq(_transitions(result.events, LevelFlowState.Phase.GAME_OVER), 1)
			assert_eq(result.final_snapshot.frog.lives, 0)
			assert_eq(result.final_snapshot.frog.flags & FrogFlags.ACTIVE, 0)
		for event: TickEvent in result.events:
			death_completed = death_completed or event.kind == TickEvent.Kind.DEATH_COMPLETE
	assert_eq(entered, 1, "the timeout kill on the second tick, timeout_ticks 59")
	assert_true(death_completed, "the dying frog finished under the page")
	assert_eq(run.snapshot().flow.phase, LevelFlowState.Phase.GAME_OVER)
	assert_eq(run.snapshot().flow.remaining_time, 0)
	assert_eq(run.snapshot().tick_index, 200)

func test_quit_game_removes_control_and_requests_the_game_over_page() -> void:
	var empty := GameplayRun.new()
	assert_ne(empty.quit_game(), "")
	var run: GameplayRun = GameplayRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_ne(run.snapshot().frog.flags & FrogFlags.CONTROL_ACTIVE, 0)
	assert_eq(run.quit_game(), "")
	var state: GameplayState = run.snapshot()
	assert_eq(state.frog.flags & FrogFlags.CONTROL_ACTIVE, 0)
	assert_ne(state.frog.flags & FrogFlags.ACTIVE, 0)
	assert_eq(state.flow.phase, LevelFlowState.Phase.GAME_OVER)
	assert_false(state.completed)
	assert_false(PausePage.allowed(state))
	for tick: int in 5:
		var command := TickCommand.new()
		command.tick_index = run.snapshot().tick_index
		assert_eq(run.step(command).error, "", "tick %d" % tick)
	assert_eq(run.snapshot().flow.phase, LevelFlowState.Phase.GAME_OVER)

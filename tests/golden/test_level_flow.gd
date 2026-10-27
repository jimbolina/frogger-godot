extends GutTest
## Independent source start HUD clocks, including timer overshoot and parallel animations.

func test_start_clock_matches_independent_sprite_interpreter() -> void:
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/level_flow.json"))
	for fixture: Dictionary in facts.start:
		var state := GameplayState.new()
		state.flow.phase = LevelFlowState.Phase.START
		state.frog.flags |= FrogFlags.JUST_BOUNCED
		var random: SourceRandom = SourceRandom.create(1)
		var events: Array[TickEvent] = []
		var seconds: int = fixture.seconds
		for row: Dictionary in fixture.rows:
			LevelStartSequence.advance(state, random, seconds * 30, events)
			var timer: int = row.timer
			var finished: bool = row.timer_finished
			var playing: bool = row.playing
			assert_eq(state.flow.remaining_time, timer, "%d seconds tick %d" % [seconds, row.tick])
			assert_eq(state.flow.start_timer_finished, finished)
			assert_eq(state.flow.phase == LevelFlowState.Phase.PLAY, playing)
		assert_eq(events.size(), 1)
		assert_eq(state.frog.mode, FrogMode.WAIT_FOR_CAMERA)

func test_checkpoint_bonus_matches_independent_hud_interpreter() -> void:
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/level_flow.json"))
	for fixture: Dictionary in facts.checkpoint:
		var entity := EntityDefinition.new()
		entity.entity_index = 7
		entity.behavior = EntityBehaviorCatalog.resolve("CHECKPOINT")
		entity.behavior.execution = EntityBehavior.Execution.CONTACT
		entity.action_lengths = PackedInt32Array([4, 4, 4])
		var definitions: Array[EntityDefinition] = [entity]
		var entities: EntityRun = EntityRun.create(definitions)
		assert_eq(entities.error, "")
		if not entities.error.is_empty():
			return
		var target: EntitySnapshot = entities.entity_snapshot(0)
		target.pop_allocated = true
		target.pop_remaining = 0
		entities.apply_tongue_target(target)
		var state := GameplayState.new()
		state.entity_environment = EntityEnvironmentState.new()
		state.entity_environment.collected = 1
		state.flow.phase = LevelFlowState.Phase.CHECKPOINT
		state.flow.checkpoint_entity_index = 7
		state.flow.remaining_time = fixture.remaining
		state.flow.score = 500
		for row: Dictionary in fixture.rows:
			var events: Array[TickEvent] = []
			var result := LevelFlow.new()
			var skip: bool = row.skip
			assert_eq(LevelFlow._checkpoint(state, entities, events, result, skip), "")
			var timer: int = row.timer
			var bonus: int = row.bonus
			var score: int = row.score
			var sound: int = row.sound
			var finished: bool = row.finished
			assert_eq(state.flow.remaining_time, timer, "remaining %d tick %d" % [fixture.remaining, row.tick])
			assert_eq(state.flow.bonus_score, bonus)
			assert_eq(state.flow.score, score)
			assert_eq(events.size() == 1, sound >= 0)
			if sound >= 0:
				assert_eq(TickEvent.trace_lines(events), ["sound:%d:0:0:0" % sound])
			assert_eq(result.reset == LevelFlow.Reset.CHECKPOINT, finished)

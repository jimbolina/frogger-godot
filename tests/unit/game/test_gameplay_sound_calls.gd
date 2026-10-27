extends GutTest
## Source sound call identities, pitch overrides and transaction ordering.

class RejectFinal extends TickGuard:
	func check(phase: Phase, _candidate: TickGuardCandidate) -> String:
		return "sound commit rejected" if phase == Phase.FINAL else ""

func _samples(ids: PackedInt32Array) -> Array[LogicalSoundDefinition]:
	var result: Array[LogicalSoundDefinition] = []
	for id: int in ids:
		var sample := LogicalSoundDefinition.new()
		sample.sound_id = id
		sample.pitch_mod = 60
		sample.frame_count = 10000
		result.append(sample)
	return result

func _level() -> LevelDefinition:
	var result := LevelDefinition.new()
	result.sounds = _samples([6, 7])
	result.grid = GridDefinition.new()
	result.grid.dimensions = Vector2i(3, 3)
	for z: int in 3:
		for x: int in 3:
			var stack := GridStackDefinition.new()
			stack.first_square_index = result.grid.squares.size()
			stack.square_count = 1
			result.grid.stacks.append(stack)
			var square := GridSquareDefinition.new()
			square.flags = GridSquareFlags.USABLE | GridSquareFlags.SAFE
			square.vertices.assign([Vector3i(x * 256, 0, (z + 1) * 256), Vector3i((x + 1) * 256, 0, (z + 1) * 256), Vector3i(x * 256, 0, z * 256), Vector3i((x + 1) * 256, 0, z * 256)])
			result.grid.squares.append(square)
	return result

func test_hop_pitch_random_and_voice_allocation_roll_back_together() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var command := TickCommand.new()
	command.pressed_mask = TickCommand.NORTH
	var before: GameplayState = run.snapshot()
	run._tick_guard = RejectFinal.new()
	var failed: TickResult = run.step(command)
	assert_eq(failed.error, "sound commit rejected")
	assert_eq(run.snapshot().rng_state, before.rng_state)
	assert_null(run.snapshot().sound.voices[0].sample)
	assert_true(failed.events.is_empty())
	run._tick_guard = null
	var result: TickResult = run.step(command)
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.final_snapshot.sound.voices[0].sample.sound_id, 6)
	assert_eq(result.rng_consumers, ["sound:6:pitch"])

func test_nonzero_hop_pitch_uses_frame_clock_without_random_draw() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	run._state.tick_index = 1
	var command := TickCommand.new()
	command.tick_index = 1
	command.pressed_mask = TickCommand.NORTH
	var result: TickResult = run.step(command)
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.final_snapshot.sound.voices[0].note, 61)
	assert_true(result.rng_consumers.is_empty())

func test_reward_jingles_apply_source_pitch_override() -> void:
	var kinds := PackedInt32Array([RewardDefinition.LIFE, RewardDefinition.POWERUP, RewardDefinition.POWERUP, RewardDefinition.POWERUP, RewardDefinition.POWERUP])
	var values := PackedInt32Array([1, PowerupFlags.TIMER_SPEED, PowerupFlags.AUTO_HOP, PowerupFlags.SUPER_TONGUE, PowerupFlags.QUICK_JUMP])
	var notes := PackedInt32Array([60, 61, 61, 62, 63])
	for index: int in kinds.size():
		var state := GameplayState.new()
		state.sound = LogicalSoundState.create(_samples([26]))
		var random: SourceRandom = SourceRandom.create(1)
		var reward := RewardDefinition.new()
		reward.flags = kinds[index]
		reward.value = values[index]
		var events: Array[TickEvent] = []
		assert_eq(GameplayRewards.apply(reward, state, events, random), "")
		assert_eq(state.sound.voices[0].sample.sound_id, 26)
		assert_eq(state.sound.voices[0].note, notes[index])
		assert_eq(random.draw_count, 1 if index == 0 else 0)

func test_timer_hud_sound_order_precedes_timer_decrement_and_demo_omits_hud() -> void:
	var frog := Frog.new()
	var state := GameplayState.new()
	state.sound = LogicalSoundState.create(_samples([10, 24, 25]))
	state.flow.remaining_time = 55
	var random: SourceRandom = SourceRandom.create(1)
	var events: Array[TickEvent] = []
	assert_eq(LevelFlow.advance(frog, state, null, events, false, random).error, "")
	assert_eq(TickEvent.trace_lines(events), ["sound:10:0:0:0", "sound:24:0:0:0"])
	assert_eq(random.consumers, ["sound:10:pitch", "sound:24:pitch"])
	assert_eq(state.flow.remaining_time, 54)
	events.clear()
	assert_eq(LevelFlow.advance(frog, state, null, events, false, random).error, "")
	assert_true(events.is_empty())
	assert_eq(random.draw_count, 2)
	state.flow.remaining_time = 55
	assert_eq(LevelFlow.advance(frog, state, null, events, true, random).error, "")
	assert_true(events.is_empty())
	assert_eq(random.draw_count, 2)

func test_super_hop_uses_its_own_sample_without_hop_pitch_override() -> void:
	var run: GameplayRun = GameplayRun.create(_level())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var command := TickCommand.new()
	command.pressed_mask = TickCommand.SUPER_HOP
	var result: TickResult = run.step(command)
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.final_snapshot.sound.voices[0].sample.sound_id, 7)
	assert_eq(result.rng_consumers, ["sound:7:pitch"])

func test_surface_and_death_height_sound_identities_match_source() -> void:
	var flags := PackedInt32Array([GridSquareFlags.DEADLY, GridSquareFlags.POPDEATH, GridSquareFlags.WATER])
	var ids := PackedInt32Array([12, 17, 2])
	for index: int in flags.size():
		var frog := Frog.new()
		frog.random = SourceRandom.create(1)
		var state := GameplayState.new()
		state.sound = LogicalSoundState.create(_samples(ids))
		var events: Array[TickEvent] = []
		frog.react(state, GridSquareFlags.USABLE | flags[index], events)
		assert_eq(frog.callback_error, "")
		assert_eq(state.sound.voices[0].sample.sound_id, ids[index])
	for theme: int in [1, 8, 5]:
		var frog := Frog.new()
		frog.theme = theme
		frog.random = SourceRandom.create(1)
		frog.collision_bounds = Rect2i(-100, -100, 200, 200)
		frog.death_height = 0
		var state := GameplayState.new()
		state.frog.world_position.y = 100
		state.sound = LogicalSoundState.create(_samples([1, 12]))
		var events: Array[TickEvent] = []
		frog.collide(state, events)
		assert_eq(frog.callback_error, "")
		assert_eq(state.sound.voices[0].sample.sound_id, 1 if theme == 5 else 12)

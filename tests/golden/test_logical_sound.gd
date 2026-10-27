extends GutTest
## Independent native voice lifetimes, allocation pressure and detached moving owners.

func _sample(sound_id: int = 21) -> LogicalSoundDefinition:
	var result := LogicalSoundDefinition.new()
	result.sound_id = sound_id
	result.first_voice = 0
	result.last_voice = 0
	result.pitch_mod = 60
	result.frame_count = 184
	return result

func test_voice_lifetimes_match_independent_native_facts() -> void:
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/logical_sound.json"))
	for fixture: Dictionary in facts.cases:
		var sample: LogicalSoundDefinition = _sample()
		sample.flags = fixture.flags
		sample.frame_count = fixture.length
		var state: LogicalSoundState = LogicalSoundState.create([sample])
		var random: SourceRandom = SourceRandom.create(1)
		for row: Dictionary in fixture.rows:
			var tick: int = row.tick
			var tag: int = -2
			if tick in [0, 3, 7]:
				tag = state.play(21, random)
			if tick == 4 and state.voices[0].sample != null:
				state.bend(state.voices[0].identifier << 16, 96)
			assert_eq(state.advance(random), "")
			var expected_tag: int = row.tag
			var expected_rng: int = row.rng
			var expected_draws: int = row.draws
			var allocated: bool = row.allocated
			assert_eq(tag, expected_tag)
			assert_eq(random.state, expected_rng)
			assert_eq(random.draw_count, expected_draws)
			assert_eq(state.voices[0].sample != null, allocated)
			if allocated:
				var voice: LogicalSoundVoice = state.voices[0]
				var observed: Array[int] = [voice.cursor_16, voice.step_16, voice.base_step_16, voice.pitch]
				var expected: Array[int] = [row.pos, row.step, row.base, row.pitch]
				assert_eq(observed, expected)
				var playing: bool = row.playing
				var initialising: bool = row.initialising
				assert_eq(voice.playing, playing)
				assert_eq(voice.initialising, initialising)

func test_moving_allocation_order_radius_and_candidate_isolation() -> void:
	var sample: LogicalSoundDefinition = _sample()
	sample.flags = LogicalSoundDefinition.LOOPED
	var original: LogicalSoundState = LogicalSoundState.create([sample])
	assert_eq(original.create_moving(1, 21, 256, 768, Vector3i(768, 0, 0), false), "")
	assert_eq(original.create_moving(2, 21, 256, 768, Vector3i(768, 0, 0), false), "")
	var state: LogicalSoundState = original.copy()
	var random: SourceRandom = SourceRandom.create(1)
	assert_eq(state.advance(random), "")
	assert_eq(state.moving_for(2).voice_tag, 65536)
	assert_eq(state.moving_for(1).voice_tag, -1)
	assert_eq(random.draw_count, 1)
	assert_eq(original.moving_for(2).voice_tag, -1)
	state.moving_for(2).position.x = 784
	assert_eq(state.advance(random), "")
	assert_eq(state.moving_for(2).voice_tag, -1)
	assert_eq(state.moving_for(1).voice_tag, -1)
	assert_eq(random.draw_count, 1)
	assert_eq(state.advance(random), "")
	assert_eq(state.moving_for(1).voice_tag, 131072)
	assert_eq(random.draw_count, 2)
	state.retire_moving(1)
	assert_null(state.moving_for(1))
	assert_not_null(state.voices[0].sample)
	assert_eq(state.advance(random), "")
	assert_null(state.voices[0].sample)
	assert_eq(original.moving.size(), 2)

func test_pitch_offset_and_identifier_wrap_do_not_draw_random() -> void:
	var sample: LogicalSoundDefinition = _sample()
	var state: LogicalSoundState = LogicalSoundState.create([sample])
	state.next_identifier = 32766
	var random: SourceRandom = SourceRandom.create(1)
	var tag: int = state.play(21, random, 257)
	assert_eq(random.draw_count, 0)
	assert_eq(state.voices[0].note, 62)
	assert_eq(state.voices[0].fine, 1)
	assert_eq(state.next_identifier, 1)
	state.kill(tag)
	assert_eq(state.advance(random), "")
	assert_eq(state.advance(random), "")
	var next_tag: int = state.play(21, random, 128)
	state.kill(tag)
	assert_not_null(state.voices[0].sample)
	assert_eq(next_tag, 65536)
	assert_eq(random.draw_count, 0)

func test_killed_voices_remain_occupied_until_source_update() -> void:
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/logical_sound.json"))
	for fixture: Dictionary in facts.killed_cases:
		var sample: LogicalSoundDefinition = _sample()
		sample.flags = fixture.flags
		sample.frame_count = 10000
		var state: LogicalSoundState = LogicalSoundState.create([sample])
		var random: SourceRandom = SourceRandom.create(1)
		var tag: int = state.play(21, random)
		var fresh: bool = fixture.fresh
		if not fresh:
			assert_eq(state.advance(random), "")
		state.kill(tag)
		for row: Dictionary in fixture.rows:
			var occupied: bool = row.occupied
			var allocation: int = row.allocation
			assert_eq(state.voices[0].sample != null, occupied)
			assert_eq(state.copy().play(21, random.copy()), allocation)
			assert_eq(state.advance(random), "")
		assert_eq(random.draw_count, 1)

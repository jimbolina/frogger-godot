extends GutTest
## SoundVoiceView starts, bends, pans and stops players from committed voice sequences only.

var _view: SoundVoiceView
var _definitions: Array[LogicalSoundDefinition] = []

func before_each() -> void:
	_definitions = [
		_definition(1, LogicalSoundDefinition.SINGLE, 20, 100),
		_definition(2, LogicalSoundDefinition.LOOPED, 10, 120),
		_definition(3, LogicalSoundDefinition.REPEAT, 0, 127),
	]
	_view = SoundVoiceView.new()
	add_child_autofree(_view)
	_view.configure(_resources())

func _resources() -> AudioResources:
	var bank_of: Dictionary[int, int] = {1: 0, 2: 0, 3: 0}
	var loader: Callable = func(_bank_id: int) -> SoundBankSetup: return _bank()
	return AudioResources.from_loader(_definitions, bank_of, loader)

func _definition(sound_id: int, flags: int, minimum: int, maximum: int) -> LogicalSoundDefinition:
	var definition := LogicalSoundDefinition.new()
	definition.sound_id = sound_id
	definition.flags = flags
	definition.frame_count = 400
	definition.minimum_volume = minimum
	definition.maximum_volume = maximum
	return definition

func _bank() -> SoundBankSetup:
	var bank := SoundBankSetup.new()
	bank.header = SoundBankHeader.new()
	var samples := AudioStreamWAV.new()
	samples.format = AudioStreamWAV.FORMAT_16_BITS
	samples.mix_rate = 11025
	var silence := PackedByteArray()
	silence.resize(800)
	samples.data = silence
	for sound_id: int in 4:
		var entry := SoundBankEntry.new()
		entry.sound_id = sound_id
		entry.audio_present = sound_id > 0
		entry.data_size = 800 if sound_id > 0 else 0
		entry.sample_rate = 11025
		entry.sample_bits = 16
		entry.stream = samples if sound_id > 0 else null
		bank.header.entries.append(entry)
	return bank

func _state(tick: int) -> GameplayState:
	var state := GameplayState.new()
	state.tick_index = tick
	state.sound = LogicalSoundState.create(_definitions)
	return state

func _voice(state: GameplayState, slot: int, sound_index: int, identifier: int, note: int = 60, fine: int = 0) -> LogicalSoundVoice:
	var voice := LogicalSoundVoice.new()
	voice.sample = _definitions[sound_index].copy()
	voice.identifier = identifier
	voice.note = note
	voice.fine = fine
	voice.key_on()
	state.sound.voices[slot] = voice
	return voice

func test_a_new_identifier_starts_its_sample_at_the_voice_pitch_and_full_fixed_volume() -> void:
	var before: GameplayState = _state(0)
	var after: GameplayState = _state(1)
	_voice(after, 3, 0, 7, 62, 32)
	_view.accept_state(before, after)
	var player: AudioStreamPlayer = _view.players[3]
	assert_true(player.playing)
	assert_eq(_view.identifier(3), 7)
	assert_almost_eq(player.pitch_scale, AudioResources.pitch_scale(62, 32, 64), 0.00001)
	assert_almost_eq(player.volume_db, SoundVoiceView.mix(Vector2i(100, 100)).x, 0.0001)
	assert_almost_eq(_view.pan(3), 0.0, 0.0001)
	assert_eq(player.bus, &"Sfx voice 3")
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(player.bus)), SoundVoiceView.BUS)
	for slot: int in SoundVoiceView.VOICES:
		if slot != 3:
			assert_false(_view.players[slot].playing, str(slot))

func test_a_repeated_tick_is_ignored_and_a_pitch_change_bends() -> void:
	var first: GameplayState = _state(1)
	_voice(first, 0, 1, 4)
	_view.accept_state(_state(0), first)
	var repeated: GameplayState = _state(1)
	var repeated_voice: LogicalSoundVoice = _voice(repeated, 0, 1, 4)
	repeated_voice.bend(100)
	_view.accept_state(first, repeated)
	assert_almost_eq(_view.players[0].pitch_scale, AudioResources.pitch_scale(60, 0, 64), 0.00001, "the repeated tick does not bend")
	var bent: GameplayState = _state(2)
	var bent_voice: LogicalSoundVoice = _voice(bent, 0, 1, 4)
	bent_voice.bend(100)
	_view.accept_state(first, bent)
	assert_almost_eq(_view.players[0].pitch_scale, AudioResources.pitch_scale(60, 0, 100), 0.00001)
	assert_true(_view.players[0].playing, "a bend does not restart")
	assert_eq(_view.identifier(0), 4)

func test_kills_stop_and_a_recycled_slot_restarts() -> void:
	var playing: GameplayState = _state(1)
	_voice(playing, 5, 0, 9)
	_view.accept_state(_state(0), playing)
	var recycled: GameplayState = _state(2)
	_voice(recycled, 5, 2, 10)
	_view.accept_state(playing, recycled)
	assert_eq(_view.identifier(5), 10)
	assert_true(_view.players[5].playing)
	var looped: AudioStreamWAV = _view.players[5].stream as AudioStreamWAV
	assert_eq(looped.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	var killed: GameplayState = _state(3)
	var voice: LogicalSoundVoice = _voice(killed, 5, 2, 10)
	voice.killed = true
	voice.playing = false
	_view.accept_state(recycled, killed)
	assert_false(_view.players[5].playing)
	assert_eq(_view.identifier(5), 0)

func test_looping_voices_stop_when_released_but_one_shots_finish_on_their_own() -> void:
	var started: GameplayState = _state(1)
	_voice(started, 0, 0, 1)
	_voice(started, 1, 1, 2)
	_view.accept_state(_state(0), started)
	var ended: GameplayState = _state(2)
	var one_shot: LogicalSoundVoice = _voice(ended, 0, 0, 1)
	one_shot.playing = false
	var loop: LogicalSoundVoice = _voice(ended, 1, 1, 2)
	loop.playing = false
	_view.accept_state(started, ended)
	assert_true(_view.players[0].playing, "the one-shot keeps its tail")
	assert_false(_view.players[1].playing, "the loop stops with its voice")
	var released: GameplayState = _state(3)
	_view.accept_state(ended, released)
	assert_true(_view.players[0].playing)
	assert_eq(_view.identifier(0), 0)

func test_moving_voices_follow_distance_and_pan_about_the_frog() -> void:
	var state: GameplayState = _state(1)
	state.sound.create_moving(11, 2, 256, 2048, Vector3i(1024, 0, 0))
	state.sound.listener = Vector3i.ZERO
	var moving_voice: LogicalSoundVoice = _voice(state, 2, 1, 6)
	moving_voice.moving_owner = 11
	_view.accept_state(_state(0), state)
	var expected: Vector2 = SoundVoiceView.mix(AudioResources.moving_volumes(_definitions[1], state.sound.moving_for(11), Vector3i.ZERO, state.frog.matrix12))
	assert_almost_eq(_view.players[2].volume_db, expected.x, 0.0001)
	assert_almost_eq(_view.pan(2), expected.y, 0.0001)
	assert_gt(_view.pan(2), 0.0, "a source on the frog's right pans right")
	var nearer: GameplayState = _state(2)
	nearer.sound.create_moving(11, 2, 256, 2048, Vector3i(-300, 0, 0))
	var nearer_voice: LogicalSoundVoice = _voice(nearer, 2, 1, 6)
	nearer_voice.moving_owner = 11
	_view.accept_state(state, nearer)
	assert_lt(_view.pan(2), 0.0)
	assert_gt(_view.players[2].volume_db, expected.x, "nearer is louder")
	assert_eq(_view.identifier(2), 6, "updates do not restart the voice")

func test_collapse_stops_everything_and_allows_the_same_tick_again() -> void:
	var state: GameplayState = _state(1)
	_voice(state, 0, 0, 1)
	_voice(state, 8, 1, 2)
	_view.accept_state(_state(0), state)
	_view.collapse()
	for slot: int in SoundVoiceView.VOICES:
		assert_false(_view.players[slot].playing, str(slot))
		assert_eq(_view.identifier(slot), 0)
	_view.accept_state(_state(0), state)
	assert_true(_view.players[8].playing)

func test_pause_holds_players_and_stopping_releases_the_hold() -> void:
	var state: GameplayState = _state(1)
	_voice(state, 0, 1, 1)
	_view.accept_state(_state(0), state)
	_view.pause(true)
	assert_true(_view.players[0].stream_paused)
	_view.collapse()
	assert_false(_view.players[0].stream_paused)

func test_missing_state_resources_or_streams_stay_silent() -> void:
	var state: GameplayState = _state(1)
	_voice(state, 0, 0, 1)
	_view.configure(null)
	_view.accept_state(_state(0), state)
	assert_false(_view.players[0].playing)
	var silent := GameplayState.new()
	silent.tick_index = 2
	_view.accept_state(state, silent)
	assert_false(_view.players[0].playing)
	var missing: Array[LogicalSoundDefinition] = []
	var no_banks: Dictionary[int, int] = {}
	var resources: AudioResources = AudioResources.from_loader(missing, no_banks, Callable())
	_view.configure(resources)
	var unknown: GameplayState = _state(3)
	_voice(unknown, 0, 0, 1)
	_view.accept_state(_state(2), unknown)
	assert_false(_view.players[0].playing)
	assert_eq(resources.diagnostics.size(), 1)

func test_mix_turns_left_and_right_levels_into_volume_and_pan() -> void:
	var centred: Vector2 = SoundVoiceView.mix(Vector2i(127, 127), 127)
	assert_almost_eq(centred.x, linear_to_db(AudioResources.gain(127, 127)), 0.0001)
	assert_almost_eq(centred.y, 0.0, 0.0001)
	var left: Vector2 = SoundVoiceView.mix(Vector2i(100, 0))
	assert_almost_eq(left.y, -1.0, 0.0001)
	assert_almost_eq(db_to_linear(left.x) * (1.0 - left.y), AudioResources.gain(100), 0.0001, "the panner's left side gets the left gain")
	var skewed: Vector2 = SoundVoiceView.mix(Vector2i(30, 90))
	assert_almost_eq(db_to_linear(skewed.x) * (1.0 - skewed.y), AudioResources.gain(30), 0.0001)
	assert_almost_eq(db_to_linear(skewed.x) * (1.0 + skewed.y), AudioResources.gain(90), 0.0001)
	assert_eq(SoundVoiceView.mix(Vector2i.ZERO), Vector2(SoundVoiceView.SILENT_DB, 0.0))

func test_the_world_view_creates_forwards_and_collapses_audio_only_when_enabled() -> void:
	var muted := GameplayWorldView.new()
	add_child_autofree(muted)
	muted.build_world()
	assert_null(muted.voice_view())
	assert_null(muted.music_player())
	muted.configure_audio(null)
	muted.pause_audio(true)
	var world := GameplayWorldView.new()
	world.audio_enabled = true
	add_child_autofree(world)
	world.build_world()
	world.configure_audio(_resources(), PackedInt32Array([1, 2]))
	world.accept_state(_state(0))
	var state: GameplayState = _state(1)
	_voice(state, 4, 1, 3)
	world.accept_state(state)
	assert_true(world.voice_view().players[4].playing)
	world.collapse_effects()
	assert_false(world.voice_view().players[4].playing)
	assert_false(world.music_player().is_playing())

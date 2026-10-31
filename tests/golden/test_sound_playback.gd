extends GutTest
## Pitch, distance volume and pan, PCM slices, loop modes and voice diffs against tests/golden/synthetic/sound_playback.json.

const PCM_ERRORS: Dictionary[String, String] = {"absent": "no PCM", "span": "exceeds", "partial": "partial sample"}

var _facts: Dictionary = {}

func before_all() -> void:
	_facts = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/sound_playback.json"))

func _vector(value: Variant) -> Vector3i:
	var values: Array = value
	var x: int = values[0]
	var y: int = values[1]
	var z: int = values[2]
	return Vector3i(x, y, z)

func _digest(values: Array[int]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value: int in values:
		parts.append(str(value))
	return ",".join(parts).sha256_text()

func _definition(row: Dictionary) -> LogicalSoundDefinition:
	var definition := LogicalSoundDefinition.new()
	var minimum: int = row.min_volume
	var maximum: int = row.max_volume
	definition.minimum_volume = minimum
	definition.maximum_volume = maximum
	return definition

func _body(pcm: Dictionary) -> PackedByteArray:
	var size: int = pcm.body_size
	var body := PackedByteArray()
	body.resize(size)
	var values: Array[int] = []
	for index: int in size:
		body[index] = (index * 73 + 41) & 255
		values.append(body[index])
	assert_eq(_digest(values), str(pcm.body_digest), "body rule")
	return body

func test_pitch_scale_matches_native_steps() -> void:
	var reference: Dictionary = _facts.reference
	var reference_rate: int = reference.reference_rate
	var mix_rate: int = reference.mix_rate
	assert_eq(AudioResources.MIX_RATE, reference_rate)
	assert_eq(AudioResources.OUTPUT_RATE, mix_rate)
	for row: Dictionary in _facts.pitch:
		var note: int = row.note
		var fine: int = row.fine
		var bend: int = row.bend
		var step: int = row.step_16
		var exact: float = row.pitch_scale
		var observed: float = AudioResources.pitch_scale(note, fine, bend)
		var label: String = "note %d fine %d bend %d" % [note, fine, bend]
		assert_almost_eq(observed, float(step) * float(mix_rate) / (65536.0 * float(reference_rate)), 1e-12, label)
		assert_almost_eq(observed, exact, 7e-5 * maxf(1.0, exact), label)

func test_distance_volume_and_pan() -> void:
	for row: Dictionary in _facts.volume:
		var definition: LogicalSoundDefinition = _definition(row)
		var left: int = row.left
		var right: int = row.right
		var fixed: bool = row.get("fixed", false)
		if fixed:
			assert_eq(AudioResources.fixed_volumes(definition), Vector2i(left, right))
			continue
		var moving := LogicalMovingSound.new()
		moving.position = _vector(row.source)
		var near_radius: int = row.min_radius
		var far_radius: int = row.max_radius
		moving.near_radius = near_radius
		moving.far_radius = far_radius
		var listener: Vector3i = _vector(row.listener)
		var matrix_values: Array = row.matrix
		var matrix := PackedInt32Array()
		for value: int in matrix_values:
			matrix.append(value)
		var label: String = "source %s listener %s" % [moving.position, listener]
		var radius: int = AudioResources.radius(moving.position - listener)
		var expected_radius: int = row.radius
		var expected_volume: int = row.volume_12
		assert_eq(radius, expected_radius, label)
		assert_eq(AudioResources.fade_volume(definition, radius, near_radius, far_radius), expected_volume, label)
		assert_eq(AudioResources.moving_volumes(definition, moving, listener, matrix), Vector2i(left, right), label)

func test_pcm_slices() -> void:
	var pcm_facts: Dictionary = _facts.pcm
	var body: PackedByteArray = _body(pcm_facts)
	for row: Dictionary in pcm_facts.rows:
		var entry := SoundBankEntry.new()
		var present: bool = row.present
		var offset: int = row.offset
		var size: int = row.size
		var bits: int = row.bits
		entry.sound_id = 7
		entry.audio_present = present
		entry.data_offset = offset
		entry.data_size = size
		entry.sample_bits = bits
		entry.sample_rate = 11025
		var pcm: SoundBankPcm = SoundBankPcm.slice(entry, body)
		var label: String = "offset %d size %d bits %d" % [offset, size, bits]
		var error: String = row.error
		if not error.is_empty():
			assert_string_contains(pcm.error, PCM_ERRORS[error], label)
			continue
		assert_eq(pcm.error, "", label)
		var frames: int = row.frames
		assert_eq(pcm.frame_count(), frames, label)
		var widened: PackedByteArray = pcm.to_signed_16()
		assert_eq(widened.size(), frames * 2, label)
		var samples: Array[int] = []
		for index: int in widened.size() >> 1:
			samples.append(widened.decode_s16(index * 2))
		var expected: Array = row.samples
		assert_eq(samples, Array(expected, TYPE_INT, "", null), label)
		assert_eq(_digest(samples), str(row.digest), label)

func test_loop_modes_follow_sample_flags() -> void:
	var reference: Dictionary = _facts.reference
	var reference_rate: int = reference.reference_rate
	for row: Dictionary in _facts.loop:
		var flags: int = row.flags
		var frames: int = row.frames
		var imported := AudioStreamWAV.new()
		imported.format = AudioStreamWAV.FORMAT_16_BITS
		imported.mix_rate = reference_rate
		var pcm := PackedByteArray()
		pcm.resize(frames * 2)
		imported.data = pcm
		var stream: AudioStreamWAV = AudioResources.imported_stream(imported, flags)
		var label: String = "flags %d frames %d" % [flags, frames]
		var loop: bool = row.loop
		assert_eq(stream.mix_rate, reference_rate, label)
		assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, label)
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED, label)
		if loop:
			var loop_begin: int = row.loop_begin
			var loop_end: int = row.loop_end
			assert_eq(stream.loop_begin, loop_begin, label)
			assert_eq(stream.loop_end, loop_end, label)

func _voice_resources(diff: Dictionary) -> AudioResources:
	var definitions: Array[LogicalSoundDefinition] = []
	var bank_of: Dictionary[int, int] = {}
	var header := SoundBankHeader.new()
	var pairs: Array = diff.sample_flags
	for pair: Array in pairs:
		var sound_id: int = pair[0]
		var flags: int = pair[1]
		var definition := LogicalSoundDefinition.new()
		definition.sound_id = sound_id
		definition.flags = flags
		definition.frame_count = 32
		definitions.append(definition)
		bank_of[sound_id] = 0
		var entry := SoundBankEntry.new()
		entry.sound_id = sound_id
		entry.audio_present = true
		entry.data_size = 64
		entry.sample_rate = 11025
		entry.sample_bits = 16
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 11025
		var body := PackedByteArray()
		body.resize(64)
		stream.data = body
		entry.stream = stream
		header.entries.append(entry)
	var bank := SoundBankSetup.new()
	bank.header = header
	var loader: Callable = func(_bank_id: int) -> SoundBankSetup:
		return bank
	return AudioResources.from_loader(definitions, bank_of, loader)

func _voice_state(resources: AudioResources, tick: int, voices: Array) -> GameplayState:
	var state := GameplayState.new()
	state.tick_index = tick
	state.sound = LogicalSoundState.new()
	for slot: int in SoundVoiceView.VOICES:
		state.sound.voices.append(LogicalSoundVoice.new())
	for row: Dictionary in voices:
		var slot: int = row.slot
		var voice: LogicalSoundVoice = state.sound.voices[slot]
		if row.sample != null:
			var sound_id: int = row.sample
			voice.sample = resources.definition_for(sound_id).copy()
		var identifier: int = row.identifier
		var note: int = row.note
		var fine: int = row.fine
		var pitch: int = row.pitch
		var playing: bool = row.playing
		var killed: bool = row.killed
		voice.identifier = identifier
		voice.note = note
		voice.fine = fine
		voice.pitch = pitch
		voice.playing = playing
		voice.killed = killed
	return state

func test_voice_diff_starts_bends_and_stops_players() -> void:
	var diff: Dictionary = _facts.voice_diff
	var resources: AudioResources = _voice_resources(diff)
	for sequence: Dictionary in diff.sequences:
		var view: SoundVoiceView = autofree(SoundVoiceView.new())
		view.configure(resources)
		var previous: GameplayState = null
		for step: Dictionary in sequence.steps:
			var tick: int = step.tick
			var before_rows: Array = step.before
			var after_rows: Array = step.after
			if previous == null:
				previous = _voice_state(resources, tick - 1, before_rows)
			var after: GameplayState = _voice_state(resources, tick, after_rows)
			var identifiers := PackedInt32Array()
			var scales := PackedFloat32Array()
			for slot: int in SoundVoiceView.VOICES:
				identifiers.append(view.identifier(slot))
				scales.append(view.players[slot].pitch_scale)
			view.accept_state(previous, after)
			var acted: Dictionary[int, bool] = {}
			for action: Dictionary in step.actions:
				var slot: int = action.slot
				var kind: String = action.action
				var label: String = "%s tick %d slot %d %s" % [sequence.name, tick, slot, kind]
				acted[slot] = true
				if kind == "start" or kind == "bend":
					var note: int = action.note
					var fine: int = action.fine
					var pitch: int = action.pitch
					assert_almost_eq(view.players[slot].pitch_scale, AudioResources.pitch_scale(note, fine, pitch), 1e-6, label)
				if kind == "start":
					var identifier: int = action.identifier
					assert_eq(view.identifier(slot), identifier, label)
				elif kind == "bend":
					assert_eq(view.identifier(slot), identifiers[slot], label)
				else:
					assert_eq(view.identifier(slot), 0, label)
			for slot: int in SoundVoiceView.VOICES:
				if not acted.has(slot):
					var label: String = "%s tick %d slot %d unchanged" % [sequence.name, tick, slot]
					assert_eq(view.identifier(slot), identifiers[slot], label)
					assert_almost_eq(view.players[slot].pitch_scale, scales[slot], 1e-6, label)
			previous = after

extends GutTest
## AudioResources streams, pitch, fade, pan and gain on synthetic banks and definitions.

func _definition(sound_id: int, flags: int, minimum: int = 20, maximum: int = 100) -> LogicalSoundDefinition:
	var definition := LogicalSoundDefinition.new()
	definition.sound_id = sound_id
	definition.flags = flags
	definition.frame_count = 2
	definition.minimum_volume = minimum
	definition.maximum_volume = maximum
	return definition

func _row(sound_id: int, present: bool, offset: int, size: int, bits: int) -> SoundBankEntry:
	var entry := SoundBankEntry.new()
	entry.sound_id = sound_id
	entry.audio_present = present
	entry.data_offset = offset
	entry.data_size = size
	entry.sample_rate = 22050
	entry.sample_bits = bits
	return entry

func _bank() -> SoundBankSetup:
	var bank := SoundBankSetup.new()
	bank.header = SoundBankHeader.new()
	bank.header.entries.append(_row(0, false, 0, 0, 16))
	bank.header.entries.append(_row(1, true, 0, 4, 16))
	bank.header.entries.append(_row(2, true, 4, 2, 8))
	bank.header.entries.append(_row(3, false, 0, 0, 16))
	bank.body = PackedByteArray([1, 2, 3, 4, 0, 255])
	return bank

func _moving(position: Vector3i) -> LogicalMovingSound:
	var moving := LogicalMovingSound.new()
	moving.near_radius = 1792
	moving.far_radius = 7168
	moving.position = position
	return moving

func _resources(calls: Array[int]) -> AudioResources:
	var definitions: Array[LogicalSoundDefinition] = [
		_definition(1, LogicalSoundDefinition.LOOPED),
		_definition(2, LogicalSoundDefinition.SINGLE),
		_definition(3, LogicalSoundDefinition.REPEAT),
		_definition(4, LogicalSoundDefinition.SINGLE),
	]
	var bank_of: Dictionary[int, int] = {1: 0, 2: 0, 3: 0, 4: 9}
	var loader: Callable = func(bank_id: int) -> SoundBankSetup:
		calls.append(bank_id)
		return _bank() if bank_id == 0 else null
	return AudioResources.from_loader(definitions, bank_of, loader)

func test_streams_are_built_lazily_once_per_bank() -> void:
	var calls: Array[int] = []
	var resources: AudioResources = _resources(calls)
	assert_eq(calls.size(), 0)
	var looped: AudioStreamWAV = resources.stream_for(1)
	var single: AudioStreamWAV = resources.stream_for(2)
	assert_eq(PackedInt32Array(calls), PackedInt32Array([0]))
	assert_same(resources.stream_for(1), looped)
	assert_eq(looped.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_false(looped.stereo)
	assert_eq(looped.mix_rate, 11025)
	assert_eq(looped.data, PackedByteArray([1, 2, 3, 4]))
	assert_eq(looped.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(looped.loop_begin, 0)
	assert_eq(looped.loop_end, 2)
	assert_eq(single.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	assert_eq(single.data.decode_s16(0), -32768)
	assert_eq(single.data.decode_s16(2), 32512)
	assert_eq(resources.diagnostics.size(), 0)

func test_repeat_samples_loop_like_looped_samples() -> void:
	var pcm := SoundBankPcm.new()
	pcm.sample_bits = 16
	pcm.bytes = PackedByteArray([0, 0, 1, 0, 2, 0])
	var stream: AudioStreamWAV = AudioResources.build_stream(pcm, LogicalSoundDefinition.REPEAT)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(stream.loop_end, 3)

func test_missing_samples_report_one_diagnostic_each() -> void:
	var calls: Array[int] = []
	var resources: AudioResources = _resources(calls)
	assert_null(resources.stream_for(3))
	assert_null(resources.stream_for(3))
	assert_null(resources.stream_for(4))
	assert_null(resources.stream_for(5))
	assert_eq(resources.diagnostics.size(), 3)
	assert_eq(PackedInt32Array(calls), PackedInt32Array([0, 9]))
	assert_null(AudioResources.from_data(null, []).stream_for(1))

func test_pitch_scale_matches_the_native_step() -> void:
	assert_almost_eq(AudioResources.pitch_scale(60, 0, 64), 1.0, 0.000001)
	assert_almost_eq(AudioResources.pitch_scale(72, 0, 64), 2.0, 0.000001)
	assert_almost_eq(AudioResources.pitch_scale(48, 0, 64), 0.5, 0.000001)
	assert_almost_eq(AudioResources.pitch_scale(60, 64, 64), roundi(16384.0 * pow(2.0, 0.5 / 12.0)) / 16384.0, 0.000001)
	assert_almost_eq(AudioResources.pitch_scale(60, 0, 0), roundi(16384.0 * pow(2.0, -2.0 / 12.0)) / 16384.0, 0.000001)
	assert_almost_eq(AudioResources.pitch_scale(60, 0, 127), roundi(16384.0 * pow(2.0, 63.0 / 64.0 * 2.0 / 12.0)) / 16384.0, 0.000001)

func test_fixed_voices_use_the_maximum_volume() -> void:
	assert_eq(AudioResources.fixed_volumes(_definition(1, LogicalSoundDefinition.SINGLE, 20, 90)), Vector2i(90, 90))

func test_moving_fade_runs_from_maximum_to_minimum() -> void:
	var definition := _definition(1, LogicalSoundDefinition.LOOPED)
	assert_eq(AudioResources.fade_volume(definition, 0, 1792, 7168), 3200)
	assert_eq(AudioResources.fade_volume(definition, 1792, 1792, 7168), 3200)
	assert_eq(AudioResources.fade_volume(definition, 4480, 1792, 7168), 1390)
	assert_eq(AudioResources.fade_volume(definition, 7168, 1792, 7168), 640)
	assert_eq(AudioResources.fade_volume(definition, 9000, 1792, 7168), 640)

func test_moving_pan_follows_the_listener_rotation() -> void:
	var definition := _definition(1, LogicalSoundDefinition.LOOPED)
	var listener := Vector3i(100, 0, 100)
	assert_eq(AudioResources.moving_volumes(definition, _moving(listener + Vector3i(0, 0, 1000)), listener), Vector2i(49, 50))
	assert_eq(AudioResources.moving_volumes(definition, _moving(listener + Vector3i(-1000, 0, 0)), listener), Vector2i(99, 0))
	assert_eq(AudioResources.moving_volumes(definition, _moving(listener + Vector3i(9000, 0, 0)), listener), Vector2i(0, 19))
	var turned := PackedInt32Array([-4096, 0, 0, 0, 4096, 0, 0, 0, -4096, 0, 0, 0])
	assert_eq(AudioResources.moving_volumes(definition, _moving(listener + Vector3i(1000, 0, 0)), listener, turned), Vector2i(99, 0))
	assert_eq(AudioResources.moving_volumes(definition, _moving(listener), listener), Vector2i(49, 50))

func test_radius_keeps_the_sixteen_bit_store() -> void:
	assert_eq(AudioResources.radius(Vector3i(0, 0, 4480)), 4480)
	assert_eq(AudioResources.radius(Vector3i(30, 40, 0)), 32)
	assert_eq(AudioResources.radius(Vector3i(0, 0, 70000)), 4464)

func test_gain_applies_effect_volume_and_mixer_scale() -> void:
	assert_almost_eq(AudioResources.gain(127, 127), 126.0 / 127.0, 0.000001)
	assert_almost_eq(AudioResources.gain(100), 61.0 / 127.0, 0.000001)
	assert_eq(AudioResources.gain(0), 0.0)

func test_definition_copy_carries_volumes() -> void:
	var copied: LogicalSoundDefinition = _definition(1, LogicalSoundDefinition.SINGLE, 12, 34).copy()
	assert_eq(copied.minimum_volume, 12)
	assert_eq(copied.maximum_volume, 34)

func test_music_stream_wraps_stereo_pcm() -> void:
	var pcm := PackedByteArray()
	pcm.resize(2352)
	var stream: AudioStreamWAV = AudioResources.music_stream(pcm, true)
	assert_true(stream.stereo)
	assert_eq(stream.mix_rate, 44100)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(stream.loop_end, 588)
	assert_eq(AudioResources.music_stream(pcm, false).loop_mode, AudioStreamWAV.LOOP_DISABLED)

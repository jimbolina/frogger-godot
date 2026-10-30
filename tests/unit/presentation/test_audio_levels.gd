extends GutTest
## Volume steps become the 127-scaled levels, the music bus gain and the effect volume.

var _music_db: float
var _music_mute: bool
var _sfx_db: float
var _sfx_mute: bool


func before_each() -> void:
	var music: int = SoundVoiceView.ensure_bus(MusicPlayer.BUS, &"Master")
	var sfx: int = SoundVoiceView.ensure_bus(SoundVoiceView.BUS, &"Master")
	_music_db = AudioServer.get_bus_volume_db(music)
	_music_mute = AudioServer.is_bus_mute(music)
	_sfx_db = AudioServer.get_bus_volume_db(sfx)
	_sfx_mute = AudioServer.is_bus_mute(sfx)


func after_each() -> void:
	var music: int = AudioServer.get_bus_index(MusicPlayer.BUS)
	var sfx: int = AudioServer.get_bus_index(SoundVoiceView.BUS)
	AudioServer.set_bus_volume_db(music, _music_db)
	AudioServer.set_bus_mute(music, _music_mute)
	AudioServer.set_bus_volume_db(sfx, _sfx_db)
	AudioServer.set_bus_mute(sfx, _sfx_mute)


func test_levels_follow_the_options_formula() -> void:
	var expected: Array[int] = [0, 15, 31, 47, 63, 79, 95, 111, 127]
	for step: int in expected.size():
		assert_eq(AudioLevels.level(step), expected[step], "step %d" % step)
	assert_eq(AudioLevels.level(-1), 0, "clamped below")
	assert_eq(AudioLevels.level(9), 127, "clamped above")
	assert_eq(AudioLevels.effect_volume(ProgressStore.DEFAULT_SOUND_VOLUME), AudioResources.DEFAULT_EFFECT_VOLUME,
		"the default effects step keeps the previous effect volume")


func test_music_gain_is_the_level_over_127_and_step_zero_is_silent() -> void:
	assert_eq(AudioLevels.music_db(0), SoundVoiceView.SILENT_DB)
	assert_almost_eq(AudioLevels.music_db(8), 0.0, 0.0001)
	assert_almost_eq(db_to_linear(AudioLevels.music_db(3)), 47.0 / 127.0, 0.0001)


func test_apply_sets_the_buses_and_the_voice_effect_volume() -> void:
	var voices := SoundVoiceView.new()
	autofree(voices)
	AudioLevels.apply(4, 2, voices)
	var music: int = AudioServer.get_bus_index(MusicPlayer.BUS)
	var sfx: int = AudioServer.get_bus_index(SoundVoiceView.BUS)
	assert_almost_eq(AudioServer.get_bus_volume_db(music), linear_to_db(63.0 / 127.0), 0.0001)
	assert_false(AudioServer.is_bus_mute(music))
	assert_almost_eq(AudioServer.get_bus_volume_db(sfx), 0.0, 0.0001, "effects scale through the effect volume")
	assert_eq(voices.effect_volume, 31)
	AudioLevels.apply(0, 0, voices)
	assert_true(AudioServer.is_bus_mute(music))
	assert_true(AudioServer.is_bus_mute(sfx))
	assert_eq(voices.effect_volume, 0)

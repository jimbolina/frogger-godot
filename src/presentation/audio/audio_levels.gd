class_name AudioLevels
extends RefCounted
## Applies the options page's music and effects volume steps to the audio buses.
##
## A step 0..[constant OptionsMenu.SOUND_STAGES] becomes the level [code]127 * step / 8[/code]
## that MRSNDSetVolumeLevel receives for MRSND_CD_VOLUME and MRSND_FX_VOLUME. The music level
## sets the [constant MusicPlayer.BUS] gain as a linear fraction of 127. The effects level is
## the effect volume every sound-effect level is scaled by ([method AudioResources.gain]), so
## it goes to [member SoundVoiceView.effect_volume] and the menu sound players while the
## [constant SoundVoiceView.BUS] bus stays at unity. Step 0 mutes its bus.


## The MRSNDSetVolumeLevel level, 0..127, of [param step] clamped to the volume steps.
static func level(step: int) -> int:
	return OptionsMenu.volume_level(clampi(step, 0, OptionsMenu.SOUND_STAGES))


## The music bus volume in decibels for [param step]; step 0 is [constant SoundVoiceView.SILENT_DB].
static func music_db(step: int) -> float:
	var value: int = level(step)
	if value <= 0:
		return SoundVoiceView.SILENT_DB
	return linear_to_db(float(value) / float(AudioResources.MAX_VOLUME_LEVEL))


## The effect volume, 0..127, sound effects play at for [param step].
static func effect_volume(step: int) -> int:
	return level(step)


## Sets the music bus to [param step], creating the bus when missing.
static func apply_music(step: int) -> void:
	var index: int = SoundVoiceView.ensure_bus(MusicPlayer.BUS, &"Master")
	AudioServer.set_bus_volume_db(index, music_db(step))
	AudioServer.set_bus_mute(index, level(step) == 0)


## Sets the effects bus to [param step] and, when given, [param voices]' effect volume.
static func apply_effects(step: int, voices: SoundVoiceView = null) -> void:
	var index: int = SoundVoiceView.ensure_bus(SoundVoiceView.BUS, &"Master")
	AudioServer.set_bus_volume_db(index, 0.0)
	AudioServer.set_bus_mute(index, level(step) == 0)
	if voices != null:
		voices.effect_volume = effect_volume(step)


## Applies both steps; [param voices] receives the effects level when given.
static func apply(music_step: int, effects_step: int, voices: SoundVoiceView = null) -> void:
	apply_music(music_step)
	apply_effects(effects_step, voices)

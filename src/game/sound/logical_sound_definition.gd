class_name LogicalSoundDefinition
extends RefCounted
## Detached sample lifetime and allocation facts resolved during application setup.

const SINGLE: int = 2
const REPEAT: int = 4
const LOOPED: int = 8

var sound_id: int = 0
var flags: int = SINGLE
var first_voice: int = 0
var last_voice: int = 4
var note: int = 60
var pitch_mod: int = 0
var frame_count: int = 0
var minimum_volume: int = 0
var maximum_volume: int = 127

## Checks facts needed before any allocation or RNG consumption.
func validate() -> String:
	if sound_id < 0 or flags not in [SINGLE, REPEAT, LOOPED] or first_voice < 0 or last_voice >= 24 or first_voice > last_voice or note < 0 or note > 127 or pitch_mod < 0 or pitch_mod > 65535 or frame_count <= 0:
		return "Invalid logical sound definition"
	return ""

## Detaches the application's supplied metadata.
func copy() -> LogicalSoundDefinition:
	var result := LogicalSoundDefinition.new()
	result.sound_id = sound_id
	result.flags = flags
	result.first_voice = first_voice
	result.last_voice = last_voice
	result.note = note
	result.pitch_mod = pitch_mod
	result.frame_count = frame_count
	result.minimum_volume = minimum_volume
	result.maximum_volume = maximum_volume
	return result

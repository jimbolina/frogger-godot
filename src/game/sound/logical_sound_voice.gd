class_name LogicalSoundVoice
extends RefCounted
## One source voice slot and frozen backend sample cursor, independent of speakers.

var sample: LogicalSoundDefinition = null
var identifier: int = 0
var initialising: bool = false
var moving_owner: int = -1
var note: int = 60
var fine: int = 0
var pitch: int = 64
var cursor_16: int = 0
var base_step_16: int = 16384
var step_16: int = 16384
var playing: bool = false
var killed: bool = false

## Starts or retriggers the sample without allocating a new source voice identifier.
func key_on() -> void:
	cursor_16 = 0
	base_step_16 = maxi(1, roundi(11025.0 * pow(2.0, (float(note - 60) + float(fine) / 128.0) / 12.0) * 65536.0 / 44100.0))
	bend(64)
	playing = true

## Applies the frozen backend's bounded two-semitone pitch bend to future samples.
func bend(value: int) -> void:
	pitch = clampi(value, 0, 127)
	step_16 = base_step_16 if pitch == 64 else maxi(1, roundi(float(base_step_16) * pow(2.0, float(pitch - 64) / 64.0 * 2.0 / 12.0)))

## Advances exactly the native quantum; exhausted samples become off before the next read.
func advance(output_frames: int) -> void:
	if not playing or sample == null:
		return
	var limit: int = sample.frame_count << 16
	if sample.flags == LogicalSoundDefinition.LOOPED:
		cursor_16 = (cursor_16 + step_16 * output_frames) % limit
		return
	for index: int in output_frames:
		if cursor_16 >= limit:
			playing = false
			break
		cursor_16 += step_16

## Copies logical playback independently of the preceding committed tick.
func copy() -> LogicalSoundVoice:
	var result := LogicalSoundVoice.new()
	result.sample = sample.copy() if sample != null else null
	result.identifier = identifier
	result.initialising = initialising
	result.moving_owner = moving_owner
	result.note = note
	result.fine = fine
	result.pitch = pitch
	result.cursor_16 = cursor_16
	result.base_step_16 = base_step_16
	result.step_16 = step_16
	result.playing = playing
	result.killed = killed
	return result

class_name SoundBankEntry
extends RefCounted
## One Windows sound header row, retaining its global sound identity and byte span.

var sound_id: int = 0
var source_offset: int = 0
var audio_present: bool = false
var data_offset: int = 0
var data_size: int = 0
var sample_rate: int = 0
var sample_bits: int = 0

## Number of mono PCM frames represented by the validated body span.
func frame_count() -> int:
	return data_size / (sample_bits / 8)

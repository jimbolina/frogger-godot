class_name SoundBankEntry
extends Resource
## One Windows sound header row, retaining its global sound identity and byte span.

@export var sound_id: int = 0
@export var source_offset: int = 0
@export var audio_present: bool = false
@export var data_offset: int = 0
@export var data_size: int = 0
@export var sample_rate: int = 0
@export var sample_bits: int = 0
## The imported audio for this row, or null until an importer supplies one.
@export var stream: AudioStream

## Number of mono PCM frames represented by the validated body span.
func frame_count() -> int:
	return data_size / (sample_bits / 8)

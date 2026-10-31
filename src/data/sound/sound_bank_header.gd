class_name SoundBankHeader
extends Resource
## FrogLord Windows sound-bank metadata; holds no PCM and no audio objects.

@export var entries: Array[SoundBankEntry] = []
@export var error: String = ""

## Decodes a v3.0e header; see [method SoundBankReader.read].
static func read(bytes: PackedByteArray, body_size: int, source_id: String = "") -> SoundBankHeader:
	return SoundBankReader.read(bytes, body_size, source_id)

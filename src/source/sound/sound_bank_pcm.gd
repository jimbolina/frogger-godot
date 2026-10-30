class_name SoundBankPcm
extends RefCounted
## Mono PCM bytes of one present Windows sound-bank row, sliced from the bank body.

var bytes: PackedByteArray = PackedByteArray()
var sample_bits: int = 0
var error: String = ""

## Slices [param entry]'s span from [param body], rejecting absent rows, unsupported depths and out-of-range spans.
static func slice(entry: SoundBankEntry, body: PackedByteArray) -> SoundBankPcm:
	var result := SoundBankPcm.new()
	if entry == null:
		result.error = "PCM slice requires a sound-bank row"
		return result
	if not entry.audio_present:
		result.error = "Sound %d has no PCM in its bank" % entry.sound_id
		return result
	if entry.sample_bits not in [8, 16]:
		result.error = "Sound %d has unsupported %d-bit PCM" % [entry.sound_id, entry.sample_bits]
		return result
	if entry.data_offset < 0 or entry.data_size <= 0 or entry.data_offset > body.size() or entry.data_size > body.size() - entry.data_offset:
		result.error = "Sound %d PCM span exceeds the %d-byte body" % [entry.sound_id, body.size()]
		return result
	if entry.data_size % (entry.sample_bits / 8) != 0:
		result.error = "Sound %d PCM span contains a partial sample" % entry.sound_id
		return result
	result.sample_bits = entry.sample_bits
	result.bytes = body.slice(entry.data_offset, entry.data_offset + entry.data_size)
	return result

## Number of mono frames held by the slice.
func frame_count() -> int:
	return 0 if sample_bits == 0 else bytes.size() / (sample_bits / 8)

## Returns the slice as signed 16-bit little-endian frames; unsigned 8-bit samples are recentred and widened.
func to_signed_16() -> PackedByteArray:
	if sample_bits == 16:
		return bytes.duplicate()
	var result := PackedByteArray()
	result.resize(bytes.size() * 2)
	for index: int in bytes.size():
		result.encode_s16(index * 2, (bytes[index] - 128) << 8)
	return result

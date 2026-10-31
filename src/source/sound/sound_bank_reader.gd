class_name SoundBankReader
extends RefCounted
## Decodes FrogLord Windows sound-bank headers into [SoundBankHeader]s; reads no PCM and creates no audio objects.

## Decodes a v3.0e header and validates present samples against the supplied body size.
static func read(bytes: PackedByteArray, body_size: int, source_id: String = "") -> SoundBankHeader:
	var result := SoundBankHeader.new()
	var reader := ByteReader.new(bytes)
	var count: int = reader.read_s32()
	if reader.has_error() or count < 0 or count > (bytes.size() - 4) / 28 or body_size < 0:
		result.error = "%s sound header at 0x0: invalid count or body size" % source_id
		return result
	for index: int in count:
		var entry := SoundBankEntry.new()
		entry.sound_id = index
		entry.source_offset = reader.get_position()
		entry.audio_present = reader.read_s32() == 1
		entry.data_offset = reader.read_s32()
		entry.data_size = reader.read_s32()
		var unknown_1: int = reader.read_s32()
		var unknown_2: int = reader.read_s32()
		entry.sample_rate = reader.read_s32()
		entry.sample_bits = reader.read_s32()
		var issue: String = ""
		if unknown_1 != 1 or unknown_2 != 1:
			issue = "reserved fields must both equal 1"
		elif entry.sample_rate <= 0 or entry.sample_bits not in [8, 16]:
			issue = "unsupported PCM sample format"
		elif entry.data_offset < 0 or entry.data_size < 0:
			issue = "negative PCM body span"
		elif entry.audio_present and (entry.data_offset > body_size or entry.data_size > body_size - entry.data_offset):
			issue = "PCM span exceeds supplied body"
		elif entry.audio_present and entry.data_size % (entry.sample_bits / 8) != 0:
			issue = "PCM span contains a partial sample"
		if not issue.is_empty():
			result.error = "%s sound %d at 0x%X: %s" % [source_id, index, entry.source_offset, issue]
			return result
		result.entries.append(entry)
	return result

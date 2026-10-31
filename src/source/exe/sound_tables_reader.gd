class_name SoundTablesReader
extends RefCounted
## Reads the v3.0e sound tables ([SoundTables]) at the addresses the executable's
## sound-initialization arguments name.


## Reads original or saved table contents, including PC-specific 32-byte sample rows.
static func read(exe: ExeImage) -> SoundTables:
	var result := SoundTables.new()
	if exe == null or exe.version.internal_name != "pc-retail-v3.0e":
		result.error = "Sound tables are unverified for this build"
		return result
	var reader: ByteReader = exe.reader_at_pointer(SoundTables.BANK_ADDRESS)
	for index: int in 12:
		var header_id: int = reader.read_s32()
		var body_id: int = reader.read_s32()
		reader.skip(4)
		result.banks.append(Vector2i(header_id, body_id))
	if reader.has_error():
		result.error = "Sound banks at 0x%X: %s" % [SoundTables.BANK_ADDRESS, reader.error]
		return result
	reader = exe.reader_at_pointer(SoundTables.GROUP_ADDRESS)
	for index: int in 4:
		var first: int = reader.read_s16()
		var last: int = reader.read_s16()
		if first < 0 or last >= 24 or first > last:
			result.error = "Sound group %d at 0x%X has invalid voice bounds" % [index, SoundTables.GROUP_ADDRESS + index * 4]
			return result
		result.groups.append(Vector2i(first, last))
	if reader.has_error():
		result.error = "Sound groups at 0x%X: %s" % [SoundTables.GROUP_ADDRESS, reader.error]
		return result
	reader = exe.reader_at_pointer(SoundTables.SAMPLE_ADDRESS)
	for index: int in 174:
		var sample := SoundSampleEntry.new()
		sample.sound_id = index
		sample.flags = reader.read_u32()
		sample.bank_id = reader.read_u16()
		sample.group_id = reader.read_u16()
		sample.program = reader.read_u16()
		sample.tone = reader.read_u16()
		sample.note = reader.read_u16()
		sample.pitch_mod = reader.read_u16()
		sample.minimum_volume = reader.read_u16()
		sample.maximum_volume = reader.read_u16()
		reader.skip(12)
		if reader.has_error():
			result.error = "Sound sample %d at 0x%X: %s" % [index, SoundTables.SAMPLE_ADDRESS + index * 32, reader.error]
			return result
		if sample.bank_id >= result.banks.size() or sample.group_id >= result.groups.size() or sample.flags not in [2, 4, 8] or sample.note > 127:
			result.error = "Sound sample %d at 0x%X has unsupported metadata" % [index, SoundTables.SAMPLE_ADDRESS + index * 32]
			return result
		result.samples.append(sample)
	reader = exe.reader_at_pointer(SoundTables.MUSIC_PITCH_ADDRESS)
	for index: int in 60:
		var checkpoint_pitch: int = reader.read_s32()
		var completion_pitch: int = reader.read_s32()
		result.music_pitches.append(Vector2i(checkpoint_pitch, completion_pitch))
	if reader.has_error():
		result.error = "Music pitch table at 0x%X: %s" % [SoundTables.MUSIC_PITCH_ADDRESS, reader.error]
	return result

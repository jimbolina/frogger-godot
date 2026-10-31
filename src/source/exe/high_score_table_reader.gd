class_name HighScoreTableReader
extends RefCounted
## Reads the v3.0e default high-score tables ([HighScoreTable]) from the executable.


## Reads both tables from [param exe]; only the v3.0e layout is verified.
static func read(exe: ExeImage) -> HighScoreTable:
	var result := HighScoreTable.new()
	if exe.version.internal_name != "pc-retail-v3.0e":
		result.error = "high-score tables are unverified for this build"
		return result
	result.error = _read_rows(exe, HighScoreTable.MAIN_POINTER, HighScoreTable.MAIN_COUNT, "Game_high_score",
			result.main_initials, result.main_scores, result.main_times)
	if result.error.is_empty():
		result.error = _read_rows(exe, HighScoreTable.LEVEL_POINTER,
				HighScoreTable.LEVEL_COUNT * HighScoreTable.LEVEL_RANKS, "Level_high_scores",
				result.level_initials, result.level_scores, result.level_times)
	return result


static func _read_rows(exe: ExeImage, pointer: int, count: int, label: String,
		initials: PackedStringArray, scores: PackedInt32Array, times: PackedInt32Array) -> String:
	var reader: ByteReader = exe.reader_at_pointer(pointer)
	for index: int in count:
		var letters: String = ""
		for letter: int in HighScoreTable.INITIALS_LENGTH:
			var byte: int = reader.read_u8()
			letters += String.chr(byte if byte != 0 else 0x20)
		reader.skip(1)
		initials.append(letters)
		scores.append(reader.read_s32())
		for checkpoint: int in HighScoreTable.TIMES_PER_ROW:
			times.append(reader.read_u16())
		reader.skip(2)
		if reader.has_error():
			return "%s[%d] at 0x%X: %s" % [label, index, pointer + index * HighScoreTable.ENTRY_SIZE, reader.error]
	return ""

class_name HighScoreTable
extends RefCounted
## The v3.0e default high-score tables: the ten main-table rows and three rows for each of the 60 levels.
##
## Each record is [code]HIGH_SCORE_ENTRY[/code] from HSView.h: four initial
## bytes (three letters and a zero), a 32-bit score and five 16-bit
## checkpoint times in whole seconds, padded to 20 bytes. Initials keep their bytes
## as read, so the original's [code]'Z'+1[/code] stays [code][[/code]; only a
## zero byte, which Godot strings cannot hold, becomes a space. Level
## rows are indexed [code]level * 3 + rank[/code] with level ids in
## LIBRARY.H order; times are indexed [code]row * 5 + checkpoint[/code].

## In-program address of [code]Game_high_score[/code].
const MAIN_POINTER: int = 0x477400
## In-program address of [code]Level_high_scores[/code].
const LEVEL_POINTER: int = 0x4774c8
## Rows in the main table.
const MAIN_COUNT: int = 10
## Levels in the per-level table.
const LEVEL_COUNT: int = 60
## Rows kept for each level.
const LEVEL_RANKS: int = 3
## Checkpoint times in each row.
const TIMES_PER_ROW: int = 5
## Letters in each row's initials.
const INITIALS_LENGTH: int = 3
## Bytes in each record.
const ENTRY_SIZE: int = 20

## Main-table initials, best first.
var main_initials: PackedStringArray = PackedStringArray()
## Main-table scores, best first.
var main_scores: PackedInt32Array = PackedInt32Array()
## Main-table checkpoint times, five per row.
var main_times: PackedInt32Array = PackedInt32Array()
## Per-level initials, index [code]level * 3 + rank[/code].
var level_initials: PackedStringArray = PackedStringArray()
## Per-level scores, index [code]level * 3 + rank[/code].
var level_scores: PackedInt32Array = PackedInt32Array()
## Per-level checkpoint times, five per row.
var level_times: PackedInt32Array = PackedInt32Array()
## Why the tables could not be read, or "".
var error: String = ""


## Reads both tables from [param exe]; only the v3.0e layout is verified.
static func read(exe: ExeImage) -> HighScoreTable:
	var result := HighScoreTable.new()
	if exe.version.internal_name != "pc-retail-v3.0e":
		result.error = "high-score tables are unverified for this build"
		return result
	result.error = _read_rows(exe, MAIN_POINTER, MAIN_COUNT, "Game_high_score",
			result.main_initials, result.main_scores, result.main_times)
	if result.error.is_empty():
		result.error = _read_rows(exe, LEVEL_POINTER, LEVEL_COUNT * LEVEL_RANKS, "Level_high_scores",
				result.level_initials, result.level_scores, result.level_times)
	return result


static func _read_rows(exe: ExeImage, pointer: int, count: int, label: String,
		initials: PackedStringArray, scores: PackedInt32Array, times: PackedInt32Array) -> String:
	var reader: ByteReader = exe.reader_at_pointer(pointer)
	for index: int in count:
		var letters: String = ""
		for letter: int in INITIALS_LENGTH:
			var byte: int = reader.read_u8()
			letters += String.chr(byte if byte != 0 else 0x20)
		reader.skip(1)
		initials.append(letters)
		scores.append(reader.read_s32())
		for checkpoint: int in TIMES_PER_ROW:
			times.append(reader.read_u16())
		reader.skip(2)
		if reader.has_error():
			return "%s[%d] at 0x%X: %s" % [label, index, pointer + index * ENTRY_SIZE, reader.error]
	return ""

extends GutTest
## HighScoreTable on a small synthetic executable laid out like v3.0e (no game files needed).

const BASE: int = 0x400
const RAM: int = HighScoreTable.MAIN_POINTER - BASE


func _exe(size: int = 0x1400) -> SyntheticExe:
	var s := SyntheticExe.new(size)
	s.version.internal_name = "pc-retail-v3.0e"
	s.version.ram_offset = RAM
	return s


func _entry(s: SyntheticExe, row: int, initials: PackedByteArray, score: int, times: Array[int]) -> void:
	var at: int = BASE + row * HighScoreTable.ENTRY_SIZE
	s.put(at, initials)
	s.u32(at + 4, score)
	s.s16s(at + 8, times)


func test_reads_main_then_level_rows_and_keeps_initial_bytes() -> void:
	var s := _exe()
	for row: int in 190:
		_entry(s, row, PackedByteArray([0x41, 0x41, 0x41, 0]), 0, [0, 0, 0, 0, 0])
	_entry(s, 0, PackedByteArray([0x54, 0x49, 0x4d, 0]), 250000, [0, 0, 0, 0, 0])
	_entry(s, 1, PackedByteArray([0x4d, 0x5b, 0x42, 0]), 225000, [1, 2, 3, 4, 5])
	_entry(s, 10, PackedByteArray([0x4b, 0x45, 0x56, 0]), 4000, [60, 60, 60, 60, 60])
	_entry(s, 10 + 19 * 3 + 2, PackedByteArray([0x4e, 0x45, 0x20, 0]), 64, [754, 0, 0, 0, 0])
	var table: HighScoreTable = HighScoreTable.read(s.image())
	assert_eq(table.error, "")
	assert_eq(table.main_initials.size(), 10)
	assert_eq(table.main_scores.size(), 10)
	assert_eq(table.main_times.size(), 50)
	assert_eq(table.level_initials.size(), 180)
	assert_eq(table.level_scores.size(), 180)
	assert_eq(table.level_times.size(), 900)
	assert_eq(table.main_initials[0], "TIM")
	assert_eq(table.main_initials[1], "M[B")
	assert_eq(table.main_scores[1], 225000)
	assert_eq(table.main_times.slice(5, 10), PackedInt32Array([1, 2, 3, 4, 5]))
	assert_eq(table.level_initials[0], "KEV")
	assert_eq(table.level_times.slice(0, 5), PackedInt32Array([60, 60, 60, 60, 60]))
	assert_eq(table.level_initials[19 * 3 + 2], "NE ")
	assert_eq(table.level_scores[19 * 3 + 2], 64)
	assert_eq(table.level_times[(19 * 3 + 2) * 5], 754)


func test_level_table_follows_the_main_table() -> void:
	assert_eq(HighScoreTable.MAIN_POINTER + HighScoreTable.MAIN_COUNT * HighScoreTable.ENTRY_SIZE,
			HighScoreTable.LEVEL_POINTER)


func test_zero_initial_bytes_become_spaces() -> void:
	var s := _exe()
	_entry(s, 0, PackedByteArray([0x41, 0, 0x42, 0]), 1, [0, 0, 0, 0, 0])
	for row: int in range(1, 190):
		_entry(s, row, PackedByteArray([0x41, 0x41, 0x41, 0]), 0, [0, 0, 0, 0, 0])
	var table: HighScoreTable = HighScoreTable.read(s.image())
	assert_eq(table.error, "")
	assert_eq(table.main_initials[0], "A B")


func test_other_builds_are_unverified() -> void:
	var s := _exe()
	s.version.internal_name = "pc-retail-v1.0"
	var table: HighScoreTable = HighScoreTable.read(s.image())
	assert_string_contains(table.error, "unverified")
	assert_eq(table.main_scores.size(), 0)


func test_short_program_names_the_table_and_address() -> void:
	var s := _exe(BASE + 10 * HighScoreTable.ENTRY_SIZE + 3 * HighScoreTable.ENTRY_SIZE)
	var table: HighScoreTable = HighScoreTable.read(s.image())
	assert_string_contains(table.error, "Level_high_scores[3] at 0x%X" % (HighScoreTable.LEVEL_POINTER + 60))


func test_exe_tables_reads_once_and_reports_problems() -> void:
	var s := _exe(0x800)
	var tables := ExeTables.new(s.image(), null, null)
	assert_same(tables.high_scores(), tables.high_scores())
	assert_string_contains(tables.high_scores().error, "Level_high_scores")

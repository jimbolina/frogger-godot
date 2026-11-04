extends RetailTest
## Needs the retail files: the default high-score tables read from FROGGER.EXE match the
## independent facts in tests/golden/pc-retail-v3.0e/exe_high_scores.tsv
## (tools/golden/make_golden_high_scores.py, see tests/golden/specs/frontend.md).

var _data: GameData
var _table: HighScoreTable
var _rows: Array[PackedStringArray] = []


func before_all() -> void:
	if not retail_skip_reason().is_empty():
		return
	var version: GameVersionConfig = FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e")
	_data = GameData.open(retail_source(), version)
	_table = _data.tables.high_scores()
	_rows = GoldenFiles.rows("exe_high_scores.tsv")


func after_all() -> void:
	if _data != null:
		_data.close()


func _kind(kind: String) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	for row: PackedStringArray in _rows:
		if row[0] == kind:
			result.append(row)
	return result


func _encoded(initials: String) -> String:
	var out: String = ""
	for index: int in initials.length():
		var code: int = initials.unicode_at(index)
		out += initials[index] if code >= 0x21 and code <= 0x7e and code != 0x5c else "\\x%02x" % code
	return out


func _entry(table: String, level: int, rank: int, initials: String, score: int,
		times: PackedInt32Array, first_time: int) -> PackedStringArray:
	var row: PackedStringArray = ["entry", table, str(level), str(rank), _encoded(initials), str(score)]
	for checkpoint: int in HighScoreTable.TIMES_PER_ROW:
		row.append(str(times[first_time + checkpoint]))
	return row


func test_every_row_matches_independent_facts() -> void:
	assert_eq(_table.error, "")
	var got: Array[PackedStringArray] = []
	for rank: int in _table.main_scores.size():
		got.append(_entry("main", -1, rank, _table.main_initials[rank], _table.main_scores[rank],
				_table.main_times, rank * HighScoreTable.TIMES_PER_ROW))
	for index: int in _table.level_scores.size():
		got.append(_entry("level", index / HighScoreTable.LEVEL_RANKS, index % HighScoreTable.LEVEL_RANKS,
				_table.level_initials[index], _table.level_scores[index], _table.level_times,
				index * HighScoreTable.TIMES_PER_ROW))
	var problems: PackedStringArray = GoldenFiles.differences("exe_high_scores.tsv", got, _kind("entry"))
	assert_eq(problems.size(), 0, "\n".join(problems))
	assert_eq(_table.main_times.size(), HighScoreTable.MAIN_COUNT * HighScoreTable.TIMES_PER_ROW)
	assert_eq(_table.level_times.size(),
			HighScoreTable.LEVEL_COUNT * HighScoreTable.LEVEL_RANKS * HighScoreTable.TIMES_PER_ROW)


func test_layout_facts_match_the_reader() -> void:
	var facts: Dictionary[String, String] = {}
	for row: PackedStringArray in _kind("fact"):
		facts[row[1]] = row[2]
	assert_eq(GoldenFiles.hex(HighScoreTable.MAIN_POINTER), facts["main_pointer"])
	assert_eq(GoldenFiles.hex(HighScoreTable.LEVEL_POINTER), facts["level_pointer"])
	assert_eq(str(HighScoreTable.MAIN_COUNT), facts["main_count"])
	assert_eq(str(HighScoreTable.LEVEL_COUNT), facts["level_count"])
	assert_eq(str(HighScoreTable.LEVEL_RANKS), facts["level_ranks"])
	assert_eq(str(HighScoreTable.ENTRY_SIZE), facts["entry_size"])
	assert_eq(str(HighScoreTable.TIMES_PER_ROW), facts["times_per_row"])


func test_retail_rows_that_differ_from_the_c_are_read_as_retail() -> void:
	var deviations: Array[PackedStringArray] = _kind("deviation")
	assert_eq(deviations.size(), 2)
	for row: PackedStringArray in deviations:
		var level: int = int(row[1])
		var retail: PackedStringArray = row[3].split(",")
		var original: PackedStringArray = row[4].split(",")
		for rank: int in HighScoreTable.LEVEL_RANKS:
			var initials: String = _table.level_initials[level * HighScoreTable.LEVEL_RANKS + rank]
			assert_eq(initials, retail[rank], "%s rank %d keeps the retail initials" % [row[2], rank])
		assert_ne(retail, original, "%s differs from HSView.c" % row[2])

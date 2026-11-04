extends GutTest
## HighScoreBoard and HighScoreText agree with the independent frozen-C high-score rules in
## tests/golden/synthetic/frontend_high_score_tables.json (tools/golden/make_golden_high_score_tables.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_high_score_tables.json"
const STARTUP_NAMES: Dictionary = {
	HighScoreBoard.Startup.ENTRY: "ENTRY",
	HighScoreBoard.Startup.NO_HIGH_SCORE: "NO_HIGH_SCORE",
	HighScoreBoard.Startup.GAME_QUIT: "GAME_QUIT",
}

var _document: Dictionary = {}


func before_all() -> void:
	_document = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))


static func _int(value: Variant) -> int:
	var number: float = value
	return int(number)


static func _bool(value: Variant) -> bool:
	var flag: bool = value
	return flag


static func _ints(values: Variant) -> PackedInt32Array:
	var items: Array = values
	var result := PackedInt32Array()
	for value: Variant in items:
		result.append(_int(value))
	return result


static func _row(values: Variant) -> HighScoreRow:
	var items: Array = values
	return HighScoreRow.create(str(items[0]), _int(items[1]), _ints(items[2]))


static func _rows(values: Variant) -> Array[HighScoreRow]:
	var items: Array = values
	var result: Array[HighScoreRow] = []
	for item: Variant in items:
		result.append(_row(item))
	return result


static func _row_values(row: HighScoreRow) -> Array:
	return [row.initials, row.score, Array(row.times)]


static func _golden_row_values(values: Variant) -> Array:
	var items: Array = values
	return [str(items[0]), _int(items[1]), Array(_ints(items[2]))]


func test_constants() -> void:
	var c: Dictionary = _document.constants
	assert_eq(HighScoreBoard.MAIN_COUNT, _int(c.main_rows))
	assert_eq(HighScoreBoard.LEVEL_COUNT, _int(c.levels))
	assert_eq(HighScoreBoard.LEVEL_RANKS, _int(c.level_ranks))
	assert_eq(HighScoreBoard.CHECKPOINT_COUNT, _int(c.checkpoints))
	assert_eq(HighScoreBoard.TICKS_PER_SECOND, _int(c.ticks_per_second))
	assert_eq(HighScoreBoard.SECONDS_LIMIT_TICKS, _int(c.seconds_limit_ticks))
	assert_eq(HighScoreBoard.SECONDS_LIMIT, _int(c.seconds_limit))
	assert_eq(HighScoreBoard.LEVEL_JUNGLE1, _int(c.level_jungle1))
	assert_eq(HighScoreBoard.LEVEL_JUNGLE2, _int(c.level_jungle2))
	assert_eq(HighScoreText.SCORE_DIGITS, _int(c.score_digits))
	assert_eq(HighScoreText.MINUTES_LIMIT, _int(c.minutes_limit))
	assert_eq(HighScoreText.SECONDS_AT_LIMIT, _int(c.seconds_at_limit))
	assert_eq(HighScoreBoard.redirect_level(_int(c.level_jungle2)), _int(c.level_jungle1))


func test_checkpoint_seconds() -> void:
	var cases: Array = _document.checkpoint_seconds
	assert_gt(cases.size(), 0)
	for item: Array in cases:
		assert_eq(HighScoreBoard.checkpoint_seconds(_int(item[0])), _int(item[1]), "%d ticks" % _int(item[0]))


func test_score_and_time_text() -> void:
	for item: Array in _document.score_text:
		assert_eq(HighScoreText.score_text(_int(item[0])), str(item[1]), "score %d" % _int(item[0]))
	for item: Array in _document.time_text:
		assert_eq(HighScoreText.time_text(_int(item[0])), str(item[1]), "time %d" % _int(item[0]))


func test_lines_follow_the_templates() -> void:
	var display: Dictionary = _document.display
	var prefix: String = display.prefix
	for template: String in _document.templates:
		assert_true(template.begins_with(prefix))
		assert_eq(template.length() - prefix.length(), _int(display.line_length))
	for item: Dictionary in _document.lines:
		var lines: PackedStringArray = HighScoreText.lines(_rows(item.rows))
		var expected: Array = item.lines
		assert_eq(lines, PackedStringArray(expected), str(item.name))
		for line: String in lines:
			assert_eq(line.length(), _int(display.line_length))


func test_scenarios() -> void:
	var scenarios: Array = _document.scenarios
	assert_gt(scenarios.size(), 0)
	for scenario: Dictionary in scenarios:
		_replay(scenario)


func _replay(scenario: Dictionary) -> void:
	var scenario_name: String = scenario.name
	var level_rows: Array[HighScoreRow] = []
	for index: int in HighScoreBoard.LEVEL_COUNT * HighScoreBoard.LEVEL_RANKS:
		level_rows.append(HighScoreRow.create(HighScoreBoard.EMPTY_INITIALS, 0))
	var levels: Dictionary = scenario.levels
	for key: String in levels:
		var rows: Array[HighScoreRow] = _rows(levels[key])
		for rank: int in rows.size():
			level_rows[int(key) * HighScoreBoard.LEVEL_RANKS + rank] = rows[rank]
	var board := HighScoreBoard.create(_rows(scenario.main), level_rows)
	var step_index: int = 0
	for step: Dictionary in scenario.steps:
		var label: String = "%s step %d %s" % [scenario_name, step_index, step.op]
		var args: Array = step.args
		var result: Variant = step.result
		match str(step.op):
			"qualifies":
				assert_eq(board.qualifies(_int(args[0])), _bool(result), label)
			"qualifies_arcade":
				assert_eq(board.qualifies_arcade(), _bool(result), label)
			"qualifies_any":
				assert_eq(board.qualifies_any(_int(args[0])), _bool(result), label)
			"enter":
				assert_eq(board.enter(str(args[0]), _int(args[1])), _int(result), label)
			"enter_arcade_times":
				assert_eq(board.enter_arcade_times(str(args[0])), _ints(result), label)
			"record_level":
				board.record_level(_int(args[0]), _int(args[1]), _ints(args[2]))
			"record_jungle_statue":
				board.record_jungle_statue(_int(args[0]))
			"reset_run":
				board.reset_run()
			"input_startup":
				var startup: String = STARTUP_NAMES[board.input_startup(_int(args[0]), _bool(args[1]))]
				assert_eq(startup, str(result), label)
			_:
				fail_test("%s: unknown operation" % label)
		var state: Dictionary = step.state
		_check_state(board, state, label)
		step_index += 1


func _check_state(board: HighScoreBoard, state: Dictionary, label: String) -> void:
	if state.has("main"):
		var main: Array = state.main
		for rank: int in main.size():
			assert_eq(_row_values(board.main[rank]), _golden_row_values(main[rank]), "%s main %d" % [label, rank])
	var levels: Dictionary = state.levels
	for key: String in levels:
		var rows: Array = levels[key]
		var shown: Array[HighScoreRow] = board.level_rows(int(key))
		for rank: int in rows.size():
			assert_eq(_row_values(board.levels[int(key) * HighScoreBoard.LEVEL_RANKS + rank]), _golden_row_values(rows[rank]), "%s level %s rank %d" % [label, key, rank])
			if int(key) != HighScoreBoard.LEVEL_JUNGLE2:
				assert_eq(_row_values(shown[rank]), _golden_row_values(rows[rank]), "%s shown level %s rank %d" % [label, key, rank])
	var recorded := PackedInt32Array()
	for level: int in HighScoreBoard.LEVEL_COUNT:
		if board.recorded[level] != 0:
			recorded.append(level)
	assert_eq(recorded, _ints(state.recorded), "%s recorded" % label)
	var run: Dictionary = state.run
	for key: String in run:
		var entry: Array = run[key]
		assert_eq(board.run_scores[int(key)], _int(entry[0]), "%s run score %s" % [label, key])
		assert_eq(board.run_times_of(int(key)), _ints(entry[1]), "%s run times %s" % [label, key])
	assert_eq(board.new_main, _bool(state.new_main), "%s new main" % label)
	var flagged := PackedInt32Array()
	for level: int in HighScoreBoard.LEVEL_COUNT:
		if board.new_levels[level] != 0:
			flagged.append(level)
	assert_eq(flagged, _ints(state.new_levels), "%s new levels" % label)

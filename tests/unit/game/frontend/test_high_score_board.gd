extends GutTest
## High-score tables, run recording and name entry after hsinput.c and gamesys.C.

const ORIGINAL1: int = 24


func _main(scores: Array) -> Array[HighScoreRow]:
	var rows: Array[HighScoreRow] = []
	for score: int in scores:
		rows.append(HighScoreRow.create("ABC", score))
	return rows


func _board(main_scores: Array = [1000, 900, 800, 700, 600, 500, 400, 300, 200, 100]) -> HighScoreBoard:
	var levels: Array[HighScoreRow] = []
	for index: int in HighScoreBoard.LEVEL_COUNT * HighScoreBoard.LEVEL_RANKS:
		levels.append(HighScoreRow.create("LVL", 3000 - (index % 3) * 1000, PackedInt32Array([index % 3, 0, 0, 0, 0])))
	return HighScoreBoard.create(_main(main_scores), levels)


func test_create_pads_cuts_and_copies() -> void:
	var main: Array[HighScoreRow] = _main([5, 4])
	var none: Array[HighScoreRow] = []
	var board := HighScoreBoard.create(main, none)
	assert_eq(board.main.size(), HighScoreBoard.MAIN_COUNT)
	assert_eq(board.levels.size(), HighScoreBoard.LEVEL_COUNT * HighScoreBoard.LEVEL_RANKS)
	assert_eq(board.main[1].score, 4)
	assert_eq(board.main[2].initials, HighScoreBoard.EMPTY_INITIALS)
	assert_eq(board.main[9].score, 0)
	main[0].score = 99
	assert_eq(board.main[0].score, 5, "The board keeps copies")
	var long: Array[HighScoreRow] = _main([9, 8, 7, 6, 5, 4, 3, 2, 1, 0, -1])
	assert_eq(HighScoreBoard.create(long, none).main.size(), HighScoreBoard.MAIN_COUNT)
	assert_eq(board.recorded.size(), HighScoreBoard.LEVEL_COUNT)
	assert_eq(board.run_times.size(), HighScoreBoard.LEVEL_COUNT * HighScoreBoard.CHECKPOINT_COUNT)
	assert_eq(board.new_levels.size(), HighScoreBoard.LEVEL_COUNT)


func test_checkpoint_seconds_round_up_and_cap() -> void:
	assert_eq(HighScoreBoard.checkpoint_seconds(0), 0)
	assert_eq(HighScoreBoard.checkpoint_seconds(1), 1)
	assert_eq(HighScoreBoard.checkpoint_seconds(30), 1)
	assert_eq(HighScoreBoard.checkpoint_seconds(31), 2)
	assert_eq(HighScoreBoard.checkpoint_seconds(2970), 99)
	assert_eq(HighScoreBoard.checkpoint_seconds(2971), 99)
	assert_eq(HighScoreBoard.checkpoint_seconds(-5), 0, "Truncating division rounds a negative timer to 0")


func test_redirect_only_moves_jungle2() -> void:
	assert_eq(HighScoreBoard.redirect_level(HighScoreBoard.LEVEL_JUNGLE2), HighScoreBoard.LEVEL_JUNGLE1)
	assert_eq(HighScoreBoard.redirect_level(HighScoreBoard.LEVEL_JUNGLE1), HighScoreBoard.LEVEL_JUNGLE1)
	assert_eq(HighScoreBoard.redirect_level(ORIGINAL1), ORIGINAL1)


func test_record_keeps_the_better_score_and_converts_ticks() -> void:
	var board := _board()
	board.record_level(ORIGINAL1, 500, PackedInt32Array([30, 31]))
	assert_eq(board.recorded[ORIGINAL1], 1)
	assert_eq(board.run_scores[ORIGINAL1], 500)
	assert_eq(board.run_times_of(ORIGINAL1), PackedInt32Array([1, 2, 0, 0, 0]), "Missing ticks count as 0")
	board.record_level(ORIGINAL1, 500, PackedInt32Array([90, 90, 90, 90, 90]))
	assert_eq(board.run_times_of(ORIGINAL1), PackedInt32Array([1, 2, 0, 0, 0]), "An equal score keeps the record")
	board.record_level(ORIGINAL1, 501, PackedInt32Array([90, 90, 90, 90, 90]))
	assert_eq(board.run_times_of(ORIGINAL1), PackedInt32Array([3, 3, 3, 3, 3]))
	board.record_level(HighScoreBoard.LEVEL_COUNT, 900, PackedInt32Array())
	board.record_level(-1, 900, PackedInt32Array())
	assert_eq(board.run_scores[ORIGINAL1], 501)
	board.reset_run()
	assert_eq(board.recorded[ORIGINAL1], 0)
	assert_eq(board.run_scores[ORIGINAL1], 0)
	assert_eq(board.run_times_of(ORIGINAL1), PackedInt32Array([0, 0, 0, 0, 0]))


func test_jungle_statue_records_jungle1_without_times() -> void:
	var board := _board()
	board.record_jungle_statue(700)
	assert_eq(board.recorded[HighScoreBoard.LEVEL_JUNGLE1], 1)
	assert_eq(board.recorded[HighScoreBoard.LEVEL_JUNGLE2], 0)
	assert_eq(board.run_scores[HighScoreBoard.LEVEL_JUNGLE1], 700)
	assert_eq(board.run_times_of(HighScoreBoard.LEVEL_JUNGLE1), PackedInt32Array([0, 0, 0, 0, 0]))


func test_qualification_is_strict() -> void:
	var board := _board()
	assert_false(board.qualifies(100))
	assert_true(board.qualifies(101))
	assert_false(board.qualifies_arcade())
	board.record_level(ORIGINAL1, 1000, PackedInt32Array())
	assert_false(board.qualifies_arcade(), "Equal to the third row")
	board.record_level(ORIGINAL1, 1001, PackedInt32Array())
	assert_true(board.qualifies_arcade())
	assert_true(board.qualifies_any(0))


func test_input_startup_bails_or_clears_flags() -> void:
	var board := _board()
	assert_eq(board.enter("TOP", 5000), 0)
	assert_true(board.new_main)
	assert_eq(board.input_startup(9999, true), HighScoreBoard.Startup.GAME_QUIT)
	assert_eq(board.input_startup(0, false), HighScoreBoard.Startup.NO_HIGH_SCORE)
	assert_true(board.new_main, "A bail leaves the flags")
	assert_eq(board.input_startup(9999, false), HighScoreBoard.Startup.ENTRY)
	assert_false(board.new_main)


func test_enter_pads_initials_and_keeps_main_times() -> void:
	var board := _board()
	board.main[9].times = PackedInt32Array([9, 9, 9, 9, 9])
	assert_eq(board.enter("Q", 150), 9)
	assert_eq(board.main[9].initials, "Q  ")
	assert_eq(board.main[9].times, PackedInt32Array([9, 9, 9, 9, 9]), "Times stay with the rank")
	assert_eq(board.enter("TOOLONG", 50), -1)


func test_arcade_entry_redirects_jungle2_and_flags_the_table() -> void:
	var board := _board()
	board.record_level(HighScoreBoard.LEVEL_JUNGLE1, 2500, PackedInt32Array([30, 60, 90, 120, 150]))
	board.record_level(HighScoreBoard.LEVEL_JUNGLE2, 4000, PackedInt32Array())
	assert_eq(board.enter_arcade_times("JUN"), PackedInt32Array([HighScoreBoard.LEVEL_JUNGLE1, HighScoreBoard.LEVEL_JUNGLE1]))
	var rows: Array[HighScoreRow] = board.level_rows(HighScoreBoard.LEVEL_JUNGLE2)
	assert_eq(rows[0].score, 2500, "The JUNGLE2 insertion takes JUNGLE1's run row")
	assert_eq(rows[0].times, PackedInt32Array([1, 2, 3, 4, 5]))
	assert_eq(rows[1].score, 3000)
	assert_eq(rows[2].score, 2500)
	assert_eq(board.new_levels[HighScoreBoard.LEVEL_JUNGLE1], 1)
	assert_eq(board.new_levels[HighScoreBoard.LEVEL_JUNGLE2], 0)
	rows[0].score = 1
	assert_eq(board.level_rows(HighScoreBoard.LEVEL_JUNGLE1)[0].score, 2500, "level_rows returns copies")

extends GutTest
## The front-end session keeps the high-score board across scenes, records the run's levels, ends
## games on name entry, saves the tables to its own file and carries the attract cycle's
## requests between the menu and the game scene.

var _path: String = ""


func before_each() -> void:
	_path = "user://test_session_scores_%d.cfg" % Time.get_ticks_usec()
	FrontEndSession.scores_store_path = _path
	FrontEndSession.board = null
	FrontEndSession.diagnostics = PackedStringArray()


func after_each() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)
	FrontEndSession.scores_store_path = HighScoreStore.DEFAULT_PATH
	FrontEndSession.board = null
	FrontEndSession.active = false
	FrontEndSession.start_page = FrontEndPage.Page.MAIN_MENU
	FrontEndSession.final_score = 0
	FrontEndSession.game_quit = false
	FrontEndSession.attract_level = -1
	FrontEndSession.attract_return = false
	FrontEndSession.level_chosen = false
	FrontEndSession.level = -1


func _rows(count: int, first_score: int) -> Array[HighScoreRow]:
	var rows: Array[HighScoreRow] = []
	for index: int in count:
		rows.append(HighScoreRow.create("A%02d" % index, first_score - index, PackedInt32Array([index, 1, 2, 3, 4])))
	return rows


func test_without_a_file_or_tables_the_board_starts_empty_and_says_so() -> void:
	FrontEndSession.load_scores(null)
	assert_not_null(FrontEndSession.board)
	assert_eq(FrontEndSession.board.main.size(), HighScoreBoard.MAIN_COUNT)
	assert_eq(FrontEndSession.board.main[0].score, 0)
	assert_eq(FrontEndSession.diagnostics.size(), 1)
	assert_string_contains(FrontEndSession.diagnostics[0], "High scores are unavailable")


func test_saved_tables_load_back_and_a_loaded_board_is_kept() -> void:
	FrontEndSession.board = HighScoreBoard.create(_rows(10, 5000), _rows(180, 900))
	assert_eq(FrontEndSession.save_scores(), "")
	var kept: HighScoreBoard = FrontEndSession.board
	FrontEndSession.load_scores(null)
	assert_eq(FrontEndSession.board, kept, "a board already built keeps the run's data")
	FrontEndSession.board = null
	FrontEndSession.load_scores(null)
	assert_eq(FrontEndSession.diagnostics, PackedStringArray())
	assert_eq(FrontEndSession.board.main[0].initials, "A00")
	assert_eq(FrontEndSession.board.main[3].score, 4997)
	assert_eq(FrontEndSession.board.levels[179].initials, "A179".substr(0, 3))
	assert_eq(FrontEndSession.board.levels[2].times, PackedInt32Array([2, 1, 2, 3, 4]))


func test_rows_take_five_times_each() -> void:
	var rows: Array[HighScoreRow] = FrontEndSession.rows_of(PackedStringArray(["ABC", "DEF"]), PackedInt32Array([30, 20]),
		PackedInt32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
	assert_eq(rows.size(), 2)
	assert_eq(rows[1].initials, "DEF")
	assert_eq(rows[1].times, PackedInt32Array([6, 7, 8, 9, 10]))


func test_a_game_records_levels_and_ends_on_name_entry() -> void:
	var none: Array[HighScoreRow] = []
	FrontEndSession.board = HighScoreBoard.create(none, none)
	FrontEndSession.progress = LevelProgress.create(LevelStack.create([LevelStack.Row.new(24, 1, 0, 5, 0, 1)], []))
	FrontEndSession.board.record_level(3, 100, PackedInt32Array())
	FrontEndSession.begin_game()
	assert_eq(FrontEndSession.board.recorded[3], 0, "a new game forgets the last run's levels")
	FrontEndSession.record_level(24, 750, PackedInt32Array([30, 61]))
	assert_eq(FrontEndSession.board.run_scores[24], 750)
	assert_eq(FrontEndSession.board.run_times_of(24), PackedInt32Array([1, 3, 0, 0, 0]))
	FrontEndSession.record_jungle_statue(400)
	assert_eq(FrontEndSession.board.run_scores[HighScoreBoard.LEVEL_JUNGLE1], 400)
	assert_eq(FrontEndSession.end_game(false, 1750), "")
	assert_false(FrontEndSession.active)
	assert_eq(FrontEndSession.start_page, FrontEndPage.Page.HIGH_SCORE_INPUT)
	assert_eq(FrontEndSession.final_score, 1750)
	assert_false(FrontEndSession.game_quit)
	assert_true(FileAccess.file_exists(_path), "retail saves the tables when the game ends")
	FrontEndSession.end_game(true, 0)
	assert_true(FrontEndSession.game_quit)
	assert_eq(FrontEndSession.board.input_startup(FrontEndSession.final_score, FrontEndSession.game_quit), HighScoreBoard.Startup.GAME_QUIT)


func test_the_entry_request_is_consumed_once() -> void:
	assert_eq(FrontEndSession.end_game(true, 2500), "")
	FrontEndSession.consume_entry_request()
	assert_eq(FrontEndSession.start_page, FrontEndPage.Page.MAIN_MENU, "reopening the front end shows the main menu")
	assert_eq(FrontEndSession.final_score, 0)
	assert_false(FrontEndSession.game_quit)
	FrontEndSession.start_page = FrontEndPage.Page.LEVEL_SELECT
	FrontEndSession.consume_entry_request()
	assert_eq(FrontEndSession.start_page, FrontEndPage.Page.LEVEL_SELECT, "other start pages are left alone")


static func _demo(level: int, unlock_level: int, resource_id: int) -> DemoTableEntry:
	var row := DemoTableEntry.new()
	row.level = level
	row.unlock_level = unlock_level
	row.demo_resource_id = resource_id
	row.low_poly_demo_resource_id = resource_id
	return row


func test_the_attract_cycle_starts_on_the_tables_first_demo() -> void:
	var table := DemoTable.new()
	var rows: Array[DemoTableEntry] = [_demo(48, 48, 5), _demo(DemoTableEntry.SKIP, DemoTableEntry.SKIP, 0), _demo(1, 1, 6)]
	table.entries = rows
	var cycle: AttractCycle = FrontEndSession.attract_from(table)
	assert_not_null(cycle)
	assert_eq(cycle.row_count(), 3, "a skipped row stays as the INTRO slot")
	assert_eq(cycle.current_level(), 48)


func test_the_attract_rows_stop_at_the_terminator() -> void:
	var table := DemoTable.new()
	var rows: Array[DemoTableEntry] = [_demo(48, 48, 5), _demo(DemoTable.TERMINATOR, 0, 0), _demo(1, 1, 6)]
	table.entries = rows
	assert_eq(FrontEndSession.attract_from(table).row_count(), 1)
	var intro_only := DemoTable.new()
	var intro_rows: Array[DemoTableEntry] = [_demo(DemoTableEntry.SKIP, DemoTableEntry.SKIP, 0)]
	intro_only.entries = intro_rows
	assert_null(FrontEndSession.attract_from(intro_only), "a list of INTRO slots plays no demo")


func test_no_attract_cycle_without_demos() -> void:
	assert_null(FrontEndSession.attract_from(null))
	assert_null(FrontEndSession.attract_from(DemoTable.new()), "an empty table plays no demo")
	var broken := DemoTable.new()
	var rows: Array[DemoTableEntry] = [_demo(48, 48, 5)]
	broken.entries = rows
	broken.error = "unreadable"
	assert_null(FrontEndSession.attract_from(broken))


func test_an_attract_demo_is_requested_and_handed_back() -> void:
	FrontEndSession.begin_attract(48)
	assert_eq(FrontEndSession.attract_level, 48)
	assert_false(FrontEndSession.attract_return)
	FrontEndSession.end_attract(true)
	assert_eq(FrontEndSession.attract_level, -1, "the next game scene plays normally")
	assert_true(FrontEndSession.attract_return)
	FrontEndSession.begin_attract(1)
	FrontEndSession.end_attract(false)
	assert_eq(FrontEndSession.attract_level, -1)
	assert_false(FrontEndSession.attract_return)


func test_menu_start_opens_a_fresh_game_on_the_level_select() -> void:
	var none: Array[HighScoreRow] = []
	FrontEndSession.board = HighScoreBoard.create(none, none)
	FrontEndSession.progress = LevelProgress.create(LevelStack.create([LevelStack.Row.new(24, 1, 0, 5, 0, 1)], []))
	FrontEndSession.score = 900
	FrontEndSession.lives = 1
	FrontEndSession.level_chosen = true
	FrontEndSession.menu_start()
	assert_true(FrontEndSession.active)
	assert_eq(FrontEndSession.score, 0)
	assert_eq(FrontEndSession.lives, 3)
	assert_false(FrontEndSession.level_chosen, "the level list may still go back")
	assert_eq(FrontEndSession.start_page, FrontEndPage.Page.LEVEL_SELECT)

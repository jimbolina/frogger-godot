extends GutTest
## Single-player page transitions, their table form and unknown-event reports.

const EXPECTED: Array = [
	["BOOT", "BOOT_DONE", "MAIN_MENU"],
	["MAIN_MENU", "START", "LEVEL_SELECT"],
	["LEVEL_SELECT", "SELECT_LEVEL", "GAME"],
	["LEVEL_SELECT", "BACK", "MAIN_MENU"],
	["GAME", "LEVEL_FINISHED", "LEVEL_COMPLETE"],
	["GAME", "GAME_FINISHED", "ENDING"],
	["GAME", "ALL_LIVES_LOST", "GAME_OVER"],
	["GAME", "QUIT", "GAME_OVER"],
	["LEVEL_COMPLETE", "NEXT_LEVEL", "GAME"],
	["LEVEL_COMPLETE", "ZONE_COMPLETE", "LEVEL_SELECT"],
	["LEVEL_COMPLETE", "BACK", "LEVEL_SELECT"],
	["GAME_OVER", "GAME_OVER_DONE", "CONTINUE"],
	["CONTINUE", "CONTINUE_DONE", "MAIN_MENU"],
	["ENDING", "ENDING_DONE", "MAIN_MENU"],
	["MAIN_MENU", "OPTIONS", "OPTIONS"],
	["OPTIONS", "CONTROLS", "CONTROLS"],
	["OPTIONS", "BACK", "MAIN_MENU"],
	["CONTROLS", "BACK", "OPTIONS"],
]

func test_table_names_match_the_frozen_transitions() -> void:
	var names: Array[PackedStringArray] = FrontEndFlow.table_names()
	assert_eq(names.size(), EXPECTED.size())
	for index: int in EXPECTED.size():
		var expected: Array = EXPECTED[index]
		assert_eq(names[index], PackedStringArray(expected), "row %d" % index)
	assert_eq(FrontEndFlow.sources().size(), EXPECTED.size(), "Every row cites its source")

func test_every_table_row_drives_next_page() -> void:
	for row: PackedInt32Array in FrontEndFlow.table():
		var diagnostics := PackedStringArray()
		assert_eq(FrontEndFlow.next_page(row[0], row[1], diagnostics), row[2])
		assert_true(FrontEndFlow.accepts(row[0], row[1]))
		assert_eq(diagnostics, PackedStringArray())

func test_table_is_detached_and_pairs_are_unique() -> void:
	var first: Array[PackedInt32Array] = FrontEndFlow.table()
	first[0][2] = FrontEndPage.Page.GAME
	first.clear()
	assert_eq(FrontEndFlow.table()[0][2], FrontEndPage.Page.MAIN_MENU)
	var seen: Dictionary = {}
	for row: PackedInt32Array in FrontEndFlow.table():
		var key: Vector2i = Vector2i(row[0], row[1])
		assert_false(seen.has(key), "One next page per page and event")
		seen[key] = true

func test_single_player_round_trip() -> void:
	var diagnostics := PackedStringArray()
	var page: int = FrontEndPage.Page.BOOT
	for event: int in [FrontEndFlow.Event.BOOT_DONE, FrontEndFlow.Event.START, FrontEndFlow.Event.SELECT_LEVEL,
			FrontEndFlow.Event.LEVEL_FINISHED, FrontEndFlow.Event.NEXT_LEVEL, FrontEndFlow.Event.LEVEL_FINISHED,
			FrontEndFlow.Event.ZONE_COMPLETE, FrontEndFlow.Event.SELECT_LEVEL, FrontEndFlow.Event.ALL_LIVES_LOST,
			FrontEndFlow.Event.GAME_OVER_DONE, FrontEndFlow.Event.CONTINUE_DONE]:
		page = FrontEndFlow.next_page(page, event, diagnostics)
	assert_eq(page, FrontEndPage.Page.MAIN_MENU)
	assert_eq(diagnostics, PackedStringArray())

func test_options_round_trip() -> void:
	var diagnostics := PackedStringArray()
	var page: int = FrontEndPage.Page.MAIN_MENU
	for event: int in [FrontEndFlow.Event.OPTIONS, FrontEndFlow.Event.CONTROLS, FrontEndFlow.Event.BACK,
			FrontEndFlow.Event.BACK, FrontEndFlow.Event.START]:
		page = FrontEndFlow.next_page(page, event, diagnostics)
	assert_eq(page, FrontEndPage.Page.LEVEL_SELECT)
	assert_eq(diagnostics, PackedStringArray())
	assert_false(FrontEndFlow.accepts(FrontEndPage.Page.CONTROLS, FrontEndFlow.Event.OPTIONS))

func test_unknown_events_keep_the_page_and_are_reported() -> void:
	var diagnostics := PackedStringArray()
	assert_eq(FrontEndFlow.next_page(FrontEndPage.Page.MAIN_MENU, FrontEndFlow.Event.ALL_LIVES_LOST, diagnostics), FrontEndPage.Page.MAIN_MENU)
	assert_eq(FrontEndFlow.next_page(FrontEndPage.Page.CONTINUE, FrontEndFlow.Event.BACK, diagnostics), FrontEndPage.Page.CONTINUE)
	assert_eq(FrontEndFlow.next_page(42, 99, diagnostics), 42)
	assert_false(FrontEndFlow.accepts(FrontEndPage.Page.GAME, FrontEndFlow.Event.START))
	assert_eq(diagnostics, PackedStringArray([
		"front end: page MAIN_MENU ignores event ALL_LIVES_LOST",
		"front end: page CONTINUE ignores event BACK",
		"front end: page 42 ignores event 99",
	]))

func test_names_resolve_both_ways() -> void:
	assert_eq(FrontEndPage.name_of(FrontEndPage.Page.LEVEL_COMPLETE), "LEVEL_COMPLETE")
	assert_eq(FrontEndPage.from_name("GAME_OVER"), FrontEndPage.Page.GAME_OVER)
	assert_eq(FrontEndPage.name_of(-1), "")
	assert_eq(FrontEndPage.from_name("OPTIONS"), FrontEndPage.Page.OPTIONS)
	assert_eq(FrontEndPage.from_name("CHOOSE_WIN_CONTROLLER"), -1)
	assert_eq(FrontEndFlow.event_name(FrontEndFlow.Event.ZONE_COMPLETE), "ZONE_COMPLETE")
	assert_eq(FrontEndFlow.event_from_name("CONTINUE_DONE"), FrontEndFlow.Event.CONTINUE_DONE)
	assert_eq(FrontEndFlow.event_name(100), "")
	assert_eq(FrontEndFlow.event_from_name("start"), -1, "Names are upper case")

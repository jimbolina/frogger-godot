extends GutTest
## The front-end pages' disc tracks and page-change policy against PlayOptionsMusic and
## ShutdownOptionsMusic (FROGGER.EXE 0x00446450 and 0x00446470) and the level select's PlayCD(13, 1).


func _walk(pages: Array[int], playing: int = FrontEndMusic.SILENT) -> Array[int]:
	var changes: Array[int] = []
	for page: int in pages:
		var next: int = FrontEndMusic.track_for_page(page)
		changes.append(FrontEndMusic.change(playing, next))
		playing = next
	return changes


func test_every_page_has_its_track() -> void:
	var expected: Dictionary[int, int] = {
		FrontEndPage.Page.BOOT: -1,
		FrontEndPage.Page.MAIN_MENU: 11,
		FrontEndPage.Page.LEVEL_SELECT: 13,
		FrontEndPage.Page.GAME: -1,
		FrontEndPage.Page.LEVEL_COMPLETE: -1,
		FrontEndPage.Page.GAME_OVER: -1,
		FrontEndPage.Page.CONTINUE: -1,
		FrontEndPage.Page.ENDING: -1,
		FrontEndPage.Page.OPTIONS: 11,
		FrontEndPage.Page.CONTROLS: 11,
		FrontEndPage.Page.HIGH_SCORE_INPUT: -1,
		FrontEndPage.Page.HIGH_SCORE_VIEW: 11,
	}
	assert_eq(expected.size(), FrontEndPage.Page.size())
	for page: int in expected:
		assert_eq(FrontEndMusic.track_for_page(page), expected[page], FrontEndPage.name_of(page))
	assert_eq(FrontEndMusic.track_for_page(-1), FrontEndMusic.SILENT)
	assert_eq(FrontEndMusic.track_for_page(99), FrontEndMusic.SILENT)


func test_change_keeps_starts_or_stops() -> void:
	assert_eq(FrontEndMusic.change(11, 11), FrontEndMusic.Change.KEEP)
	assert_eq(FrontEndMusic.change(-1, -1), FrontEndMusic.Change.KEEP)
	assert_eq(FrontEndMusic.change(-1, 11), FrontEndMusic.Change.START)
	assert_eq(FrontEndMusic.change(13, 11), FrontEndMusic.Change.START)
	assert_eq(FrontEndMusic.change(11, 13), FrontEndMusic.Change.START)
	assert_eq(FrontEndMusic.change(11, -1), FrontEndMusic.Change.STOP)
	assert_eq(FrontEndMusic.change(13, -1), FrontEndMusic.Change.STOP)


func test_options_pages_keep_the_menu_tune_playing() -> void:
	var pages: Array[int] = [FrontEndPage.Page.MAIN_MENU, FrontEndPage.Page.OPTIONS, FrontEndPage.Page.CONTROLS,
		FrontEndPage.Page.OPTIONS, FrontEndPage.Page.HIGH_SCORE_VIEW, FrontEndPage.Page.OPTIONS, FrontEndPage.Page.MAIN_MENU]
	var expected: Array[int] = [FrontEndMusic.Change.START, FrontEndMusic.Change.KEEP, FrontEndMusic.Change.KEEP,
		FrontEndMusic.Change.KEEP, FrontEndMusic.Change.KEEP, FrontEndMusic.Change.KEEP, FrontEndMusic.Change.KEEP]
	assert_eq(_walk(pages), expected)


func test_level_select_starts_its_track_and_the_menu_restarts_after_it() -> void:
	var pages: Array[int] = [FrontEndPage.Page.LEVEL_SELECT, FrontEndPage.Page.MAIN_MENU]
	var expected: Array[int] = [FrontEndMusic.Change.START, FrontEndMusic.Change.START]
	assert_eq(_walk(pages, FrontEndMusic.MENU_TRACK), expected)
	assert_eq(FrontEndMusic.track_for_page(FrontEndPage.Page.LEVEL_SELECT), FrontEndMusic.LEVEL_SELECT_TRACK)


func test_name_entry_is_silent_and_the_view_starts_the_menu_tune() -> void:
	var pages: Array[int] = [FrontEndPage.Page.HIGH_SCORE_INPUT, FrontEndPage.Page.HIGH_SCORE_VIEW, FrontEndPage.Page.MAIN_MENU]
	var expected: Array[int] = [FrontEndMusic.Change.KEEP, FrontEndMusic.Change.START, FrontEndMusic.Change.KEEP]
	assert_eq(_walk(pages), expected)


func test_name_entry_left_without_a_score_starts_the_menu_tune() -> void:
	var pages: Array[int] = [FrontEndPage.Page.HIGH_SCORE_INPUT, FrontEndPage.Page.MAIN_MENU]
	var expected: Array[int] = [FrontEndMusic.Change.KEEP, FrontEndMusic.Change.START]
	assert_eq(_walk(pages), expected)


func test_a_demo_stops_the_menu_tune_and_the_return_starts_it_afresh() -> void:
	assert_eq(FrontEndMusic.change(FrontEndMusic.MENU_TRACK, FrontEndMusic.SILENT), FrontEndMusic.Change.STOP)
	var returned: Array[int] = [FrontEndPage.Page.MAIN_MENU]
	assert_eq(_walk(returned), [FrontEndMusic.Change.START] as Array[int])


func test_a_return_from_a_level_to_options_starts_the_menu_tune() -> void:
	var pages: Array[int] = [FrontEndPage.Page.OPTIONS, FrontEndPage.Page.MAIN_MENU]
	var expected: Array[int] = [FrontEndMusic.Change.START, FrontEndMusic.Change.KEEP]
	assert_eq(_walk(pages), expected)

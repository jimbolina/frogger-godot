extends GutTest
## The port's page transitions agree with the independent frozen-C request table in
## tests/golden/synthetic/frontend_flow.json (tools/make_golden_frontend.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_flow.json"
const PAGE_ALIASES: Dictionary = {
	"BOOT": ["ANTI_PIRACY", "HASBRO_LOGO", "LANGUAGE_SELECTION"],
	"MAIN_MENU": ["MAIN_OPTIONS"],
	"ENDING": ["OUTRO", "CREDITS"],
	"CONTROLS": ["CHOOSE_WIN_CONTROLLER"],
}
const EVENT_ALIASES: Dictionary = {
	"BOOT_DONE": ["language_detected"],
	"START": ["start"],
	"SELECT_LEVEL": ["play"],
	"BACK": ["back_before_first_play", "back", "exit"],
	"LEVEL_FINISHED": ["level_complete"],
	"GAME_FINISHED": ["jungle_complete", "jungle_complete_all_gold_frogs"],
	"ALL_LIVES_LOST": ["lives_lost"],
	"QUIT": ["pause_quit"],
	"NEXT_LEVEL": ["timeout_next_level"],
	"ZONE_COMPLETE": ["timeout_zone_complete"],
	"GAME_OVER_DONE": ["timeout", "confirm"],
	"CONTINUE_DONE": ["arcade"],
	"ENDING_DONE": ["finished"],
	"OPTIONS": ["options"],
	"CONTROLS": ["controller_config"],
	"ENTERED": ["entered"],
	"NO_HIGH_SCORE": ["no_high_score"],
	"GAME_QUIT": ["game_quit"],
	"TIMEOUT": ["timeout", "levels_shown"],
	"VIEW_HIGH_SCORES": ["view_high_scores"],
	"BACK_TO_OPTIONS": ["back_to_options", "back_to_options_from_scores"],
}

var _transitions: Array[Dictionary] = []


func before_all() -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	for item: Dictionary in document.transitions:
		_transitions.append(item)


func _pages(port_page: String) -> Array:
	var aliases: Array = PAGE_ALIASES.get(port_page, [port_page])
	return aliases


func _events(port_event: String) -> Array:
	var aliases: Array = EVENT_ALIASES.get(port_event, [])
	return aliases


func _golden_next(page: String, event: String) -> String:
	for item: Dictionary in _transitions:
		if item.page == page and item.event == event:
			return str(item.next)
	return ""


## Follows golden rows through pages the port folds into the page it left.
func _resolve(page: String, wanted: Array, folded: Array, event: String) -> String:
	var current: String = page
	for _guard: int in 8:
		if wanted.has(current) or not folded.has(current):
			break
		current = _golden_next(current, event)
	return current


func _port_row_for(page: String, event: String) -> PackedStringArray:
	for row: PackedStringArray in FrontEndFlow.table_names():
		if _pages(row[0]).has(page) and _events(row[1]).has(event):
			return row
	return PackedStringArray()


func test_golden_rows_cite_known_phases_and_pages() -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	var pages: Array = document.pages
	assert_eq(str(document.start_page), "ANTI_PIRACY")
	assert_eq(str(document.p13a_start_page), "MAIN_OPTIONS")
	for item: Dictionary in _transitions:
		assert_true(pages.has(item.page) and pages.has(item.next), "%s %s names known pages" % [item.page, item.event])
		assert_true(["P13a", "P13c", "P13d", "P15", "P16"].has(item.phase))


func test_every_port_transition_agrees_with_the_frozen_requests() -> void:
	var rows: Array[PackedStringArray] = FrontEndFlow.table_names()
	assert_gt(rows.size(), 0)
	for row: PackedStringArray in rows:
		var label: String = "%s %s -> %s" % [row[0], row[1], row[2]]
		var wanted: Array = _pages(row[2])
		var matched: int = 0
		for item: Dictionary in _transitions:
			if not _pages(row[0]).has(item.page) or not _events(row[1]).has(item.event):
				continue
			matched += 1
			var reached: String = _resolve(str(item.next), wanted, _pages(row[0]), str(item.event))
			assert_true(wanted.has(reached), "%s: golden %s %s reaches %s" % [label, item.page, item.event, reached])
		assert_gt(matched, 0, "%s has a golden request" % label)


func test_every_p13a_request_is_ported() -> void:
	_check_phase_is_ported("P13a")


func test_every_p13c_request_is_ported() -> void:
	_check_phase_is_ported("P13c")


func test_every_p13d_request_is_ported() -> void:
	_check_phase_is_ported("P13d")


func test_high_score_rows_reach_their_pages() -> void:
	assert_eq(_golden_next("CONTINUE", "arcade"), "HIGH_SCORE_INPUT")
	assert_eq(_golden_next("CREDITS", "finished"), "HIGH_SCORE_INPUT")
	assert_eq(_golden_next("HIGH_SCORE_INPUT", "entered"), "HIGH_SCORE_VIEW")
	assert_eq(_golden_next("HIGH_SCORE_VIEW", "back_to_options"), "OPTIONS")
	assert_eq(_golden_next("OPTIONS", "view_high_scores"), "HIGH_SCORE_VIEW")


func _check_phase_is_ported(phase: String) -> void:
	var checked: int = 0
	for item: Dictionary in _transitions:
		if item.phase != phase:
			continue
		checked += 1
		var row: PackedStringArray = _port_row_for(str(item.page), str(item.event))
		assert_eq(row.size(), 3, "%s %s is in the port table" % [item.page, item.event])
		if row.size() == 3:
			var reached: String = _resolve(str(item.next), _pages(row[2]), _pages(row[0]), str(item.event))
			assert_true(_pages(row[2]).has(reached), "%s %s leads to %s" % [item.page, item.event, row[2]])
	assert_gt(checked, 0, "%s has golden rows" % phase)


func test_retail_boot_order_is_recorded_over_the_vendored_one() -> void:
	assert_eq(_golden_next("HASBRO_LOGO", "video_finished"), "LANGUAGE_SELECTION")
	assert_eq(_golden_next("LANGUAGE_SELECTION", "language_detected"), "MAIN_OPTIONS")
	for item: Dictionary in _transitions:
		if item.has("source_next") or item.has("retail"):
			assert_true(str(item.retail).begins_with("KF-"), "%s cites the retail fact" % item.page)


func test_options_rows_reach_the_controller_page_and_back() -> void:
	assert_eq(_golden_next("MAIN_OPTIONS", "options"), "OPTIONS")
	assert_eq(_golden_next("OPTIONS", "controller_config"), "CHOOSE_WIN_CONTROLLER")
	assert_eq(_golden_next("CHOOSE_WIN_CONTROLLER", "back"), "OPTIONS")
	assert_eq(_golden_next("OPTIONS", "back"), "MAIN_OPTIONS")
	assert_eq(_golden_next("OPTIONS", "exit"), "MAIN_OPTIONS")

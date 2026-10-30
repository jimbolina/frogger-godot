extends GutTest
## The port's page transitions agree with the independent frozen-C request table in
## tests/golden/synthetic/frontend_flow.json (tools/make_golden_frontend.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_flow.json"
const PAGE_ALIASES: Dictionary = {
	"BOOT": ["ANTI_PIRACY", "HASBRO_LOGO", "LANGUAGE_SELECTION"],
	"MAIN_MENU": ["MAIN_OPTIONS"],
	"ENDING": ["OUTRO", "CREDITS"],
}
const EVENT_ALIASES: Dictionary = {
	"BOOT_DONE": ["language_detected"],
	"START": ["start"],
	"SELECT_LEVEL": ["play"],
	"BACK": ["back_before_first_play", "back"],
	"LEVEL_FINISHED": ["level_complete"],
	"GAME_FINISHED": ["jungle_complete", "jungle_complete_all_gold_frogs"],
	"ALL_LIVES_LOST": ["lives_lost"],
	"QUIT": ["pause_quit"],
	"NEXT_LEVEL": ["timeout_next_level"],
	"ZONE_COMPLETE": ["timeout_zone_complete"],
	"GAME_OVER_DONE": ["timeout", "confirm"],
	"CONTINUE_DONE": ["arcade"],
	"ENDING_DONE": ["finished"],
}
const SKIPPED_PAGES: Dictionary = {"HIGH_SCORE_INPUT": "no_high_score"}

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


## Follows golden rows through pages the port skips or folds into the page it left.
func _resolve(page: String, wanted: Array, folded: Array, event: String) -> String:
	var current: String = page
	for _guard: int in 8:
		if wanted.has(current):
			break
		if SKIPPED_PAGES.has(current):
			current = _golden_next(current, str(SKIPPED_PAGES[current]))
		elif folded.has(current):
			current = _golden_next(current, event)
		else:
			break
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
	for item: Dictionary in _transitions:
		if item.phase != "P13a" or SKIPPED_PAGES.has(item.page):
			continue
		var row: PackedStringArray = _port_row_for(str(item.page), str(item.event))
		assert_eq(row.size(), 3, "%s %s is in the port table" % [item.page, item.event])
		if row.size() == 3:
			var reached: String = _resolve(str(item.next), _pages(row[2]), _pages(row[0]), str(item.event))
			assert_true(_pages(row[2]).has(reached), "%s %s leads to %s" % [item.page, item.event, row[2]])


func test_retail_boot_order_is_recorded_over_the_vendored_one() -> void:
	assert_eq(_golden_next("HASBRO_LOGO", "video_finished"), "LANGUAGE_SELECTION")
	assert_eq(_golden_next("LANGUAGE_SELECTION", "language_detected"), "MAIN_OPTIONS")
	for item: Dictionary in _transitions:
		if item.has("source_next"):
			assert_true(str(item.retail).begins_with("KF-"), "%s cites the retail fact" % item.page)

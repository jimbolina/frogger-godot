class_name FrontEndFlow
extends RefCounted
## Pure single-player page transitions after the frozen options page requests, retail order first.
##
## Each row cites the request it follows. Retail build 71 compiles the continue choice out
## (tempopt.c:3831-3996), so CONTINUE always moves on; with high scores not yet ported, the
## name-entry page's no-score exit to the main menu (hsinput.c:222-226) is taken directly.
## LEVEL_SELECT accepts BACK only before the first level of a game is chosen
## (SELECT.C:2036-2046, Sel_first_time); the host decides when to offer it. The options pages
## leave once their fly-off ends (HSView.c:2991); BACK on OPTIONS covers both the back key and
## the exit row.

enum Event {
	BOOT_DONE,
	START,
	SELECT_LEVEL,
	BACK,
	LEVEL_FINISHED,
	GAME_FINISHED,
	ALL_LIVES_LOST,
	QUIT,
	NEXT_LEVEL,
	ZONE_COMPLETE,
	GAME_OVER_DONE,
	CONTINUE_DONE,
	ENDING_DONE,
	OPTIONS,
	CONTROLS,
}

## Page of each transition, parallel to [constant EVENTS] and [constant TO_PAGES].
const FROM_PAGES: PackedInt32Array = [
	FrontEndPage.Page.BOOT,
	FrontEndPage.Page.MAIN_MENU,
	FrontEndPage.Page.LEVEL_SELECT,
	FrontEndPage.Page.LEVEL_SELECT,
	FrontEndPage.Page.GAME,
	FrontEndPage.Page.GAME,
	FrontEndPage.Page.GAME,
	FrontEndPage.Page.GAME,
	FrontEndPage.Page.LEVEL_COMPLETE,
	FrontEndPage.Page.LEVEL_COMPLETE,
	FrontEndPage.Page.LEVEL_COMPLETE,
	FrontEndPage.Page.GAME_OVER,
	FrontEndPage.Page.CONTINUE,
	FrontEndPage.Page.ENDING,
	FrontEndPage.Page.MAIN_MENU,
	FrontEndPage.Page.OPTIONS,
	FrontEndPage.Page.OPTIONS,
	FrontEndPage.Page.CONTROLS,
]
## Event of each transition.
const EVENTS: PackedInt32Array = [
	Event.BOOT_DONE,
	Event.START,
	Event.SELECT_LEVEL,
	Event.BACK,
	Event.LEVEL_FINISHED,
	Event.GAME_FINISHED,
	Event.ALL_LIVES_LOST,
	Event.QUIT,
	Event.NEXT_LEVEL,
	Event.ZONE_COMPLETE,
	Event.BACK,
	Event.GAME_OVER_DONE,
	Event.CONTINUE_DONE,
	Event.ENDING_DONE,
	Event.OPTIONS,
	Event.CONTROLS,
	Event.BACK,
	Event.BACK,
]
## Next page of each transition.
const TO_PAGES: PackedInt32Array = [
	FrontEndPage.Page.MAIN_MENU,
	FrontEndPage.Page.LEVEL_SELECT,
	FrontEndPage.Page.GAME,
	FrontEndPage.Page.MAIN_MENU,
	FrontEndPage.Page.LEVEL_COMPLETE,
	FrontEndPage.Page.ENDING,
	FrontEndPage.Page.GAME_OVER,
	FrontEndPage.Page.GAME_OVER,
	FrontEndPage.Page.GAME,
	FrontEndPage.Page.LEVEL_SELECT,
	FrontEndPage.Page.LEVEL_SELECT,
	FrontEndPage.Page.CONTINUE,
	FrontEndPage.Page.MAIN_MENU,
	FrontEndPage.Page.MAIN_MENU,
	FrontEndPage.Page.OPTIONS,
	FrontEndPage.Page.CONTROLS,
	FrontEndPage.Page.MAIN_MENU,
	FrontEndPage.Page.OPTIONS,
]

## The frozen request each transition follows.
const SOURCES: PackedStringArray = [
	"port: retail version, logo, language and intro pages are skipped",
	"tempopt.c:1829 MainOptionsUpdate START",
	"SELECT.C:1424 SelectUpdateGame fade end",
	"SELECT.C:2036-2046 SelectUpdateInput triangle on first visit",
	"gamesys.C:2729 GameMainloopSingleCompleteUpdate",
	"gamesys.C:2724 and 3955-3960 jungle end of game, outro or credits",
	"gamesys.C:1902 and 2586 every frog inactive, single failed",
	"pause.c:502 pause quit, pause.c:118 select and start held",
	"tempopt.c:6058-6063 LevelCompleteUpdate count-down with a next level",
	"tempopt.c:6052-6055 LevelCompleteUpdate count-down without a next level",
	"tempopt.c:6031-6041 LevelCompleteUpdate triangle",
	"tempopt.c:4124 and 4131 GameOverUpdate count-down or fire",
	"tempopt.c:3993 ContinueUpdate, hsinput.c:222-226 no score to enter",
	"credits.c:882 CreditsUpdate, hsinput.c:222-226 no score to enter",
	"tempopt.c:1950 MainOptionsUpdate OPTIONS, after the fly-off",
	"tempopt.c:4833 OptionsUpdate fire on controller config, after the fly-off",
	"tempopt.c:4662 OptionsUpdate triangle, start or retail Escape; tempopt.c:4782 fire on exit",
	"tempopt.c:5744 ChooseWINControllerUpdate; retail page 25 shuts down toward the options camera (KF-482)",
]


## The page after [param page] for [param event]; an unknown pair keeps the page and is reported.
static func next_page(page: int, event: int, diagnostics: PackedStringArray) -> int:
	var index: int = _index_of(page, event)
	if index >= 0:
		return TO_PAGES[index]
	diagnostics.append("front end: page %s ignores event %s" % [_page_label(page), _event_label(event)])
	return page


## True when [param page] has a transition for [param event].
static func accepts(page: int, event: int) -> bool:
	return _index_of(page, event) >= 0


## A detached copy of every transition as [page, event, next] integers, in table order.
static func table() -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	for index: int in FROM_PAGES.size():
		result.append(PackedInt32Array([FROM_PAGES[index], EVENTS[index], TO_PAGES[index]]))
	return result


## Every transition as [page, event, next] names, in table order.
static func table_names() -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	for index: int in FROM_PAGES.size():
		result.append(PackedStringArray([FrontEndPage.name_of(FROM_PAGES[index]), event_name(EVENTS[index]), FrontEndPage.name_of(TO_PAGES[index])]))
	return result


## The frozen request each transition row follows, parallel to [method table].
static func sources() -> PackedStringArray:
	return SOURCES.duplicate()


## The upper-case name of [param event], or "" when it is not an event.
static func event_name(event: int) -> String:
	var names := PackedStringArray(Event.keys())
	return names[event] if event >= 0 and event < names.size() else ""


## The event called [param name_text], or -1.
static func event_from_name(name_text: String) -> int:
	return PackedStringArray(Event.keys()).find(name_text)


static func _index_of(page: int, event: int) -> int:
	for index: int in FROM_PAGES.size():
		if FROM_PAGES[index] == page and EVENTS[index] == event:
			return index
	return -1


static func _page_label(page: int) -> String:
	var label: String = FrontEndPage.name_of(page)
	return label if not label.is_empty() else str(page)


static func _event_label(event: int) -> String:
	var label: String = event_name(event)
	return label if not label.is_empty() else str(event)

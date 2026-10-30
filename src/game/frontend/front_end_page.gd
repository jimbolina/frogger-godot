class_name FrontEndPage
extends RefCounted
## The single-player front-end pages, named after the frozen options pages they stand for.
##
## BOOT covers the version, logo, language and intro pages the port skips; MAIN_MENU is
## OPTIONS_PAGE_MAIN_OPTIONS; ENDING covers the jungle end-of-game sequence with the outro
## or credits pages that follow it. OPTIONS is OPTIONS_PAGE_OPTIONS and CONTROLS is the PC
## controller page OPTIONS_PAGE_CHOOSE_WIN_CONTROLLER (retail page 25).

enum Page { BOOT, MAIN_MENU, LEVEL_SELECT, GAME, LEVEL_COMPLETE, GAME_OVER, CONTINUE, ENDING, OPTIONS, CONTROLS }


## The upper-case name of [param page], or "" when it is not a page.
static func name_of(page: int) -> String:
	var names := PackedStringArray(Page.keys())
	return names[page] if page >= 0 and page < names.size() else ""


## The page called [param page_name], or -1.
static func from_name(page_name: String) -> int:
	return PackedStringArray(Page.keys()).find(page_name)

class_name FrontEndMusic
extends RefCounted
## The disc track each front-end page plays on retail PC, and what a page change does to it.
##
## The main menu, options, controller and high-score view pages share the menu tune, track 11
## (JUNGLE2), looping: PlayOptionsMusic (FROGGER.EXE 0x00446450) starts it only when it is not
## already playing, from the main menu's resting state (0x00440930), OptionsStartup (0x00443894)
## and HSViewStartup (0x0042c05f), so it plays on uninterrupted between them; the controller page
## makes no CD calls. ShutdownOptionsMusic (0x00446470) stops it on Start (0x00440c6b) and when a
## demo loads (0x00440375). The level select plays track 13 (LEVEL_SELECT), looping, from its
## startup (PlayCD(13, 1), 0x0040f079) and stops it at shutdown (0x0040f27a), so the main menu
## after it starts track 11 afresh. High-score name entry, like the intro and language pages,
## makes no CD calls and is silent.

## What a page change does to the music.
enum Change { KEEP, START, STOP }

## The options music, PlayOptionsMusic's PlayCD(11, 1).
const MENU_TRACK: int = 11
## The level-select music, PlayCD(13, 1).
const LEVEL_SELECT_TRACK: int = 13
## No track: the page makes no CD calls.
const SILENT: int = -1


## The looping track [param page] of [enum FrontEndPage.Page] plays, or [constant SILENT].
static func track_for_page(page: int) -> int:
	match page:
		FrontEndPage.Page.MAIN_MENU, FrontEndPage.Page.OPTIONS, FrontEndPage.Page.CONTROLS, FrontEndPage.Page.HIGH_SCORE_VIEW:
			return MENU_TRACK
		FrontEndPage.Page.LEVEL_SELECT:
			return LEVEL_SELECT_TRACK
	return SILENT


## The [enum Change] from [param playing], the track playing before, to [param next], the next
## page's track: KEEP when they match (PlayOptionsMusic leaves a playing track alone), STOP for a
## silent page, otherwise START [param next] from its beginning.
static func change(playing: int, next: int) -> int:
	if next == playing:
		return Change.KEEP
	if next == SILENT:
		return Change.STOP
	return Change.START

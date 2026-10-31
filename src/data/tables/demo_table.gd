class_name DemoTable
extends Resource
## The attract-mode demo list: which recorded demo plays on which level.
##
## Each row is three 32-bit values: level, demo file resource id, and the
## level that must be unlocked before the demo is shown; -2 in a row means
## "skip this row", and a row whose level is -1 ends the list. The PC release
## has two lists back to back: the first for low-poly levels (demos named
## [code]W*.DAT[/code]) and the second for high-poly levels. They list the
## same levels in the same order.
##
## The build's FrogLord version file does not give this table's address, so it
## is found the way FrogLord's [code]FroggerDemoTable[/code] finds it:
## [br]- A FrogLord-saved executable records it in its build information
##   ([code]demoTableAddress[/code], and [code]lowPolyDemoTable=true[/code] when
##   there are two lists).
## [br]- Otherwise the program is searched for the first row of Suburbia 1:
##   the level number 48 followed by the resource id of
##   [code]WSUB1DEMO.DAT[/code] (which also means there are two lists) or,
##   failing that, of [code]SUB1DEMO.DAT[/code].


## One row ([DemoTableEntry]); kept so existing references still resolve.
const Entry := preload("res://src/data/tables/demo_table_entry.gd")

## How the table's address was found: from FrogLord's build information.
const FOUND_IN_BUILD_INFO: String = "FrogLord build information"
## How the table's address was found: by searching the program.
const FOUND_BY_SEARCH: String = "search"
## Level number the search looks for (Suburbia 1).
const SEARCH_LEVEL: int = 48
## Level value ending a list.
const TERMINATOR: int = -1

## File offset of the (first) list, -1 when none was found.
@export var file_offset: int = -1
## True when the program has a low-poly list followed by a high-poly list.
@export var has_low_poly_list: bool = false
## [constant FOUND_IN_BUILD_INFO] or [constant FOUND_BY_SEARCH]; "" when not found.
@export var found_by: String = ""
## Rows in list order.
@export var entries: Array[DemoTableEntry] = []
## Why no table could be read, or "" (a build without demos is not an error).
@export var error: String = ""


## Finds and reads the demo table of [param exe], using [param mwi] to find
## the demo files (see [DemoTableReader]).
static func read(exe: ExeImage, mwi: MwiIndex) -> DemoTable:
	return DemoTableReader.read(exe, mwi)


## Number of rows.
func size() -> int:
	return entries.size()


## The first row for level [param level] that is not skipped, or null.
func entry_for_level(level: int) -> DemoTableEntry:
	for e: DemoTableEntry in entries:
		if e.level == level and not e.is_skipped():
			return e
	return null

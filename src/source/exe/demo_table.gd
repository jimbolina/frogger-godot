class_name DemoTable
extends RefCounted
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


## One row, with both lists' demo ids for its level.
class Entry:
	extends RefCounted
	## Value marking a row to skip.
	const SKIP: int = -2
	## Level number, or [constant SKIP].
	var level: int = 0
	## Demo resource id for high-poly levels (the only list when there is one).
	var demo_resource_id: int = 0
	## Level that must be unlocked first, or [constant SKIP].
	var unlock_level: int = 0
	## Demo resource id for low-poly levels (same as [member demo_resource_id]
	## when the build has one list).
	var low_poly_demo_resource_id: int = 0

	## True when the game skips this row.
	func is_skipped() -> bool:
		return level == SKIP or unlock_level == SKIP or demo_resource_id < 0

	## The demo for the chosen detail level.
	func demo_id(low_poly: bool = false) -> int:
		return low_poly_demo_resource_id if low_poly else demo_resource_id


## How the table's address was found: from FrogLord's build information.
const FOUND_IN_BUILD_INFO: String = "FrogLord build information"
## How the table's address was found: by searching the program.
const FOUND_BY_SEARCH: String = "search"
## Level number the search looks for (Suburbia 1).
const SEARCH_LEVEL: int = 48
## Level value ending a list.
const TERMINATOR: int = -1

## File offset of the (first) list, -1 when none was found.
var file_offset: int = -1
## True when the program has a low-poly list followed by a high-poly list.
var has_low_poly_list: bool = false
## [constant FOUND_IN_BUILD_INFO] or [constant FOUND_BY_SEARCH]; "" when not found.
var found_by: String = ""
## Rows in list order.
var entries: Array[Entry] = []
## Why no table could be read, or "" (a build without demos is not an error).
var error: String = ""


## Finds and reads the demo table of [param exe], using [param mwi] to find the demo files.
static func read(exe: ExeImage, mwi: MwiIndex) -> DemoTable:
	var table := DemoTable.new()
	var recorded: String = exe.trailer_value("demoTableAddress")
	if not recorded.is_empty():
		var address: Variant = FrogLordConfig.decode_integer(recorded)
		if not address is int:
			table.error = "the build information's demoTableAddress '%s' is not a number" % recorded
			return table
		var offset: int = address
		table.file_offset = offset
		table.has_low_poly_list = exe.trailer_value("lowPolyDemoTable").to_lower() == "true"
		table.found_by = FOUND_IN_BUILD_INFO
	else:
		table._search(exe, mwi)
	if table.file_offset >= 0:
		table._read_lists(exe)
	return table


## Number of rows.
func size() -> int:
	return entries.size()


## The first row for level [param level] that is not skipped, or null.
func entry_for_level(level: int) -> Entry:
	for e: Entry in entries:
		if e.level == level and not e.is_skipped():
			return e
	return null


func _search(exe: ExeImage, mwi: MwiIndex) -> void:
	var demo: MwiEntry = mwi.find_by_name("WSUB1DEMO.DAT")
	has_low_poly_list = demo != null
	if demo == null:
		demo = mwi.find_by_name("SUB1DEMO.DAT")
	if demo == null:
		return
	var pattern := PackedByteArray()
	pattern.resize(8)
	pattern.encode_s32(0, SEARCH_LEVEL)
	pattern.encode_s32(4, demo.index)
	file_offset = exe.find(pattern)
	if file_offset >= 0:
		found_by = FOUND_BY_SEARCH


func _read_lists(exe: ExeImage) -> void:
	var reader: ByteReader = exe.reader_at(file_offset)
	var first: Array[PackedInt32Array] = _read_rows(reader)
	if not has_low_poly_list:
		for row: PackedInt32Array in first:
			entries.append(_entry(row, row[1]))
		return
	var second: Array[PackedInt32Array] = _read_rows(reader)
	if first.size() != second.size():
		error = "the low-poly demo list has %d rows, the high-poly list %d" % [first.size(), second.size()]
		return
	for i: int in second.size():
		if first[i][0] != second[i][0] or first[i][2] != second[i][2]:
			error = "demo row %d names different levels in the two lists" % i
			entries.clear()
			return
		entries.append(_entry(second[i], first[i][1]))


func _read_rows(reader: ByteReader) -> Array[PackedInt32Array]:
	var rows: Array[PackedInt32Array] = []
	while reader.remaining() >= 12:
		var level: int = reader.read_s32()
		var demo: int = reader.read_s32()
		var unlock: int = reader.read_s32()
		if level == TERMINATOR:
			return rows
		rows.append(PackedInt32Array([level, demo, unlock]))
	error = "a demo list has no end marker"
	return rows


static func _entry(row: PackedInt32Array, low_poly_demo: int) -> Entry:
	var e := Entry.new()
	e.level = row[0]
	e.demo_resource_id = row[1]
	e.unlock_level = row[2]
	e.low_poly_demo_resource_id = low_poly_demo
	return e

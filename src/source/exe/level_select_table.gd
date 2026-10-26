class_name LevelSelectTable
extends RefCounted
## The level-select stacks: the arcade list followed directly by the race list.
##
## Each list ends with a row whose level is -1 (FrogLord's [code]readLevelData[/code]).
## [member arcade] and [member race] hold the real rows; the ending rows are
## kept apart in [member arcade_terminator] and [member race_terminator]
## (FrogLord keeps them in its lists).

## Arcade-mode levels in stack order.
var arcade: Array[LevelSelectEntry] = []
## Race-mode (multiplayer) levels in stack order.
var race: Array[LevelSelectEntry] = []
## The row ending the arcade list.
var arcade_terminator: LevelSelectEntry
## The row ending the race list.
var race_terminator: LevelSelectEntry
## Why reading failed, or "".
var error: String = ""


## Reads both lists of [param exe].
static func read(exe: ExeImage) -> LevelSelectTable:
	var table := LevelSelectTable.new()
	if exe.version.arcade_level_address <= 0:
		table.error = "this build has no level select address"
		return table
	var reader: ByteReader = exe.reader_at(exe.version.arcade_level_address)
	table.arcade_terminator = table._read_list(reader, table.arcade)
	if table.error.is_empty():
		table.race_terminator = table._read_list(reader, table.race)
	return table


## The arcade entry for level [param level], else the race entry, else null.
func entry_for_level(level: int) -> LevelSelectEntry:
	for e: LevelSelectEntry in arcade:
		if e.level == level:
			return e
	for e: LevelSelectEntry in race:
		if e.level == level:
			return e
	return null


func _read_list(reader: ByteReader, into: Array[LevelSelectEntry]) -> LevelSelectEntry:
	var e: LevelSelectEntry = null
	while e == null or not e.is_terminator():
		e = LevelSelectEntry.read(reader)
		if reader.has_error():
			error = "level select: %s" % reader.error
			return null
		if e.runtime_area_dirty:
			error = "level select row %d has data in its run-time area" % into.size()
			return null
		if not e.is_terminator():
			into.append(e)
	return e

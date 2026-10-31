class_name LevelSelectTableReader
extends RefCounted
## Reads the level-select stacks ([LevelSelectTable]) from the executable.


## Reads both lists of [param exe]: the arcade list, then the race list right after it.
static func read(exe: ExeImage) -> LevelSelectTable:
	var table := LevelSelectTable.new()
	if exe.version.arcade_level_address <= 0:
		table.error = "this build has no level select address"
		return table
	var reader: ByteReader = exe.reader_at(exe.version.arcade_level_address)
	table.arcade_terminator = _read_list(table, reader, table.arcade)
	if table.error.is_empty():
		table.race_terminator = _read_list(table, reader, table.race)
	return table


## Reads one entry ([LevelSelectEntry], 92 bytes) at [param reader]'s cursor.
static func read_entry(reader: ByteReader) -> LevelSelectEntry:
	var e := LevelSelectEntry.new()
	e.level = reader.read_s32()
	e.world = reader.read_s32()
	e.stack_position = reader.read_s32()
	e.theme = reader.read_s32()
	e.local_level = reader.read_s32()
	e.levels_in_world = reader.read_s32()
	for _i: int in 6:
		e.image_pointers.append(reader.read_u32())
	for _i: int in LevelSelectEntry.RUNTIME_SIZE:
		if reader.read_u8() != 0:
			e.runtime_area_dirty = true
	return e


static func _read_list(table: LevelSelectTable, reader: ByteReader, into: Array[LevelSelectEntry]) -> LevelSelectEntry:
	var e: LevelSelectEntry = null
	while e == null or not e.is_terminator():
		e = read_entry(reader)
		if reader.has_error():
			table.error = "level select: %s" % reader.error
			return null
		if e.runtime_area_dirty:
			table.error = "level select row %d has data in its run-time area" % into.size()
			return null
		if not e.is_terminator():
			into.append(e)
	return e

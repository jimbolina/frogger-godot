class_name DemoTableReader
extends RefCounted
## Finds and reads the attract-mode demo list ([DemoTable]) the way FrogLord's
## [code]FroggerDemoTable[/code] does: from FrogLord's build information, or
## by searching the program for Suburbia 1's first row.


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
		table.found_by = DemoTable.FOUND_IN_BUILD_INFO
	else:
		_search(table, exe, mwi)
	if table.file_offset >= 0:
		_read_lists(table, exe)
	return table


static func _search(table: DemoTable, exe: ExeImage, mwi: MwiIndex) -> void:
	var demo: MwiEntry = mwi.find_by_name("WSUB1DEMO.DAT")
	table.has_low_poly_list = demo != null
	if demo == null:
		demo = mwi.find_by_name("SUB1DEMO.DAT")
	if demo == null:
		return
	var pattern := PackedByteArray()
	pattern.resize(8)
	pattern.encode_s32(0, DemoTable.SEARCH_LEVEL)
	pattern.encode_s32(4, demo.index)
	table.file_offset = exe.find(pattern)
	if table.file_offset >= 0:
		table.found_by = DemoTable.FOUND_BY_SEARCH


static func _read_lists(table: DemoTable, exe: ExeImage) -> void:
	var reader: ByteReader = exe.reader_at(table.file_offset)
	var first: Array[PackedInt32Array] = _read_rows(table, reader)
	if not table.has_low_poly_list:
		for row: PackedInt32Array in first:
			table.entries.append(_entry(row, row[1]))
		return
	var second: Array[PackedInt32Array] = _read_rows(table, reader)
	if first.size() != second.size():
		table.error = "the low-poly demo list has %d rows, the high-poly list %d" % [first.size(), second.size()]
		return
	for i: int in second.size():
		if first[i][0] != second[i][0] or first[i][2] != second[i][2]:
			table.error = "demo row %d names different levels in the two lists" % i
			table.entries.clear()
			return
		table.entries.append(_entry(second[i], first[i][1]))


static func _read_rows(table: DemoTable, reader: ByteReader) -> Array[PackedInt32Array]:
	var rows: Array[PackedInt32Array] = []
	while reader.remaining() >= 12:
		var level: int = reader.read_s32()
		var demo: int = reader.read_s32()
		var unlock: int = reader.read_s32()
		if level == DemoTable.TERMINATOR:
			return rows
		rows.append(PackedInt32Array([level, demo, unlock]))
	table.error = "a demo list has no end marker"
	return rows


static func _entry(row: PackedInt32Array, low_poly_demo: int) -> DemoTableEntry:
	var e := DemoTableEntry.new()
	e.level = row[0]
	e.demo_resource_id = row[1]
	e.unlock_level = row[2]
	e.low_poly_demo_resource_id = low_poly_demo
	return e

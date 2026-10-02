extends GutTest
## Synthetic final-PC FORM records and bounded pointer failures.

func _tag(bytes: PackedByteArray, offset: int, value: String) -> void:
	var tag: PackedByteArray = value.to_ascii_buffer()
	for index: int in tag.size():
		bytes[offset + index] = tag[index]

func _map() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(608)
	_tag(bytes, 0, "FROG")
	bytes.encode_u32(4, bytes.size())
	_tag(bytes, 8, "2.00")
	var names: Array[String] = ["GENE", "GRAP", "FORM", "EMTP", "ZONE", "PATH", "LITE", "GROU", "POLY", "VRTX", "GRID", "ANIM"]
	var offsets: Array[int] = [100, 148, 524, 184, 196, 204, 212, 220, 312, 400, 432, 444]
	for index: int in names.size():
		_tag(bytes, offsets[index], names[index])
	for index: int in 6:
		bytes.encode_u32(76 + index * 4, offsets[index])
		bytes.encode_u32(152 + index * 4, offsets[index + 6])
	bytes.encode_u32(188, 12)
	bytes[242] = 1
	bytes.encode_u32(260, 372)
	bytes.encode_u16(320, 1)
	for index: int in 9:
		bytes.encode_u32(336 + index * 4, 372 if index == 2 else 400)
	bytes.encode_u16(372, 2)
	bytes.encode_u16(376, 1)
	bytes.encode_u16(378, 65535)
	bytes.encode_u16(404, 3)
	bytes.encode_s16(418, -256)
	bytes.encode_s16(424, 256)
	bytes.encode_u32(448, 1)
	bytes.encode_u32(452, 456)
	bytes[456] = 255
	bytes.encode_u16(458, 8)
	bytes.encode_u16(476, 1)
	bytes.encode_u16(478, 1)
	bytes.encode_u32(484, 488)
	bytes.encode_u32(488, 372)
	bytes.encode_u16(528, 2)
	bytes.encode_u32(532, 540)
	bytes.encode_u32(536, 584)
	bytes.encode_u16(540, 1)
	bytes.encode_s16(542, 0)
	bytes.encode_s16(544, 1)
	bytes.encode_s16(546, 3)
	bytes.encode_s16(548, -115)
	bytes.encode_s16(550, -386)
	bytes.encode_u32(552, 556)
	bytes.encode_u16(556, 0)
	bytes.encode_s16(558, -91)
	bytes.encode_u32(560, 568)
	bytes.encode_u32(564, 558)
	for index: int in 3:
		bytes.encode_u16(568 + index * 2, 3)
	bytes.encode_u16(574, 0xA341) # Exporter scratch is permitted.
	bytes.encode_s16(588, -32768)
	bytes.encode_s16(590, 32767)
	return bytes

func test_form_grid_and_empty_garbage_dimensions_are_retained() -> void:
	var map: MapFile = MapFile.read(_map())
	assert_eq(map.error, "")
	assert_eq(map.forms.size(), 2)
	var grid: MapForm = map.forms[0]
	assert_eq(grid.form_index, 0)
	assert_eq(grid.source_offset, 540)
	assert_eq(grid.end_offset, 584)
	assert_eq(grid.dimensions, Vector2i(1, 3))
	assert_eq(grid.offsets, Vector2i(-115, -386))
	assert_eq(grid.data[0].height_type, 0)
	assert_eq(grid.data[0].height, -91)
	assert_eq(grid.data[0].grid_flags, PackedInt32Array([3, 3, 3]))
	assert_eq(map.forms[1].data_count, 0)
	assert_eq(map.forms[1].dimensions, Vector2i(-32768, 32767))
	assert_false(map.forms[1].diagnostics.is_empty())

func test_bad_form_pointers_fail_without_crossing_record_boundaries() -> void:
	var bytes: PackedByteArray = _map()
	bytes.encode_u32(552, 585)
	assert_string_contains(MapFile.read(bytes).error, "FORM_DATA")
	bytes = _map()
	bytes.encode_u32(560, 583)
	assert_string_contains(MapFile.read(bytes).error, "grid flags")
	bytes = _map()
	bytes.encode_u16(540, 2)
	bytes.encode_u32(552, 560)
	bytes.encode_u32(556, 565)
	assert_string_contains(MapFile.read(bytes).error, "FORM_DATA")

func test_unsupported_height_mode_remains_decoded() -> void:
	var bytes: PackedByteArray = _map()
	bytes.encode_u16(556, 2)
	bytes.encode_u32(564, 555) # Metadata only; never dereferenced in GRID mode.
	var map: MapFile = MapFile.read(bytes)
	assert_eq(map.error, "")
	assert_eq(map.forms[0].data[0].height_type, 2)
	assert_eq(map.forms[0].data[0].grid_flags, PackedInt32Array([3, 3, 3]))
	assert_eq(map.forms[0].data[0].diagnostics.size(), 2)

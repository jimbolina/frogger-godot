extends GutTest
## Synthetic final-PC PATH bounds and raw-payload contracts.

func _tag(bytes: PackedByteArray, offset: int, value: String) -> void:
	var data: PackedByteArray = value.to_ascii_buffer()
	for i: int in data.size():
		bytes[offset + i] = data[i]

func _base() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(520)
	_tag(b, 0, "FROG")
	_tag(b, 8, "2.00")
	var names: Array[String] = ["GENE", "GRAP", "FORM", "EMTP", "ZONE", "PATH", "LITE", "GROU", "POLY", "VRTX", "GRID", "ANIM"]
	var offsets: Array[int] = [100, 148, 176, 184, 196, 204, 212, 220, 312, 400, 432, 444]
	for i: int in names.size():
		_tag(b, offsets[i], names[i])
	for i: int in 6:
		b.encode_u32(76 + i * 4, offsets[i])
		b.encode_u32(152 + i * 4, offsets[i + 6])
	b.encode_u32(188, 12)
	b[242] = 1
	b.encode_u32(260, 372)
	b.encode_u16(320, 1)
	for i: int in 9:
		b.encode_u32(336 + i * 4, 372 if i == 2 else 400)
	b.encode_u16(372, 2)
	b.encode_u16(374, 0)
	b.encode_u16(376, 1)
	b.encode_u16(378, 1)
	b.encode_u16(404, 3)
	b.encode_u32(448, 1)
	b.encode_u32(452, 456)
	b.encode_u16(458, 8)
	b.encode_u16(476, 1)
	b.encode_u16(478, 1)
	b.encode_u32(484, 488)
	b.encode_u32(488, 372)
	return b

func _one_path(segment_type: int, segment_size: int) -> PackedByteArray:
	var b: PackedByteArray = _base()
	b.resize(544 + segment_size)
	b.encode_u32(4, b.size())
	b.encode_u32(96, 520)
	_tag(b, 520, "PATH")
	b.encode_u32(524, 1)
	b.encode_u32(528, 532)
	b.encode_u32(532, 0xFFFFFFF0)
	b.encode_u32(536, 1)
	b.encode_u32(540, 544)
	b.encode_u32(544, segment_type)
	b.encode_s32(548, 4096)
	return b

func test_line_decode_preserves_identity_and_external_entity_pointer() -> void:
	var bytes: PackedByteArray = _one_path(2, 24)
	bytes.encode_s16(552, -100)
	bytes.encode_s16(554, 200)
	bytes.encode_s16(556, 300)
	bytes.encode_s16(560, 400)
	var map: MapFile = MapFileReader.read(bytes)
	assert_eq(map.error, "")
	assert_eq(map.paths.size(), 1)
	assert_eq(map.paths[0].path_index, 0)
	assert_eq(map.paths[0].entity_list_pointer, 0xFFFFFFF0)
	assert_eq(map.paths[0].segments[0].source_offset, 544)
	assert_eq(map.paths[0].segments[0].end_offset, 568)
	assert_eq(map.paths[0].segments[0].length, 4096)
	assert_eq(map.paths[0].segments[0].start, Vector3i(-100, 200, 300))
	assert_eq(map.paths[0].segments[0].end.x, 400)

func test_arc_and_spline_keep_encoded_values() -> void:
	var arc: PackedByteArray = _one_path(1, 40)
	arc.encode_s16(552, -12)
	arc.encode_s16(560, 13)
	arc.encode_s16(568, -14)
	arc.encode_s32(576, -500)
	arc.encode_s32(580, 600)
	var arc_map: MapFile = MapFileReader.read(arc)
	assert_eq(arc_map.error, "")
	assert_eq(arc_map.paths[0].segments[0].start.x, -12)
	assert_eq(arc_map.paths[0].segments[0].centre.x, 13)
	assert_eq(arc_map.paths[0].segments[0].normal.x, -14)
	assert_eq(arc_map.paths[0].segments[0].radius, -500)
	assert_eq(arc_map.paths[0].segments[0].pitch, 600)
	var spline: PackedByteArray = _one_path(0, 120)
	for i: int in 12:
		spline.encode_s32(552 + i * 4, i - 6)
		spline.encode_s32(616 + i * 4, i * -3)
	for i: int in 4:
		spline.encode_s32(600 + i * 4, i * 7)
	var spline_map: MapFile = MapFileReader.read(spline)
	assert_eq(spline_map.error, "")
	assert_eq(spline_map.paths[0].segments[0].matrix.size(), 12)
	assert_eq(spline_map.paths[0].segments[0].matrix[0], -6)
	assert_eq(spline_map.paths[0].segments[0].smooth_t[3], 21)
	assert_eq(spline_map.paths[0].segments[0].smooth_c[11], -33)

func test_path_count_pointer_and_payload_bounds() -> void:
	var bytes: PackedByteArray = _one_path(2, 24)
	bytes.encode_u32(524, 1000)
	assert_string_contains(MapFileReader.read(bytes).error, "PATH pointer table")
	bytes.encode_u32(524, 1)
	bytes.encode_u32(528, 544)
	assert_string_contains(MapFileReader.read(bytes).error, "PATH segment pointer table")
	bytes.encode_u32(528, 532)
	bytes.encode_u32(536, 1000)
	assert_string_contains(MapFileReader.read(bytes).error, "segment pointer table")
	bytes.encode_u32(536, 1)
	bytes.encode_u32(540, 530)
	assert_string_contains(MapFileReader.read(bytes).error, "Invalid PATH segment pointer")
	bytes.encode_u32(540, 544)
	assert_string_contains(MapFileReader.read(bytes.slice(0, 560)).error, "PATH segment payload")

func test_unknown_bounded_type_retains_identity() -> void:
	var bytes: PackedByteArray = _one_path(99, 12)
	var map: MapFile = MapFileReader.read(bytes)
	assert_eq(map.error, "")
	assert_eq(map.paths[0].segments[0].segment_type, 99)
	assert_eq(map.paths[0].segments[0].end_offset, bytes.size())
	assert_true(map.warnings.any(func(warning: String) -> bool: return warning.contains("Unknown PATH segment type")))

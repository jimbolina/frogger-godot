extends GutTest
## Synthetic ZONE packet spans and signed camera rectangles.

func _tag(bytes: PackedByteArray, offset: int, value: String) -> void:
	var word: PackedByteArray = value.to_ascii_buffer()
	for i: int in word.size():
		bytes[offset + i] = word[i]

func _map() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(724)
	_tag(b, 0, "FROG")
	b.encode_u32(4, b.size())
	_tag(b, 8, "2.00")
	var names: Array[String] = ["GENE", "GRAP", "FORM", "EMTP", "ZONE", "PATH", "LITE", "GROU", "POLY", "VRTX", "GRID", "ANIM"]
	var offsets: Array[int] = [100, 148, 176, 184, 520, 204, 212, 220, 312, 400, 432, 444]
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
	b.encode_u16(376, 1)
	b.encode_u16(378, 65535)
	b[396] = 20
	b.encode_u16(404, 3)
	b.encode_u32(448, 1)
	b.encode_u32(452, 456)
	b.encode_u16(458, 8)
	b.encode_u16(476, 1)
	b.encode_u16(478, 1)
	b.encode_u32(484, 488)
	b.encode_u32(488, 372)
	b.encode_u32(524, 2)
	b.encode_u32(528, 540)
	b.encode_u32(532, 640)
	b.encode_u16(540, 0)
	b.encode_u16(542, 2)
	var outer_a := PackedInt32Array([13, 22, 18, 32])
	for i: int in 4:
		b.encode_s16(544 + i * 2, outer_a[i])
	b.encode_u32(552, 624)
	b.encode_u16(556, 0x14)
	b.encode_s16(558, -1)
	b.encode_s16(560, -123)
	b.encode_s16(562, 456)
	b.encode_s16(564, -789)
	var child_a := PackedInt32Array([15, 22, 18, 32])
	var child_b := PackedInt32Array([13, 23, 14, 23])
	for i: int in 4:
		b.encode_s16(624 + i * 2, child_a[i])
		b.encode_s16(632 + i * 2, child_b[i])
	b.encode_u16(640, 0)
	b.encode_u16(642, 0)
	var outer_b := PackedInt32Array([12, 40, 15, 39])
	for i: int in 4:
		b.encode_s16(644 + i * 2, outer_b[i])
	b.encode_s16(658, 1)
	return b

func test_ordered_regions_camera_and_inverted_bounds() -> void:
	var map: MapFile = MapFile.read(_map())
	assert_eq(map.error, "")
	assert_eq(map.zones.size(), 2)
	assert_eq(map.zones[0].source_offset, 540)
	assert_eq(map.zones[0].end_offset, 640)
	assert_eq(map.zones[0].bounds, PackedInt32Array([13, 22, 18, 32]))
	assert_eq(map.zones[0].camera_flags, 0x14)
	assert_eq(map.zones[0].camera_direction, -1)
	assert_eq(map.zones[0].camera_offsets.size(), 8)
	assert_eq(map.zones[0].camera_offsets[0], Vector3i(-123, 456, -789))
	assert_eq(map.zones[0].regions[1].source_offset, 632)
	assert_eq(map.zones[0].regions[1].bounds, PackedInt32Array([13, 23, 14, 23]))
	assert_eq(map.zones[1].bounds, PackedInt32Array([12, 40, 15, 39]))
	assert_eq(map.zones[1].regions.size(), 0)

func test_broken_zone_records_retain_map_with_source_diagnostics() -> void:
	var bytes: PackedByteArray = _map()
	bytes.encode_u32(552, 700)
	var map: MapFile = MapFile.read(bytes)
	assert_eq(map.error, "")
	assert_string_contains(map.zones[0].diagnostics[0], "540")
	bytes = _map()
	bytes.encode_u32(532, 632)
	map = MapFile.read(bytes)
	assert_eq(map.error, "")
	assert_string_contains(map.zones[0].diagnostics[0], "region pointer")
	bytes = _map()
	bytes.encode_u32(532, 700)
	map = MapFile.read(bytes)
	assert_eq(map.error, "")
	assert_string_contains(map.zones[1].diagnostics[0], "84-byte")
	bytes = _map()
	bytes.encode_u32(532, 540)
	map = MapFile.read(bytes)
	assert_eq(map.error, "")
	assert_string_contains(map.zones[1].diagnostics[0], "duplicate")
	bytes = _map()
	bytes.encode_u32(532, 530)
	map = MapFile.read(bytes)
	assert_eq(map.error, "")
	assert_string_contains(map.zones[1].diagnostics[0], "invalid")

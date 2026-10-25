extends GutTest
## Synthetic map pointer and corner-order contracts, without retail assets.

func _tag(bytes: PackedByteArray, offset: int, value: String) -> void:
	var data: PackedByteArray = value.to_ascii_buffer()
	for i: int in data.size():
		bytes[offset + i] = data[i]

func _map() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(520)
	_tag(b, 0, "FROG")
	b.encode_u32(4, b.size())
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
	b.encode_u16(378, 65535)
	b[396] = 20
	b[397] = 40
	b[398] = 60
	b.encode_u16(404, 3)
	b.encode_s16(418, -256)
	b.encode_s16(424, 256)
	b.encode_u32(448, 1)
	b.encode_u32(452, 456)
	b[456] = 255
	b.encode_u16(458, 8)
	b.encode_u16(476, 1)
	b.encode_u16(478, 1)
	b.encode_u32(484, 488)
	b.encode_u32(488, 372)
	return b

func test_corner_identity_and_inactive_padding() -> void:
	var map: MapFile = MapFile.read(_map())
	assert_eq(map.error, "")
	assert_eq(map.vertices[1], Vector3i(0, -256, 0))
	assert_eq(map.polygons[0].vertex_indices, PackedInt32Array([2, 0, 1]))
	assert_eq(map.polygons[0].grid_vertex_indices, PackedInt32Array([2, 0, 1, 65535]))
	assert_eq(map.polygons[0].colors[0], Color8(20, 40, 60))
	assert_eq(map.groups[0].polygon_indices, PackedInt32Array([0]))
	assert_false(map.groups[0].visible)
	assert_eq(map.animations[0].delta_u, -1)
	assert_eq(map.animations[0].target_polygon_indices, PackedInt32Array([0]))

func test_ordered_grid_records_and_invalid_polygon_pointer() -> void:
	var bytes: PackedByteArray = _map()
	bytes.resize(568)
	bytes.encode_u32(4, bytes.size())
	bytes.encode_u32(168, 524)
	_tag(bytes, 524, "GRID")
	bytes.encode_u16(528, 2)
	bytes.encode_u16(530, 2)
	bytes.encode_u16(532, 256)
	bytes.encode_u16(534, 256)
	bytes[536] = 2
	bytes[537] = 255
	for i: int in range(1, 4):
		bytes.encode_u16(538 + i * 4, 2)
	bytes.encode_u32(552, 0x80000003)
	bytes.encode_u32(556, 372)
	bytes.encode_u32(560, 8)
	bytes.encode_u32(564, 372)
	var map: MapFile = MapFile.read(bytes)
	assert_eq(map.error, "")
	assert_eq(map.grid_stacks.size(), 4)
	assert_eq(map.grid_stacks[0].source_offset, 536)
	assert_eq(map.grid_stacks[0].cliff_height_byte, 255)
	assert_eq(map.grid_squares[0].flags, 0x80000003)
	assert_eq(map.grid_squares[1].polygon_index, 0)
	assert_string_contains(TerrainGridSetup.from_map(map).error, "fourth")
	bytes.encode_u16(378, 1)
	map = MapFile.read(bytes)
	var setup: TerrainGridSetup = TerrainGridSetup.from_map(map)
	assert_eq(setup.error, "")
	assert_eq(setup.definition.stacks[0].source_offset, 536)
	assert_eq(setup.definition.squares[0].source_offset, 552)
	assert_eq(setup.definition.squares[0].polygon_index, 0)
	assert_eq(setup.definition.squares[0].polygon_source_offset, 372)
	assert_eq(setup.definition.squares[0].vertices[3], map.vertices[1])
	map.vertices[1] = Vector3i(1, 2, 3)
	assert_eq(setup.definition.squares[0].vertices[3], Vector3i(0, -256, 0))
	bytes.encode_u32(556, 374)
	assert_string_contains(MapFile.read(bytes).error, "Grid square pointer")
	bytes.encode_u32(556, 372)
	bytes.encode_u16(542, 1)
	assert_string_contains(MapFile.read(bytes).error, "not contiguous")
	bytes.encode_u16(542, 2)
	assert_string_contains(MapFile.read(bytes.slice(0, 564)).error, "grid squares")
	bytes.encode_u16(532, 128)
	map = MapFile.read(bytes)
	assert_eq(map.error, "")
	assert_true(map.warnings.any(func(value: String) -> bool: return value.contains("non-256")))
	assert_string_contains(TerrainGridSetup.from_map(map).error, "256-unit")
	bytes.encode_u16(532, 256)
	bytes.encode_u16(528, 1)
	bytes.encode_u16(542, 2)
	bytes.encode_u32(548, 372)
	bytes.encode_u32(556, 372)
	map = MapFile.read(bytes)
	assert_eq(map.error, "")
	assert_true(map.warnings.any(func(value: String) -> bool: return value.contains("odd")))
	assert_eq(TerrainGridSetup.from_map(map).error, "")

func test_unreferenced_polygon_is_retained_and_reported() -> void:
	var bytes: PackedByteArray = _map()
	bytes[242] = 0
	var map: MapFile = MapFile.read(bytes)
	assert_eq(map.error, "")
	assert_eq(map.polygons.size(), 1)
	assert_eq(map.warnings.size(), 1)

func test_active_vertex_and_group_and_animation_pointers_are_checked() -> void:
	var bytes: PackedByteArray = _map()
	bytes.encode_u16(372, 3)
	assert_false(MapFile.read(bytes).error.is_empty())
	bytes = _map()
	bytes.encode_u32(260, 374)
	assert_false(MapFile.read(bytes).error.is_empty())
	bytes = _map()
	bytes.encode_u32(488, 374)
	assert_false(MapFile.read(bytes).error.is_empty())

func test_truncation_version_and_count_bounds() -> void:
	var bytes: PackedByteArray = _map()
	assert_false(MapFile.read(bytes.slice(0, 96)).error.is_empty())
	bytes[8] = 51
	assert_false(MapFile.read(bytes).error.is_empty())
	bytes = _map()
	bytes.encode_u16(404, 65535)
	assert_false(MapFile.read(bytes).error.is_empty())

func test_sky_tile_identity_rotation_and_bounds() -> void:
	var bytes := PackedByteArray([2, 0, 1, 0, 7, 0, 9, 192])
	var sky: SkyLandFile = SkyLandFile.read(bytes)
	assert_eq(sky.error, "")
	assert_eq(sky.dimensions, Vector2i(2, 1))
	assert_eq(sky.texture_ids, PackedInt32Array([7, 9]))
	assert_eq(sky.rotations, PackedInt32Array([0, 3]))
	assert_false(SkyLandFile.read(bytes.slice(0, 7)).error.is_empty())


func test_animation_and_entity_header_overlaps_set_errors() -> void:
	var bytes: PackedByteArray = _map()
	bytes.encode_u32(452, 444)
	assert_false(MapFile.read(bytes).error.is_empty())
	bytes = _map()
	bytes.encode_u32(484, 460)
	assert_false(MapFile.read(bytes).error.is_empty())
	bytes = _map()
	bytes.encode_u16(476, 2)
	bytes.encode_u16(464, 1)
	bytes.encode_u32(468, 460)
	assert_false(MapFile.read(bytes).error.is_empty())
	bytes = _map()
	bytes.encode_u32(188, 8)
	assert_false(MapFile.read(bytes).error.is_empty())

func test_animation_rejects_untextured_target_layout() -> void:
	var bytes: PackedByteArray = _map()
	bytes.encode_u16(320, 0)
	bytes.encode_u16(316, 1)
	bytes.encode_u32(336, 372)
	bytes[242] = 0
	bytes[240] = 1
	bytes.encode_u32(252, 372)
	assert_string_contains(MapFile.read(bytes).error, "untextured")

func test_static_entity_pointer_cannot_overlap_group_headers() -> void:
	var bytes: PackedByteArray = _map()
	bytes.encode_u32(288, 224)
	assert_string_contains(MapFile.read(bytes).error, "Static entity pointer")

func test_entity_packet_length_field_is_bounded_before_decode() -> void:
	var bytes: PackedByteArray = _map()
	bytes.encode_u32(88, 516)
	_tag(bytes, 516, "EMTP")
	assert_string_contains(MapFile.read(bytes).error, "EMTP length field")

func test_polygon_type_byte_ranges_cannot_intersect() -> void:
	var bytes: PackedByteArray = _map()
	bytes.encode_u16(316, 1)
	bytes.encode_u32(336, 374)
	assert_string_contains(MapFile.read(bytes).error, "byte ranges overlap")

func test_unknown_textured_flags_are_retained_and_warned() -> void:
	var bytes: PackedByteArray = _map()
	bytes.encode_u16(380, 8)
	var map: MapFile = MapFile.read(bytes)
	assert_eq(map.error, "")
	assert_eq(map.polygons[0].flags, 8)
	assert_eq(map.warnings.size(), 1)

func test_texture_animation_requires_bounded_initial_cel() -> void:
	var bytes: PackedByteArray = _map()
	bytes.encode_u16(476, 2)
	assert_string_contains(MapFile.read(bytes).error, "requires cels")
	bytes.encode_u16(464, 1)
	bytes.encode_u16(466, 1)
	bytes.encode_u32(468, 500)
	assert_string_contains(MapFile.read(bytes).error, "bounded initial cel")

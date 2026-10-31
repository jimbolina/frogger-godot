extends GutTest
## Synthetic map polygons, grid stacks and squares survive packed-column storage and resource round trips.

const ROOT: String = "user://test_map_file_storage"


func after_each() -> void:
	if not DirAccess.dir_exists_absolute(ROOT):
		return
	for file: String in DirAccess.get_files_at(ROOT):
		DirAccess.remove_absolute(ROOT.path_join(file))
	DirAccess.remove_absolute(ROOT)


func _polygon(type_index: int, index: int, textured: bool) -> MapPolygon:
	var polygon := MapPolygon.new()
	polygon.type_index = type_index
	polygon.index = index
	polygon.source_offset = 1000 + index * 40
	polygon.vertex_indices = PackedInt32Array([index, index + 1, index + 2, index + 3])
	polygon.grid_vertex_indices = PackedInt32Array([index, index + 1, index + 2, 65535])
	polygon.raw_words = PackedInt32Array([1, 65535, 3, index])
	polygon.colors = PackedColorArray([Color8(20, 40, 60), Color(0.125, 0.5, 0.75)])
	if textured:
		polygon.uvs = PackedVector2Array([Vector2(1.0, 0.0), Vector2(17, 255) / 255.0, Vector2(0.5, 0.25)])
		polygon.texture_id = -2
		polygon.flags = 0x8007
	polygon.visible = index % 2 == 0
	return polygon


func _square(index: int, flags: int) -> MapGridSquare:
	var square := MapGridSquare.new()
	square.source_offset = 4000 + index * 8
	square.flags = flags
	square.polygon_pointer = 1000 + index * 40
	square.polygon_index = index
	return square


func _map() -> MapFile:
	var map := MapFile.new()
	map.version = "2.00"
	map.polygons.append(_polygon(7, 0, true))
	map.polygons.append(_polygon(5, 1, false))
	map.polygons.append(_polygon(8, 2, false))
	map.grid_squares.append(_square(0, 0xFFFFFFFF))
	map.grid_squares.append(_square(2, 0x1))
	var stack := MapGridStack.new()
	stack.source_offset = 3000
	stack.square_count = 2
	stack.cliff_height_byte = 255
	stack.first_square_index = 7
	map.grid_stacks.append(stack)
	map.grid_stacks.append(MapGridStack.new())
	var group := MapGroup.new()
	group.polygon_indices = PackedInt32Array([0, 2])
	map.groups.append(group)
	map.packets["GRID"] = MapPacket.new()
	return map


func _assert_polygons(actual: Array[MapPolygon], expected: Array[MapPolygon]) -> void:
	assert_eq(actual.size(), expected.size())
	for i: int in mini(actual.size(), expected.size()):
		var got: MapPolygon = actual[i]
		var want: MapPolygon = expected[i]
		assert_eq([got.type_index, got.index, got.source_offset, got.texture_id, got.flags, got.visible],
			[want.type_index, want.index, want.source_offset, want.texture_id, want.flags, want.visible])
		assert_eq(got.vertex_indices, want.vertex_indices)
		assert_eq(got.grid_vertex_indices, want.grid_vertex_indices)
		assert_eq(got.raw_words, want.raw_words)
		assert_eq(got.colors, want.colors)
		assert_eq(got.uvs, want.uvs)


func _assert_squares(actual: Array[MapGridSquare], expected: Array[MapGridSquare]) -> void:
	assert_eq(actual.size(), expected.size())
	for i: int in mini(actual.size(), expected.size()):
		assert_eq([actual[i].source_offset, actual[i].flags, actual[i].polygon_pointer, actual[i].polygon_index],
			[expected[i].source_offset, expected[i].flags, expected[i].polygon_pointer, expected[i].polygon_index])


func _assert_stacks(actual: Array[MapGridStack], expected: Array[MapGridStack]) -> void:
	assert_eq(actual.size(), expected.size())
	for i: int in mini(actual.size(), expected.size()):
		assert_eq([actual[i].source_offset, actual[i].square_count, actual[i].cliff_height_byte, actual[i].first_square_index],
			[expected[i].source_offset, expected[i].square_count, expected[i].cliff_height_byte, expected[i].first_square_index])


func test_columns_rebuild_every_polygon_and_square_field() -> void:
	var map: MapFile = _map()
	var rebuilt := MapFile.new()
	rebuilt.polygon_records = map.polygon_records
	rebuilt.polygon_words = map.polygon_words
	rebuilt.polygon_colors = map.polygon_colors
	rebuilt.polygon_uvs = map.polygon_uvs
	rebuilt.grid_square_records = map.grid_square_records
	rebuilt.grid_stack_records = map.grid_stack_records
	_assert_stacks(rebuilt.grid_stacks, map.grid_stacks)
	_assert_polygons(rebuilt.polygons, map.polygons)
	_assert_squares(rebuilt.grid_squares, map.grid_squares)
	var polygon_script: Script = rebuilt.polygons.get_typed_script()
	assert_eq(polygon_script.get_global_name(), &"MapPolygon")


func test_truncated_columns_stop_before_an_unsupplied_record() -> void:
	var map: MapFile = _map()
	var words: PackedInt32Array = map.polygon_words
	var squares: PackedInt64Array = map.grid_square_records
	assert_eq(MapColumns.build_polygons(map.polygon_records, words.slice(0, words.size() - 1),
		map.polygon_colors, map.polygon_uvs).size(), 2)
	assert_eq(MapColumns.build_grid_squares(squares.slice(0, squares.size() - 1)).size(), 1)
	var stacks: PackedInt32Array = map.grid_stack_records
	assert_eq(MapColumns.build_grid_stacks(stacks.slice(0, stacks.size() - 1)).size(), 1)


func test_assigning_polygons_replaces_pending_columns() -> void:
	var map: MapFile = _map()
	var loaded := MapFile.new()
	loaded.polygon_records = map.polygon_records
	var replacement: Array[MapPolygon] = [_polygon(2, 9, true)]
	loaded.polygons = replacement
	_assert_polygons(loaded.polygons, replacement)
	assert_eq(loaded.polygon_records, MapColumns.polygon_records(replacement))


func test_binary_and_text_resources_round_trip_maps() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var map: MapFile = _map()
	map.polygons[1].visible = true
	for extension: String in ["res", "tres"]:
		var path: String = ROOT.path_join("map." + extension)
		assert_eq(ResourceSaver.save(map, path), OK, extension)
		var loaded: MapFile = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapFile
		assert_not_null(loaded, extension)
		if loaded == null:
			continue
		_assert_polygons(loaded.polygons, map.polygons)
		_assert_squares(loaded.grid_squares, map.grid_squares)
		_assert_stacks(loaded.grid_stacks, map.grid_stacks)
		assert_eq(loaded.version, "2.00")
		assert_eq(loaded.groups[0].polygon_indices, PackedInt32Array([0, 2]))
		var group_script: Script = loaded.groups.get_typed_script()
		assert_eq(group_script.get_global_name(), &"MapGroup")
		assert_true(loaded.packets["GRID"] is MapPacket)

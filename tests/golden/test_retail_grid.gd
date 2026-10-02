extends RetailTest
## Every authored retail GRID record and calculation corner matches Python facts.

var _data: GameData

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func test_all_grid_records_geometry_and_surface_averages() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("grid_facts.tsv")
	rows.pop_front()
	assert_eq(rows.size(), 78)
	var problems := PackedStringArray()
	for row: PackedStringArray in rows:
		var file: MapFile = _data.read_map(int(row[0]), problems)
		assert_not_null(file, row[1])
		if file == null:
			continue
		var packet: MapPacket = file.packets["GRID"]
		var grid := GridDefinition.new()
		grid.base = Vector2i(-(packet.dimensions.x * packet.cell_size.x >> 1), -(packet.dimensions.y * packet.cell_size.y >> 1))
		var stacks := PackedInt64Array()
		for stack: MapGridStack in file.grid_stacks:
			stacks.append_array(PackedInt64Array([stack.square_count, stack.cliff_height_byte, stack.first_square_index]))
		var records := PackedInt64Array()
		var geometry := PackedInt64Array()
		var heights := PackedInt64Array()
		var centres := PackedInt64Array()
		for record: MapGridSquare in file.grid_squares:
			records.append_array(PackedInt64Array([record.flags, record.polygon_pointer, record.polygon_index]))
			var polygon: MapPolygon = file.polygons[record.polygon_index]
			var square := GridSquareDefinition.new()
			for index: int in polygon.grid_vertex_indices:
				geometry.append(index)
				square.vertices.append(file.vertices[index])
			for vertex: Vector3i in square.vertices:
				geometry.append_array(PackedInt64Array([vertex.x, vertex.y, vertex.z]))
			heights.append(GridQueries.square_height(square))
			var centre: Vector3i = GridQueries.square_centre(grid, square)
			centres.append_array(PackedInt64Array([centre.x, centre.y, centre.z]))
		var actual: Array = [int(row[0]), row[1], packet.dimensions.x, packet.dimensions.y,
			packet.cell_size.x, packet.cell_size.y, grid.base.x, grid.base.y,
			file.grid_stacks.size(), file.grid_squares.size(), GoldenFiles.list_digest(stacks),
			GoldenFiles.list_digest(records), GoldenFiles.list_digest(geometry),
			GoldenFiles.list_digest(heights), GoldenFiles.list_digest(centres)]
		for i: int in row.size():
			assert_eq(str(actual[i]), row[i], "%s column %d" % [row[1], i])
	assert_eq(problems.size(), 0, str(problems))

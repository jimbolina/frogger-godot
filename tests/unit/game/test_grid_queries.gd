extends GutTest
## Independent Python/frozen-C facts exercise static grid algorithms.

func _i(value: Variant) -> int:
	var number: float = value
	return int(number)

func _v(values: Array, start: int = 0) -> Vector3i:
	return Vector3i(_i(values[start]), _i(values[start + 1]), _i(values[start + 2]))

func test_independent_c_grid_query_corpus() -> void:
	_assert_corpus("res://tests/golden/synthetic/grid.json")

func test_independent_odd_grid_and_signed16_centre_corpus() -> void:
	_assert_corpus("res://tests/golden/synthetic/grid_odd.json")

func test_independent_signed32_grid_width_and_double_normal_corpus() -> void:
	_assert_corpus("res://tests/golden/synthetic/grid_width.json")

func _assert_corpus(path: String) -> void:
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var grid := GridDefinition.new()
	grid.base = Vector2i(_i(facts.base[0]), _i(facts.base[1]))
	grid.dimensions = Vector2i(_i(facts.dimensions[0]), _i(facts.dimensions[1]))
	for record: Array in facts.stacks:
		var stack := GridStackDefinition.new()
		stack.square_count = _i(record[0])
		stack.first_square_index = _i(record[1])
		grid.stacks.append(stack)
	for record: Array in facts.squares:
		var square := GridSquareDefinition.new()
		for vertex: Array in record:
			square.vertices.append(_v(vertex))
		grid.squares.append(square)
	for row: Array in facts.expected:
		var index: int = _i(row[1])
		if row[0] == "W":
			var query: Array = facts.queries[index]
			assert_eq(GridQueries.world_to_cell(grid, _i(query[0]), _i(query[2])), Vector2i(_i(row[2]), _i(row[3])))
			assert_null(GridQueries.info_at(grid, _i(query[0]), _i(query[2])))
		elif row[0] == "S":
			var square: GridSquareDefinition = grid.squares[index]
			assert_eq(GridQueries.square_height(square), _i(row[2]), str(row))
			assert_eq(GridQueries.square_centre(grid, square), _v(row, 3), str(row))
			assert_eq(GridQueries.average_normal(square), _v(row, 6), str(row))
		else:
			var query: Array = facts.queries[index]
			var selected: GridSurfaceInfo = GridQueries.height_at(grid, _i(query[0]), _i(query[1]), _i(query[2]))
			if _i(row[3]) < 0:
				assert_null(selected, str(row))
				assert_null(GridQueries.info_at(grid, _i(query[0]), _i(query[2])), str(row))
			else:
				assert_not_null(selected, str(row))
				assert_eq(selected.height, _i(row[2]), str(row))
				assert_eq(selected.square_index, _i(row[3]), str(row))
				var first: GridSurfaceInfo = GridQueries.info_at(grid, _i(query[0]), _i(query[2]))
				assert_eq(first.height, _i(row[4]), str(row))
				assert_eq(first.x_slope, _v(row, 5), str(row))
				assert_eq(first.z_slope, _v(row, 8), str(row))

func test_negative_boundaries_empty_cells_and_unsigned_cliff() -> void:
	var grid := GridDefinition.new()
	grid.dimensions = Vector2i(2, 2)
	grid.base = Vector2i(-256, -256)
	for i: int in 4:
		grid.stacks.append(GridStackDefinition.new())
	assert_eq(GridQueries.world_to_cell(grid, -257, -257), Vector2i(-1, -1))
	assert_eq(GridQueries.world_to_cell(grid, 255, 255), Vector2i(1, 1))
	assert_null(GridQueries.info_at(grid, -257, 0))
	assert_null(GridQueries.height_at(grid, 0, 0, 0))
	grid.stacks[0].cliff_height_byte = 255
	assert_eq(GridQueries.stack_height(grid.stacks[0]), 16320)

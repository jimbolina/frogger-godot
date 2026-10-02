extends GutTest
## Independent actual-C terrain matrix facts; no GDScript-derived expectations.

func test_source_rotation_corpus() -> void:
	var file: FileAccess = FileAccess.open("res://tests/golden/synthetic/terrain_matrix.csv", FileAccess.READ)
	assert_not_null(file)
	file.get_csv_line()
	var heights: Array[PackedInt32Array] = [PackedInt32Array([0, 0, 0, 0]), PackedInt32Array([0, 256, 0, 256]), PackedInt32Array([-3, 257, -131, 121]), PackedInt32Array([100, 120, 80, 80]), PackedInt32Array([300, -200, -100, 400])]
	for scenario: int in range(7):
		for direction: int in range(4):
			var row: PackedStringArray = file.get_csv_line()
			var previous: PackedInt32Array = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, -128, 0, -128])
			if scenario >= 5:
				previous = PackedInt32Array([3000, 1000, 0, 0, 3500, -1000, 100, 0, 3500, -128, 0, -128])
			var square := GridSquareDefinition.new()
			if scenario < 5:
				var h: PackedInt32Array = heights[scenario]
				square.vertices = [Vector3i(-256, h[0], 0), Vector3i(0, h[1], 0), Vector3i(-256, h[2], -256), Vector3i(0, h[3], -256)]
				if scenario == 3:
					square.vertices[3] = square.vertices[2]
			else:
				square = null
			var flags: int = 2049 | (128 if scenario == 6 else 0)
			var result: PackedInt32Array = TerrainMatrix.update(previous, flags, direction, square)
			assert_eq(int(row[0]), scenario)
			assert_eq(int(row[1]), direction)
			for index: int in range(12):
				assert_eq(result[index], int(row[index + 4]), "scenario %d direction %d matrix %d" % [scenario, direction, index])
			assert_eq(previous[9], -128, "Input matrix is detached")

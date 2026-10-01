extends GutTest
## Asset-free projection expectations generated independently from frozen C.

func _vector(row: PackedStringArray, at: int) -> Vector3i:
	return Vector3i(int(row[at]), int(row[at + 1]), int(row[at + 2]))

func test_reference_fixed_point_projection_samples() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("map_projection.tsv")
	rows.pop_front()
	assert_eq(rows.size(), 37)
	for row: PackedStringArray in rows:
		var camera: Vector3i = _vector(row, 1)
		var vertex: Vector3i = _vector(row, 4)
		var source_sample: PackedInt64Array = MapReferenceProjection.sample(vertex, camera)
		var translation := Vector3i(source_sample[0], source_sample[1], source_sample[2])
		assert_eq(translation, _vector(row, 7), row[0] + " separately quantized camera translation")
		assert_eq(MapReferenceProjection.rotate(vertex) + translation, _vector(row, 10), row[0] + " view coordinate")
		var projected: Vector3i = MapReferenceProjection.project(vertex, camera)
		assert_eq(projected, Vector3i(int(row[14]), int(row[15]), int(row[13])), row[0] + " screen and clamped depth")
		var expected := PackedInt64Array()
		for i: int in range(7, 16):
			expected.append(int(row[i]))
		expected.append(int(row[18]))
		assert_eq(MapReferenceProjection.sample(vertex, camera), expected, row[0] + " depth word storage")

func test_reference_ordering_depth_samples() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("map_projection.tsv")
	rows.pop_front()
	for row: PackedStringArray in rows:
		var depth: int = int(row[13])
		assert_eq(MapReferenceProjection.ordering_bucket(PackedInt32Array([depth, depth, depth])),
			int(row[21]), row[0] + " weighted triangle depth")
		assert_eq(MapReferenceProjection.ordering_bucket(PackedInt32Array([depth, depth, depth, depth])),
			int(row[22]), row[0] + " quad depth")

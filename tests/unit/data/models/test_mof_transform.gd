extends GutTest
## XAR transform expansion and interpolation, on records built in memory.


func test_quaternion_matrix_uses_authored_values_without_normalizing() -> void:
	var authored: MofTransform = SyntheticMofAnimation.transform(2, [64, 0, 0, 32, 0, 0, 0])
	assert_eq(authored.matrix_values(), PackedInt32Array([2048, 4096, 0, -4096, 2048, 0, 0, 0, 4096, 0, 0, 0]))


func test_scaling_applies_to_rows_and_wraps_short_results() -> void:
	var authored: MofTransform = SyntheticMofAnimation.transform(4, [64, 0, 0, 32, 1, 2, 3, 64, 16, -32, 1])
	assert_eq(authored.matrix_values(), PackedInt32Array([4096, 8192, 0, -2048, 1024, 0, 0, 0, -4096, 1, 2, 3]))
	var large: MofTransform = SyntheticMofAnimation.transform(5, [16384, 0, 0, 4096, 0, 0, 0, 127, 127, 127, 1])
	var values: PackedInt32Array = large.matrix_values()
	assert_eq(values[1], 1024, "32768 wraps to -32768, then scaled short wraps again")


func test_interpolated_rotation_and_scaling() -> void:
	var first: MofTransform = SyntheticMofAnimation.transform(5, [4096, 0, 0, 0, 0, 0, 0, 32, 32, 32, 1])
	var last: MofTransform = SyntheticMofAnimation.transform(5, [0, 0, 0, 4096, 100, -101, 0, 64, 16, -32, 1])
	var matrix: PackedInt32Array = first.interpolate(last, 2048)
	assert_almost_eq(matrix[1], 6144, 8)
	assert_almost_eq(matrix[3], -3072, 8)
	assert_eq(matrix[8], 0)
	assert_eq(matrix[9], 50)
	assert_eq(matrix[10], -51)


func test_scale_flags_apply_across_interpolation_even_at_endpoints() -> void:
	var first: MofTransform = SyntheticMofAnimation.transform(5, [4096, 0, 0, 0, 0, 0, 0, 64, 32, 32, 0])
	var last: MofTransform = SyntheticMofAnimation.transform(5, [4096, 0, 0, 0, 0, 0, 0, 32, 32, 32, 1])
	assert_eq(first.matrix_values()[0], 4096, "flag zero ignores authored scale for ordinary samples")
	assert_eq(first.interpolate(last, 0)[0], 8192, "either endpoint flag activates scale across the segment")
	assert_eq(first.interpolate(last, 2048)[0], 6144)
	assert_eq(first.interpolate(last, 4096)[0], 4096)
	first.raw_values[10] = 2
	assert_eq(first.matrix_values()[0], 4096, "only bit zero enables scaling")


func test_byte_quaternion_interpolation_preserves_authored_magnitudes() -> void:
	var first: MofTransform = SyntheticMofAnimation.transform(2, [64, 0, 0, 32, 0, 0, 0])
	var last: MofTransform = SyntheticMofAnimation.transform(2, [64, 0, 0, 32, 100, 0, 0])
	assert_eq(first.interpolate(last, 0), first.matrix_values(), "C's zero endpoint uses authored byte quaternion directly")
	var halfway: PackedInt32Array = first.interpolate(last, 2048)
	assert_eq(halfway[0], 2080)
	assert_eq(halfway[1], 4032)
	assert_eq(halfway[9], 50)
	assert_ne(last.interpolate(last, 4096)[1], last.matrix_values()[1], "nonzero C byte interpolation runs limited normalization")

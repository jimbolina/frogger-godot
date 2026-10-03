extends GutTest
## Frozen source-ordered camera zone rectangle checks.

func _zone(index: int, bounds: PackedInt32Array, children: Array[PackedInt32Array] = []) -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_index = index
	zone.source_offset = 100 + index * 8
	zone.bounds = bounds
	for child: PackedInt32Array in children:
		zone.regions.append(child)
	return zone

func test_first_source_match_with_nonsequential_authored_indices() -> void:
	var zones: Array[ZoneDefinition] = [
		_zone(19, PackedInt32Array([2, 3, 7, 8])),
		_zone(2, PackedInt32Array([2, 3, 7, 8]))
	]
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(2, 3)), 19)
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(7, 8)), 19)
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(1, 3)), -1)
	zones[0].regions.append(PackedInt32Array([2, 3, 3, 4]))
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(3, 4)), 19)
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(7, 8)), 2)

func test_children_gaps_and_inverted_bounds() -> void:
	var children: Array[PackedInt32Array] = [
		PackedInt32Array([1, 1, 2, 2]),
		PackedInt32Array([4, 4, 5, 5])
	]
	var zones: Array[ZoneDefinition] = [_zone(8, PackedInt32Array([0, 0, 6, 6]), children)]
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(1, 1)), 8)
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(5, 5)), 8)
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(3, 3)), -1)
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(0, 0)), -1)
	zones[0].regions[0] = PackedInt32Array([3, 3, 2, 2])
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(2, 2)), -1)
	zones[0].bounds = PackedInt32Array([6, 6, 0, 0])
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(5, 5)), -1)

func test_outer_unsigned_words_and_signed_children() -> void:
	var outer := _zone(12, PackedInt32Array([-1, -1, -1, -1]))
	var zones: Array[ZoneDefinition] = [outer]
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(65535, 65535)), 12)
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(-1, -1)), -1)
	outer.regions.append(PackedInt32Array([-1, -1, -1, -1]))
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(65535, 65535)), -1)
	outer.zone_type = 77
	assert_eq(ZoneQueries.first_camera_match(zones, Vector2i(65535, 65535)), -1)
	assert_false(outer.validate().is_empty())

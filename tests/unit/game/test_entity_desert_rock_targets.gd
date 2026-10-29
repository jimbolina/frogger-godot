extends GutTest
## Hand-derived ENTSTRDesCreateFallingRock target snapping, layer choice and first-target lift.

func _square(heights: Array[int]) -> GridSquareDefinition:
	var square := GridSquareDefinition.new()
	for height: int in heights:
		square.vertices.append(Vector3i(0, height, 0))
	return square

func _grid() -> GridDefinition:
	var grid := GridDefinition.new()
	grid.dimensions = Vector2i(3, 1)
	grid.base = Vector2i.ZERO
	var layered := GridStackDefinition.new()
	layered.first_square_index = 0
	layered.square_count = 2
	var sloped := GridStackDefinition.new()
	sloped.first_square_index = 2
	sloped.square_count = 1
	grid.stacks.append_array([layered, sloped, GridStackDefinition.new()])
	grid.squares.append_array([_square([0, 0, 0, 0]), _square([-500, -500, -500, -500]), _square([0, 256, 512, 768])])
	return grid

func test_used_targets_snap_to_cell_centres_and_only_the_first_is_lifted() -> void:
	var authored: Array[Vector3i] = [Vector3i(0x13, -1000, 0xf5), Vector3i(0x1ff, -200, 0x01), Vector3i(0x40, -200, 0x40), Vector3i(5, 5, 5)]
	var result: EntityDesertRockTargets = EntityDesertRockTargets.resolve(authored, _grid(), 3)
	assert_eq(result.error, "")
	assert_eq(result.targets, [Vector3i(128, -628, 128), Vector3i(384, 384, 128), Vector3i(128, 0, 128), Vector3i(5, 5, 5)] as Array[Vector3i])
	assert_eq(authored[0], Vector3i(0x13, -1000, 0xf5))

func test_single_bounce_lifts_its_only_target() -> void:
	var authored: Array[Vector3i] = [Vector3i(0x40, 100, 0x40), Vector3i(0x13, -1000, 0xf5)]
	var result: EntityDesertRockTargets = EntityDesertRockTargets.resolve(authored, _grid(), 1)
	assert_eq(result.targets, [Vector3i(128, -128, 128), Vector3i(0x13, -1000, 0xf5)] as Array[Vector3i])

func test_empty_or_outside_stacks_and_invalid_counts_are_rejected() -> void:
	var empty: Array[Vector3i] = [Vector3i(0x40, 0, 0x40), Vector3i(0x2ff, 0, 0x40)]
	var result: EntityDesertRockTargets = EntityDesertRockTargets.resolve(empty, _grid(), 2)
	assert_string_contains(result.error, "target 1")
	assert_true(result.targets.is_empty())
	var outside: Array[Vector3i] = [Vector3i(-1, 0, 0x40)]
	assert_string_contains(EntityDesertRockTargets.resolve(outside, _grid(), 1).error, "(-128, 128)")
	assert_ne(EntityDesertRockTargets.resolve(outside, _grid(), 0).error, "")
	assert_ne(EntityDesertRockTargets.resolve(outside, _grid(), 2).error, "")
	assert_ne(EntityDesertRockTargets.resolve(outside, null, 1).error, "")

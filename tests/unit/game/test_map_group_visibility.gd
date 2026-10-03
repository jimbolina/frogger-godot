extends GutTest
## Bounded source map-view selector and polygon-budget failure.

func _definition(polygons: int = 0) -> EntityLifecycleDefinition:
	var result := EntityLifecycleDefinition.new()
	result.group_base = Vector3i(-4096, 0, -4096)
	result.group_dimensions = Vector2i.ONE
	result.group_size = Vector2i(8192, 8192)
	result.polygon_counts = PackedInt32Array([polygons])
	return result

func _camera(x: int = 0) -> GameplayCameraSnapshot:
	var result := GameplayCameraSnapshot.new()
	result.source_world = Vector3i(x, -500, -500)
	result.target_world = Vector3i(x, 0, 0)
	result.axis_x_12 = Vector3i(4096, 0, 0)
	result.axis_y_12 = Vector3i(0, 2896, -2896)
	result.axis_z_12 = Vector3i(0, 2896, 2896)
	return result

func test_selected_group_and_offscreen_empty() -> void:
	var result: MapGroupVisibilityResult = MapGroupVisibility.query(_definition(40), _camera())
	assert_eq(result.error, "")
	assert_eq(result.groups, PackedInt32Array([0]))
	assert_eq(result.polygon_total, 40)
	assert_eq(MapGroupVisibility.query(_definition(), _camera(100000)).groups, PackedInt32Array())
	var detached: MapGroupVisibilityResult = result.copy()
	detached.groups.clear()
	assert_eq(result.groups, PackedInt32Array([0]))

func test_polygon_budget_and_invalid_geometry_fail_closed() -> void:
	var within_budget: MapGroupVisibilityResult = MapGroupVisibility.query(_definition(2499), _camera())
	assert_eq(within_budget.error, "")
	assert_eq(within_budget.groups, PackedInt32Array([0]))
	assert_eq(within_budget.polygon_total, 2499)
	var budget: MapGroupVisibilityResult = MapGroupVisibility.query(_definition(2500), _camera())
	assert_false(budget.error.is_empty())
	assert_eq(budget.groups, PackedInt32Array())
	var invalid: EntityLifecycleDefinition = _definition()
	invalid.polygon_counts.clear()
	assert_false(MapGroupVisibility.query(invalid, _camera()).error.is_empty())
	assert_false(MapGroupVisibility.query(_definition(), null).error.is_empty())
	var rows: EntityLifecycleDefinition = _definition()
	rows.group_dimensions = Vector2i(1, 64)
	rows.polygon_counts.resize(64)
	assert_eq(rows.validate(), "")
	rows.group_dimensions.y = 65
	rows.polygon_counts.resize(65)
	assert_string_contains(rows.validate(), "64-row")

func test_border_normalization_retains_final_ray_y() -> void:
	var grid := EntityLifecycleDefinition.new()
	grid.group_base = Vector3i(-8192, 0, -8192)
	grid.group_dimensions = Vector2i(32, 32)
	grid.group_size = Vector2i(512, 512)
	grid.polygon_counts.resize(1024)
	var camera: GameplayCameraSnapshot = _camera()
	camera.source_world = Vector3i(-128, -512, -640)
	var result: MapGroupVisibilityResult = MapGroupVisibility.query(grid, camera)
	assert_eq(result.error, "")
	# Exact unchanged CreateMapViewList output; flattening the border to Y=0 adds 556.
	assert_eq(result.groups, PackedInt32Array([430, 431, 432, 433, 462, 463, 464, 465,
		493, 494, 495, 496, 497, 525, 526, 527, 528, 529, 530, 557, 558, 559, 560,
		561, 562, 588, 589, 590, 591, 592, 593, 594]))

func test_group_cap_and_away_rays_are_bounded() -> void:
	var grid := EntityLifecycleDefinition.new()
	grid.group_base = Vector3i(-4096, 0, -4096)
	grid.group_dimensions = Vector2i(64, 64)
	grid.group_size = Vector2i(128, 128)
	grid.polygon_counts.resize(4096)
	var forward: MapGroupVisibilityResult = MapGroupVisibility.query(grid, _camera())
	assert_eq(forward.error, "")
	assert_eq(forward.groups.size(), 128)
	assert_true(forward.groups[0] < forward.groups[forward.groups.size() - 1])
	var away: GameplayCameraSnapshot = _camera()
	away.axis_y_12 = Vector3i(0, -2896, 2896)
	away.axis_z_12 = Vector3i(0, -2896, -2896)
	var behind: MapGroupVisibilityResult = MapGroupVisibility.query(grid, away)
	assert_eq(behind.error, "")
	assert_true(behind.groups.size() > 0)
	assert_true(behind.groups.size() <= 128)

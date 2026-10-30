extends GutTest
## Front-end water grids, wave heights and texture mapping from HSInitialiseWater and
## HSUpdateWater.


func test_constants_follow_the_header() -> void:
	assert_eq([MenuWater.WATER_X_NUM, MenuWater.WATER_Z_NUM, MenuWater.WATER_X_LEN, MenuWater.WATER_Z_LEN], [14, 16, 0x240, 0x240])
	assert_eq([MenuWater.RIVERBED_X_NUM, MenuWater.RIVERBED_Z_NUM, MenuWater.RIVERBED_X_LEN, MenuWater.RIVERBED_Z_LEN], [14, 16, 0x240, 0x240])
	assert_eq([MenuWater.WAVE_AMP_X, MenuWater.WAVE_AMP_Z, MenuWater.WAVE_FREQ_X, MenuWater.WAVE_FREQ_Z], [0x40, 0x50, 0x60, 0x80])
	assert_eq([MenuWater.WAVE_PERIOD_X, MenuWater.WAVE_PERIOD_Z], [0x2000, 0x2000])
	assert_eq(MenuWater.prim_rgb(MenuWater.WATER_PRIM_COLOUR), Vector3i(0x60, 0x60, 0x40))
	assert_eq(MenuWater.prim_rgb(MenuWater.RIVERBED_PRIM_COLOUR), Vector3i(0x30, 0x30, 0x30))
	assert_gt(MenuWater.WATER_OT_FROM_END, MenuWater.RIVERBED_OT_FROM_END, "water draws in front of the riverbed")


func test_grids_are_centred_and_start_at_positive_z() -> void:
	var points: Array[Vector3i] = MenuWater.water_vertices()
	assert_eq(points.size(), 15 * 17)
	assert_eq(points[0], Vector3i(-14 * 0x240 / 2, 0, 16 * 0x240 / 2))
	assert_eq(points[1], Vector3i(-14 * 0x240 / 2 + 0x240, 0, 16 * 0x240 / 2))
	assert_eq(points[15], Vector3i(-14 * 0x240 / 2, 0, 16 * 0x240 / 2 - 0x240))
	assert_eq(points[points.size() - 1], Vector3i(14 * 0x240 / 2, 0, -16 * 0x240 / 2))
	assert_eq(MenuWater.riverbed_vertices(), points)


func test_heights_sum_two_sines_per_hs_update_water() -> void:
	var start: PackedInt32Array = MenuWater.heights(0)
	assert_eq(start.size(), 15 * 17)
	assert_eq(start[0], 0)
	assert_eq(start[1], (StackLayout.rsin(0x2000 / 14) * 0x40) >> 12)
	assert_eq(start[15], (StackLayout.rsin(0x2000 / 16) * 0x50) >> 12)
	var later: PackedInt32Array = MenuWater.heights(100)
	var tx: int = (3 * 0x2000) / 14 + 100 * 0x60
	var tz: int = (5 * 0x2000) / 16 + 100 * 0x80
	assert_eq(later[5 * 15 + 3], (StackLayout.rsin(tx) * 0x40 + StackLayout.rsin(tz) * 0x50) >> 12)
	for value: int in later:
		assert_between(value, -144, 144)


func test_heights_use_an_arithmetic_shift_for_negative_sums() -> void:
	var tx: int = 7 * 0x2000 / 14 + 9 * 0x60
	var tz: int = 11 * 0x2000 / 16 + 9 * 0x80
	var sum: int = StackLayout.rsin(tx) * 0x40 + StackLayout.rsin(tz) * 0x50
	assert_eq(MenuWater.heights(9)[11 * 15 + 7], floori(float(sum) / 4096.0))


func test_frame_counter_advances_once_per_tick() -> void:
	var water: MenuWater = MenuWater.create(41)
	assert_eq(water.frame_count, 41)
	water.advance()
	assert_eq(water.frame_count, 42)
	assert_eq(water.current_heights(), MenuWater.heights(42))
	assert_eq(MenuWater.create().frame_count, 0)


func test_quads_use_the_next_row_for_corners_two_and_three() -> void:
	assert_eq(MenuWater.quad_vertices(0, 0, 14), PackedInt32Array([0, 1, 15, 16]))
	assert_eq(MenuWater.quad_vertices(13, 15, 14), PackedInt32Array([15 * 15 + 13, 15 * 15 + 14, 16 * 15 + 13, 16 * 15 + 14]))


func test_water_maps_one_texture_across_the_mesh() -> void:
	assert_eq(MenuWater.water_quad_uvs(0, 0, 10, 20, 64, 64), PackedInt32Array([10, 20, 14, 20, 10, 24, 14, 24]))
	assert_eq(MenuWater.water_quad_uvs(13, 15, 0, 0, 64, 64), PackedInt32Array([59, 60, 64, 60, 59, 64, 64, 64]))
	var fractions: Array[Vector2] = MenuWater.water_quad_fractions(13, 15)
	assert_almost_eq(fractions[0], Vector2(13.0 / 14.0, 15.0 / 16.0), Vector2(1e-6, 1e-6))
	assert_almost_eq(fractions[3], Vector2(1.0, 1.0), Vector2(1e-6, 1e-6))


func test_riverbed_rows_alternate_texture_corners() -> void:
	assert_eq(MenuWater.riverbed_corners(1), PackedInt32Array([0, 1, 2, 3]))
	assert_eq(MenuWater.riverbed_corners(0), PackedInt32Array([2, 3, 0, 1]))
	assert_eq(MenuWater.riverbed_corners(14), PackedInt32Array([2, 3, 0, 1]))

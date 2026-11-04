extends GutTest
## MenuWater, MenuWaterMesh and MenuWaterView agree with the independent frozen-C water facts
## in tests/golden/synthetic/frontend_water.json (tools/golden/make_golden_water.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_water.json"

var _document: Dictionary = {}


func before_all() -> void:
	_document = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))


static func _int(value: Variant) -> int:
	var number: float = value
	return int(number)


static func _ints(values: Variant) -> PackedInt32Array:
	var items: Array = values
	var result := PackedInt32Array()
	for value: Variant in items:
		result.append(_int(value))
	return result


static func _text(value: Variant) -> String:
	var text: String = value
	return text


static func _flag(value: Variant) -> bool:
	var flag: bool = value
	return flag


static func _table(value: Variant) -> Dictionary:
	var table: Dictionary = value
	return table


static func _vector(value: Variant) -> Vector3i:
	var items: PackedInt32Array = _ints(value)
	return Vector3i(items[0], items[1], items[2])


func test_constants() -> void:
	var c: Dictionary = _document.constants
	assert_eq(_ints(c.water_num), PackedInt32Array([MenuWater.WATER_X_NUM, MenuWater.WATER_Z_NUM]))
	assert_eq(_ints(c.riverbed_num), PackedInt32Array([MenuWater.RIVERBED_X_NUM, MenuWater.RIVERBED_Z_NUM]))
	assert_eq(_ints(c.water_len), PackedInt32Array([MenuWater.WATER_X_LEN, MenuWater.WATER_Z_LEN]))
	assert_eq(_ints(c.riverbed_len), PackedInt32Array([MenuWater.RIVERBED_X_LEN, MenuWater.RIVERBED_Z_LEN]))
	assert_eq(_ints(c.wave_amp), PackedInt32Array([MenuWater.WAVE_AMP_X, MenuWater.WAVE_AMP_Z]))
	assert_eq(_ints(c.wave_freq), PackedInt32Array([MenuWater.WAVE_FREQ_X, MenuWater.WAVE_FREQ_Z]))
	assert_eq(_ints(c.wave_period), PackedInt32Array([MenuWater.WAVE_PERIOD_X, MenuWater.WAVE_PERIOD_Z]))
	assert_eq(_int(c.perspective), MenuWater.PERSPECTIVE)
	assert_eq(_int(c.perspective), GameplayProjection.PERSPECTIVE_H, "the options camera uses the gameplay projection")
	assert_eq(_ints(c.clear_colour), PackedInt32Array([0, 0, 0]))
	assert_eq(MenuWaterMesh.WAVE_REACH, maxi(absi(_int(_document.wave.height_min)), _int(_document.wave.height_max)))


func test_vertex_grids() -> void:
	var grid: Dictionary = _document.grid
	var xs: PackedInt32Array = _ints(grid.x)
	var zs: PackedInt32Array = _ints(grid.z)
	var water: Array[Vector3i] = MenuWater.water_vertices()
	var riverbed: Array[Vector3i] = MenuWater.riverbed_vertices()
	assert_eq(water.size(), xs.size() * zs.size())
	assert_eq(_ints(grid.riverbed_x), xs)
	assert_eq(_ints(grid.riverbed_z), zs)
	for j: int in zs.size():
		for i: int in xs.size():
			var expected := Vector3i(xs[i], _int(grid.y), zs[j])
			assert_eq(water[j * xs.size() + i], expected, "water vertex %d,%d" % [i, j])
			assert_eq(riverbed[j * xs.size() + i], Vector3i(xs[i], _int(grid.riverbed_y), zs[j]), "riverbed vertex %d,%d" % [i, j])
	var steps: Array = grid.corner_steps
	for j: int in _int(grid.quads[1]):
		for i: int in _int(grid.quads[0]):
			var corners: PackedInt32Array = MenuWater.quad_vertices(i, j, MenuWater.WATER_X_NUM)
			for corner: int in 4:
				var step: PackedInt32Array = _ints(steps[corner])
				assert_eq(corners[corner], (j + step[1]) * xs.size() + i + step[0])


func test_mesh_positions_follow_the_grid() -> void:
	var mesh: MenuWaterMesh = MenuWaterMesh.create(0)
	var grid: Dictionary = _document.grid
	var xs: PackedInt32Array = _ints(grid.x)
	var zs: PackedInt32Array = _ints(grid.z)
	var heights: Array = _table(_document.wave.frames[0]).heights
	for j: int in zs.size():
		var row: PackedInt32Array = _ints(heights[j])
		for i: int in xs.size():
			assert_almost_eq(mesh.water_positions[j * xs.size() + i], GameSpace.position(xs[i], row[i], zs[j]), Vector3.ONE * 0.00001)


func test_water_texture_spans_the_mesh() -> void:
	var water: Dictionary = _document.water
	assert_eq(_ints(water.uv_divisions), PackedInt32Array([MenuWater.WATER_X_NUM, MenuWater.WATER_Z_NUM]))
	var steps: Array = water.uv_corner_steps
	var uvs: PackedVector2Array = MenuWaterMesh.water_uvs()
	for j: int in MenuWater.WATER_Z_NUM:
		for i: int in MenuWater.WATER_X_NUM:
			var fractions: Array[Vector2] = MenuWater.water_quad_fractions(i, j)
			var corners: PackedInt32Array = MenuWater.quad_vertices(i, j, MenuWater.WATER_X_NUM)
			for corner: int in 4:
				var step: PackedInt32Array = _ints(steps[corner])
				var expected := Vector2(float(i + step[0]) / MenuWater.WATER_X_NUM, float(j + step[1]) / MenuWater.WATER_Z_NUM)
				assert_almost_eq(fractions[corner], expected, Vector2.ONE * 0.000001)
				assert_almost_eq(uvs[corners[corner]], expected, Vector2.ONE * 0.000001)


func test_riverbed_corner_order() -> void:
	var corners: Dictionary = _table(_document.riverbed).texture_corners
	assert_eq(MenuWater.riverbed_corners(1), _ints(corners.odd_rows))
	assert_eq(MenuWater.riverbed_corners(0), _ints(corners.even_rows))
	assert_eq(MenuWater.riverbed_corners(15), _ints(corners.odd_rows))
	assert_eq(MenuWater.riverbed_corners(14), _ints(corners.even_rows))


func test_colour_words_and_blend() -> void:
	var water: Dictionary = _document.water
	var riverbed: Dictionary = _document.riverbed
	assert_eq(MenuWater.WATER_PRIM_COLOUR, _text(water.colour_word).hex_to_int())
	assert_eq(MenuWater.RIVERBED_PRIM_COLOUR, _text(riverbed.colour_word).hex_to_int())
	assert_eq(MenuWater.prim_rgb(MenuWater.WATER_PRIM_COLOUR), _vector(water.colour))
	assert_eq(MenuWater.prim_rgb(MenuWater.RIVERBED_PRIM_COLOUR), _vector(riverbed.colour))
	assert_eq(MenuWater.WATER_SEMI_TRANSPARENT, _flag(water.semi_transparent))
	assert_eq(MenuWater.WATER_ABR, _int(water.abr))
	assert_eq(_text(water.blend), "one_one")
	assert_eq(ModelShaders.blend_for_mode(MenuWater.WATER_ABR), ModelShaders.Blend.ADD)
	assert_false(_flag(riverbed.semi_transparent))
	assert_eq(_text(water.texture), "im_" + FrontEndAssets.WATER_NAMES[0])
	assert_eq(_text(riverbed.texture), "im_" + FrontEndAssets.WATER_NAMES[1])
	var mesh: MenuWaterMesh = MenuWaterMesh.create()
	var water_colours: PackedColorArray = mesh.water.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var bed_colours: PackedColorArray = mesh.riverbed.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_eq(water_colours[0].to_rgba32() >> 8, 0x606040)
	assert_eq(bed_colours[0].to_rgba32() >> 8, 0x303030)


func test_draw_order() -> void:
	var items: Array = _document.draw_order
	var order := PackedStringArray(items)
	assert_eq(order, PackedStringArray(["riverbed", "water"]))
	assert_eq(_int(_document.riverbed.ot_slot_from_back), MenuWater.RIVERBED_OT_FROM_END - 1)
	assert_eq(_int(_document.water.ot_slot_from_back), MenuWater.WATER_OT_FROM_END - 1)
	assert_gt(MenuWaterMesh.RIVERBED_DEPTH, MenuWaterMesh.WATER_DEPTH, "the riverbed is drawn behind the water")
	assert_lt(MenuWaterMesh.RIVERBED_DEPTH, MenuWaterMesh.CAMERA_FAR)
	var view: MenuWaterView = MenuWaterView.create(MenuWater.create(), null, null)
	autofree(view)
	assert_eq(view.riverbed.get_index(), 0)
	assert_eq(view.surface.get_index(), 1)


func test_wave_frames() -> void:
	var wave: Dictionary = _document.wave
	assert_eq(_int(wave.counter_bits), 16)
	var period: int = _int(wave.period_frames)
	for frame: Dictionary in wave.frames:
		var t: int = _int(frame.t)
		var flat := PackedInt32Array()
		for row: Array in frame.heights:
			flat.append_array(_ints(row))
		var heights: PackedInt32Array = MenuWater.heights(t)
		assert_eq(heights, flat, "frame %d" % t)
		assert_eq(GoldenFiles.list_digest32(heights), _text(frame.digest), "frame %d digest" % t)
		assert_eq(MenuWater.heights(t + period), heights, "frame %d repeats after the period" % t)
		var x_angles := PackedInt32Array()
		for i: int in MenuWater.WATER_X_NUM + 1:
			x_angles.append(StackLayout.rsin((i * MenuWater.WAVE_PERIOD_X) / MenuWater.WATER_X_NUM + t * MenuWater.WAVE_FREQ_X))
		assert_eq(x_angles, _ints(frame.sin_x), "frame %d sin_x" % t)
		var z_angles := PackedInt32Array()
		for j: int in MenuWater.WATER_Z_NUM + 1:
			z_angles.append(StackLayout.rsin((j * MenuWater.WAVE_PERIOD_Z) / MenuWater.WATER_Z_NUM + t * MenuWater.WAVE_FREQ_Z))
		assert_eq(z_angles, _ints(frame.sin_z), "frame %d sin_z" % t)


func test_view_steps_the_frame_counter_from_zero() -> void:
	var animation: MenuWater = MenuWater.create()
	var view: MenuWaterView = MenuWaterView.create(animation, null, null)
	autofree(view)
	view.smoothing_enabled = false
	var frames: Array = _document.wave.frames
	var first: Dictionary = frames[0]
	assert_eq(_int(first.t), 0)
	var expected: PackedFloat32Array = PackedFloat32Array()
	for row: Array in first.heights:
		for value: Variant in row:
			expected.append(_int(value))
	assert_eq(view.meshes.water_positions, MenuWaterMesh.positions(MenuWater.water_vertices(), expected), "a new viewport draws frame 0")
	view.tick()
	assert_eq(animation.frame_count, 1)
	expected.clear()
	for row: Array in _table(frames[1]).heights:
		for value: Variant in row:
			expected.append(_int(value))
	assert_eq(view.meshes.water_positions, MenuWaterMesh.positions(MenuWater.water_vertices(), expected))


func test_options_camera_main_preset() -> void:
	var options: Dictionary = _document.cameras.options
	assert_eq(_int(options.perspective), MenuWater.PERSPECTIVE)
	assert_eq(_vector(options.up), MenuWaterView.UP)
	var main: Dictionary = options.presets.MAIN
	assert_eq(_vector(main.source), MenuWaterView.MAIN_SOURCE)
	assert_eq(_vector(main.target), MenuWaterView.MAIN_TARGET)
	assert_eq(_vector(main.translation), MenuWaterView.MAIN_SOURCE)
	var matrix := PackedInt32Array()
	for row: Array in main.matrix:
		matrix.append_array(_ints(row))
	assert_eq(MenuWaterView.point_matrix(MenuWaterView.MAIN_SOURCE, MenuWaterView.MAIN_TARGET), matrix)
	for preset_name: String in ["OPTIONS", "HS_STATIC", "HS_INPUT"]:
		var preset: Dictionary = options.presets[preset_name]
		var expected := PackedInt32Array()
		for row: Array in preset.matrix:
			expected.append_array(_ints(row))
		assert_eq(MenuWaterView.point_matrix(_vector(preset.source), _vector(preset.target)), expected, preset_name)


func test_level_select_uses_the_stack_camera() -> void:
	var level_select: Dictionary = _document.cameras.level_select
	assert_eq(_int(level_select.perspective), StackLayout.PERSPECTIVE)
	var pages: Array = _document.pages
	var found: bool = false
	for page: Dictionary in pages:
		if page.page == "LEVEL_SELECT":
			found = true
			assert_eq(_text(page.camera), "level_select")
	assert_true(found)

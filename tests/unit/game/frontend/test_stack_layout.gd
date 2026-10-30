extends GutTest
## Level-select stack geometry from SelectLevelInit, SelectCreateScene and SelectCreateMOF over a
## stack shaped like retail's arcade table.

const LEVELS: PackedInt32Array = [24, 25, 26, 27, 28, 48, 49, 50, 51, 52, 12, 13, 54, 56, 55, 0, 2, 3, 42, 44, 45, 43, 36, 39, 38, 37, 40, 6, 7, 8, 9, 10, 18]
const WORLDS: PackedInt32Array = [1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 4, 4, 5, 5, 5, 7, 7, 7, 3, 3, 3, 3, 2, 2, 2, 2, 2, 6, 6, 6, 6, 6, 8]
const THEMES: PackedInt32Array = [5, 5, 5, 5, 5, 9, 9, 9, 9, 9, 3, 3, 10, 10, 10, 1, 1, 1, 8, 8, 8, 8, 7, 7, 7, 7, 7, 2, 2, 2, 2, 2, 4]


static func retail_stack() -> LevelStack:
	var rows: Array[LevelStack.Row] = []
	var block: int = -1
	for index: int in LEVELS.size():
		var world: int = WORLDS[index]
		if index == 0 or WORLDS[index - 1] != world:
			block += 1
		var local: int = 0
		for earlier: int in index:
			if WORLDS[earlier] == world:
				local += 1
		rows.append(LevelStack.Row.new(LEVELS[index], world, block, THEMES[index], local, WORLDS.count(world)))
	var race: Array[LevelStack.Row] = []
	return LevelStack.create(rows, race)


func _layout() -> StackLayout:
	return StackLayout.create(retail_stack())


func test_row_heights_divide_the_box_by_the_world_size() -> void:
	var layout: StackLayout = _layout()
	var expected: PackedInt32Array = PackedInt32Array()
	for size: int in [48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 120, 120, 80, 80, 80, 80, 80, 80, 60, 60, 60, 60, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 240]:
		expected.append(size)
	var actual: PackedInt32Array = PackedInt32Array()
	for row: int in layout.row_count():
		actual.append(layout.y_size(row))
	assert_eq(actual, expected, "li_y_size is 0xf0 / levels_in_world")


func test_rows_tile_edge_to_edge_with_the_last_at_zero() -> void:
	var layout: StackLayout = _layout()
	var last: int = layout.row_count() - 1
	assert_eq(layout.y_position(last), 0, "The last row sits at Y 0")
	for row: int in last:
		assert_eq(layout.y_position(row + 1) - layout.y_position(row), layout.y_size(row) + layout.y_size(row + 1),
			"Row %d touches row %d" % [row, row + 1])
	assert_eq(layout.y_position(0), -4032, "The first row is 2 * 2160 - 48 - 240 above the last")
	assert_eq(layout.y_position(5), -3552, "SUB1 centre")
	assert_eq(layout.y_position(10), -3000, "FOR1 centre")


func test_camera_targets_add_the_adjusted_camera_y() -> void:
	var layout: StackLayout = _layout()
	assert_eq(StackLayout.CAMERA_Y_OFFSET, -0xf00, "-0x1800 + 0x900")
	assert_eq(layout.camera_target_y(5), -3552 - 0xf00)
	assert_eq(layout.camera_target_y(32), -0xf00)
	assert_eq(StackLayout.CAMERA_EYE, Vector3i(-0x1a00, -0x1800, -0x2200))
	assert_eq(StackLayout.camera_translation(-100), Vector3i(-0x1300, -100, -0x1b00))


func test_scene_constants_match_select_create_scene() -> void:
	assert_eq(StackLayout.BOX_HALF_SIZE, 240)
	assert_eq(StackLayout.STACK_ORIGIN, Vector3i(-2560, 0, -2560))
	assert_eq(StackLayout.PERSPECTIVE, 1000)
	assert_eq(StackLayout.AMBIENT_COLOUR, 0x202020)
	assert_eq(StackLayout.LIGHT_COLOURS, PackedInt32Array([0x606060, 0x404040, 0x303030]))
	assert_eq(StackLayout.LIGHT_Y_ROTATIONS, PackedInt32Array([-512, 512, 0]), "-45, +45 and 0 degrees of 4096")
	assert_eq(StackLayout.light_direction(0), Vector3i(-2896, 0, 2896))
	assert_eq(StackLayout.light_direction(2), Vector3i(0, 0, 4096))


func test_camera_looks_at_the_stack_origin() -> void:
	var matrix: PackedInt32Array = StackLayout.camera_matrix()
	assert_eq(StackLayout.matrix_column(matrix, 2), Vector3i(1747, 2620, 2620),
		"(0x1000, 0x1800, 0x1800) / sqrt(5.5) at 4.12")
	assert_eq(matrix[3], 0, "The camera's X axis is level")
	assert_eq(_layout().spin_start(5), Vector3i(-2560, -3552, -3040), "Fully slid out by default")


func test_box_vertices_follow_select_create_mof() -> void:
	var layout: StackLayout = _layout()
	var vertices: Array[Vector3i] = layout.row_vertices(5, -64)
	var expected: Array[Vector3i] = [
		Vector3i(-240, -3600, -304), Vector3i(240, -3600, -304), Vector3i(-240, -3504, -304), Vector3i(240, -3504, -304),
		Vector3i(-240, -3600, 176), Vector3i(240, -3600, 176), Vector3i(-240, -3504, 176), Vector3i(240, -3504, 176),
	]
	assert_eq(vertices, expected, "Half sizes 240, row height 48, slid by current_z")
	assert_eq(StackLayout.box_vertices(48, 0)[7], Vector3i(240, 48, 240), "The spin box is centred on its frame")


func test_face_tables() -> void:
	var faces: Array[PackedInt32Array] = []
	for face: int in StackLayout.FACE_COUNT:
		faces.append(StackLayout.face_indices(face))
	var expected: Array[PackedInt32Array] = [
		PackedInt32Array([0, 1, 3, 2]), PackedInt32Array([4, 0, 2, 6]), PackedInt32Array([5, 4, 6, 7]),
		PackedInt32Array([1, 5, 7, 3]), PackedInt32Array([4, 5, 1, 0]), PackedInt32Array([6, 2, 3, 7]),
	]
	assert_eq(faces, expected)
	assert_eq(StackLayout.FACE_NORMALS[1], Vector3i(4096, 0, 0))
	assert_eq(StackLayout.FACE_NORMALS[5], Vector3i(0, -4096, 0))
	assert_eq(StackLayout.gpu_face_indices(1), PackedInt32Array([4, 0, 6, 2]), "POLY_FT4 order swaps the last two corners")
	assert_eq(StackLayout.SPIN_IMAGE_CORNERS, PackedInt32Array([2, 0, 3, 1]), "The spin box's last face takes u2,u0,u3,u1")


func test_side_strip_slices_the_world_image() -> void:
	assert_eq(StackLayout.side_strip(240, 2, 5), Vector2i(96, 48))
	assert_eq(StackLayout.side_strip(127, 1, 2), Vector2i(63, 63), "Strip heights truncate")
	assert_true(StackLayout.shows_unlocked_image(LevelProgress.ZONE_ACCESSIBLE))
	assert_false(StackLayout.shows_unlocked_image(LevelProgress.COMPLETED))


func test_blocks_and_gold_frog_quads() -> void:
	var layout: StackLayout = _layout()
	var starts: PackedInt32Array = PackedInt32Array()
	for block: int in layout.block_count():
		starts.append(layout.block_start(block))
	assert_eq(starts, PackedInt32Array([0, 5, 10, 12, 15, 18, 22, 27, 32]))
	var first: Array[Vector3i] = [Vector3i(-2800, -4080, -2320), Vector3i(-2800, -4080, -2800),
		Vector3i(-2800, -3600, -2320), Vector3i(-2800, -3600, -2800)]
	assert_eq(layout.gold_frog_quad(0), first, "Top of the first world down to the top of the next")
	var last: Array[Vector3i] = [Vector3i(-2800, -240, -2320), Vector3i(-2800, -240, -2800),
		Vector3i(-2800, 240, -2320), Vector3i(-2800, 240, -2800)]
	assert_eq(layout.gold_frog_quad(8), last, "The last world ends at the bottom of the last row")
	assert_true(layout.gold_frog_quad(9).is_empty())


func test_level_table_maps_gold_frog_bits_to_their_theme_block() -> void:
	var layout: StackLayout = _layout()
	for slot: int in StackLayout.GOLD_FROG_SLOTS:
		if LevelProgress.ALL_GOLD_FROGS & (1 << (slot + 1)) == 0:
			continue
		var block: int = StackLayout.gold_frog_block(slot)
		assert_eq(THEMES[layout.block_start(block)], slot + 1, "Slot %d decorates its theme's world" % slot)

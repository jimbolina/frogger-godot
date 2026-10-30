extends GutTest
## StackLayout and StackSelector agree with the independent frozen-C stack facts in
## tests/golden/synthetic/frontend_stack_layout.json and frontend_stack_motion.json
## (tools/make_golden_stack.py).

const LAYOUT_GOLDEN: String = "res://tests/golden/synthetic/frontend_stack_layout.json"
const MOTION_GOLDEN: String = "res://tests/golden/synthetic/frontend_stack_motion.json"
const MODE_NAMES: PackedStringArray = ["SELECTING", "SHOW_LEVEL_INFO", "START_FADE", "UPDATE_FADE"]
const SPIN_NAMES: Dictionary = {1: "OUT", 2: "IN", 4: "HOLD"}
const EVENT_NAMES: Dictionary = {"hop": StackSelector.EventKind.HOP, "croak": StackSelector.EventKind.CROAK,
	"enter_game": StackSelector.EventKind.ENTER_GAME, "back": StackSelector.EventKind.BACK}
const SYNTHETIC_LEVEL_BASE: int = 1000

var _layout_document: Dictionary = {}
var _motion_document: Dictionary = {}


func before_all() -> void:
	_layout_document = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_GOLDEN))
	_motion_document = JSON.parse_string(FileAccess.get_file_as_string(MOTION_GOLDEN))


static func _int(value: Variant) -> int:
	var number: float = value
	return int(number)


static func _vector(value: Variant) -> Vector3i:
	var items: Array = value
	return Vector3i(_int(items[0]), _int(items[1]), _int(items[2]))


static func _vectors(values: Variant) -> Array[Vector3i]:
	var items: Array = values
	var result: Array[Vector3i] = []
	for value: Variant in items:
		result.append(_vector(value))
	return result


static func _ints(values: Variant) -> PackedInt32Array:
	var items: Array = values
	var result := PackedInt32Array()
	for value: Variant in items:
		result.append(_int(value))
	return result


static func _stack(rows: Array, levels: PackedInt32Array) -> LevelStack:
	var arcade: Array[LevelStack.Row] = []
	var block: int = -1
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var previous: Dictionary = rows[index - 1] if index > 0 else row
		if index == 0 or _int(previous.world) != _int(row.world):
			block += 1
		var local: int = _int(row.local_level) if row.has("local_level") else _int(row.local)
		arcade.append(LevelStack.Row.new(levels[index], _int(row.world), block, _int(row.theme), local,
			_int(row.levels_in_world)))
	var race: Array[LevelStack.Row] = []
	return LevelStack.create(arcade, race)


func _retail_layout() -> StackLayout:
	var rows: Array = _layout_document.rows
	var levels := PackedInt32Array()
	for row: Dictionary in rows:
		levels.append(_int(row.level))
	return StackLayout.create(_stack(rows, levels))


func test_constants() -> void:
	var c: Dictionary = _layout_document.constants
	assert_eq(StackLayout.BOX_HALF_SIZE, _int(c.box_half_x))
	assert_eq(StackLayout.BOX_HALF_SIZE, _int(c.box_half_z))
	assert_eq(StackLayout.STACK_ORIGIN, _vector(c.stack_origin))
	assert_eq(StackLayout.INIT_CAMERA_OFFSET, _vector(c.camera_init_offset))
	assert_eq(StackLayout.ADJUST_CAMERA_OFFSET, _vector(c.camera_adjust))
	var matrix := PackedInt32Array()
	for row: Array in c.camera_matrix:
		matrix.append_array(_ints(row))
	assert_eq(StackLayout.camera_matrix(), matrix, "MRPointMatrixAtVector at the stack origin")
	assert_eq(StackLayout.CAMERA_Y_OFFSET, _int(c.camera_y_offset))
	assert_eq(StackLayout.camera_translation(StackLayout.CAMERA_Y_OFFSET), _vector(c.camera_translation))
	assert_eq(StackLayout.PERSPECTIVE, _int(c.perspective))
	assert_eq(Vector2i(StackLayout.DISPLAY_WIDTH, StackLayout.DISPLAY_HEIGHT), Vector2i(_int(c.display[0]), _int(c.display[1])))
	assert_eq(StackSelector.SLIDE_INC, _int(c.slide_inc))
	assert_eq(StackSelector.SLIDE_DIST, _int(c.slide_dist))
	assert_eq(StackSelector.CAMERA_ACC, _int(c.camera_acc))
	assert_eq(StackSelector.CAMERA_MAX_VEL, _int(c.camera_max_vel))
	assert_eq(StackSelector.SPIN_TIME, _int(c.spin_time))
	assert_eq(StackLayout.SPIN_TARGET_OFFSET, _vector(c.spin_target_offset))
	assert_eq(StackLayout.spin_dest_vec_y(), _vector(c.spin_dest_vec_y))
	assert_eq(StackLayout.spin_dest_vec_roll(), _vector(c.spin_dest_vec_roll))
	assert_eq(StackLayout.SPIN_START_VEC_Y, _vector(c.spin_start_vec_y))
	assert_eq(StackLayout.SPIN_START_VEC_ROLL, _vector(c.spin_start_vec_roll))
	assert_eq(StackLayout.STATUS_START_X, _int(c.status_start_x))
	assert_eq(StackLayout.STATUS_END_X, _int(c.status_end_x))
	assert_eq(StackLayout.STATUS_WIDTH, _int(c.status_width))
	assert_eq(StackLayout.LEVEL_TITLE_Y, _int(c.level_title_y))
	assert_eq(StackLayout.SCORE_LINE_Y, _ints(c.score_line_y))
	assert_eq(StackLayout.PROMPT_Y, _int(c.prompt_y))
	assert_eq(StackLayout.TITLE_Y, _int(c.title_y))
	assert_eq(StackLayout.SPRITE_DIM_COLOUR, _int(c.sprite_dim_colour))
	assert_eq(StackSelector.GLOWY_MIN, _int(c.glow_min))
	assert_eq(StackSelector.GLOWY_MAX, _int(c.glow_max))
	assert_eq(StackSelector.GLOWY_SPEED, _int(c.glow_speed))
	assert_eq(StackSelector.DARK_COLOUR, _int(c.dark_colour))
	assert_eq(StackSelector.LIGHT_COLOUR, _int(c.light_colour))
	assert_eq(StackSelector.FADE_TICKS, _int(c.fade_ticks))


func test_lights() -> void:
	var lights: Array = _layout_document.lights
	assert_eq(lights.size(), 1 + StackLayout.LIGHT_COLOURS.size())
	var ambient: Dictionary = lights[0]
	assert_eq(str(ambient.type), "ambient")
	assert_eq(_ints(ambient.colour), _channels(StackLayout.AMBIENT_COLOUR))
	for index: int in StackLayout.LIGHT_COLOURS.size():
		var light: Dictionary = lights[index + 1]
		assert_eq(str(light.type), "parallel")
		assert_eq(StackLayout.LIGHT_Y_ROTATIONS[index], _int(light.rotation_y))
		assert_eq(_channels(StackLayout.LIGHT_COLOURS[index]), _ints(light.colour))
		assert_eq(StackLayout.light_direction(index), _vector(light.direction))


static func _channels(colour: int) -> PackedInt32Array:
	return PackedInt32Array([(colour >> 16) & 0xff, (colour >> 8) & 0xff, colour & 0xff])


func test_faces() -> void:
	var faces: Array = _layout_document.faces
	assert_eq(faces.size(), StackLayout.FACE_COUNT)
	for face: Dictionary in faces:
		var index: int = _int(face.face)
		assert_eq(StackLayout.face_indices(index), _ints(face.mof_vertices), "Face %d MOF corners" % index)
		assert_eq(StackLayout.gpu_face_indices(index), _ints(face.gpu_vertices), "Face %d GPU corners" % index)
		assert_eq(StackLayout.FACE_NORMALS[index], _vector(face.normal))
		assert_eq("world_slice" if index < StackLayout.SIDE_FACES else "world_full", str(face.uv))
	var spin: Dictionary = _layout_document.spin_image_face
	assert_eq(StackLayout.SPIN_IMAGE_FACE, _int(spin.face))
	assert_eq(StackLayout.SPIN_IMAGE_CORNERS, _ints(spin.gpu_image_corners))
	assert_eq(StackSelector.SPIN_IMAGE_COLOUR, _int(spin.tint))


func test_retail_rows() -> void:
	var layout: StackLayout = _retail_layout()
	var rows: Array = _layout_document.rows
	assert_eq(layout.row_count(), rows.size())
	for row: Dictionary in rows:
		var index: int = _int(row.position)
		assert_eq(layout.y_size(index), _int(row.y_size), "Row %d y size" % index)
		assert_eq(layout.y_position(index), _int(row.y_position), "Row %d y position" % index)
		assert_eq(layout.camera_target_y(index), _int(row.camera_target_y), "Row %d camera target" % index)
		assert_eq(layout.row_vertices(index), _vectors(row.vertices), "Row %d vertices" % index)
		assert_eq(layout.spin_start(index), _vector(row.spin_start), "Row %d spin start" % index)
		assert_eq(layout.spin_end(index), _vector(row.spin_end), "Row %d spin end" % index)
		var divisions: int = _int(row.slice_divisions)
		assert_eq(StackLayout.side_strip(divisions * 7, _int(row.slice_v_index), divisions),
			Vector2i(_int(row.slice_v_index) * 7, 7), "Row %d slice" % index)


func test_gold_frogs() -> void:
	var layout: StackLayout = _retail_layout()
	var gold: Dictionary = _layout_document.gold_frogs
	assert_eq(StackLayout.LEVEL_TABLE, _ints(gold.level_table))
	for entry: Dictionary in gold.themes:
		var slot: int = _int(entry.theme) - 1
		assert_eq(1 << (slot + 1), _int(entry.bit))
		assert_eq(StackLayout.gold_frog_block(slot), _int(entry.slot), "Theme %d block" % _int(entry.theme))
	var slots: Array = gold.slots
	assert_eq(layout.block_count(), slots.size())
	for entry: Dictionary in slots:
		var block: int = _int(entry.slot)
		assert_eq(layout.gold_frog_quad(block), _vectors(entry.corners), "Block %d quad" % block)


func test_motion_scenarios() -> void:
	var scenarios: Array = _motion_document.scenarios
	assert_gt(scenarios.size(), 0)
	for scenario: Dictionary in scenarios:
		_check_scenario(scenario)


func _check_scenario(scenario: Dictionary) -> void:
	var name: String = str(scenario.name)
	var rows: Array = scenario.rows
	var levels := PackedInt32Array()
	for index: int in rows.size():
		levels.append(SYNTHETIC_LEVEL_BASE + index)
	var stack: LevelStack = _stack(rows, levels)
	var layout: StackLayout = StackLayout.create(stack)
	var progress: LevelProgress = LevelProgress.create(stack)
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		progress.arcade_flags[index] = _int(row.flags)
	for index: int in rows.size():
		assert_eq(layout.y_size(index), _int(scenario.y_size[index]), "%s row %d y size" % [name, index])
		assert_eq(layout.y_position(index), _int(scenario.y_position[index]), "%s row %d y position" % [name, index])
	var widths := PackedInt32Array()
	widths.resize(rows.size())
	widths.fill(_int(scenario.name_width))
	var first_time: bool = scenario.first_time
	var selector: StackSelector = StackSelector.create(layout, progress, levels[_int(scenario.start_row)],
		first_time, widths)
	var trace: Array = scenario.trace
	var no_events: Array[StackSelector.Event] = []
	var initial: Dictionary = trace[0]
	_check_tick(name, selector, initial, no_events, levels)
	var tick: int = 0
	var inputs: Array = scenario.inputs
	for item: Array in inputs:
		var names: Array = item[1]
		for _repeat: int in _int(item[0]):
			if selector.finished:
				break
			tick += 1
			var buttons := StackSelector.Buttons.new(names.has("up"), names.has("down"), names.has("go"), names.has("back"))
			var events: Array[StackSelector.Event] = selector.step(buttons)
			if tick >= trace.size():
				fail_test("%s: the port ran past the golden trace at tick %d" % [name, tick])
				return
			var expected: Dictionary = trace[tick]
			if not _check_tick(name, selector, expected, events, levels):
				return
	assert_eq(tick + 1, trace.size(), "%s: trace length" % name)


func _check_tick(name: String, selector: StackSelector, expected: Dictionary, events: Array[StackSelector.Event],
		levels: PackedInt32Array) -> bool:
	var label: String = "%s tick %d" % [name, _int(expected.tick)]
	var actual: Dictionary = {
		"mode": MODE_NAMES[selector.mode], "camera_y": selector.camera_y, "camera_vel": selector.camera_velocity,
		"camera_acc": selector.camera_acceleration, "camera_flags": selector.camera_flag,
		"target_y": selector.target_y, "work_row": selector.focused_row, "glowy_row": selector.glowy_row,
		"glow": selector.glow_value, "glow_dir": selector.glow_direction, "first_time": selector.first_time,
	}
	var wanted: Dictionary = {}
	for key: String in actual:
		var value: Variant = expected[key]
		wanted[key] = value if typeof(value) == TYPE_STRING or typeof(value) == TYPE_BOOL else _int(value)
	var slides := PackedInt32Array()
	var tints := PackedInt32Array()
	for row: int in selector.row_count():
		slides.append(selector.current_z(row))
		tints.append(selector.tint(row))
	actual["current_z"] = slides
	actual["tint"] = tints
	wanted["current_z"] = _ints(expected.current_z)
	wanted["tint"] = _ints(expected.tint)
	var kinds: Array[int] = []
	for event: StackSelector.Event in events:
		kinds.append(event.kind)
		if event.kind == StackSelector.EventKind.ENTER_GAME:
			actual["enter_level"] = event.level
			wanted["enter_level"] = levels[selector.focused_row]
	var expected_kinds: Array[int] = []
	for event_name: String in expected.events:
		if EVENT_NAMES.has(event_name):
			expected_kinds.append(_int(EVENT_NAMES[event_name]))
	actual["events"] = kinds
	wanted["events"] = expected_kinds
	actual["spin"] = _spin_state(selector)
	wanted["spin"] = _expected_spin(expected.spin)
	actual["fade"] = _fade_state(selector)
	wanted["fade"] = _expected_fade(expected.fade)
	for key: String in wanted:
		if str(actual[key]) != str(wanted[key]):
			assert_eq(str(actual[key]), str(wanted[key]), "%s %s" % [label, key])
			return false
	return true


static func _spin_state(selector: StackSelector) -> Variant:
	if not selector.spin_visible():
		return null
	return {"mode": SPIN_NAMES.get(selector.spin_mode, "?"), "time": selector.spin_time,
		"pos": selector.spin_position, "vec_y": selector.spin_vec_y, "vec_roll": selector.spin_vec_roll,
		"axes": selector.spin_axes(), "status_x": selector.panel_x, "title_x": selector.title_x}


static func _expected_spin(spin: Variant) -> Variant:
	if spin == null:
		return null
	var value: Dictionary = spin
	return {"mode": str(value.mode), "time": _int(value.time), "pos": _vector(value.pos),
		"vec_y": _vector(value.vec_y), "vec_roll": _vector(value.vec_roll), "axes": _vectors(value.axes),
		"status_x": _int(value.status_x), "title_x": _int(value.title_x)}


static func _fade_state(selector: StackSelector) -> Variant:
	if selector.mode != StackSelector.Mode.UPDATE_FADE:
		return null
	return {"count": selector.fade_count, "screen": selector.fade_shade(), "loading": selector.fade_loading_colour(),
		"title_y": selector.fade_title_y, "prompt_y": selector.fade_prompt_y, "name_x": selector.fade_name_x}


static func _expected_fade(fade: Variant) -> Variant:
	if fade == null:
		return null
	var value: Dictionary = fade
	return {"count": _int(value.count), "screen": _int(value.screen), "loading": _int(value.loading),
		"title_y": _int(value.title_y), "prompt_y": _int(value.prompt_y), "name_x": _int(value.name_x)}

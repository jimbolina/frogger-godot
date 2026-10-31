extends GutTest
## HighScoreTour and HighScoreScene agree with the independent frozen-C high-score view facts in
## tests/golden/synthetic/frontend_high_score_view.json (tools/make_golden_high_score_view.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_high_score_view.json"
const EVENT_NAMES: PackedStringArray = ["hop", "croak", "splash", "spin_out", "spin_in", "switched", "back",
	"back_to_options", "timeout", "leave"]
const OPERATION_NAMES: PackedStringArray = ["SCROLLY", "LEVEL_SELECT"]
const CAMERA_NAMES: PackedStringArray = ["STATIC", "SCROLLY"]
const REQUEST_NAMES: Array = [null, "MAIN_MENU", "OPTIONS"]
const MODE_NAMES: PackedStringArray = ["SELECTING", "SHOW_LEVEL_INFO", "START_FADE", "UPDATE_FADE"]
const SPIN_NAMES: Dictionary = {1: "OUT", 2: "IN", 4: "HOLD"}
const HELD_BUTTONS: Dictionary = {"up": OptionsMenu.Buttons.UP, "down": OptionsMenu.Buttons.DOWN}
const PRESSED_BUTTONS: Dictionary = {
	"left": OptionsMenu.Buttons.LEFT,
	"right": OptionsMenu.Buttons.RIGHT,
	"fire": OptionsMenu.Buttons.FIRE,
	"back": OptionsMenu.Buttons.BACK,
}
const LEVEL_SLOTS: int = 60

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


static func _vector(value: Variant) -> Vector3i:
	var items: PackedInt32Array = _ints(value)
	return Vector3i(items[0], items[1], items[2])


static func _normalised(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return _int(value)
		TYPE_ARRAY:
			var items: Array = value
			var result: Array = []
			for item: Variant in items:
				result.append(_normalised(item))
			return result
		TYPE_DICTIONARY:
			var entries: Dictionary = value
			var result: Dictionary = {}
			for key: Variant in entries:
				result[key] = _normalised(entries[key])
			return result
	return value


static func _list(values: Variant) -> Array:
	var result: Array = []
	match typeof(values):
		TYPE_PACKED_INT32_ARRAY:
			var packed: PackedInt32Array = values
			for value: int in packed:
				result.append(value)
		TYPE_VECTOR3I:
			var vector: Vector3i = values
			result = [vector.x, vector.y, vector.z]
		_:
			var items: Array = values
			for item: Variant in items:
				result.append(_list(item) if typeof(item) in [TYPE_PACKED_INT32_ARRAY, TYPE_VECTOR3I, TYPE_ARRAY] else item)
	return result


## The first difference between [param actual] and [param expected] under [param path], or "".
static func _difference(path: String, actual: Variant, expected: Variant) -> String:
	if typeof(expected) == TYPE_DICTIONARY:
		if typeof(actual) != TYPE_DICTIONARY:
			return "%s: expected a record, got %s" % [path, str(actual)]
		var wanted: Dictionary = expected
		var have: Dictionary = actual
		for key: Variant in wanted:
			if not have.has(key):
				return "%s.%s missing" % [path, key]
			var found: String = _difference("%s.%s" % [path, key], have[key], wanted[key])
			if found != "":
				return found
		return ""
	if str(actual) != str(expected):
		return "%s: %s != expected %s" % [path, str(actual), str(expected)]
	return ""


static func _buttons(names: Array) -> OptionsMenu.Buttons:
	var held: int = 0
	var pressed: int = 0
	for item: String in names:
		if HELD_BUTTONS.has(item):
			held |= _int(HELD_BUTTONS[item])
		elif PRESSED_BUTTONS.has(item):
			pressed |= _int(PRESSED_BUTTONS[item])
	return OptionsMenu.Buttons.new(held, pressed)


static func _event_names(events: Array[int]) -> Array:
	var names: Array = []
	for kind: int in events:
		names.append(EVENT_NAMES[kind])
	return names


func _main_rows() -> Array[HighScoreRow]:
	var rows: Array[HighScoreRow] = []
	var table: Array = _document.default_table
	for entry: Array in table:
		rows.append(HighScoreRow.create(str(entry[0]), _int(entry[1])))
	return rows


func test_constants() -> void:
	var c: Dictionary = _document.constants
	assert_eq(HighScoreTour.AFTER_INPUT_DURATION, _int(c.after_input_duration))
	assert_eq(HighScoreTour.LEVEL_DURATION, _int(c.level_duration))
	assert_eq(HighScoreScene.FROG_WAIT_TIME, _int(c.frog_wait_time))
	assert_eq(HighScoreScene.FROG_JUMP_TIME, _int(c.frog_jump_time))
	assert_eq(HighScoreScene.FLY_TIME, _int(c.fly_time))
	assert_eq(OptionsMenu.FLY_ON_SPEED, _int(c.fly_on_speed))
	assert_eq(OptionsMenu.FLY_OFF_SPEED, _int(c.fly_off_speed))
	assert_eq(OptionsMenu.FLY_ON_HEIGHT, _int(c.fly_on_height))
	assert_eq(HighScoreScene.MODEL_SCALE, _int(c.model_scale))
	assert_eq(HighScoreScene.LOG_SCALE_X, _int(c.log_scale_x))
	assert_eq(HighScoreScene.LOG_TILT, _int(c.log_tilt))
	assert_eq(HighScoreScene.FROG_SCALE, _int(c.frog_scale))
	assert_eq(HighScoreScene.FROG_RAISE, _int(c.frog_raise))
	assert_eq(HighScoreScene.THROAT_SCALE, _int(c.throat_scale))
	assert_eq(HighScoreScene.TURTLE_MODEL_ROTATION_Y, _int(c.turtle_model_rotation_y))
	assert_eq(HighScoreScene.TURTLE_ANIMATED_POLYS, _int(c.turtle_animated_polys))
	assert_eq(OptionsScene.LOG_POLY_INDICES, _ints(c.log_poly_indices))
	assert_eq(HighScoreScene.LOG_DIGITS, _int(c.log_digits))
	assert_eq(HighScoreScene.BLANK_DIGIT_CEL, _int(c.blank_digit_cel))
	assert_eq(HighScoreScene.SPLASH_SCALE, _int(c.splash_scale))
	assert_eq(HighScoreScene.SPLASH_OT_OFFSET, _int(c.splash_ot_offset))
	assert_eq(HighScoreScene.CAMERA_FOLLOW_OFFSET, _int(c.follow_offset))
	assert_eq(HighScoreTour.CREEP_STEP, _int(c.creep_step))
	assert_eq(HighScoreTour.TOUR_WAIT, _int(c.tour_wait))
	var cameras: Dictionary = c.cameras
	var static_camera: Dictionary = cameras.STATIC
	var main_camera: Dictionary = cameras.MAIN
	assert_eq(HighScoreTour.STATIC_CAMERA_SOURCE, _vector(static_camera.source))
	assert_eq(HighScoreTour.STATIC_CAMERA_TARGET, _vector(static_camera.target))
	assert_eq(HighScoreScene.MAIN_CAMERA_SOURCE, _vector(main_camera.source))
	assert_eq(HighScoreScene.MAIN_CAMERA_TARGET, _vector(main_camera.target))
	var arrows: Dictionary = c.arrows
	var left: PackedInt32Array = _ints(arrows.left)
	var right: PackedInt32Array = _ints(arrows.right)
	assert_eq(HighScoreTour.ARROW_LEFT, Vector2i(left[0], left[1]))
	assert_eq(HighScoreTour.ARROW_RIGHT, Vector2i(right[0], right[1]))
	assert_eq(str(c.start_action), str(HighScoreScene.ACTION_WAIT2))


func test_models_and_layout() -> void:
	var names: Dictionary = _document.models
	assert_eq(HighScoreScene.TURTLE_MODEL, str(names.turtle))
	assert_eq(HighScoreScene.LOG_MODEL, str(names.log))
	var letters: Array = names.letters
	var extras: Array = names.extras
	assert_eq(HighScoreScene.LETTER_MODELS, PackedStringArray(letters))
	assert_eq(HighScoreScene.EXTRA_MODELS, PackedStringArray(extras))
	var scene: HighScoreScene = HighScoreScene.create(_main_rows())
	var layout: Dictionary = _document.layout
	var groups: Dictionary = {"turtles": scene.turtles, "pads": scene.pads, "logs": scene.logs, "extras": scene.extras}
	for group: String in groups:
		var matrices: Array[PackedInt32Array] = groups[group]
		var entries: Array = layout[group]
		assert_eq(matrices.size(), entries.size(), group)
		for index: int in entries.size():
			var entry: Dictionary = entries[index]
			assert_eq(matrices[index][9], _int(entry.x), "%s %d x" % [group, index])
			assert_eq(matrices[index][10], OptionsMenu.FLY_ON_HEIGHT, "%s %d y" % [group, index])
			assert_eq(matrices[index][11], _int(entry.z), "%s %d z" % [group, index])
			if entry.has("cel"):
				assert_eq(HighScoreScene.turtle_cel(index), _int(entry.cel), "turtle %d cel" % index)
	assert_eq(scene.pad_letters, _ints(layout.pad_letters))


func test_log_cels() -> void:
	var samples: Array = _document.log_cels
	for sample: Dictionary in samples:
		var score: int = _int(sample.score)
		assert_eq(HighScoreScene.digit_cels(score), _ints(sample.digits), "digits of %d" % score)
		assert_eq(HighScoreScene.log_poly_cels(score), _ints(sample.polys), "polys of %d" % score)


func test_letter_indices() -> void:
	for group: String in ["letter_indices", "port_fallback_letters"]:
		var entries: Array = _document[group]
		for entry: Array in entries:
			assert_eq(HighScoreScene.letter_index(str(entry[0])), _int(entry[1]), "%s '%s'" % [group, entry[0]])


func test_frog_motion_and_arrow_glow() -> void:
	var motion: Array = _document.frog_motion
	assert_eq(motion.size(), HighScoreScene.FROG_JUMP_TIME)
	for entry: Dictionary in motion:
		assert_eq(HighScoreScene.jump_lift(_int(entry.count)), _int(entry.lift), "lift at %d" % _int(entry.count))
	var glow: Array = _document.arrow_glow
	for entry: Array in glow:
		assert_eq(HighScoreTour.arrow_glow(_int(entry[0])), _int(entry[1]), "glow at frame %d" % _int(entry[0]))


func test_events_are_named_in_enum_order() -> void:
	var names: Array = _document.events
	assert_eq(PackedStringArray(names), EVENT_NAMES)
	assert_eq(HighScoreTour.EventKind.size(), EVENT_NAMES.size())


func test_tour_scenarios() -> void:
	var scenarios: Array = _document.tour_scenarios
	assert_gt(scenarios.size(), 0)
	for scenario: Dictionary in scenarios:
		_check_tour(scenario)


func test_scene_scenarios() -> void:
	var scenarios: Array = _document.scene_scenarios
	assert_gt(scenarios.size(), 0)
	for scenario: Dictionary in scenarios:
		_check_scene(scenario)


func _tour(scenario: Dictionary) -> HighScoreTour:
	var rows: Array = _document.tour_stack
	var arcade: Array[LevelStack.Row] = []
	var block: int = -1
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		var previous: Dictionary = rows[index - 1] if index > 0 else row
		if index == 0 or _int(previous.world) != _int(row.world):
			block += 1
		arcade.append(LevelStack.Row.new(_int(row.level), _int(row.world), block, _int(row.theme), _int(row.local),
			_int(row.levels_in_world)))
	var race: Array[LevelStack.Row] = []
	var stack: LevelStack = LevelStack.create(arcade, race)
	var progress: LevelProgress = LevelProgress.create(stack)
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		progress.arcade_flags[index] = _int(row.flags)
	var flags := PackedByteArray()
	flags.resize(LEVEL_SLOTS)
	var pairs: Array = scenario.new_levels
	for pair: Array in pairs:
		flags[_int(pair[0])] = _int(pair[1])
	var widths := PackedInt32Array()
	widths.resize(rows.size())
	widths.fill(_int(_document.tour_name_width))
	var from_options: bool = scenario.from_options
	var automatic: bool = scenario.automatic
	var new_main: bool = scenario.new_main
	var first_time: bool = scenario.first_time
	return HighScoreTour.create(StackLayout.create(stack), progress, _main_rows(), from_options, automatic, new_main,
		flags, first_time, widths)


func _tour_state(tour: HighScoreTour, tick: int, inputs: Array, events: Array[int]) -> Dictionary:
	var record: Dictionary = {
		"tick": tick, "input": inputs, "events": _event_names(events), "operation": OPERATION_NAMES[tour.operation],
		"camera_mode": CAMERA_NAMES[tour.camera_mode], "request": REQUEST_NAMES[tour.request], "counter": tour.counter,
		"tour_wait": tour.tour_wait, "picked": tour.picked, "prompt": str(tour.prompt),
		"arrows": [tour.left_arrow_visible, tour.right_arrow_visible], "title_visible": tour.title_visible,
		"background": tour.background_counter, "shown_level": tour.shown_level, "stack": null, "scene": null,
	}
	if tick > 0:
		record["frame"] = tour.frame
	var selector: StackSelector = tour.selector
	if selector != null:
		var slides: Array = []
		for row: int in selector.row_count():
			slides.append(selector.current_z(row))
		var spin: Variant = null
		if selector.spin_visible():
			spin = {"mode": SPIN_NAMES.get(selector.spin_mode, "?"), "time": selector.spin_time,
				"pos": _list(selector.spin_position), "status_x": selector.panel_x}
		record["stack"] = {"mode": MODE_NAMES[selector.mode], "camera_y": selector.camera_y,
			"camera_vel": selector.camera_velocity, "camera_acc": selector.camera_acceleration,
			"camera_flags": selector.camera_flag, "target_y": selector.target_y, "work_row": selector.focused_row,
			"current_z": slides, "spin": spin}
	if tour.scene != null:
		record["scene"] = {"fly_on": tour.fly_on, "fly_off": tour.fly_off, "frog_visible": tour.scene.frog_visible}
	return record


func _check_tour(scenario: Dictionary) -> void:
	var name: String = str(scenario.name)
	var tour: HighScoreTour = _tour(scenario)
	var expected_by_tick: Dictionary = {}
	var trace: Array = scenario.trace
	for item: Dictionary in trace:
		expected_by_tick[_int(item.tick)] = _normalised(item)
	var initial: Dictionary = expected_by_tick[0]
	initial.erase("frame")
	var no_events: Array[int] = []
	var found: String = _difference(name + " tick 0", _tour_state(tour, 0, [], no_events), initial)
	if found != "":
		fail_test(found)
		return
	var water: MenuWater = MenuWater.create(_int(scenario.frame_start))
	var tick: int = 0
	var runs: Array = scenario.inputs
	for run: Array in runs:
		var names: Array = run[1]
		for _repeat: int in _int(run[0]):
			if tour.request != HighScoreTour.Request.NONE:
				break
			tick += 1
			var events: Array[int] = tour.tick(_buttons(names), water)
			water.advance()
			if expected_by_tick.has(tick):
				found = _difference("%s tick %d" % [name, tick], _tour_state(tour, tick, names, events), expected_by_tick[tick])
				if found != "":
					fail_test(found)
					return
	assert_eq(tick, _int(scenario.ticks), "%s: tick count" % name)
	assert_ne(tour.request, HighScoreTour.Request.NONE, "%s: the page left" % name)


func _scene_state(scene: HighScoreScene, tick: int, inputs: Array, events: Array[int], with_models: bool) -> Dictionary:
	var record: Dictionary = {
		"tick": tick, "input": inputs, "events": _event_names(events), "fly_on": scene.fly_on, "fly_off": scene.fly_off,
		"camera": {"followed": scene.camera_followed, "source_z": scene.camera_source_z,
			"target_z": scene.camera_target_z},
		"frog": {"visible": scene.frog_visible, "translation": [scene.frog[9], scene.frog[10], scene.frog[11]],
			"position": _list(scene.frog_position), "turtle": scene.frog_turtle,
			"direction": "N" if scene.frog_direction == HighScoreScene.Direction.NORTH else "S",
			"jumping": scene.frog_jumping, "count": scene.frog_count, "lift": scene.frog_lift,
			"action": str(FrogAnimationCatalog.ACTION_NAMES[scene.frog_action]), "action_set": scene.frog_action_set,
			"splashes": _list(scene.splashes), "shadow_visible": scene.shadow_visible,
			"shadow_phase": scene.shadow_phase},
	}
	if tick > 0:
		record["frame"] = scene.frame
	if with_models:
		record["frog_matrix"] = _list(scene.frog)
		record["models"] = {"turtles": _list(scene.turtles), "pads": _list(scene.pads), "logs": _list(scene.logs),
			"extras": _list(scene.extras)}
	return record


func _check_scene(scenario: Dictionary) -> void:
	var name: String = str(scenario.name)
	var scene: HighScoreScene = HighScoreScene.create(_main_rows())
	var expected_by_tick: Dictionary = {}
	var trace: Array = scenario.trace
	for item: Dictionary in trace:
		expected_by_tick[_int(item.tick)] = _normalised(item)
	var initial: Dictionary = expected_by_tick[0]
	initial.erase("frame")
	var no_events: Array[int] = []
	var found: String = _difference(name + " tick 0", _scene_state(scene, 0, [], no_events, initial.has("models")), initial)
	if found != "":
		fail_test(found)
		return
	var water: MenuWater = MenuWater.create(_int(scenario.frame_start))
	var scrolly: bool = scenario.scrolly
	var tick: int = 0
	var runs: Array = scenario.inputs
	for run: Array in runs:
		var names: Array = run[1]
		for _repeat: int in _int(run[0]):
			tick += 1
			var events: Array[int] = scene.tick(water, scrolly)
			if names.has("fly_off"):
				scene.start_fly_off()
			water.advance()
			if expected_by_tick.has(tick):
				var expected: Dictionary = expected_by_tick[tick]
				found = _difference("%s tick %d" % [name, tick], _scene_state(scene, tick, names, events,
					expected.has("models")), expected)
				if found != "":
					fail_test(found)
					return
	assert_eq(tick, _int(scenario.ticks), "%s: tick count" % name)
	pass_test("%s replayed" % name)

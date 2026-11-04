extends GutTest
## OptionsMenu agrees with the independent frozen-C and retail options page facts in
## tests/golden/synthetic/frontend_options.json (tools/golden/make_golden_options.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_options.json"
const EVENT_NAMES: PackedStringArray = ["hop", "splash", "volume_step", "croak", "volume_test_sound",
	"stop_test_sound", "back", "controls", "view_scores", "leave"]
const REQUEST_NAMES: Dictionary = {
	OptionsMenu.Request.MAIN_MENU: "MAIN_MENU",
	OptionsMenu.Request.CONTROLS: "CONTROLS",
	OptionsMenu.Request.VIEW_SCORES: "VIEW_SCORES",
}
const CAMERA_NAMES: PackedStringArray = ["OPTIONS", "MAIN", "CONTROLS"]
const HELD_BUTTONS: Dictionary = {"up": OptionsMenu.Buttons.UP, "down": OptionsMenu.Buttons.DOWN}
const PRESSED_BUTTONS: Dictionary = {
	"left": OptionsMenu.Buttons.LEFT,
	"right": OptionsMenu.Buttons.RIGHT,
	"fire": OptionsMenu.Buttons.FIRE,
	"back": OptionsMenu.Buttons.BACK,
}

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


static func _row_kind(row_name: String) -> int:
	return PackedStringArray(OptionsMenu.ROW_NAMES).find(row_name)


func test_constants() -> void:
	var c: Dictionary = _document.constants
	assert_eq(OptionsMenu.SOUND_STAGES, _int(c.sound_stages))
	assert_eq(OptionsMenu.START_MUSIC, _int(c.start_music))
	assert_eq(OptionsMenu.START_SOUND, _int(c.start_sound))
	assert_eq(OptionsMenu.VOLUME_SCALE, _int(c.volume_scale))
	assert_eq(OptionsMenu.FROG_JUMP_TIME, _int(c.frog_jump_time))
	assert_eq(OptionsMenu.FLY_ON_TIME, _int(c.fly_on_time))
	assert_eq(OptionsMenu.FLY_OFF_TIME, _int(c.fly_off_time))
	assert_eq(OptionsMenu.FLY_ON_SPEED, _int(c.fly_on_speed))
	assert_eq(OptionsMenu.FLY_OFF_SPEED, _int(c.fly_off_speed))
	assert_eq(OptionsMenu.FLY_ON_HEIGHT, _int(c.fly_on_height))
	assert_eq(OptionsMenu.CAMERA_MOVE_TIME, _int(c.camera_move_time))
	assert_eq(OptionsMenu.PROMPT_STEP, _int(c.prompt_step))
	assert_eq(OptionsMenu.GLOW_IDLE, _int(c.glow_idle))
	var cels: Dictionary = c.log_cels
	assert_eq(OptionsMenu.LOG_CEL_BLANK, _int(cels.blank))
	assert_eq(OptionsMenu.LOG_CEL_FULL, _int(cels.full))
	assert_eq(OptionsMenu.LOG_CEL_HALF, _int(cels.half))


func test_volume_levels_and_log_cels() -> void:
	var levels: PackedInt32Array = _ints(_document.volume_levels)
	var cels: Array = _document.volume_log_cels
	assert_eq(levels.size(), OptionsMenu.SOUND_STAGES + 1)
	for step: int in levels.size():
		assert_eq(OptionsMenu.volume_level(step), levels[step], "level of step %d" % step)
		assert_eq(OptionsMenu.log_cels(step), _ints(cels[step]), "log cels of step %d" % step)


func test_jump_lift() -> void:
	var lifts: PackedInt32Array = _ints(_document.jump_lift)
	assert_eq(lifts.size(), OptionsMenu.FROG_JUMP_TIME)
	for index: int in lifts.size():
		assert_eq(OptionsMenu.jump_lift(OptionsMenu.FROG_JUMP_TIME - index), lifts[index])


func test_layout_and_cameras() -> void:
	var retail: Dictionary = _document.retail
	var lily_z: PackedInt32Array = _ints(retail.lily_z)
	assert_eq(lily_z.size(), _int(retail.rows))
	assert_eq(OptionsMenu.ROW_PITCH, _int(retail.row_pitch))
	assert_eq(OptionsMenu.LILY_X, _int(retail.lily_x))
	assert_eq(OptionsMenu.LOG_X, _int(retail.log_x))
	for index: int in lily_z.size():
		assert_eq(OptionsMenu.lily_z(index), lily_z[index], "retail lily %d" % index)
	var undecoded: Dictionary = _document.undecoded
	for entry: Array in [[true, undecoded.port_rows], [false, undecoded.port_rows_without_scores]]:
		var names: Array = entry[1]
		var kinds := PackedInt32Array()
		for row_name: String in names:
			kinds.append(_row_kind(row_name))
		var show: bool = entry[0]
		assert_eq(OptionsMenu.rows_for(show), kinds, "rows with scores %s" % show)
	assert_eq(OptionsMenu.rows_for(false).size(), _int(retail.rows), "hidden scores gives retail's lily count")
	var controls: Dictionary = _document.cameras.CONTROLS
	var source: PackedInt32Array = _ints(controls.source)
	var target: PackedInt32Array = _ints(controls.target)
	assert_eq(OptionsMenu.CONTROLS_CAMERA_SOURCE, Vector3i(source[0], source[1], source[2]))
	assert_eq(OptionsMenu.CONTROLS_CAMERA_TARGET, Vector3i(target[0], target[1], target[2]))


func test_events_are_named_in_enum_order() -> void:
	var names: Array = _document.events
	assert_eq(PackedStringArray(names), EVENT_NAMES)
	assert_eq(OptionsMenu.EventKind.size(), EVENT_NAMES.size())


func test_scenarios() -> void:
	var scenarios: Array = _document.scenarios
	assert_gt(scenarios.size(), 0)
	for scenario: Dictionary in scenarios:
		_check_scenario(scenario)


func _check_scenario(scenario: Dictionary) -> void:
	var name: String = str(scenario.name)
	var show: bool = scenario.scores_available
	var menu: OptionsMenu = OptionsMenu.create(_int(scenario.music), _int(scenario.effects),
		_row_kind(str(scenario.start_row)), show)
	var trace: Array = scenario.trace
	var initial: Dictionary = trace[0]
	if not _check_tick(name, menu, initial, PackedInt32Array()):
		return
	var frame_start: int = _int(scenario.frame_start)
	var tick: int = 0
	var inputs: Array = scenario.inputs
	for item: Array in inputs:
		var names: Array = item[1]
		var held: int = 0
		var pressed: int = 0
		for button: String in names:
			held |= _int(HELD_BUTTONS.get(button, 0))
			pressed |= _int(PRESSED_BUTTONS.get(button, 0))
		for _repeat: int in _int(item[0]):
			if menu.finished:
				break
			tick += 1
			var events: PackedInt32Array = menu.step(OptionsMenu.Buttons.new(held, pressed), frame_start + tick - 1)
			if tick >= trace.size():
				fail_test("%s: the port ran past the golden trace at tick %d" % [name, tick])
				return
			var expected: Dictionary = trace[tick]
			if not _check_tick(name, menu, expected, events):
				return
	assert_eq(tick + 1, trace.size(), "%s: trace length" % name)
	assert_true(menu.finished, "%s ends by leaving the page" % name)


func _check_tick(name: String, menu: OptionsMenu, expected: Dictionary, events: PackedInt32Array) -> bool:
	var label: String = "%s tick %d" % [name, _int(expected.tick)]
	var expected_events: Array = expected.events
	var event_names := PackedStringArray()
	for event: int in events:
		event_names.append(EVENT_NAMES[event])
	var actual: Dictionary = {
		"row": OptionsMenu.row_name(menu.row_kind), "frog": "JUMPING" if menu.jumping else "STATIONARY",
		"count": menu.jump_count, "lift": menu.lift, "music": menu.music_volume, "effects": menu.effects_volume,
		"glow": PackedInt32Array([menu.music_glow, menu.effects_glow]), "fly_on": menu.fly_on,
		"fly_off": menu.fly_off, "camera": CAMERA_NAMES[menu.camera], "camera_timer": menu.camera_timer,
		"test_sound": menu.test_sound, "request": REQUEST_NAMES.get(menu.request, null), "events": event_names,
	}
	var wanted: Dictionary = {
		"row": str(expected.row), "frog": str(expected.frog), "count": _int(expected["count"]),
		"lift": _int(expected.lift), "music": _int(expected.music), "effects": _int(expected.effects),
		"glow": _ints(expected.glow), "fly_on": _int(expected.fly_on), "fly_off": _int(expected.fly_off),
		"camera": str(expected.camera), "camera_timer": _int(expected.camera_timer),
		"test_sound": expected.test_sound, "request": expected.request,
		"events": PackedStringArray(expected_events),
	}
	for key: String in wanted:
		if str(actual[key]) != str(wanted[key]):
			assert_eq(str(actual[key]), str(wanted[key]), "%s %s" % [label, key])
			return false
	return true

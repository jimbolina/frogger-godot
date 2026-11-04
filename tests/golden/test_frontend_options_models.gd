extends GutTest
## OptionsScene agrees with the independent frozen-C options page model facts in
## tests/golden/synthetic/frontend_options_models.json (tools/golden/make_golden_options_models.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_options_models.json"
const HELD_BUTTONS: Dictionary = {"up": OptionsMenu.Buttons.UP, "down": OptionsMenu.Buttons.DOWN}
const PRESSED_BUTTONS: Dictionary = {
	"left": OptionsMenu.Buttons.LEFT,
	"right": OptionsMenu.Buttons.RIGHT,
	"fire": OptionsMenu.Buttons.FIRE,
	"back": OptionsMenu.Buttons.BACK,
}
const DIRECTION_NAMES: PackedStringArray = ["N", "S"]

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


static func _vector(values: Variant) -> Vector3i:
	var items: PackedInt32Array = _ints(values)
	return Vector3i(items[0], items[1], items[2])


static func _row_kind(row_name: String) -> int:
	return PackedStringArray(OptionsMenu.ROW_NAMES).find(row_name)


func test_constants() -> void:
	var c: Dictionary = _document.constants
	assert_eq(OptionsScene.LILY_SCALE, _int(c.lily_scale))
	assert_eq(OptionsScene.LOG_SCALE, _int(c.log_scale))
	assert_eq(OptionsScene.TITLE_SCALE, _vector(c.title_scale))
	assert_eq(OptionsScene.EXTRA_SCALE, _int(c.extra_scale))
	assert_eq(OptionsScene.FROG_SCALE, _int(c.frog_scale))
	assert_eq(OptionsScene.VOLUME_MODEL_TILT, _int(c.volume_tilt))
	assert_eq("vp_frame_count << %d" % OptionsScene.VOLUME_MODEL_SPIN_SHIFT, str(c.volume_spin))
	var offset: PackedInt32Array = _ints(c.volume_model_offset)
	assert_eq(OptionsScene.VOLUME_MODEL_X, offset[0])
	assert_eq(OptionsScene.VOLUME_MODEL_Z_OFFSET, offset[1])
	assert_eq(OptionsScene.SPRITE_SCALE, _int(c.sprite_scale))
	assert_eq(OptionsScene.TITLE_RAISE, _int(c.title_raise))
	assert_eq(OptionsScene.REFLECTION_OFFSET, _int(c.reflection_offset))
	assert_eq(OptionsScene.REFLECTION_COLOUR, _int(c.reflection_colour))
	assert_eq(OptionsScene.REFLECTION_OT_OFFSET, _int(c.reflection_ot_offset))
	assert_eq(OptionsScene.SPLASH_OT_OFFSET, _int(c.splash_ot_offset))
	assert_eq(OptionsScene.PROMPT_START, _int(c.prompt_start))
	assert_eq(OptionsScene.SLOPE_STEP, _int(c.slope_step))
	assert_eq(OptionsScene.FROG_UPDATE_PERIOD, _int(c.frog_update_period))
	assert_eq(str(OptionsScene.ACTION_WAIT2), str(c.frog_start_action))
	assert_eq(FrogCroak.MIN_SCALE, _int(c.throat_scale))
	assert_eq(OptionsScene.LOG_POLY_INDICES, _ints(c.log_poly_indices))
	assert_eq("%d + (te_w >> 1) * %d" % [OptionsScene.TITLE_X_BASE, OptionsScene.TITLE_X_STEP], str(c.title_x))
	assert_eq(OptionsScene.title_x(46), OptionsScene.TITLE_X_BASE + 23 * OptionsScene.TITLE_X_STEP)


func test_extras_actions_and_shadow_tables() -> void:
	var statics: Array = _document.extras.port_statics
	assert_eq(statics.size(), OptionsScene.EXTRA_COORDS.size())
	for index: int in statics.size():
		var entry: Array = statics[index]
		var kind: int = OptionsScene.Extra.BULLRUSH if str(entry[0]) == "OPT_STAT_BULLRUSH" else OptionsScene.Extra.STATIC_LILY
		assert_eq(OptionsScene.EXTRA_KINDS[index], kind, "extra %d kind" % index)
		assert_eq(OptionsScene.EXTRA_COORDS[index], Vector2i(_int(entry[1]), _int(entry[2])), "extra %d" % index)
	var actions: Array = _document.actions
	for index: int in actions.size():
		assert_eq(str(FrogAnimationCatalog.ACTION_NAMES[index]), str(actions[index]))
	var shadow: Dictionary = _document.shadow
	var table: PackedInt32Array = _ints(shadow.phase_table)
	assert_eq(table.size(), OptionsScene.SHADOW_PHASES)


func test_log_poly_cels() -> void:
	var cels: Array = _document.log_poly_cels
	assert_eq(cels.size(), OptionsMenu.SOUND_STAGES + 1)
	for volume: int in cels.size():
		assert_eq(OptionsScene.log_poly_cels(volume), _ints(cels[volume]), "volume %d" % volume)


func test_water_surface() -> void:
	var samples: Array = _document.surface
	assert_gt(samples.size(), 0)
	for sample: Dictionary in samples:
		var label: String = "(%d, %d) frame %d" % [_int(sample.x), _int(sample.z), _int(sample.frame)]
		var info: Array[Vector3i] = OptionsScene.surface(_int(sample.x), _int(sample.z), _int(sample.frame))
		assert_eq(info[0].x, _int(sample.height), label + " height")
		assert_eq(info[1], _vector(sample.x_slope), label + " x slope")
		assert_eq(info[2], _vector(sample.z_slope), label + " z slope")
		assert_eq(OptionsScene.surface_height(_int(sample.x), _int(sample.z), _int(sample.frame)), _int(sample.height))


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
	var widths: Dictionary[int, int] = {}
	var given: Dictionary = scenario.title_widths
	for row_name: String in given:
		widths[_row_kind(row_name)] = _int(given[row_name])
	var scene: OptionsScene = OptionsScene.create(menu, widths)
	var trace: Array = scenario.trace
	var initial: Dictionary = trace[0]
	if not _check_tick(name, scene, initial, true):
		return
	var shadow_tables: Array = _document.shadow.offsets
	var phase_table: PackedInt32Array = _ints(_document.shadow.phase_table)
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
			var frame: int = frame_start + tick - 1
			var buttons := OptionsMenu.Buttons.new(held, pressed)
			var events: PackedInt32Array = menu.step(buttons, frame)
			scene.step(menu, buttons, events, frame)
			if tick >= trace.size():
				fail_test("%s: the port ran past the golden trace at tick %d" % [name, tick])
				return
			var expected: Dictionary = trace[tick]
			if not _check_tick(name, scene, expected, false):
				return
			var offsets: Array[Vector3i] = []
			for corner: Variant in shadow_tables[phase_table[scene.shadow_phase]]:
				offsets.append(_vector(corner))
			var corners: Array = expected.shadow.corners
			var wanted: Array[Vector3i] = []
			for corner: Variant in corners:
				wanted.append(_vector(corner))
			if scene.shadow_corners(offsets) != wanted:
				assert_eq(str(scene.shadow_corners(offsets)), str(wanted), "%s tick %d shadow corners" % [name, tick])
				return
	assert_eq(tick + 1, trace.size(), "%s: trace length" % name)


func _check_tick(name: String, scene: OptionsScene, expected: Dictionary, startup: bool) -> bool:
	var label: String = "%s tick %d" % [name, _int(expected.tick)]
	var actual: Dictionary = {
		"lilies": str(scene.lilies), "titles": str(scene.titles), "logs": str(scene.logs),
		"volume_models": str(scene.volume_models), "extras": str(scene.extras), "frog": str(scene.frog),
		"frog_position": str(scene.frog_position), "frog_direction": DIRECTION_NAMES[scene.frog_direction],
		"action": str(FrogAnimationCatalog.ACTION_NAMES[scene.frog_action]), "action_set": scene.frog_action_set,
		"looping": scene.frog_looping, "splashes": str(scene.splashes), "prompt_offset": scene.prompt_offset,
	}
	var wanted: Dictionary = {
		"lilies": str(_matrices(expected.lilies)), "titles": str(_matrices(expected.titles)),
		"logs": str(_matrices(expected.logs)), "volume_models": str(_matrices(expected.volume_models)),
		"extras": str(_matrices(expected.extras)), "frog": str(_ints(expected.frog)),
		"frog_position": str(_vector(expected.frog_position)), "frog_direction": str(expected.frog_direction),
		"action": str(expected.action), "action_set": expected.action_set, "looping": expected.looping,
		"splashes": str(_ints(expected.splashes)), "prompt_offset": _int(expected.prompt_offset),
	}
	if not startup:
		var shadow: Dictionary = expected.shadow
		actual["shadow"] = [scene.shadow_visible, scene.shadow_phase, scene.shadow_on_water]
		wanted["shadow"] = [shadow.visible, _int(shadow.phase), shadow.on_water]
	for key: String in wanted:
		if str(actual[key]) != str(wanted[key]):
			assert_eq(str(actual[key]), str(wanted[key]), "%s %s" % [label, key])
			return false
	return true


static func _matrices(values: Variant) -> Array[PackedInt32Array]:
	var items: Array = values
	var result: Array[PackedInt32Array] = []
	for item: Variant in items:
		result.append(_ints(item))
	return result

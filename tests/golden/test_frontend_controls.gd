extends GutTest
## KeyBindings, KeyScancodes and ControlsPage agree with the independent retail page-25 facts
## in tests/golden/synthetic/frontend_controls.json (tools/golden/make_golden_controls.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_controls.json"
const EVENT_NAMES: Dictionary = {
	"refuse_exit": ControlsPage.EventKind.REFUSE_EXIT, "refuse_unnamed": ControlsPage.EventKind.REFUSE_UNNAMED,
	"refuse_duplicate": ControlsPage.EventKind.REFUSE_DUPLICATE, "cursor": ControlsPage.EventKind.CURSOR,
	"page": ControlsPage.EventKind.PAGE, "accept": ControlsPage.EventKind.ACCEPT,
	"back": ControlsPage.EventKind.BACK, "enter": ControlsPage.EventKind.ENTER,
	"exit": ControlsPage.EventKind.EXIT,
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


static func _text(value: Variant) -> String:
	if value == null:
		return ""
	var text: String = value
	return text


static func _flag(value: Variant) -> bool:
	var flag: bool = value
	return flag


static func _rows(value: Variant) -> Array:
	var rows: Array = value
	return rows


func _godot_constants(names: PackedStringArray) -> Dictionary:
	var entries := PackedStringArray()
	var seen: Dictionary = {}
	for constant: String in names:
		if seen.has(constant):
			continue
		seen[constant] = true
		entries.append("\"%s\": %s" % [constant, constant])
	var script := GDScript.new()
	script.source_code = "extends RefCounted\nconst VALUES: Dictionary = {%s}\n" % ", ".join(entries)
	assert_eq(script.reload(), OK, "Godot resolves every named key constant")
	var values: Dictionary = script.get_script_constant_map()["VALUES"]
	return values


func test_layout_and_devices() -> void:
	var layout: Dictionary = _document.layout
	assert_eq(_int(layout.record_count), KeyBindings.RECORD_COUNT)
	assert_eq(_int(layout.key_slots), KeyBindings.ACTION_COUNT)
	assert_eq(_int(layout.record_stride), KeyBindings.RECORD_STRIDE)
	assert_eq(_int(layout.length), KeyBindings.SERIALISED_LENGTH)
	var devices: Dictionary = _document.devices
	assert_eq(_int(devices.none), KeyBindings.DEVICE_NONE)
	assert_eq(_int(devices.keyboard), KeyBindings.DEVICE_KEYBOARD)
	assert_eq(_int(devices.first_joystick), KeyBindings.DEVICE_FIRST_JOYSTICK)


func test_actions_in_retail_slot_order() -> void:
	var actions: Array = _rows(_document.actions)
	assert_eq(actions.size(), KeyBindings.ACTION_COUNT)
	for row: Dictionary in actions:
		var slot: int = _int(row.slot)
		assert_eq(KeyBindings.ACTION_NAMES[slot], _text(row.name))
		var enum_name: String = KeyBindings.Action.keys()[slot]
		assert_eq(enum_name, _text(row.name))


func test_shipped_defaults() -> void:
	var defaults := KeyBindings.create_default()
	assert_eq(defaults.to_array(), _ints(_document.default_array))
	for row: Dictionary in _rows(_document.defaults):
		var record: int = _int(row.record)
		assert_eq(defaults.device(record), _int(row.device))
		assert_eq(defaults.is_valid(record), _int(row.valid) == 1)
		assert_eq(defaults.keys(record), _ints(row.keys))


func test_scancode_table_and_godot_keys() -> void:
	var rows: Array = _rows(_document.scancodes)
	var names := PackedStringArray()
	for row: Dictionary in rows:
		names.append(_text(row.godot_key))
		names.append(_text(row.location))
	var godot: Dictionary = _godot_constants(names)
	var listed := PackedInt32Array()
	for row: Dictionary in rows:
		var scancode: int = _int(row.scancode)
		listed.append(scancode)
		var label: String = _text(row.dik)
		var key: int = godot[_text(row.godot_key)]
		var location: int = godot[_text(row.location)]
		assert_eq(KeyScancodes.godot_key(scancode), key, label)
		assert_eq(KeyScancodes.godot_location(scancode), location, label)
		assert_eq(KeyScancodes.from_godot(key, location), scancode, label)
		assert_eq(KeyScancodes.is_bindable(scancode), _flag(row.bindable), label)
		assert_eq(KeyScancodes.english_name(scancode), _text(row.name), label)
	listed.sort()
	assert_eq(KeyScancodes.listed_scancodes(), listed)
	assert_eq(KeyScancodes.bindable_scancodes().size(), _int(_document.bindable_count))
	assert_eq(KeyScancodes.BINDABLE_COUNT, _int(_document.bindable_count))
	assert_eq(KeyScancodes.UNKNOWN, _int(_document.unknown_scancode))
	assert_false(KeyScancodes.is_bindable(KeyScancodes.UNKNOWN))


func test_page_keys_and_rules() -> void:
	var keys: Dictionary = _document.page_keys
	assert_eq(KeyScancodes.ESCAPE, _int(keys.ESCAPE))
	assert_eq(KeyScancodes.RETURN, _int(keys.RETURN))
	assert_eq(KeyScancodes.F1, _int(keys.F1))
	assert_eq(KeyScancodes.F2, _int(keys.F2))
	assert_eq(KeyScancodes.F3, _int(keys.F3))
	assert_eq(KeyScancodes.LEFT, _int(keys.LEFT))
	assert_eq(KeyScancodes.RIGHT, _int(keys.RIGHT))
	var rules: Dictionary = _document.rules
	assert_eq(ControlsPage.SLIDE_FRAMES, _int(rules.slide_frames))
	assert_eq(ControlsPage.SHOWN_BLANK, _int(rules.shown_blank))
	assert_eq(ControlsPage.SHOWN_PROMPT, _int(rules.shown_prompt))


func test_event_sounds() -> void:
	var events: Array = _rows(_document.events)
	assert_eq(events.size(), EVENT_NAMES.size())
	for row: Dictionary in events:
		var kind: int = EVENT_NAMES[_text(row.name)]
		assert_eq(ControlsPage.sound_name(kind), _text(row.froglord), _text(row.name))


func test_scenarios() -> void:
	var scenarios: Array = _rows(_document.scenarios)
	assert_gt(scenarios.size(), 0)
	for scenario: Dictionary in scenarios:
		_check_scenario(scenario)


func _check_scenario(scenario: Dictionary) -> void:
	var scenario_name: String = _text(scenario.name)
	var bindings: KeyBindings = KeyBindings.from_array(_ints(scenario.initial))
	assert_eq(bindings.error, "", scenario_name)
	var page := ControlsPage.new(bindings, _int(scenario.joysticks))
	var trace: Array = _rows(scenario.trace)
	var expected_bindings := PackedInt32Array()
	var expected_shown := PackedInt32Array()
	for row: Dictionary in trace:
		var tick: int = _int(row.tick)
		var events: Array[int] = []
		if tick > 0:
			events = page.step(_ints(row.pressed))
		var wanted: Array[int] = []
		for event: Variant in _rows(row.events):
			var kind: int = EVENT_NAMES[_text(event)]
			wanted.append(kind)
		if row.has("bindings"):
			expected_bindings = _ints(row.bindings)
		if row.has("shown"):
			expected_shown = _ints(row.shown)
		var actual: Dictionary = {
			"events": events, "state": page.state(), "helper_a": page.chooser_state(),
			"helper_b": page.key_list_state(), "helper_c": page.capture_state(), "phase": page.phase(),
			"counter": page.counter(), "record": page.record(), "cursor": page.device_cursor(),
			"action": page.action(), "finished": page.is_finished(), "bindings": bindings.to_array(),
			"shown": page.shown_values(),
		}
		var expected: Dictionary = {
			"events": wanted, "state": _int(row.state), "helper_a": _int(row.helper_a),
			"helper_b": _int(row.helper_b), "helper_c": _int(row.helper_c), "phase": _int(row.phase),
			"counter": _int(row.counter), "record": _int(row.record), "cursor": _int(row.cursor),
			"action": _int(row.action), "finished": _flag(row.finished), "bindings": expected_bindings,
			"shown": expected_shown,
		}
		assert_eq(actual, expected, "%s tick %d" % [scenario_name, tick])
	assert_true(page.is_finished(), scenario_name + " reaches the exit")

extends GutTest
## HighScoreEntry agrees with the independent frozen-C high-score name-entry facts in
## tests/golden/synthetic/frontend_high_score_entry.json (tools/golden/make_golden_high_score_entry.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_high_score_entry.json"
const EVENT_NAMES: PackedStringArray = ["hop", "splash", "letter", "rub", "end", "entered", "no_high_score", "game_quit"]
const MODE_NAMES: PackedStringArray = ["ACTIVE", "JUMPING", "STUNNED"]
const FACING_NAMES: PackedStringArray = ["N", "E", "S", "W"]
const REQUEST_NAMES: Dictionary = {
	HighScoreEntry.Request.VIEW: "VIEW",
	HighScoreEntry.Request.MAIN_MENU: "MAIN_MENU",
}
const BUTTONS: Dictionary = {
	"up": HighScoreEntry.Buttons.UP,
	"down": HighScoreEntry.Buttons.DOWN,
	"left": HighScoreEntry.Buttons.LEFT,
	"right": HighScoreEntry.Buttons.RIGHT,
	"fire": HighScoreEntry.Buttons.FIRE,
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


func test_constants() -> void:
	var c: Dictionary = _document.constants
	assert_eq(HighScoreEntry.GRID_COLUMNS, _int(c.columns))
	assert_eq(HighScoreEntry.GRID_ROWS, _int(c.rows))
	assert_eq(HighScoreEntry.PAD_COUNT, _int(c.pads))
	assert_eq(HighScoreEntry.INITIALS_COUNT, _int(c.initials))
	assert_eq(HighScoreEntry.EXTRA_COORDS.size(), _int(c.extras))
	assert_eq(HighScoreEntry.PAD_DOT, _int(c.pad_dot))
	assert_eq(HighScoreEntry.PAD_SPACE, _int(c.pad_space))
	assert_eq(HighScoreEntry.PAD_RUB, _int(c.pad_rub))
	assert_eq(HighScoreEntry.PAD_END, _int(c.pad_end))
	assert_eq(HighScoreEntry.FROG_JUMP_TIME, _int(c.frog_jump_time))
	assert_eq(HighScoreEntry.FLIP_STEP, _int(c.flip_step))
	assert_eq(HighScoreEntry.FLIP_SWAP_ANGLE, _int(c.flip_swap_angle))
	assert_eq(HighScoreEntry.FLIP_RESUME_ANGLE, _int(c.flip_resume_angle))
	assert_eq(HighScoreEntry.POP_DURATION, _int(c.pop_duration))
	assert_eq(HighScoreEntryScene.PAD_SCALE, _int(c.pad_scale))
	assert_eq(HighScoreEntryScene.FROG_SCALE, _int(c.frog_scale))
	assert_eq(HighScoreEntry.BLANK_MODEL, str(c.blank_model))
	var sounds: Dictionary = c.sounds
	var names: Dictionary = {"hop": HighScoreEntry.SOUND_HOP, "splash": HighScoreEntry.SOUND_SPLASH,
		"letter": HighScoreEntry.SOUND_LETTER, "rub": HighScoreEntry.SOUND_RUB, "end": HighScoreEntry.SOUND_END}
	for key: String in names:
		var sound: Dictionary = sounds[key]
		assert_eq(str(names[key]), str(sound.name), "sound %s" % key)
	var letter: Dictionary = sounds.letter
	var rub: Dictionary = sounds.rub
	var end: Dictionary = sounds.end
	assert_eq(HighScoreEntry.SOUND_LETTER_ID, _int(letter.id))
	assert_eq(HighScoreEntry.SOUND_RUB_ID, _int(rub.id))
	assert_eq(HighScoreEntry.SOUND_END_ID, _int(end.id))
	var actions: Dictionary = c.frog_actions
	assert_eq(str(HighScoreEntryScene.ACTION_SIT), str(actions.start))
	assert_eq(str(HighScoreEntryScene.ACTION_HOP), str(actions.hop))
	assert_eq(HighScoreEntryScene.FROG_UPDATE_PERIOD, _int(actions.update_period))


func test_jump_lift() -> void:
	var lifts: PackedInt32Array = _ints(_document.jump_lift)
	assert_eq(lifts.size(), HighScoreEntry.FROG_JUMP_TIME)
	for index: int in lifts.size():
		assert_eq(HighScoreEntry.lift_for(HighScoreEntry.FROG_JUMP_TIME - index), lifts[index])


func test_layout() -> void:
	var layout: Dictionary = _document.layout
	var pads: Array = layout.pads
	assert_eq(pads.size(), HighScoreEntry.PAD_COUNT)
	for index: int in pads.size():
		var pad: Array = pads[index]
		assert_eq(HighScoreEntry.pad_position(index), Vector3i(_int(pad[0]), 0, _int(pad[1])), "pad %d" % index)
		assert_eq(HighScoreEntry.model_name(index), str(pad[2]), "pad %d model" % index)
		var label: String = str(pad[3])
		var expected: String = label if label.length() == 1 else ""
		assert_eq(HighScoreEntry.pad_character(index), expected, "pad %d character" % index)
	var initials: Array = layout.initials_pads
	for index: int in initials.size():
		var at: Array = initials[index]
		var at_position: Vector3i = HighScoreEntry.initials_pad_position(index % HighScoreEntry.INITIALS_COUNT,
			index / HighScoreEntry.INITIALS_COUNT)
		assert_eq(at_position, Vector3i(_int(at[0]), 0, _int(at[1])), "initials pad %d" % index)
	var extras: Array = layout.extras
	assert_eq(extras.size(), HighScoreEntry.EXTRA_MODELS.size())
	for index: int in extras.size():
		var extra: Array = extras[index]
		assert_eq(HighScoreEntry.extra_position(index), Vector3i(_int(extra[0]), 0, _int(extra[1])), "extra %d" % index)
		assert_eq(HighScoreEntry.EXTRA_MODELS[index], str(extra[2]), "extra %d model" % index)
	var camera: Dictionary = layout.camera
	var source: PackedInt32Array = _ints(camera.source)
	var target: PackedInt32Array = _ints(camera.target)
	assert_eq(HighScoreEntry.CAMERA_PERSPECTIVE, _int(camera.perspective))
	assert_eq(HighScoreEntry.CAMERA_SOURCE, Vector3i(source[0], source[1], source[2]))
	assert_eq(HighScoreEntry.CAMERA_TARGET, Vector3i(target[0], target[1], target[2]))
	var starts: Array = layout.start
	var first: Dictionary = starts[0]
	assert_eq(HighScoreEntry.START_GRID.y * HighScoreEntry.GRID_COLUMNS + HighScoreEntry.START_GRID.x, _int(first.cell))
	assert_eq(FACING_NAMES[HighScoreEntry.START_FACING], str(first.facing))


func test_events_are_named_in_enum_order() -> void:
	var names: Array = _document.events
	assert_eq(PackedStringArray(names), EVENT_NAMES)
	assert_eq(HighScoreEntry.EventKind.size(), EVENT_NAMES.size())


func test_scenarios() -> void:
	var scenarios: Array = _document.scenarios
	assert_gt(scenarios.size(), 0)
	for scenario: Dictionary in scenarios:
		_check_scenario(scenario)


func _check_scenario(scenario: Dictionary) -> void:
	var name: String = str(scenario.name)
	var qualifies: bool = scenario.qualifies
	var quit: bool = scenario.quit
	var entry: HighScoreEntry = HighScoreEntry.create(qualifies, quit)
	entry.set_blocked_cells(_ints(scenario.blocked_cells))
	var trace: Array = scenario.trace
	var initial: Dictionary = trace[0]
	if not _check_tick(name, entry, initial, entry.startup_events()):
		return
	var tick: int = 0
	var inputs: Array = scenario.inputs
	for item: Array in inputs:
		var names: Array = item[1]
		var buttons: int = 0
		for button: String in names:
			buttons |= _int(BUTTONS[button])
		for _repeat: int in _int(item[0]):
			if entry.finished:
				break
			tick += 1
			var events: Array[int] = entry.tick(buttons)
			if tick >= trace.size():
				fail_test("%s: the port ran past the golden trace at tick %d" % [name, tick])
				return
			var expected: Dictionary = trace[tick]
			if not _check_tick(name, entry, expected, events):
				return
	assert_eq(tick + 1, trace.size(), "%s: trace length" % name)


func _check_tick(name: String, entry: HighScoreEntry, expected: Dictionary, events: Array[int]) -> bool:
	var label: String = "%s tick %d" % [name, _int(expected.tick)]
	var event_names := PackedStringArray()
	for event: int in events:
		event_names.append(EVENT_NAMES[event])
	var actual: Dictionary = {
		"cell": entry.cell, "facing": FACING_NAMES[entry.facing], "mode": MODE_NAMES[entry.mode],
		"count": entry.jump_count, "lift": entry.jump_lift, "position": entry.position, "initials": entry.initials,
		"pad_angle": entry.pad_angle, "pad_turn": entry.pad_turn, "pad_letter": entry.pad_letter,
		"pop_timer": entry.pop_timer, "request": REQUEST_NAMES.get(entry.request, null), "events": event_names,
	}
	var expected_events: Array = expected.events
	var wanted: Dictionary = {
		"cell": _int(expected.cell), "facing": str(expected.facing), "mode": str(expected.mode),
		"count": _int(expected["count"]), "lift": _int(expected.lift), "position": _int(expected.position),
		"initials": str(expected.initials), "pad_angle": _ints(expected.pad_angle),
		"pad_turn": _ints(expected.pad_turn), "pad_letter": _ints(expected.pad_letter),
		"pop_timer": _int(expected.pop_timer), "request": expected.request,
		"events": PackedStringArray(expected_events),
	}
	for key: String in wanted:
		if str(actual[key]) != str(wanted[key]):
			assert_eq(str(actual[key]), str(wanted[key]), "%s %s" % [label, key])
			return false
	for index: int in HighScoreEntry.INITIALS_COUNT:
		var flipping: bool = entry.pad_angle[index] != 0
		if flipping and not entry.pad_flipping(index):
			assert_true(false, "%s pad %d turns without flipping" % [label, index])
			return false
	return true

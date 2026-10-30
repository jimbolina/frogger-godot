extends GutTest
## KeyBindings defaults, record access, retail's uniqueness rules and the serialised layout.


func test_defaults_are_four_valid_keyboards() -> void:
	var bindings := KeyBindings.create_default()
	for record: int in KeyBindings.RECORD_COUNT:
		assert_eq(bindings.device(record), KeyBindings.DEVICE_KEYBOARD)
		assert_true(bindings.is_valid(record))
		assert_true(bindings.keys_unique(record))
	assert_true(bindings.every_record_valid())
	assert_eq(bindings.keys(0), PackedInt32Array([0xCB, 0xCD, 0xC8, 0xD0, 0x1C, 0x9D, 0x36, 0x28, 0x27]))
	assert_eq(bindings.key(3, KeyBindings.Action.CAMERA_ANTICLOCKWISE), 0x0B)
	assert_eq(bindings.error, "")


func test_serialised_layout_is_device_valid_then_nine_keys_per_record() -> void:
	var bindings := KeyBindings.create_default()
	bindings.set_device(2, 0)
	bindings.set_valid(1, false)
	bindings.set_key(3, KeyBindings.Action.UP, 0x1E)
	var values: PackedInt32Array = bindings.to_array()
	assert_eq(values.size(), 44)
	assert_eq(values[2 * 11], 0)
	assert_eq(values[1 * 11 + 1], 0)
	assert_eq(values[3 * 11 + 2 + KeyBindings.Action.UP], 0x1E)
	var loaded: KeyBindings = KeyBindings.from_array(values)
	assert_eq(loaded.error, "")
	assert_eq(loaded.to_array(), values)


func test_empty_array_gives_defaults_without_error() -> void:
	var loaded: KeyBindings = KeyBindings.from_array(PackedInt32Array())
	assert_eq(loaded.error, "")
	assert_eq(loaded.to_array(), KeyBindings.create_default().to_array())


func test_malformed_arrays_give_defaults_and_say_why() -> void:
	var defaults: PackedInt32Array = KeyBindings.create_default().to_array()
	var negative: PackedInt32Array = defaults.duplicate()
	negative[11] = -1
	var flag: PackedInt32Array = defaults.duplicate()
	flag[1] = 2
	var unnamed: PackedInt32Array = defaults.duplicate()
	unnamed[2] = KeyScancodes.F1
	var shared: PackedInt32Array = defaults.duplicate()
	shared[11 + 2] = 0xCB
	var repeated: PackedInt32Array = defaults.duplicate()
	repeated[3] = 0xCB
	var cases: Dictionary = {
		"have 3 values": PackedInt32Array([1, 1, 2]),
		"negative device": negative,
		"valid flag 2": flag,
		"unnamed scancode 59": unnamed,
		"in records 0 and 1": shared,
		"repeat scancode 203 in the valid record 0": repeated,
	}
	for reason: String in cases:
		var values: PackedInt32Array = cases[reason]
		var loaded: KeyBindings = KeyBindings.from_array(values)
		assert_string_contains(loaded.error, reason)
		assert_string_contains(loaded.error, "using defaults")
		assert_eq(loaded.to_array(), defaults, reason)


func test_a_repeat_in_an_invalid_record_is_kept() -> void:
	var values: PackedInt32Array = KeyBindings.create_default().to_array()
	values[1] = 0
	values[3] = 0xCB
	var loaded: KeyBindings = KeyBindings.from_array(values)
	assert_eq(loaded.error, "")
	assert_false(loaded.is_valid(0))
	assert_false(loaded.keys_unique(0))
	assert_false(loaded.every_record_valid())


func test_key_already_bound_checks_other_records_and_earlier_slots_only() -> void:
	var bindings := KeyBindings.create_default()
	assert_true(bindings.key_already_bound(0, 0, 0x12), "record 1's LEFT")
	assert_false(bindings.key_already_bound(0, 0, 0xCB), "this slot's own key")
	assert_false(bindings.key_already_bound(0, 3, 0xD0), "this record's DOWN, not below slot 3")
	assert_true(bindings.key_already_bound(0, 4, 0xD0), "this record's DOWN, below slot 4")
	assert_false(bindings.key_already_bound(0, 8, 0x1E), "A is unbound")


func test_copy_is_independent_and_action_lookup() -> void:
	var bindings := KeyBindings.create_default()
	var other: KeyBindings = bindings.copy()
	other.set_key(0, 0, 0x1E)
	assert_eq(bindings.key(0, 0), 0xCB)
	assert_eq(other.action_for(0, 0x1E), KeyBindings.Action.LEFT)
	assert_eq(bindings.action_for(1, 0x0F), KeyBindings.Action.CROAK)
	assert_eq(bindings.action_for(1, 0xCB), -1)
	assert_eq(KeyBindings.ACTION_NAMES.size(), KeyBindings.ACTION_COUNT)


func test_set_keys_replaces_one_record() -> void:
	var bindings := KeyBindings.create_default()
	var fresh := PackedInt32Array([0x10, 0x11, 0x12, 0x13, 0x14, 0x16, 0x1E, 0x1F, 0x20])
	bindings.set_keys(2, fresh)
	assert_eq(bindings.keys(2), fresh)
	assert_eq(bindings.keys(1), KeyBindings.create_default().keys(1))

extends GutTest
## KeyScancodes: the bindable set and the scancode/Godot physical-key translation.


func test_bindable_set_has_retail_count_and_excludes_page_keys() -> void:
	assert_eq(KeyScancodes.bindable_scancodes().size(), KeyScancodes.BINDABLE_COUNT)
	for scancode: int in [KeyScancodes.ESCAPE, KeyScancodes.F1, KeyScancodes.F2, KeyScancodes.F3, KeyScancodes.UNKNOWN]:
		assert_false(KeyScancodes.is_bindable(scancode), str(scancode))
	assert_true(KeyScancodes.is_bindable(KeyScancodes.RETURN))
	assert_eq(KeyScancodes.english_name(0xCB), "Left")
	assert_eq(KeyScancodes.english_name(0x3E), "")


func test_every_listed_scancode_round_trips_through_godot() -> void:
	for scancode: int in KeyScancodes.listed_scancodes():
		var key: int = KeyScancodes.godot_key(scancode)
		assert_ne(key, KEY_NONE, str(scancode))
		assert_eq(KeyScancodes.from_godot(key, KeyScancodes.godot_location(scancode)), scancode, str(scancode))


func test_modifier_sides_and_unknown_keys() -> void:
	assert_eq(KeyScancodes.from_godot(KEY_CTRL, KEY_LOCATION_RIGHT), 0x9D)
	assert_eq(KeyScancodes.from_godot(KEY_CTRL, KEY_LOCATION_LEFT), 0x1D)
	assert_eq(KeyScancodes.from_godot(KEY_SHIFT, KEY_LOCATION_UNSPECIFIED), 0x2A, "unspecified reads as left")
	assert_eq(KeyScancodes.from_godot(KEY_A, KEY_LOCATION_RIGHT), 0x1E, "location ignored for unsided keys")
	assert_eq(KeyScancodes.from_godot(KEY_F13), KeyScancodes.UNKNOWN)
	assert_eq(KeyScancodes.godot_key(0xFF), KEY_NONE)

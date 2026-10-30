extends GutTest
## Key events become player 1's bound actions and gameplay command bits.


func _event(key: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED, physical: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	if physical:
		event.physical_keycode = key
	else:
		event.keycode = key
	event.location = location
	return event


func test_default_player_one_keys_map_to_the_nine_commands() -> void:
	var input := BindingInput.new()
	var cases: Array = [
		[KEY_LEFT, KEY_LOCATION_UNSPECIFIED, TickCommand.WEST],
		[KEY_RIGHT, KEY_LOCATION_UNSPECIFIED, TickCommand.EAST],
		[KEY_UP, KEY_LOCATION_UNSPECIFIED, TickCommand.NORTH],
		[KEY_DOWN, KEY_LOCATION_UNSPECIFIED, TickCommand.SOUTH],
		[KEY_ENTER, KEY_LOCATION_UNSPECIFIED, TickCommand.SUPER_HOP],
		[KEY_CTRL, KEY_LOCATION_RIGHT, TickCommand.TONGUE],
		[KEY_SHIFT, KEY_LOCATION_RIGHT, TickCommand.CROAK],
		[KEY_APOSTROPHE, KEY_LOCATION_UNSPECIFIED, TickCommand.CAMERA_CLOCKWISE],
		[KEY_SEMICOLON, KEY_LOCATION_UNSPECIFIED, TickCommand.CAMERA_ANTICLOCKWISE],
	]
	for row: Array in cases:
		var key: Key = row[0]
		var location: KeyLocation = row[1]
		var expected: int = row[2]
		assert_eq(input.command(_event(key, location)), expected, OS.get_keycode_string(key))


func test_unbound_and_unknown_keys_give_nothing() -> void:
	var input := BindingInput.new()
	assert_eq(input.command(_event(KEY_CTRL, KEY_LOCATION_LEFT)), 0, "left Ctrl is not player 1's")
	assert_eq(input.command(_event(KEY_E)), 0, "E belongs to player 2")
	assert_eq(input.action(_event(KEY_F13)), -1, "no retail identity")


func test_key_code_is_used_without_a_physical_key() -> void:
	assert_eq(BindingInput.new().command(_event(KEY_UP, KEY_LOCATION_UNSPECIFIED, false)), TickCommand.NORTH)


func test_rebinding_and_saved_arrays_are_followed() -> void:
	var bindings := KeyBindings.create_default()
	bindings.set_key(0, KeyBindings.Action.UP, KeyScancodes.from_godot(KEY_Z))
	var input := BindingInput.from_array(bindings.to_array())
	assert_eq(input.action(_event(KEY_Z)), KeyBindings.Action.UP)
	assert_eq(input.command(_event(KEY_UP)), 0)
	assert_eq(BindingInput.from_array(PackedInt32Array([1, 2, 3])).command(_event(KEY_UP)), TickCommand.NORTH,
		"a malformed array falls back to the defaults")


func test_another_record_can_be_read() -> void:
	var input := BindingInput.new(KeyBindings.create_default(), 1)
	assert_eq(input.command(_event(KEY_E)), TickCommand.WEST)

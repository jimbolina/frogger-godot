extends GutTest
## ControlsPage state machine: entry, chooser keys, record turn, key list, capture and exit.


func _idle(page: ControlsPage, ticks: int) -> Array[int]:
	var events: Array[int] = []
	for _tick: int in ticks:
		events.append_array(page.step(PackedInt32Array()))
	return events


func _press(page: ControlsPage, codes: Array[int]) -> Array[int]:
	return page.step(PackedInt32Array(codes))


func _to_chooser(page: ControlsPage) -> void:
	_idle(page, 18)
	assert_eq(page.state(), ControlsPage.State.CHOOSER)
	assert_eq(page.chooser_state(), ControlsPage.Chooser.IDLE)


func _to_capture(page: ControlsPage) -> void:
	_to_chooser(page)
	assert_eq(_press(page, [KeyScancodes.F3]), [ControlsPage.EventKind.ENTER])
	_idle(page, 33)
	assert_eq(page.state(), ControlsPage.State.KEY_LIST)
	assert_eq(_press(page, [KeyScancodes.F1]), [ControlsPage.EventKind.ENTER])
	_idle(page, 33)
	assert_eq(page.state(), ControlsPage.State.CAPTURE)
	assert_eq(page.capture_state(), ControlsPage.Capture.WAIT)


func test_entry_takes_eighteen_ticks_then_reads_keys() -> void:
	var page := ControlsPage.new(KeyBindings.create_default())
	assert_eq(page.state(), ControlsPage.State.SEED)
	_idle(page, 1)
	assert_eq(page.state(), ControlsPage.State.ENTER)
	assert_eq(_idle(page, 16), [])
	assert_eq(page.state(), ControlsPage.State.CHOOSER)
	assert_eq(_press(page, [KeyScancodes.ESCAPE]), [], "the entry tick reads no keys")
	assert_eq(_press(page, [KeyScancodes.ESCAPE]), [ControlsPage.EventKind.BACK])
	assert_eq(page.state(), ControlsPage.State.EXIT)
	assert_eq(_idle(page, 15), [])
	assert_eq(_idle(page, 1), [ControlsPage.EventKind.EXIT])
	assert_true(page.is_finished())
	assert_eq(_press(page, [KeyScancodes.ESCAPE]), [])


func test_escape_is_refused_while_a_record_is_invalid() -> void:
	var bindings := KeyBindings.create_default()
	bindings.set_valid(2, false)
	var page := ControlsPage.new(bindings)
	_to_chooser(page)
	assert_eq(_press(page, [KeyScancodes.ESCAPE, KeyScancodes.LEFT]), [ControlsPage.EventKind.REFUSE_EXIT, ControlsPage.EventKind.CURSOR], "the refusal falls through")
	assert_eq(page.device_cursor(), KeyBindings.DEVICE_NONE)
	assert_eq(page.state(), ControlsPage.State.CHOOSER)
	assert_eq(ControlsPage.sound_name(ControlsPage.EventKind.REFUSE_EXIT), "GEN_FROG_CROAK")


func test_carousel_clamps_and_return_commits() -> void:
	var bindings := KeyBindings.create_default()
	var page := ControlsPage.new(bindings)
	_to_chooser(page)
	assert_eq(page.device_cursor_max(), KeyBindings.DEVICE_KEYBOARD)
	assert_eq(_press(page, [KeyScancodes.RIGHT]), [], "already at the highest free device")
	assert_eq(_press(page, [KeyScancodes.LEFT]), [ControlsPage.EventKind.CURSOR])
	assert_eq(page.chooser_state(), ControlsPage.Chooser.SLIDE_LEFT)
	assert_eq(_press(page, [KeyScancodes.RIGHT]), [], "keys are ignored during the slide")
	_idle(page, 15)
	assert_eq(page.chooser_state(), ControlsPage.Chooser.IDLE)
	assert_eq(_press(page, [KeyScancodes.RETURN, KeyScancodes.F3]), [ControlsPage.EventKind.ENTER], "F3 needs the keyboard")
	assert_eq(bindings.device(0), KeyBindings.DEVICE_NONE)


func test_record_turn_rederives_valid_and_drops_an_absent_joystick() -> void:
	var bindings := KeyBindings.create_default()
	bindings.set_valid(1, false)
	bindings.set_device(2, KeyBindings.DEVICE_FIRST_JOYSTICK)
	var page := ControlsPage.new(bindings)
	_to_chooser(page)
	assert_eq(_press(page, [KeyScancodes.F1]), [], "clamped at record 0")
	assert_eq(_press(page, [KeyScancodes.F2]), [ControlsPage.EventKind.PAGE])
	assert_eq(page.record(), 1)
	_idle(page, 16)
	assert_true(bindings.is_valid(1))
	_idle(page, 16)
	assert_eq(page.chooser_state(), ControlsPage.Chooser.IDLE)
	_press(page, [KeyScancodes.F2])
	_idle(page, 32)
	assert_eq(bindings.device(2), KeyBindings.DEVICE_NONE)
	assert_eq(page.device_cursor(), KeyBindings.DEVICE_NONE)


func test_capture_refusals_and_acceptance() -> void:
	var bindings := KeyBindings.create_default()
	var page := ControlsPage.new(bindings)
	_to_capture(page)
	assert_eq(page.shown(0), ControlsPage.SHOWN_PROMPT)
	assert_eq(page.shown(1), ControlsPage.SHOWN_BLANK)
	assert_eq(_press(page, [0x3E]), [ControlsPage.EventKind.REFUSE_UNNAMED])
	assert_eq(_press(page, [KeyScancodes.UNKNOWN]), [ControlsPage.EventKind.REFUSE_UNNAMED])
	assert_eq(_press(page, [0x12]), [ControlsPage.EventKind.REFUSE_DUPLICATE], "record 1's key")
	assert_eq(_press(page, [0x1F, 0x1E]), [ControlsPage.EventKind.ACCEPT], "lowest scancode first")
	assert_eq(bindings.key(0, 0), 0x1E)
	assert_eq(page.shown(0), 0x1E)
	_idle(page, 16)
	assert_eq(page.shown(1), ControlsPage.SHOWN_PROMPT)
	_idle(page, 16)
	assert_eq(page.action(), 1)
	assert_eq(_press(page, [0x1E]), [ControlsPage.EventKind.REFUSE_DUPLICATE], "an earlier slot's key")


func test_capture_escape_restores_the_record() -> void:
	var bindings := KeyBindings.create_default()
	var before: PackedInt32Array = bindings.to_array()
	var page := ControlsPage.new(bindings)
	_to_capture(page)
	_press(page, [0x1E])
	_idle(page, 32)
	assert_ne(bindings.to_array(), before)
	assert_eq(_press(page, [KeyScancodes.ESCAPE]), [ControlsPage.EventKind.BACK])
	assert_eq(bindings.to_array(), before)
	assert_eq(page.state(), ControlsPage.State.FROM_CAPTURE)
	_idle(page, 33)
	assert_eq(page.state(), ControlsPage.State.KEY_LIST)
	assert_eq(page.shown_values(), bindings.keys(0))


func test_nine_captures_validate_and_return_to_the_key_list() -> void:
	var bindings := KeyBindings.create_default()
	bindings.set_valid(0, false)
	var page := ControlsPage.new(bindings)
	_to_capture(page)
	var fresh: Array[int] = [0x10, 0x1E, 0x1F, 0x20, 0x25, 0x26, 0x2C, 0x2D, 0x2E]
	for scancode: int in fresh:
		assert_eq(_press(page, [scancode]), [ControlsPage.EventKind.ACCEPT])
		_idle(page, 32)
	assert_eq(page.state(), ControlsPage.State.FROM_CAPTURE)
	assert_eq(bindings.keys(0), PackedInt32Array(fresh))
	assert_true(bindings.is_valid(0))


func test_joystick_is_reachable_but_has_no_key_list() -> void:
	var bindings := KeyBindings.create_default()
	var page := ControlsPage.new(bindings, 1)
	_to_chooser(page)
	assert_eq(page.device_cursor_max(), KeyBindings.DEVICE_FIRST_JOYSTICK)
	assert_eq(_press(page, [KeyScancodes.RIGHT]), [ControlsPage.EventKind.CURSOR])
	_idle(page, 16)
	assert_eq(_press(page, [KeyScancodes.RETURN, KeyScancodes.F3]), [ControlsPage.EventKind.ENTER])
	assert_eq(bindings.device(0), KeyBindings.DEVICE_FIRST_JOYSTICK)
	assert_eq(page.state(), ControlsPage.State.CHOOSER)

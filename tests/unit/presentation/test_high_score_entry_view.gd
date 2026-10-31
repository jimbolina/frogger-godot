extends GutTest
## The name-entry view steps its entry at 30 Hz from player 1's direction keys and fire, drives
## the water and raises the entry's events without changing committed state.


func _view() -> HighScoreEntryView:
	var view: HighScoreEntryView = HighScoreEntryView.create(FrontEndAssets.new(), MenuWater.create(), HighScoreEntry.create(true, false))
	autofree(view)
	return view


func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	return event


func _idle(view: HighScoreEntryView, ticks: int) -> void:
	for _tick: int in ticks:
		view.tick(0)


func test_direction_keys_are_held_and_fire_counts_once() -> void:
	var view: HighScoreEntryView = _view()
	view._unhandled_key_input(_key(KEY_RIGHT, true))
	view._unhandled_key_input(_key(KEY_ENTER, true))
	assert_eq(view.sample_buttons(), HighScoreEntry.Buttons.RIGHT | HighScoreEntry.Buttons.FIRE)
	assert_eq(view.sample_buttons(), HighScoreEntry.Buttons.RIGHT, "a held direction stays held; fire counts once")
	view._unhandled_key_input(_key(KEY_RIGHT, false))
	view._unhandled_key_input(_key(KEY_UP, true))
	view._unhandled_key_input(_key(KEY_UP, false))
	assert_eq(view.sample_buttons(), HighScoreEntry.Buttons.UP, "a tap between ticks still counts")
	view._unhandled_key_input(_key(KEY_SPACE, true))
	assert_eq(view.sample_buttons(), HighScoreEntry.Buttons.FIRE)
	view._unhandled_key_input(_key(KEY_KP_ENTER, true))
	assert_eq(view.sample_buttons(), HighScoreEntry.Buttons.FIRE)


func test_escape_does_nothing() -> void:
	var view: HighScoreEntryView = _view()
	view._unhandled_key_input(_key(KEY_ESCAPE, true))
	assert_eq(view.sample_buttons(), 0, "name entry has no cancel")


func test_rebound_direction_keys_follow_player_one() -> void:
	var view: HighScoreEntryView = _view()
	var bindings: KeyBindings = KeyBindings.create_default()
	bindings.set_key(0, KeyBindings.Action.LEFT, KeyScancodes.from_godot(KEY_A))
	view.input = BindingInput.new(bindings)
	view._unhandled_key_input(_key(KEY_A, true))
	assert_eq(view.sample_buttons(), HighScoreEntry.Buttons.LEFT)
	view._unhandled_key_input(_key(KEY_A, false))
	view._unhandled_key_input(_key(KEY_LEFT, true))
	assert_eq(view.sample_buttons(), 0, "an unbound arrow is not a direction")


func test_ticks_drive_the_water_and_raise_hop_then_splash() -> void:
	var animation: MenuWater = MenuWater.create(5)
	var view: HighScoreEntryView = HighScoreEntryView.create(FrontEndAssets.new(), animation, HighScoreEntry.create(true, false))
	autofree(view)
	watch_signals(view)
	view.tick(HighScoreEntry.Buttons.RIGHT)
	assert_signal_emitted_with_parameters(view, "page_event", [HighScoreEntry.EventKind.HOP])
	assert_eq(animation.frame_count, 6, "one water frame a tick")
	assert_eq(view.scene.frame, animation.frame_count, "models sit on the heights being drawn")
	_idle(view, HighScoreEntry.FROG_JUMP_TIME)
	assert_signal_emitted_with_parameters(view, "page_event", [HighScoreEntry.EventKind.SPLASH])
	assert_eq(view.entry.cell, 15)
	assert_eq(view.scene.frog[9], view.scene.pads[15][9], "the frog lands on P")
	assert_eq(view.model_instances().size(), 0, "no models without player data")


func test_letters_flip_and_end_finishes_with_entered() -> void:
	var view: HighScoreEntryView = _view()
	watch_signals(view)
	view.tick(HighScoreEntry.Buttons.FIRE)
	assert_signal_emitted_with_parameters(view, "page_event", [HighScoreEntry.EventKind.LETTER])
	assert_eq(view.entry.initials, "O  ")
	for direction: int in [HighScoreEntry.Buttons.DOWN, HighScoreEntry.Buttons.DOWN, HighScoreEntry.Buttons.RIGHT,
			HighScoreEntry.Buttons.RIGHT, HighScoreEntry.Buttons.RIGHT, HighScoreEntry.Buttons.RIGHT, HighScoreEntry.Buttons.RIGHT]:
		view.tick(direction)
		_idle(view, HighScoreEntry.FROG_JUMP_TIME)
	assert_eq(view.entry.cell, HighScoreEntry.PAD_END)
	view.tick(HighScoreEntry.Buttons.FIRE)
	assert_signal_emitted_with_parameters(view, "page_event", [HighScoreEntry.EventKind.END])
	assert_false(view.scene.frog_visible)
	_idle(view, HighScoreEntry.POP_DURATION)
	assert_signal_emitted_with_parameters(view, "page_event", [HighScoreEntry.EventKind.ENTERED])
	assert_true(view.entry.finished)
	assert_eq(view.tick(HighScoreEntry.Buttons.FIRE), [], "a finished page does nothing")


func test_drawing_leaves_the_committed_state_alone() -> void:
	var view: HighScoreEntryView = _view()
	view.tick(HighScoreEntry.Buttons.RIGHT)
	var frog: PackedInt32Array = view.scene.frog.duplicate()
	view.render(0.5)
	view.render(1.0)
	assert_eq(view.scene.frog, frog)

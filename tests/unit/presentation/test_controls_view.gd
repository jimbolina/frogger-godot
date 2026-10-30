extends GutTest
## The controller view turns key events into scancodes for one page tick and raises its events.


func _view(bindings: KeyBindings = KeyBindings.create_default()) -> ControlsView:
	var rig := OptionsCamera.new()
	rig.aim(OptionsMenu.Camera.CONTROLS, 10)
	var view: ControlsView = ControlsView.create(FrontEndAssets.new(), bindings, MenuWater.create(), rig)
	autofree(view)
	return view


func _press(view: ControlsView, code: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.location = location
	event.pressed = true
	view._unhandled_key_input(event)


func _ticks(view: ControlsView, count: int) -> void:
	for _tick: int in count:
		view.tick()


func test_enters_and_leaves_on_escape_with_the_exit_event() -> void:
	var view: ControlsView = _view()
	watch_signals(view)
	_ticks(view, 1 + ControlsPage.SLIDE_FRAMES + 1)
	assert_eq(view.page.state(), ControlsPage.State.CHOOSER)
	_press(view, KEY_ESCAPE)
	view.tick()
	assert_signal_emitted_with_parameters(view, "page_event", [ControlsPage.EventKind.BACK])
	_ticks(view, ControlsPage.SLIDE_FRAMES)
	assert_true(view.page.is_finished())
	assert_signal_emitted_with_parameters(view, "page_event", [ControlsPage.EventKind.EXIT])


func test_capture_rebinds_with_godot_keys() -> void:
	var bindings := KeyBindings.create_default()
	var view: ControlsView = _view(bindings)
	_ticks(view, 1 + ControlsPage.SLIDE_FRAMES + 1)
	_press(view, KEY_F3)
	view.tick()
	_ticks(view, 2 * ControlsPage.SLIDE_FRAMES + 1)
	assert_eq(view.page.state(), ControlsPage.State.KEY_LIST)
	assert_eq(ControlsView.key_label(view.page.shown(0)), "Left")
	_press(view, KEY_F1)
	view.tick()
	_ticks(view, 2 * ControlsPage.SLIDE_FRAMES + 1)
	assert_eq(view.page.state(), ControlsPage.State.CAPTURE)
	assert_eq(ControlsView.key_label(view.page.shown(0)), "_")
	_press(view, KEY_A)
	view.tick()
	assert_eq(bindings.key(0, KeyBindings.Action.LEFT), KeyScancodes.from_godot(KEY_A))


func test_sweeps_the_camera_on_to_the_controls_preset() -> void:
	var view: ControlsView = _view()
	_ticks(view, 10)
	assert_eq(view.camera_rig.source, OptionsMenu.CONTROLS_CAMERA_SOURCE)
	assert_eq(view.camera_rig.timer, 0)

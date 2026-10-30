extends GutTest
## The options view steps its menu at 30 Hz from fixed menu keys, sweeps the shared camera and
## draws the frog between lilies without changing committed state.


func _view(rig: OptionsCamera = OptionsCamera.new()) -> OptionsView:
	var view: OptionsView = OptionsView.create(FrontEndAssets.new(), MenuWater.create(), rig, 3, 5)
	autofree(view)
	return view


func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _idle(view: OptionsView, ticks: int) -> void:
	for _tick: int in ticks:
		view.tick(OptionsMenu.Buttons.new())


func test_keys_become_held_and_pressed_buttons_once() -> void:
	var view: OptionsView = _view()
	view._unhandled_key_input(_key(KEY_DOWN, true))
	view._unhandled_key_input(_key(KEY_RIGHT, true))
	view._unhandled_key_input(_key(KEY_ENTER, true))
	view._unhandled_key_input(_key(KEY_ESCAPE, true))
	var buttons: OptionsMenu.Buttons = view.sample_buttons()
	assert_eq(buttons.held, OptionsMenu.Buttons.DOWN)
	assert_eq(buttons.pressed, OptionsMenu.Buttons.RIGHT | OptionsMenu.Buttons.FIRE | OptionsMenu.Buttons.BACK)
	var next: OptionsMenu.Buttons = view.sample_buttons()
	assert_eq(next.held, OptionsMenu.Buttons.DOWN, "a held key stays held")
	assert_eq(next.pressed, 0, "pressed keys count once")
	view._unhandled_key_input(_key(KEY_DOWN, false))
	assert_eq(view.sample_buttons().held, 0)


func test_camera_sweeps_to_the_options_preset_and_events_are_raised() -> void:
	var rig := OptionsCamera.new()
	var view: OptionsView = _view(rig)
	watch_signals(view)
	_idle(view, OptionsMenu.FLY_ON_TIME)
	assert_eq(rig.source, OptionsCamera.OPTIONS_SOURCE)
	view.tick(OptionsMenu.Buttons.new(OptionsMenu.Buttons.DOWN))
	assert_signal_emitted_with_parameters(view, "menu_event", [OptionsMenu.EventKind.HOP])
	assert_true(view.menu.jumping)


func test_frog_is_drawn_between_lilies_while_hopping() -> void:
	var view: OptionsView = _view()
	_idle(view, OptionsMenu.FLY_ON_TIME)
	view.tick(OptionsMenu.Buttons.new(OptionsMenu.Buttons.DOWN))
	_idle(view, 6)
	view.render(1.0)
	var z: float = view._drawn.frog.z
	assert_lt(z, float(OptionsMenu.lily_z(0)))
	assert_gt(z, float(OptionsMenu.lily_z(1)))
	assert_lt(view._drawn.frog.y, 0.0, "the hop lifts the frog")
	_idle(view, 6)
	view.render(1.0)
	assert_eq(view._drawn.frog.z, float(OptionsMenu.lily_z(1)))
	assert_eq(view.menu.row_kind, OptionsMenu.Row.CONTROLS)


func test_fly_on_drops_models_onto_the_water() -> void:
	var view: OptionsView = _view()
	assert_eq(view._drawn.lilies[0].y, float(OptionsMenu.FLY_ON_HEIGHT))
	_idle(view, OptionsMenu.FLY_ON_TIME)
	view.render(1.0)
	assert_eq(view._drawn.lilies[0].y, 0.0)
	assert_eq(view._drawn.logs.size(), view.menu.rows().size())


func test_projection_centres_the_camera_target() -> void:
	var at: Vector3 = OptionsView.project(OptionsCamera.OPTIONS_SOURCE, OptionsCamera.OPTIONS_TARGET, Vector3(OptionsCamera.OPTIONS_TARGET))
	assert_almost_eq(Vector2(at.x, at.y), OptionsView.CENTRE, Vector2.ONE * 0.5, "within the 4.12 camera matrix rounding")
	assert_gt(at.z, 0.0)

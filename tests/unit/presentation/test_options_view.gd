extends GutTest
## The options view steps its menu at 30 Hz from fixed menu keys, sweeps the shared camera and
## places the frog between lilies without changing committed state.


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


func test_frog_is_placed_between_lilies_while_hopping() -> void:
	var view: OptionsView = _view()
	_idle(view, OptionsMenu.FLY_ON_TIME)
	view.tick(OptionsMenu.Buttons.new(OptionsMenu.Buttons.DOWN))
	_idle(view, 6)
	var z: int = view.scene.frog[11]
	assert_lt(z, OptionsMenu.lily_z(0))
	assert_gt(z, OptionsMenu.lily_z(1))
	assert_lt(view.scene.frog[10], view.scene.lilies[1][10], "the hop lifts the frog above the water")
	_idle(view, 6)
	assert_eq(view.scene.frog[11], view.scene.lilies[1][11])
	assert_eq(view.menu.row_kind, OptionsMenu.Row.CONTROLS)


func test_fly_on_drops_models_onto_the_water_the_view_draws() -> void:
	var animation: MenuWater = MenuWater.create(7)
	var view: OptionsView = OptionsView.create(FrontEndAssets.new(), animation, OptionsCamera.new(), 3, 5)
	autofree(view)
	assert_eq(view.scene.lilies[0][10], OptionsMenu.FLY_ON_HEIGHT)
	_idle(view, OptionsMenu.FLY_ON_TIME)
	assert_eq(animation.frame_count, 7 + OptionsMenu.FLY_ON_TIME, "the view drives the water one frame a tick")
	assert_eq(view.scene.frame, animation.frame_count, "models sit on the heights being drawn")
	var lily: PackedInt32Array = view.scene.lilies[0]
	assert_eq(lily[10], OptionsScene.surface_height(lily[9], lily[11], animation.frame_count))
	assert_eq(view.scene.logs.size(), 2, "music and effects logs")
	assert_eq(view.model_instances().size(), 0, "no models without player data")


func test_projection_centres_the_camera_target() -> void:
	var at: Vector3 = OptionsView.project(OptionsCamera.OPTIONS_SOURCE, OptionsCamera.OPTIONS_TARGET, Vector3(OptionsCamera.OPTIONS_TARGET))
	assert_almost_eq(Vector2(at.x, at.y), OptionsView.CENTRE, Vector2.ONE * 0.5, "within the 4.12 camera matrix rounding")
	assert_gt(at.z, 0.0)


func test_the_page_is_lit_with_the_options_lights() -> void:
	var view: OptionsView = _view()
	var spec: SceneLightingSpec = SceneLightingBuilder.from_lighting(OptionsModels.options_lighting(), false)
	var lighting: SceneLighting = view.water.scene_lighting
	assert_not_null(lighting)
	assert_null(view.water.world_environment, "the scene lighting owns the world's environment")
	assert_eq(view.find_children("*", "WorldEnvironment", true, false).size(), 1)
	assert_eq(lighting.light_nodes().size(), spec.lights.size())
	assert_eq(lighting.light_nodes().size(), 1)
	assert_false(lighting.light_nodes()[0].shadow_enabled)
	assert_almost_eq(lighting.light_nodes()[0].light_energy, spec.lights[0].energy, 1e-6)
	assert_almost_eq(lighting.applied_ambient, spec.ambient, Vector3.ONE * 1e-6)
	assert_eq(lighting.environment.background_mode, Environment.BG_COLOR)
	assert_eq(lighting.environment.background_color, Color.BLACK)

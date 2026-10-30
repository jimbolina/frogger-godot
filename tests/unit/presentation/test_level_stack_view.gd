extends GutTest
## The level-select view draws committed selector state, interpolates between ticks and raises its events.

const StackLayoutTest := preload("res://tests/unit/game/frontend/test_stack_layout.gd")
const ORG1: int = 24


func _view(first_time: bool = true, gold_frogs: int = 0) -> LevelStackView:
	var stack: LevelStack = StackLayoutTest.retail_stack()
	var progress: LevelProgress = LevelProgress.create(stack)
	progress.gold_frogs = gold_frogs
	var view: LevelStackView = LevelStackView.create(FrontEndAssets.new(), stack, progress, -1, first_time)
	autofree(view)
	return view


func _idle(view: LevelStackView, ticks: int) -> void:
	for _tick: int in ticks:
		view.tick(StackSelector.Buttons.new())


func test_builds_one_box_per_row_and_the_gold_frog_slots() -> void:
	var view: LevelStackView = _view()
	assert_eq(view.boxes.size(), 33)
	assert_eq(view.gold_frogs.size(), StackLayout.GOLD_FROG_SLOTS)
	assert_false(view.spin_box.visible)
	assert_eq(view.selector.focused_level(), ORG1, "ORG1 when no level was played")
	for quad: MeshInstance3D in view.gold_frogs:
		if quad != null:
			assert_false(quad.visible)


func test_gold_frog_shows_its_theme_bit() -> void:
	var view: LevelStackView = _view(true, 1 << 1)
	assert_true(view.gold_frogs[0].visible)
	assert_false(view.gold_frogs[1].visible)


func test_camera_uses_perspective_1000_on_the_pc_display() -> void:
	assert_almost_eq(LevelStackView.vertical_fov_degrees(), rad_to_deg(2.0 * atan(240.0 / 2000.0)), 0.00001)
	var transform: Transform3D = LevelStackView.camera_transform(StackLayout.CAMERA_Y_OFFSET)
	var view_axis: Vector3i = StackLayout.STACK_ORIGIN - StackLayout.CAMERA_EYE
	var forward: Vector3 = GameSpace.normal(view_axis.x, view_axis.y, view_axis.z).normalized()
	assert_almost_eq(-transform.basis.z.normalized(), forward, Vector3.ONE * 0.001)
	var at: Vector3i = StackLayout.camera_translation(StackLayout.CAMERA_Y_OFFSET)
	assert_almost_eq(transform.origin, GameSpace.position(at.x, at.y, at.z), Vector3.ONE * 0.0001)


func test_focused_box_slides_out_and_interpolates_between_ticks() -> void:
	var view: LevelStackView = _view()
	view.tick(StackSelector.Buttons.new())
	assert_almost_eq(view.boxes[0].position, LevelStackView.box_position(0), Vector3.ONE * 0.0001, "drawn at the previous tick")
	view.render(0.5)
	assert_almost_eq(view.boxes[0].position, LevelStackView.box_position(-0x20), Vector3.ONE * 0.0001)
	view.render(1.0)
	assert_almost_eq(view.boxes[0].position, LevelStackView.box_position(-0x40), Vector3.ONE * 0.0001)
	assert_eq(view.selector.current_z(0), -0x40, "drawing leaves the committed state alone")
	_idle(view, 7)
	view.render(1.0)
	assert_almost_eq(view.boxes[0].position, LevelStackView.box_position(StackSelector.SLIDE_DIST), Vector3.ONE * 0.0001)
	assert_almost_eq(view.boxes[1].position, LevelStackView.box_position(0), Vector3.ONE * 0.0001)


func test_tints_follow_the_selector() -> void:
	var view: LevelStackView = _view()
	_idle(view, 3)
	for row: int in view.boxes.size():
		var material: ShaderMaterial = view.boxes[row].get_surface_override_material(0)
		assert_eq(StackMeshBuilder.material_tint(material), view.selector.tint(row), "row %d" % row)


func test_go_on_an_extended_box_spins_it_out_and_hides_the_box() -> void:
	var view: LevelStackView = _view()
	watch_signals(view)
	_idle(view, 8)
	view.tick(StackSelector.Buttons.new(false, false, true))
	assert_signal_emitted_with_parameters(view, "stack_event", [StackSelector.EventKind.HOP, -1])
	view.render(1.0)
	assert_true(view.spin_box.visible)
	assert_false(view.boxes[0].visible)
	assert_eq(view.spin_box.mesh.get_surface_count(), 2)
	assert_true(view.panel.level_name.visible)
	_idle(view, 11)
	view.render(1.0)
	assert_almost_eq(view.spin_box.transform.origin, GameSpace.position(view.selector.spin_position.x,
		view.selector.spin_position.y, view.selector.spin_position.z), Vector3.ONE * 0.0001)
	assert_eq(view.panel.level_name.position, Vector2(view.selector.title_x, StackLayout.LEVEL_TITLE_Y))


func test_back_returns_the_spin_then_leaves_on_the_first_entry() -> void:
	var view: LevelStackView = _view()
	_idle(view, 8)
	view.tick(StackSelector.Buttons.new(false, false, true))
	_idle(view, 11)
	view.tick(StackSelector.Buttons.new(false, false, false, true))
	_idle(view, 12)
	view.render(1.0)
	assert_false(view.spin_box.visible)
	assert_true(view.boxes[0].visible)
	watch_signals(view)
	view.tick(StackSelector.Buttons.new(false, false, false, true))
	assert_signal_emitted_with_parameters(view, "stack_event", [StackSelector.EventKind.BACK, -1])


func test_second_go_croaks_fades_and_enters_the_level() -> void:
	var view: LevelStackView = _view()
	_idle(view, 8)
	view.tick(StackSelector.Buttons.new(false, false, true))
	_idle(view, 11)
	watch_signals(view)
	view.tick(StackSelector.Buttons.new(false, false, true))
	assert_signal_emitted_with_parameters(view, "stack_event", [StackSelector.EventKind.CROAK, -1])
	_idle(view, 16)
	view.render(1.0)
	assert_true(view.panel.fade.visible)
	assert_eq(view.panel.fade.color.r8, view.selector.fade_shade())
	assert_eq(view.panel.title.position.y, float(view.selector.fade_title_y))
	_idle(view, 32)
	assert_signal_emitted_with_parameters(view, "stack_event", [StackSelector.EventKind.ENTER_GAME, ORG1])
	assert_true(view.selector.finished)


func test_keys_become_held_directions_and_single_presses() -> void:
	var view: LevelStackView = _view()
	view._unhandled_key_input(_key(KEY_DOWN, true))
	view._unhandled_key_input(_key(KEY_DOWN, false))
	view._unhandled_key_input(_key(KEY_ENTER, true))
	var buttons: StackSelector.Buttons = view.sample_buttons()
	assert_true(buttons.down_held, "a tap between ticks still counts")
	assert_true(buttons.go_pressed)
	view._unhandled_key_input(_key(KEY_UP, true))
	buttons = view.sample_buttons()
	assert_false(buttons.down_held)
	assert_false(buttons.go_pressed, "presses are counted once")
	assert_true(buttons.up_held)
	assert_true(view.sample_buttons().up_held, "held until released")
	view._unhandled_key_input(_key(KEY_ESCAPE, true))
	assert_true(view.sample_buttons().back_pressed)


func test_prompt_follows_mode_and_first_entry() -> void:
	assert_eq(StackPanel.prompt_name(StackSelector.Mode.SELECTING, true), "select1")
	assert_eq(StackPanel.prompt_name(StackSelector.Mode.SELECTING, false), "select5")
	assert_eq(StackPanel.prompt_name(StackSelector.Mode.SHOW_LEVEL_INFO, true), "select2")
	assert_eq(StackPanel.prompt_name(StackSelector.Mode.UPDATE_FADE, false), "select2")


func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	return event

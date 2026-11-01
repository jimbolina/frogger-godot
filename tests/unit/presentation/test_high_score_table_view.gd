extends GutTest
## The high-score view page steps its tour at 30 Hz from player 1's bound and fixed keys, switches
## between the level stack and the scrolly table, shows the spun-out level's rows and raises the
## tour's events.

const StackLayoutTest := preload("res://tests/unit/game/frontend/test_stack_layout.gd")


func _view(from_options: bool, touring: bool = false, water_animation: MenuWater = MenuWater.create()) -> HighScoreTableView:
	var stack: LevelStack = StackLayoutTest.retail_stack()
	var progress: LevelProgress = LevelProgress.create(stack)
	var none: Array[HighScoreRow] = []
	var board: HighScoreBoard = HighScoreBoard.create(none, none)
	board.levels[24 * HighScoreBoard.LEVEL_RANKS] = HighScoreRow.create("ABC", 1234, PackedInt32Array([10, 20]))
	var tour: HighScoreTour = HighScoreTour.create(StackLayout.create(stack), progress, board.main, from_options, touring,
		false, board.new_levels)
	var view: HighScoreTableView = HighScoreTableView.create(FrontEndAssets.new(), water_animation, tour, stack, progress, board)
	autofree(view)
	return view


func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _idle(view: HighScoreTableView, ticks: int) -> void:
	for _tick: int in ticks:
		view.tick(OptionsMenu.Buttons.new())


func test_keys_become_held_and_pressed_buttons_once() -> void:
	var view: HighScoreTableView = _view(true)
	view._unhandled_key_input(_key(KEY_UP, true))
	view._unhandled_key_input(_key(KEY_LEFT, true))
	view._unhandled_key_input(_key(KEY_SPACE, true))
	view._unhandled_key_input(_key(KEY_ESCAPE, true))
	var buttons: OptionsMenu.Buttons = view.sample_buttons()
	assert_eq(buttons.held, OptionsMenu.Buttons.UP)
	assert_eq(buttons.pressed, OptionsMenu.Buttons.LEFT | OptionsMenu.Buttons.FIRE | OptionsMenu.Buttons.BACK)
	var next: OptionsMenu.Buttons = view.sample_buttons()
	assert_eq(next.held, OptionsMenu.Buttons.UP)
	assert_eq(next.pressed, 0)
	view._unhandled_key_input(_key(KEY_RIGHT, true))
	view._unhandled_key_input(_key(KEY_ENTER, true))
	assert_eq(view.sample_buttons().pressed, OptionsMenu.Buttons.RIGHT | OptionsMenu.Buttons.FIRE)


func test_from_options_opens_the_stack_and_left_switches_to_the_table() -> void:
	var view: HighScoreTableView = _view(true)
	assert_not_null(view.stack_view)
	assert_null(view.water)
	assert_true(view.stack_view.score_mode)
	assert_not_null(view.stack_view.checker, "the stack shows SelectLevelCreateBG's checker")
	assert_true(view.tour.left_arrow_visible)
	watch_signals(view)
	_idle(view, 1)
	view.tick(OptionsMenu.Buttons.new(0, OptionsMenu.Buttons.LEFT))
	assert_signal_emitted_with_parameters(view, "page_event", [HighScoreTour.EventKind.SWITCHED])
	assert_null(view.stack_view)
	assert_not_null(view.table)
	assert_not_null(view.water)
	assert_eq(view.table.scene, view.tour.scene)
	assert_true(view.tour.right_arrow_visible)
	view.tick(OptionsMenu.Buttons.new(0, OptionsMenu.Buttons.RIGHT))
	assert_not_null(view.stack_view, "right switches back to the stack")
	view.tick(OptionsMenu.Buttons.new(0, OptionsMenu.Buttons.BACK))
	assert_signal_emitted_with_parameters(view, "page_event", [HighScoreTour.EventKind.BACK_TO_OPTIONS])
	assert_eq(view.tour.request, HighScoreTour.Request.OPTIONS)
	assert_eq(view.tick(OptionsMenu.Buttons.new(0, OptionsMenu.Buttons.BACK)), [], "a finished page does nothing")


func test_fire_spins_the_level_out_and_shows_its_three_rows() -> void:
	var view: HighScoreTableView = _view(true)
	_idle(view, 8)
	view.tick(OptionsMenu.Buttons.new(0, OptionsMenu.Buttons.FIRE))
	assert_eq(view.tour.shown_level, 24)
	view.render(1.0)
	var lines: PackedStringArray = view.stack_view.panel.score_lines()
	assert_eq(lines.size(), 3)
	assert_eq(lines[0], "1.ABC     1234 00:30s ")
	assert_eq(StackPanel.score_line_x(lines[0], 400.0), 408.0, "22 cells centred in the 192-wide box")
	assert_eq(StackLayout.SCORE_BOX_WIDTH, 192, "retail PC's at_box_w (KF-407), not SEL_STATUS_WIDTH")
	assert_eq(StackPanel.score_line_x("1234", 0.0), 80.0)
	assert_eq(view.stack_view.panel.prompt.texture, null, "no images without player data")


func test_water_frame_count_advances_in_both_views() -> void:
	var animation: MenuWater = MenuWater.create(3)
	var view: HighScoreTableView = _view(true, false, animation)
	_idle(view, 2)
	assert_eq(animation.frame_count, 5)
	view.tick(OptionsMenu.Buttons.new(0, OptionsMenu.Buttons.LEFT))
	_idle(view, 2)
	assert_eq(animation.frame_count, 8)
	assert_eq(view.tour.scene.frame, animation.frame_count, "the table sits on the heights drawn")


func test_after_entry_without_new_scores_the_tour_times_out() -> void:
	var view: HighScoreTableView = _view(false, true)
	watch_signals(view)
	for _tick: int in 400:
		if view.tour.request != HighScoreTour.Request.NONE:
			break
		view.tick(OptionsMenu.Buttons.new())
	assert_signal_emitted_with_parameters(view, "page_event", [HighScoreTour.EventKind.TIMEOUT])
	assert_eq(view.tour.request, HighScoreTour.Request.MAIN_MENU)


func test_the_table_view_times_out_after_its_count() -> void:
	var view: HighScoreTableView = _view(false)
	assert_not_null(view.table)
	watch_signals(view)
	_idle(view, HighScoreTour.AFTER_INPUT_DURATION)
	assert_signal_not_emitted(view, "page_event", "no timeout yet")
	view.tick(OptionsMenu.Buttons.new())
	assert_signal_emitted_with_parameters(view, "page_event", [HighScoreTour.EventKind.TIMEOUT])


func test_escape_after_entry_goes_back() -> void:
	var view: HighScoreTableView = _view(false)
	watch_signals(view)
	view.tick(OptionsMenu.Buttons.new(0, OptionsMenu.Buttons.BACK))
	assert_signal_emitted_with_parameters(view, "page_event", [HighScoreTour.EventKind.BACK])


func test_direction_keys_follow_the_player_one_bindings() -> void:
	var view: HighScoreTableView = _view(true)
	var bindings: KeyBindings = KeyBindings.create_default()
	bindings.set_key(0, KeyBindings.Action.LEFT, KeyScancodes.from_godot(KEY_A))
	bindings.set_key(0, KeyBindings.Action.UP, KeyScancodes.from_godot(KEY_W))
	view.input = BindingInput.new(bindings)
	view._unhandled_key_input(_key(KEY_LEFT, true))
	view._unhandled_key_input(_key(KEY_UP, true))
	var unbound: OptionsMenu.Buttons = view.sample_buttons()
	assert_eq(unbound.held, 0, "the old Up key is no longer bound")
	assert_eq(unbound.pressed, 0, "the old Left key is no longer bound")
	view._unhandled_key_input(_key(KEY_A, true))
	view._unhandled_key_input(_key(KEY_W, true))
	view._unhandled_key_input(_key(KEY_KP_ENTER, true))
	var bound: OptionsMenu.Buttons = view.sample_buttons()
	assert_eq(bound.held, OptionsMenu.Buttons.UP)
	assert_eq(bound.pressed, OptionsMenu.Buttons.LEFT | OptionsMenu.Buttons.FIRE, "fire stays on the fixed keys")
	view._unhandled_key_input(_key(KEY_W, false))
	view._unhandled_key_input(_key(KEY_ESCAPE, true))
	var released: OptionsMenu.Buttons = view.sample_buttons()
	assert_eq(released.held, 0)
	assert_eq(released.pressed, OptionsMenu.Buttons.BACK)


func test_the_stack_and_the_table_are_lit_one_world_at_a_time() -> void:
	var stack: LevelStack = StackLayoutTest.retail_stack()
	var progress: LevelProgress = LevelProgress.create(stack)
	var none: Array[HighScoreRow] = []
	var board: HighScoreBoard = HighScoreBoard.create(none, none)
	var tour: HighScoreTour = HighScoreTour.create(StackLayout.create(stack), progress, board.main, true, false,
		false, board.new_levels)
	var models := OptionsModels.new()
	models.frog = TerrainFrogAssets.new()
	var view: HighScoreTableView = HighScoreTableView.create(FrontEndAssets.new(), MenuWater.create(), tour, stack, progress, board, models)
	add_child_autofree(view)
	assert_not_null(view.stack_view.scene_lighting)
	assert_eq(view.stack_view.scene_lighting.environment.background_mode, Environment.BG_CANVAS)
	assert_eq(view.find_children("*", "WorldEnvironment", true, false).size(), 1)
	_idle(view, 1)
	view.tick(OptionsMenu.Buttons.new(0, OptionsMenu.Buttons.LEFT))
	assert_not_null(view.table)
	assert_not_null(view.table.scene_lighting)
	assert_eq(view.table.scene_lighting.light_nodes().size(), 1)
	assert_null(view.water.world_environment, "the water gives up its environment")
	var active: int = 0
	for node: Node in view.find_children("*", "WorldEnvironment", true, false):
		if (node as WorldEnvironment).environment != null:
			active += 1
	assert_eq(active, 1, "one environment applies in the table's world")

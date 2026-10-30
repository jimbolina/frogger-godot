extends GutTest
## The options page tick machine against OptionsUpdate and OptionsUpdateFrog (tempopt.c:4551-5067).


func _idle() -> OptionsMenu.Buttons:
	return OptionsMenu.Buttons.new()


func _held(mask: int) -> OptionsMenu.Buttons:
	return OptionsMenu.Buttons.new(mask, 0)


func _pressed(mask: int) -> OptionsMenu.Buttons:
	return OptionsMenu.Buttons.new(0, mask)


func _run(menu: OptionsMenu, ticks: int, buttons: OptionsMenu.Buttons = null) -> PackedInt32Array:
	var events := PackedInt32Array()
	for _tick: int in ticks:
		events.append_array(menu.step(buttons if buttons != null else _idle(), 0))
	return events


func _settled(start_row: int = OptionsMenu.Row.EXIT, show_scores: bool = false) -> OptionsMenu:
	var menu: OptionsMenu = OptionsMenu.create(3, 5, start_row, show_scores)
	_run(menu, OptionsMenu.FLY_ON_TIME)
	return menu


func test_starts_flying_on_with_retail_defaults() -> void:
	var menu: OptionsMenu = OptionsMenu.create()
	assert_eq(menu.music_volume, 3)
	assert_eq(menu.effects_volume, 5)
	assert_eq(menu.row_kind, OptionsMenu.Row.EXIT)
	assert_eq(menu.fly_on, OptionsMenu.FLY_ON_TIME)
	assert_eq(menu.camera_timer, OptionsMenu.FLY_ON_TIME)
	assert_eq(menu.camera, OptionsMenu.Camera.OPTIONS)
	assert_false(menu.scores_available)
	assert_eq(menu.rows(), PackedInt32Array([OptionsMenu.Row.EXIT, OptionsMenu.Row.CONTROLS,
		OptionsMenu.Row.MUSIC, OptionsMenu.Row.EFFECTS]))


func test_hidden_scores_row_falls_back_to_the_first_row() -> void:
	assert_eq(OptionsMenu.create(3, 5, OptionsMenu.Row.VIEW_SCORES).row_kind, OptionsMenu.Row.EXIT)
	assert_eq(OptionsMenu.create(3, 5, OptionsMenu.Row.VIEW_SCORES, true).row_kind, OptionsMenu.Row.VIEW_SCORES)
	assert_eq(OptionsMenu.create(12, -4).music_volume, 8, "volumes are clamped to the stages")
	assert_eq(OptionsMenu.create(12, -4).effects_volume, 0)


func test_fire_and_back_wait_for_fly_on() -> void:
	var menu: OptionsMenu = OptionsMenu.create()
	assert_eq(_run(menu, OptionsMenu.FLY_ON_TIME - 1, _pressed(OptionsMenu.Buttons.FIRE | OptionsMenu.Buttons.BACK)), PackedInt32Array())
	assert_eq(menu.fly_on, 1)
	var events: PackedInt32Array = menu.step(_pressed(OptionsMenu.Buttons.BACK), 0)
	assert_eq(events, PackedInt32Array([OptionsMenu.EventKind.CROAK, OptionsMenu.EventKind.BACK]), "the counter reaches 0 before the read")
	assert_eq(menu.request, OptionsMenu.Request.MAIN_MENU)
	assert_eq(menu.camera, OptionsMenu.Camera.MAIN)
	assert_eq(menu.camera_timer, OptionsMenu.CAMERA_MOVE_TIME)


func test_hop_takes_twelve_ticks_and_held_down_repeats_every_thirteen() -> void:
	var menu: OptionsMenu = _settled()
	var hops: PackedInt32Array = PackedInt32Array()
	for tick: int in 27:
		var events: PackedInt32Array = menu.step(_held(OptionsMenu.Buttons.DOWN), 0)
		if events.has(OptionsMenu.EventKind.HOP):
			hops.append(tick)
		if events.has(OptionsMenu.EventKind.SPLASH):
			hops.append(-tick)
	assert_eq(hops, PackedInt32Array([0, -12, 13, -25, 26]))
	assert_eq(menu.row_kind, OptionsMenu.Row.EFFECTS)
	assert_true(menu.jumping)


func test_hop_stops_at_the_ends() -> void:
	var menu: OptionsMenu = _settled()
	assert_eq(menu.step(_held(OptionsMenu.Buttons.UP), 0), PackedInt32Array(), "no hop above the top lily")
	menu = _settled(OptionsMenu.Row.EFFECTS)
	assert_eq(menu.step(_held(OptionsMenu.Buttons.DOWN), 0), PackedInt32Array(), "no hop below the bottom lily")


func test_up_wins_over_down() -> void:
	var menu: OptionsMenu = _settled(OptionsMenu.Row.CONTROLS)
	menu.step(_held(OptionsMenu.Buttons.UP | OptionsMenu.Buttons.DOWN), 0)
	assert_eq(menu.row_kind, OptionsMenu.Row.EXIT)


func test_volume_steps_on_edges_and_clamps_without_wrap() -> void:
	var menu: OptionsMenu = _settled(OptionsMenu.Row.MUSIC)
	for _step: int in 7:
		menu.step(_pressed(OptionsMenu.Buttons.RIGHT), 0)
	assert_eq(menu.music_volume, 8)
	assert_eq(menu.step(_pressed(OptionsMenu.Buttons.RIGHT), 0), PackedInt32Array(), "no step past 8")
	assert_eq(menu.step(_pressed(OptionsMenu.Buttons.LEFT | OptionsMenu.Buttons.RIGHT), 0), PackedInt32Array(), "Right is read first")
	for _step: int in 10:
		menu.step(_pressed(OptionsMenu.Buttons.LEFT), 0)
	assert_eq(menu.music_volume, 0)
	assert_eq(menu.effects_volume, 5, "only the selected row changes")
	assert_eq(menu.step(_held(OptionsMenu.Buttons.RIGHT), 0), PackedInt32Array(), "held Right is not an edge")


func test_glow_follows_the_frame_on_the_selected_volume_row() -> void:
	var menu: OptionsMenu = _settled(OptionsMenu.Row.EFFECTS)
	menu.step(_idle(), 13)
	assert_eq(menu.effects_glow, (13 & 7) << 5)
	assert_eq(menu.music_glow, OptionsMenu.GLOW_IDLE)
	assert_eq(menu.glow(OptionsMenu.Row.EFFECTS), 160)
	assert_eq(menu.glow(OptionsMenu.Row.EXIT), OptionsMenu.GLOW_IDLE)
	menu.step(_held(OptionsMenu.Buttons.UP), 13)
	assert_eq(menu.effects_glow, OptionsMenu.GLOW_IDLE, "no glow while hopping away")


func test_effects_test_sound_starts_on_landing_and_stops_on_leaving() -> void:
	var menu: OptionsMenu = _settled(OptionsMenu.Row.MUSIC)
	menu.step(_held(OptionsMenu.Buttons.DOWN), 0)
	var events: PackedInt32Array = _run(menu, OptionsMenu.FROG_JUMP_TIME)
	assert_eq(events, PackedInt32Array([OptionsMenu.EventKind.SPLASH, OptionsMenu.EventKind.VOLUME_TEST_SOUND]))
	assert_true(menu.test_sound)
	assert_eq(menu.step(_held(OptionsMenu.Buttons.UP), 0), PackedInt32Array([OptionsMenu.EventKind.HOP, OptionsMenu.EventKind.STOP_TEST_SOUND]))
	assert_false(menu.test_sound)


func test_back_stops_the_test_sound() -> void:
	var menu: OptionsMenu = _settled(OptionsMenu.Row.MUSIC)
	menu.step(_held(OptionsMenu.Buttons.DOWN), 0)
	_run(menu, OptionsMenu.FROG_JUMP_TIME)
	assert_eq(menu.step(_pressed(OptionsMenu.Buttons.BACK), 0), PackedInt32Array([OptionsMenu.EventKind.STOP_TEST_SOUND, OptionsMenu.EventKind.CROAK, OptionsMenu.EventKind.BACK]))


func test_fire_on_each_row() -> void:
	var menu: OptionsMenu = _settled()
	assert_eq(menu.step(_pressed(OptionsMenu.Buttons.FIRE), 0), PackedInt32Array([OptionsMenu.EventKind.CROAK, OptionsMenu.EventKind.BACK]))
	assert_eq(menu.request, OptionsMenu.Request.MAIN_MENU)
	menu = _settled(OptionsMenu.Row.CONTROLS)
	assert_eq(menu.step(_pressed(OptionsMenu.Buttons.FIRE), 0), PackedInt32Array([OptionsMenu.EventKind.CROAK, OptionsMenu.EventKind.CONTROLS]))
	assert_eq(menu.camera, OptionsMenu.Camera.CONTROLS)
	menu = _settled(OptionsMenu.Row.MUSIC)
	assert_eq(menu.step(_pressed(OptionsMenu.Buttons.FIRE), 0), PackedInt32Array([OptionsMenu.EventKind.CROAK]), "a volume row only croaks")
	assert_eq(menu.request, OptionsMenu.Request.NONE)
	menu = _settled(OptionsMenu.Row.VIEW_SCORES, true)
	assert_eq(menu.step(_pressed(OptionsMenu.Buttons.FIRE), 0), PackedInt32Array([OptionsMenu.EventKind.CROAK, OptionsMenu.EventKind.VIEW_SCORES, OptionsMenu.EventKind.LEAVE]))
	assert_true(menu.finished, "the high-score view is requested without a fly-off")


func test_fly_off_leaves_on_its_tenth_tick_and_still_lets_the_frog_hop() -> void:
	var menu: OptionsMenu = _settled(OptionsMenu.Row.CONTROLS)
	menu.step(_pressed(OptionsMenu.Buttons.FIRE), 0)
	assert_eq(_run(menu, 3, _pressed(OptionsMenu.Buttons.FIRE | OptionsMenu.Buttons.BACK)), PackedInt32Array(), "no second choice while leaving")
	assert_eq(menu.step(_held(OptionsMenu.Buttons.DOWN), 0), PackedInt32Array([OptionsMenu.EventKind.HOP]))
	assert_eq(_run(menu, OptionsMenu.FLY_OFF_TIME - 5), PackedInt32Array())
	assert_false(menu.finished)
	assert_eq(menu.step(_idle(), 0), PackedInt32Array([OptionsMenu.EventKind.LEAVE]))
	assert_true(menu.finished)
	assert_eq(menu.request, OptionsMenu.Request.CONTROLS)
	assert_eq(menu.step(_held(OptionsMenu.Buttons.UP), 0), PackedInt32Array(), "a finished page ignores steps")


func test_static_tables() -> void:
	assert_eq(OptionsMenu.volume_level(3), 47)
	assert_eq(OptionsMenu.volume_level(8), 127)
	assert_eq(OptionsMenu.log_cels(0), PackedInt32Array([10, 10, 10, 10, 10, 10, 10, 10]))
	assert_eq(OptionsMenu.log_cels(3), PackedInt32Array([11, 11, 12, 10, 10, 10, 10, 10]))
	assert_eq(OptionsMenu.jump_lift(6), -288)
	assert_eq(OptionsMenu.lily_z(3), -0x340)
	assert_eq(OptionsMenu.row_name(OptionsMenu.Row.EFFECTS), "effects")
	assert_eq(OptionsMenu.row_name(9), "")
	assert_eq(OptionsMenu.create().volume(OptionsMenu.Row.EXIT), -1)

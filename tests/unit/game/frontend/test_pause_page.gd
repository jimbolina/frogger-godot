extends GutTest
## The pause machine against GamePause and the hidden menu (pause.c:163-606).


static func _buttons(names: PackedStringArray = PackedStringArray()) -> PausePage.Buttons:
	var buttons := PausePage.Buttons.new()
	buttons.escape = names.has("escape")
	buttons.up = names.has("up")
	buttons.down = names.has("down")
	buttons.left = names.has("left")
	buttons.right = names.has("right")
	buttons.fire_released = names.has("fire")
	return buttons


static func _press(page: PausePage, names: PackedStringArray) -> Array[PausePage.Event]:
	return page.tick(_buttons(names))


static func _idle(page: PausePage, count: int) -> Array[PausePage.Event]:
	var events: Array[PausePage.Event] = []
	for _tick: int in count:
		events.append_array(page.tick(_buttons()))
	return events


static func _in_menu(sound_volume: int = 5) -> PausePage:
	var page: PausePage = PausePage.create(sound_volume)
	_idle(page, 9)
	return page


static func _typing(page: PausePage, sequence: PackedInt32Array, arcade: bool = true) -> Array[PausePage.Event]:
	var events: Array[PausePage.Event] = []
	for key: int in sequence:
		if page.cheats != null:
			page.cheats.note_key_down()
		var buttons: PausePage.Buttons = _buttons()
		buttons.keys_down = PackedInt32Array([key])
		buttons.arcade = arcade
		events.append_array(page.tick(buttons))
	return events


func test_allowed_needs_every_term() -> void:
	var state := GameplayState.new()
	assert_true(PausePage.allowed(state))
	state.frog.start_timer = 1
	assert_false(PausePage.allowed(state), "start timer running")
	state = GameplayState.new()
	state.frog.flags &= ~FrogFlags.ACTIVE
	assert_false(PausePage.allowed(state), "frog inactive")
	state = GameplayState.new()
	state.completed = true
	assert_false(PausePage.allowed(state), "level completed")
	state = GameplayState.new()
	state.flow.phase = LevelFlowState.Phase.START
	assert_false(PausePage.allowed(state), "level starting")
	state = GameplayState.new()
	state.flow.phase = LevelFlowState.Phase.DEATH
	assert_true(PausePage.allowed(state), "death allows the pause")


func test_create_is_the_press_tick() -> void:
	var page: PausePage = PausePage.create(5)
	assert_eq(page.mode, PausePage.Mode.INIT)
	assert_eq(page.volume, 5)
	assert_eq(page.sound_volume, 5)
	assert_eq(page.fade_level, 0)
	assert_eq(page.frame, 0)
	assert_eq(page.startup_events(), [PausePage.Event.HOP] as Array[PausePage.Event])
	assert_true(page.active())
	assert_true(page.shows_sprites())
	assert_eq(page.glowing_sprite(), PausePage.Sprite.NONE)


func test_init_shows_the_menu_then_fades_down_eight_ticks() -> void:
	var page: PausePage = PausePage.create(5)
	assert_eq(page.tick(_buttons()), [] as Array[PausePage.Event])
	assert_eq(page.mode, PausePage.Mode.FADE_DOWN)
	assert_true(page.shows_sprites())
	assert_false(page.shows_quit())
	assert_eq(page.menu_mode, PausePage.MenuMode.CONTINUE)
	var volumes: Array[int] = [4, 3, 2, 1, 0, 0, 0, 0]
	for step: int in 8:
		assert_eq(page.mode, PausePage.Mode.FADE_DOWN, "step %d" % step)
		assert_eq(page.glowing_sprite(), PausePage.Sprite.NONE, "step %d" % step)
		assert_eq(page.tick(_buttons()), [] as Array[PausePage.Event])
		assert_eq(page.fade_level, (step + 1) * PausePage.FADE_STEP)
		assert_eq(page.volume, volumes[step])
	assert_eq(page.fade_level, PausePage.FADE_END)
	assert_eq(page.mode, PausePage.Mode.MENU)
	assert_eq(page.frame, 9)


func test_fade_down_from_zero_volume_stays_zero() -> void:
	var page: PausePage = PausePage.create(0)
	for _step: int in 9:
		page.tick(_buttons())
		assert_eq(page.volume, 0)
	assert_eq(page.mode, PausePage.Mode.MENU)


func test_escape_in_menu_fades_up_and_resumes() -> void:
	var page: PausePage = _in_menu(5)
	assert_eq(_press(page, ["escape"]), [PausePage.Event.HOP] as Array[PausePage.Event])
	assert_eq(page.mode, PausePage.Mode.KILL_SPRITES)
	assert_false(page.shows_sprites())
	assert_eq(page.tick(_buttons()), [] as Array[PausePage.Event])
	assert_eq(page.mode, PausePage.Mode.FADE_UP)
	var volumes: Array[int] = [1, 2, 3, 4, 5, 5, 5, 5]
	for step: int in 8:
		assert_eq(page.mode, PausePage.Mode.FADE_UP, "step %d" % step)
		assert_eq(page.tick(_buttons()), [] as Array[PausePage.Event])
		assert_eq(page.fade_level, PausePage.FADE_END - (step + 1) * PausePage.FADE_STEP)
		assert_eq(page.volume, volumes[step])
	assert_eq(page.mode, PausePage.Mode.DEINIT)
	assert_true(page.active())
	assert_eq(page.tick(_buttons()), [PausePage.Event.RESUMED] as Array[PausePage.Event])
	assert_eq(page.mode, PausePage.Mode.NO_PAUSE)
	assert_false(page.active())
	var frame: int = page.frame
	assert_eq(_press(page, ["escape", "fire"]), [] as Array[PausePage.Event])
	assert_eq(page.frame, frame)


func test_escape_is_ignored_while_fading() -> void:
	var page: PausePage = PausePage.create(5)
	page.tick(_buttons())
	assert_eq(_press(page, ["escape"]), [] as Array[PausePage.Event])
	assert_eq(page.mode, PausePage.Mode.FADE_DOWN)
	_idle(page, 7)
	assert_eq(page.mode, PausePage.Mode.MENU)
	_press(page, ["escape"])
	page.tick(_buttons())
	assert_eq(_press(page, ["escape", "fire"]), [] as Array[PausePage.Event])
	assert_eq(page.mode, PausePage.Mode.FADE_UP)


func test_menu_moves_clamp_and_hop() -> void:
	var page: PausePage = _in_menu()
	assert_eq(page.glowing_sprite(), PausePage.Sprite.CONTINUE)
	assert_eq(_press(page, ["up"]), [] as Array[PausePage.Event])
	assert_eq(page.selection, 0)
	assert_eq(_press(page, ["down"]), [PausePage.Event.HOP] as Array[PausePage.Event])
	assert_eq(page.selection, 1)
	assert_eq(page.glowing_sprite(), PausePage.Sprite.QUIT)
	assert_eq(_press(page, ["down"]), [] as Array[PausePage.Event])
	assert_eq(_press(page, ["down", "up"]), [PausePage.Event.HOP] as Array[PausePage.Event])
	assert_eq(page.selection, 0)
	assert_eq(_press(page, ["down", "up"]), [PausePage.Event.HOP, PausePage.Event.HOP] as Array[PausePage.Event])
	assert_eq(page.selection, 0)
	_press(page, ["down"])
	assert_eq(_press(page, ["fire"]), [PausePage.Event.CROAK] as Array[PausePage.Event])
	assert_true(page.shows_quit())
	assert_eq(page.quit_selection, PausePage.QUIT_NO)
	assert_eq(page.glowing_sprite(), PausePage.Sprite.NO)
	assert_eq(_press(page, ["left"]), [] as Array[PausePage.Event])
	assert_eq(_press(page, ["right"]), [PausePage.Event.HOP] as Array[PausePage.Event])
	assert_eq(page.quit_selection, PausePage.QUIT_YES)
	assert_eq(page.glowing_sprite(), PausePage.Sprite.YES)
	assert_eq(_press(page, ["right"]), [] as Array[PausePage.Event])
	assert_eq(_press(page, ["up", "down"]), [] as Array[PausePage.Event])
	assert_eq(_press(page, ["left"]), [PausePage.Event.HOP] as Array[PausePage.Event])
	assert_eq(page.quit_selection, PausePage.QUIT_NO)


func test_fire_on_continue_resumes() -> void:
	var page: PausePage = _in_menu()
	assert_eq(_press(page, ["fire"]), [PausePage.Event.CROAK] as Array[PausePage.Event])
	assert_eq(page.mode, PausePage.Mode.KILL_SPRITES)
	assert_eq(_idle(page, 9), [] as Array[PausePage.Event])
	assert_eq(page.mode, PausePage.Mode.DEINIT)
	assert_eq(page.tick(_buttons()), [PausePage.Event.RESUMED] as Array[PausePage.Event])


func test_quit_then_no_resumes() -> void:
	var page: PausePage = _in_menu()
	_press(page, ["down"])
	_press(page, ["fire"])
	assert_eq(_press(page, ["fire"]), [PausePage.Event.CROAK] as Array[PausePage.Event])
	assert_eq(page.mode, PausePage.Mode.KILL_SPRITES)
	assert_false(page.quitting)
	_idle(page, 9)
	assert_eq(page.tick(_buttons()), [PausePage.Event.RESUMED] as Array[PausePage.Event])


func test_quit_then_yes_skips_the_fade_up() -> void:
	var page: PausePage = _in_menu(5)
	_press(page, ["down"])
	_press(page, ["fire"])
	_press(page, ["right"])
	assert_eq(_press(page, ["fire"]), [PausePage.Event.CROAK] as Array[PausePage.Event])
	assert_true(page.quitting)
	assert_eq(page.mode, PausePage.Mode.DEINIT)
	assert_false(page.shows_sprites())
	assert_eq(page.fade_level, PausePage.FADE_END)
	assert_eq(page.volume, 0)
	assert_eq(page.tick(_buttons()), [PausePage.Event.QUIT] as Array[PausePage.Event])
	assert_eq(page.mode, PausePage.Mode.NO_PAUSE)


func test_escape_wins_in_the_quit_menu() -> void:
	var page: PausePage = _in_menu()
	_press(page, ["down"])
	_press(page, ["fire"])
	assert_eq(_press(page, ["escape", "right", "fire"]), [PausePage.Event.HOP] as Array[PausePage.Event])
	assert_eq(page.mode, PausePage.Mode.KILL_SPRITES)
	assert_eq(page.quit_selection, PausePage.QUIT_NO)
	assert_false(page.quitting)


func test_glowing_sprite_only_in_menu() -> void:
	var page: PausePage = PausePage.create(5)
	for _tick: int in 9:
		assert_eq(page.glowing_sprite(), PausePage.Sprite.NONE)
		page.tick(_buttons())
	assert_eq(page.glowing_sprite(), PausePage.Sprite.CONTINUE)
	_press(page, ["fire"])
	assert_eq(page.glowing_sprite(), PausePage.Sprite.NONE)


func test_glow() -> void:
	assert_eq(PausePage.glow(0), 0)
	assert_eq(PausePage.glow(1), 32)
	assert_eq(PausePage.glow(7), 224)
	assert_eq(PausePage.glow(8), 0)
	assert_eq(PausePage.glow(13), 160)


func test_sprite_positions() -> void:
	assert_eq(PausePage.sprite_x(128, PausePage.Sprite.PAUSED), 256)
	assert_eq(PausePage.sprite_x(129, PausePage.Sprite.CONTINUE), 256)
	assert_eq(PausePage.sprite_x(64, PausePage.Sprite.QUIT), 288)
	assert_eq(PausePage.sprite_x(48, PausePage.Sprite.YES), 344)
	assert_eq(PausePage.sprite_x(48, PausePage.Sprite.NO), 248)
	assert_eq(PausePage.sprite_y(PausePage.Sprite.PAUSED), 240)
	assert_eq(PausePage.sprite_y(PausePage.Sprite.CONTINUE), 272)
	assert_eq(PausePage.sprite_y(PausePage.Sprite.QUIT), 288)
	assert_eq(PausePage.sprite_y(PausePage.Sprite.YES), 304)
	assert_eq(PausePage.sprite_y(PausePage.Sprite.NO), 304)
	assert_eq(PausePage.sprite_y(PausePage.Sprite.NONE), 0)


func test_cheats_fire_their_events_in_menu() -> void:
	var page: PausePage = _in_menu()
	page.cheats = PauseCheats.new()
	var croaking: Array[PausePage.Event] = [PausePage.Event.CROAK, PausePage.Event.CHEAT_INFINITE_LIVES]
	assert_eq(_typing(page, PauseCheats.SEQUENCE_INFINITE_LIVES), croaking)
	assert_eq(page.cheats.cursors[PauseCheats.Cheat.ALL_ZONES], 1, "The S of SPLATS primes SHOW")
	croaking = [PausePage.Event.CROAK, PausePage.Event.CHEAT_ALL_ZONES]
	assert_eq(_typing(page, PauseCheats.SEQUENCE_ALL_ZONES.slice(1)), croaking)
	croaking = [PausePage.Event.CROAK, PausePage.Event.CHEAT_ALL_LEVELS]
	assert_eq(_typing(page, PauseCheats.SEQUENCE_ALL_LEVELS), croaking)
	var silent: Array[PausePage.Event] = [PausePage.Event.CHEAT_TIMEOUT_DEATHS]
	assert_eq(_typing(page, PauseCheats.SEQUENCE_TIMEOUT_DEATHS), silent)
	assert_eq(page.mode, PausePage.Mode.MENU)


func test_cheat_events_come_before_the_menu_events() -> void:
	var page: PausePage = _in_menu()
	page.cheats = PauseCheats.new()
	var sequence: PackedInt32Array = PauseCheats.SEQUENCE_INFINITE_LIVES
	_typing(page, sequence.slice(0, sequence.size() - 1))
	page.cheats.note_key_down()
	var buttons: PausePage.Buttons = _buttons(["down"])
	buttons.keys_down = PackedInt32Array([sequence[sequence.size() - 1]])
	var expected: Array[PausePage.Event] = [PausePage.Event.CROAK, PausePage.Event.CHEAT_INFINITE_LIVES,
		PausePage.Event.HOP]
	assert_eq(page.tick(buttons), expected)
	assert_eq(page.selection, PausePage.QUIT_SELECTED)


func test_cheats_are_checked_in_the_quit_menu_too() -> void:
	var page: PausePage = _in_menu()
	page.cheats = PauseCheats.new()
	_press(page, ["down"])
	_press(page, ["fire"])
	assert_true(page.shows_quit())
	var expected: Array[PausePage.Event] = [PausePage.Event.CROAK, PausePage.Event.CHEAT_INFINITE_LIVES]
	assert_eq(_typing(page, PauseCheats.SEQUENCE_INFINITE_LIVES), expected)


func test_escape_skips_the_cheat_check() -> void:
	var page: PausePage = _in_menu()
	page.cheats = PauseCheats.new()
	page.cheats.note_key_down()
	var buttons: PausePage.Buttons = _buttons(["escape"])
	buttons.keys_down = PackedInt32Array([0x31])
	assert_eq(page.tick(buttons), [PausePage.Event.HOP] as Array[PausePage.Event])
	assert_true(page.cheats.gate, "The gate waits for the next dispatcher run")
	assert_eq(page.cheats.cursors, PackedInt32Array([0, 0, 0, 0]))


func test_no_cheat_check_outside_menu() -> void:
	var page: PausePage = PausePage.create(5)
	page.cheats = PauseCheats.new()
	assert_eq(_typing(page, PackedInt32Array([0x31, 0x18, 0x39])), [] as Array[PausePage.Event])
	assert_eq(page.mode, PausePage.Mode.FADE_DOWN)
	assert_true(page.cheats.gate)
	assert_eq(page.cheats.cursors, PackedInt32Array([0, 0, 0, 0]))
	_idle(page, 6)
	assert_eq(page.mode, PausePage.Mode.MENU)
	var buttons: PausePage.Buttons = _buttons()
	buttons.keys_down = PackedInt32Array([0x31])
	assert_eq(page.tick(buttons), [] as Array[PausePage.Event])
	assert_eq(page.cheats.cursors, PackedInt32Array([1, 0, 0, 1]), "The stale gate reaches the first menu tick")
	assert_false(page.cheats.gate)


func test_stale_gate_with_nothing_down_resets_on_the_first_menu_tick() -> void:
	var page: PausePage = _in_menu()
	page.cheats = PauseCheats.new()
	_typing(page, PackedInt32Array([0x31, 0x18]))
	assert_eq(page.cheats.cursors, PackedInt32Array([2, 0, 0, 2]))
	page.cheats.note_key_down()
	assert_eq(page.tick(_buttons()), [] as Array[PausePage.Event])
	assert_eq(page.cheats.cursors, PackedInt32Array([0, 0, 0, 0]))


func test_no_cheat_check_outside_arcade() -> void:
	var page: PausePage = _in_menu()
	page.cheats = PauseCheats.new()
	assert_eq(_typing(page, PauseCheats.SEQUENCE_INFINITE_LIVES, false), [] as Array[PausePage.Event])
	assert_true(page.cheats.gate)
	assert_eq(page.cheats.cursors, PackedInt32Array([0, 0, 0, 0]))


func test_no_cheat_check_without_a_dispatcher() -> void:
	var page: PausePage = _in_menu()
	assert_null(page.cheats)
	assert_eq(_typing(page, PauseCheats.SEQUENCE_INFINITE_LIVES), [] as Array[PausePage.Event])
	assert_eq(page.mode, PausePage.Mode.MENU)


func test_cursors_persist_across_pauses() -> void:
	var cheats := PauseCheats.new()
	var page: PausePage = _in_menu()
	page.cheats = cheats
	var sequence: PackedInt32Array = PauseCheats.SEQUENCE_ALL_ZONES
	_typing(page, sequence.slice(0, 10))
	_press(page, ["escape"])
	_idle(page, 10)
	assert_false(page.active())
	assert_eq(cheats.cursors[PauseCheats.Cheat.ALL_ZONES], 10)
	page = _in_menu()
	page.cheats = cheats
	var expected: Array[PausePage.Event] = [PausePage.Event.CROAK, PausePage.Event.CHEAT_ALL_ZONES]
	assert_eq(_typing(page, sequence.slice(10)), expected)

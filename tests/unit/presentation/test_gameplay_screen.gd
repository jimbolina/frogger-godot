extends GutTest
## Dedicated play preserves host transactions, pause boundaries and fresh sessions.

var _screen: GameplayScreen

func before_each() -> void:
	FrontEndSession.cheats = CheatState.new()
	FrontEndSession.pause_cheats = PauseCheats.new()
	_screen = GameplayScreen.new()
	_screen.auto_open = false
	add_child_autofree(_screen)
	_screen.set_process(false)

func test_explicit_commands_match_the_same_detached_run() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("buffer")
	var reference: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	for tick: int in scenario.tick_limit:
		var command: TickCommand = scenario.command_at(tick)
		var expected: TickResult = reference.step(command)
		var actual: TickResult = _screen.step_command(command)
		assert_eq(actual.error, expected.error)
		assert_eq(actual.final_snapshot.frog.position_16, expected.final_snapshot.frog.position_16)
		assert_eq(actual.final_snapshot.tick_index, expected.final_snapshot.tick_index)
		_screen.draw_state(0.2)
		_screen.draw_state(0.8)
		assert_eq(_screen.run.snapshot().frog.position_16, expected.final_snapshot.frog.position_16)

func test_escape_opens_the_pause_page_after_joining_pending_work_and_resumes_from_the_menu() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	assert_true(_screen._host.submit(scenario.command_at(0)))
	_screen._held = TickCommand.NORTH
	_key(KEY_ESCAPE, true)
	assert_not_null(_screen._pause_page)
	assert_true(_screen._pause_page.active())
	assert_false(_screen._host.pending())
	assert_false(_screen.playing)
	assert_eq(_screen._held, 0)
	assert_eq(_screen.run.snapshot().tick_index, 1)
	assert_eq(_screen._status.text, "", "the page draws PAUSED itself")
	_key(KEY_ESCAPE, false)
	for tick: int in 9:
		_screen._process(GameplayHost.PERIOD)
	assert_eq(_screen._pause_page.mode, PausePage.Mode.MENU)
	assert_eq(_screen.run.snapshot().tick_index, 1, "the game holds while paused")
	assert_eq(_screen._pause_view.fade_level(), PausePage.FADE_END)
	_key(KEY_ESCAPE, true)
	_screen._process(GameplayHost.PERIOD)
	assert_eq(_screen._pause_page.mode, PausePage.Mode.KILL_SPRITES)
	assert_false(_screen.playing, "play waits for the fade-up")
	for tick: int in 10:
		_screen._process(GameplayHost.PERIOD)
	assert_null(_screen._pause_page, "DEINIT resumes")
	assert_true(_screen.playing)
	assert_eq(_screen._pause_view.fade_level(), 0)
	assert_eq(_screen.run.snapshot().tick_index, 1)

func test_refused_escape_opens_no_pause_page() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	var start := RunStart.new()
	start.start_timer = 30
	assert_eq(_screen.open_run(scenario.level, start), "")
	assert_gt(_screen._current.frog.start_timer, 0)
	_key(KEY_ESCAPE, true)
	assert_null(_screen._pause_page, "the start timer refuses the pause")
	assert_true(_screen.playing)
	assert_eq(_screen.left_for, "", "Escape does not leave the level")

func test_quit_then_yes_leaves_the_front_end_game_as_a_quit() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(24, 1, 0, 5, 0, 2)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.store = null
	FrontEndSession.board = null
	FrontEndSession.active = true
	_screen.switches_scene = false
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	_screen.level_code = FroggerIds.level_code(24)
	_key(KEY_ESCAPE, true)
	for tick: int in 9:
		_screen._process(GameplayHost.PERIOD)
	_key(KEY_DOWN, true)
	_screen._process(GameplayHost.PERIOD)
	assert_eq(_screen._pause_page.selection, PausePage.QUIT_SELECTED)
	_key(KEY_ENTER, true)
	assert_false(_screen._pause_buttons.fire_released, "fire is the release")
	_key(KEY_ENTER, false)
	_screen._process(GameplayHost.PERIOD)
	assert_eq(_screen._pause_page.menu_mode, PausePage.MenuMode.QUIT)
	_key(KEY_RIGHT, true)
	_screen._process(GameplayHost.PERIOD)
	assert_eq(_screen._pause_page.quit_selection, PausePage.QUIT_YES)
	_key(KEY_ENTER, false)
	_screen._process(GameplayHost.PERIOD)
	assert_eq(_screen._pause_page.mode, PausePage.Mode.DEINIT)
	_screen._process(GameplayHost.PERIOD)
	assert_null(_screen._pause_page)
	assert_true(_screen.playing, "Quit resumes the run under the game-over page")
	var quitting: GameplayState = _screen.run.snapshot()
	assert_eq(quitting.flow.phase, LevelFlowState.Phase.GAME_OVER)
	assert_eq(quitting.frog.flags & FrogFlags.CONTROL_ACTIVE, 0, "Quit removes the frog's control")
	assert_null(_screen._game_over_page, "the page opens on the next tick")
	assert_true(FrontEndSession.active)
	_run_tick()
	var page_opened: GameOverPage = _screen._game_over_page
	assert_not_null(page_opened)
	assert_true(page_opened.quit)
	for tick: int in GameOverPage.DURATION + GameOverPage.PREDELAY:
		_run_tick()
	var quit: bool = FrontEndSession.game_quit
	var page: int = FrontEndSession.start_page
	var still_active: bool = FrontEndSession.active
	FrontEndSession.progress = null
	_reset_front_end_session()
	assert_true(page_opened.finished())
	assert_null(_screen.run, "leaving closes the level")
	assert_eq(_screen.left_for, FrontEndScreen.SCENE)
	assert_true(quit)
	assert_eq(page, FrontEndPage.Page.HIGH_SCORE_INPUT)
	assert_false(still_active)

## One synchronous run tick with no keys held.
func _run_tick() -> void:
	_screen.step_command(_screen._host.sample(_screen._current.tick_index, 0))

func test_paused_keys_reach_only_the_page() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	_key(KEY_ESCAPE, true)
	var before: GameplayRun = _screen.run
	_key(KEY_APOSTROPHE, true)
	_key(KEY_UP, true)
	_key(KEY_R, true)
	assert_eq(_screen._held, 0, "a bound key does not reach the run")
	assert_same(_screen.run, before, "R does not restart while paused")
	assert_true(_screen._pause_buttons.up)
	_key(KEY_SPACE, false)
	assert_false(_screen._pause_buttons.fire_released, "Space is not fire")
	_key(KEY_ENTER, false)
	assert_true(_screen._pause_buttons.fire_released)
	_screen._process(GameplayHost.PERIOD)
	assert_false(_screen._pause_buttons.up, "the tick consumes the latches")
	_screen.close_data()
	assert_null(_screen._pause_page, "detaching closes the page")

func test_failed_tick_preserves_state_and_new_run_clears_failure() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	var command: TickCommand = scenario.command_at(0)
	command.tick_index = 9
	assert_false(_screen.step_command(command).error.is_empty())
	assert_eq(_screen.run.snapshot().tick_index, 0)
	assert_false(_screen.playing)
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	assert_eq(_screen.last_error, "")
	assert_true(_screen.playing)
	assert_eq(_screen.run.snapshot().tick_index, 0)

func test_close_joins_pending_worker_and_detaches_run() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	assert_true(_screen._host.submit(scenario.command_at(0)))
	_screen.close_data()
	assert_null(_screen.run)
	assert_null(_screen._host.run)
	assert_false(_screen._host.pending())
	assert_null(_screen._current)
	assert_null(_screen._hud._state)
	assert_null(_screen._hud.assets)
	assert_false(_screen.playing)

func test_hud_fills_reference_viewport_and_terminal_actions_are_hidden_during_play() -> void:
	assert_gt(_screen._hud.size.x, 0.0)
	assert_gt(_screen._hud.size.y, 0.0)
	assert_false(_screen._actions.visible)
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	_screen.set_paused(true)
	assert_false(_screen._actions.visible)
	assert_eq(_screen._status.text, "")

func test_failed_launch_has_no_stale_run_or_replay_action() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	assert_false(_screen.open_data(null, "ORG1").is_empty())
	assert_null(_screen.run)
	assert_null(_screen._hud._state)
	assert_true(_screen._actions.visible)
	assert_false(_screen._replay.visible)

func _open_pause_menu() -> void:
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	for tick: int in 9:
		_screen._process(GameplayHost.PERIOD)
	assert_eq(_screen._pause_page.mode, PausePage.Mode.MENU)

func _letter(letter: String) -> Key:
	return KEY_SPACE if letter == " " else (KEY_A + letter.unicode_at(0) - 65) as Key

## Types [param phrase] one key per pause tick and returns the events of the last key's tick.
func _type(phrase: String) -> Array[PausePage.Event]:
	var events: Array[PausePage.Event] = []
	for letter: String in phrase:
		_key(_letter(letter), true)
		_key(_letter(letter), false)
		events = _screen.step_pause()
	return events

func _key(code: Key, pressed: bool, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.location = location
	event.pressed = pressed
	_screen._unhandled_key_input(event)

func test_croak_key_croaks_on_its_pressed_edge_like_the_tongue() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	assert_true(_screen.playing)
	_key(KEY_SHIFT, true, KEY_LOCATION_RIGHT)
	assert_eq(_screen._held, TickCommand.CROAK)
	var first: TickCommand = _screen._host.sample(1, _screen._held)
	assert_eq(first.pressed_mask & TickCommand.CROAK, TickCommand.CROAK)
	var held: TickCommand = _screen._host.sample(2, _screen._held)
	assert_eq(held.pressed_mask & TickCommand.CROAK, 0, "a held croak key presses once")
	_key(KEY_SHIFT, false, KEY_LOCATION_RIGHT)
	assert_eq(_screen._held, 0)

func test_player_one_bindings_drive_play_and_fixed_keys_stay() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	_key(KEY_ENTER, true)
	_key(KEY_CTRL, true, KEY_LOCATION_RIGHT)
	_key(KEY_APOSTROPHE, true)
	_key(KEY_SEMICOLON, true)
	assert_eq(_screen._held, TickCommand.SUPER_HOP | TickCommand.TONGUE | TickCommand.CAMERA_CLOCKWISE | TickCommand.CAMERA_ANTICLOCKWISE)
	_key(KEY_C, true)
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	assert_eq(_screen._held & (TickCommand.CROAK | TickCommand.SUPER_HOP), TickCommand.SUPER_HOP, "C and left Shift are unbound")
	var bindings := KeyBindings.create_default()
	bindings.set_key(0, KeyBindings.Action.CROAK, KeyScancodes.from_godot(KEY_C))
	_screen.input = BindingInput.new(bindings)
	_key(KEY_C, true)
	assert_eq(_screen._held & TickCommand.CROAK, TickCommand.CROAK, "a rebound key takes the action")
	_key(KEY_SPACE, true)
	assert_true(_screen.playing, "Space does not pause")
	assert_null(_screen._pause_page)

func test_front_end_completion_opens_the_next_level_page_and_fire_opens_the_level() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(24, 1, 0, 5, 0, 2), LevelStack.Row.new(25, 1, 0, 5, 1, 2)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.progress.arcade_flags[1] = 0
	FrontEndSession.store = null
	FrontEndSession.level = 24
	FrontEndSession.active = true
	_finish_level(24, LevelFlowState.Phase.COMPLETE)
	var page: LevelCompletePage = _screen._complete_page
	assert_not_null(page)
	assert_eq(page.variant, LevelCompletePage.Kind.NEXT_LEVEL)
	assert_eq(page.next_level, 25)
	assert_false(_screen._actions.visible, "the Godot buttons give way to the page")
	assert_false(_screen._hud.visible, "the HUD viewport hides under the page")
	assert_false(FrontEndSession.progress.is_selectable(25), "the next level opens when the page is left, not at completion")
	var reached: int = _screen.settle_level_complete(FrontEndFlow.Event.NEXT_LEVEL)
	var level: int = FrontEndSession.level
	var selectable: bool = FrontEndSession.progress.is_selectable(25)
	_reset_front_end_session()
	assert_eq(reached, FrontEndPage.Page.GAME)
	assert_eq(level, 25)
	assert_true(selectable)
	assert_eq(FrontEndSession.selected_level, FroggerIds.level_code(25))
	FrontEndSession.selected_level = ""

func test_zone_complete_fire_returns_to_the_stack_on_the_completed_level() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(24, 1, 0, 5, 0, 1), LevelStack.Row.new(25, 2, 1, 5, 0, 1)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.store = null
	FrontEndSession.level = 24
	FrontEndSession.active = true
	_finish_level(24, LevelFlowState.Phase.COMPLETE)
	var page: LevelCompletePage = _screen._complete_page
	assert_eq(page.variant, LevelCompletePage.Kind.ZONE_COMPLETE)
	assert_eq(page.next_level, -1)
	var reached: int = _screen.settle_level_complete(FrontEndFlow.Event.ZONE_COMPLETE)
	var level: int = FrontEndSession.level
	var start_page: int = FrontEndSession.start_page
	_reset_front_end_session()
	assert_eq(reached, FrontEndPage.Page.LEVEL_SELECT)
	assert_eq(start_page, FrontEndPage.Page.LEVEL_SELECT)
	assert_eq(level, 24, "the stack keeps the completed level")

func test_direct_launch_shows_the_statistics_and_r_restarts() -> void:
	FrontEndSession.active = false
	_finish_level(24, LevelFlowState.Phase.COMPLETE, 750)
	var page: LevelCompletePage = _screen._complete_page
	assert_not_null(page)
	assert_eq(page.variant, LevelCompletePage.Kind.STATISTICS)
	assert_eq(page.level_score, 750, "a direct launch scores the run")
	assert_eq(page.checkpoint_seconds, PackedInt32Array([1, 2, 3, 4, 5]))
	assert_false(page.shows_prompt())
	assert_false(_screen._hud.visible)
	assert_false(_screen._actions.visible)
	_key(KEY_ENTER, true)
	_key(KEY_ESCAPE, true)
	assert_false(_screen._fire_latched, "the statistics page takes no fire")
	assert_false(_screen._back_latched)
	_key(KEY_R, true)
	assert_null(_screen._complete_page, "R restarts and closes the page")
	assert_true(_screen._hud.visible)

func test_page_keys_latch_until_its_tick_and_escape_leaves_through_the_page() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(24, 1, 0, 5, 0, 2), LevelStack.Row.new(25, 1, 0, 5, 1, 2)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.store = null
	FrontEndSession.active = true
	_finish_level(24, LevelFlowState.Phase.COMPLETE)
	_key(KEY_SPACE, true)
	assert_true(_screen._fire_latched, "Space is fire on the page")
	assert_eq(_screen._complete_page.frame, 0, "keys wait for the page tick")
	assert_eq(_screen.step_level_complete(), -1)
	assert_eq(_screen._complete_page.frame, 1)
	assert_false(_screen._fire_latched, "the tick consumes the latch")
	assert_eq(_screen._complete_page.units, LevelCompletePage.START_UNITS, "fire before the gate changes nothing")
	_key(KEY_ESCAPE, true)
	assert_true(_screen._back_latched)
	var exit_event: int = _screen.step_level_complete()
	_reset_front_end_session()
	assert_eq(exit_event, FrontEndFlow.Event.BACK)
	assert_true(_screen._complete_page.finished())

func test_front_end_completion_records_the_level_score_for_the_high_scores() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(24, 1, 0, 5, 0, 2), LevelStack.Row.new(25, 1, 0, 5, 1, 2)]
	var none: Array[HighScoreRow] = []
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.store = null
	FrontEndSession.board = HighScoreBoard.create(none, none)
	FrontEndSession.score = 300
	FrontEndSession.active = true
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	_screen.level_code = FroggerIds.level_code(24)
	var finished: GameplayState = _screen.run.snapshot()
	finished.completed = true
	finished.flow.phase = LevelFlowState.Phase.COMPLETE
	finished.flow.score = 1300
	finished.flow.checkpoint_times = PackedInt32Array([30, 60, 90, 120, 150])
	var result := TickResult.new()
	result.final_snapshot = finished
	_screen._accept(result)
	FrontEndSession.active = false
	var board: HighScoreBoard = FrontEndSession.board
	FrontEndSession.board = null
	FrontEndSession.score = 0
	assert_eq(board.recorded[24], 1)
	assert_eq(board.run_scores[24], 1000, "the score made in the level")
	assert_eq(board.run_times_of(24), PackedInt32Array([1, 2, 3, 4, 5]))
	var page: LevelCompletePage = _screen._complete_page
	assert_eq(page.level_score, 1000, "TOTAL SCORE is the level's recorded score")
	assert_eq(page.checkpoint_seconds, PackedInt32Array([1, 2, 3, 4, 5]))
	assert_eq(page.total_seconds, 15)

func _start_front_end_game() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(24, 1, 0, 5, 0, 2)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.store = null
	FrontEndSession.board = null
	FrontEndSession.active = true
	_screen.switches_scene = false

## Accepts a committed game-over state one tick on from the current one, as the run keeps
## ticking under the page.
func _game_over_tick(score: int) -> void:
	var state: GameplayState = _screen.run.snapshot()
	state.tick_index = _screen._current.tick_index + 1
	state.completed = false
	state.flow.phase = LevelFlowState.Phase.GAME_OVER
	state.flow.score = score
	var result := TickResult.new()
	result.final_snapshot = state
	_screen._accept(result)

func test_front_end_game_over_opens_the_page_over_the_running_level() -> void:
	_start_front_end_game()
	_finish_level(24, LevelFlowState.Phase.GAME_OVER, 2500)
	var page: GameOverPage = _screen._game_over_page
	var still_active: bool = FrontEndSession.active
	var music: MusicPlayer = _screen.music_player()
	assert_not_null(page)
	assert_false(page.quit)
	assert_eq(page.frame, 0, "the kill tick opens the page; its updates follow")
	assert_true(still_active, "the game lasts until the page ends")
	assert_true(_screen._session_finished, "the progress is settled when the page opens")
	assert_false(_screen._hud.visible, "the HUD viewport hides")
	assert_true(_screen.playing, "the run keeps ticking under the page")
	assert_false(_screen._actions.visible)
	assert_eq(_screen._status.text, "")
	assert_true(_screen._game_over_view.visible)
	assert_false(_screen._game_over_view.shows_sprite(), "the sprite waits for the predelay")
	if music != null:
		assert_eq(music.track, GameOverPage.JINGLE_TRACK)
		assert_false(music.looping, "the jingle plays once")
	_key(KEY_ESCAPE, true)
	assert_null(_screen._pause_page, "Escape does nothing on the page")
	assert_false(_screen.open_pause())
	_key(KEY_UP, true)
	assert_eq(_screen._held, 0, "play keys do not reach the run")
	_game_over_tick(2500)
	assert_eq(page.frame, 1)
	assert_eq(_screen.view_rect(), Rect2i(0, 0, 640, 480), "the predelay keeps the full viewport")
	_reset_front_end_session()
	FrontEndSession.progress = null

func test_front_end_game_over_shrinks_then_reaches_name_entry_on_the_timeout() -> void:
	_start_front_end_game()
	_finish_level(24, LevelFlowState.Phase.GAME_OVER, 4321)
	var page: GameOverPage = _screen._game_over_page
	for tick: int in GameOverPage.PREDELAY / 2 + 1:
		_game_over_tick(4321)
	assert_eq(_screen.view_rect(), page.view_rect())
	assert_eq(_screen.view_rect().size.x, 640 - page.width_step, "the first update after the predelay shrinks")
	assert_true(_screen._game_over_view.shows_sprite())
	var full: float = GameplayProjection.vertical_fov_degrees(Vector2i(_screen.get_viewport().get_visible_rect().size))
	var expected: float = rad_to_deg(2.0 * atan(tan(deg_to_rad(full) * 0.5) * 640.0 / _screen.view_rect().size.x))
	assert_almost_eq(_screen._camera.fov, expected, 0.0001, "the projection scales by width / 640")
	while _screen.run != null and page.frame < GameOverPage.DURATION + GameOverPage.PREDELAY - 1:
		_game_over_tick(4321)
	assert_not_null(_screen._game_over_page, "the page holds until its count-down ends")
	var opened: bool = FrontEndSession.active
	_game_over_tick(4321)
	var start_page: int = FrontEndSession.start_page
	var quit: bool = FrontEndSession.game_quit
	var ending: int = FrontEndSession.final_score
	var still_active: bool = FrontEndSession.active
	_reset_front_end_session()
	FrontEndSession.progress = null
	assert_true(opened)
	assert_eq(page.frame, GameOverPage.DURATION + GameOverPage.PREDELAY)
	assert_true(page.finished())
	assert_eq(start_page, FrontEndPage.Page.HIGH_SCORE_INPUT)
	assert_false(quit, "a game over is not a quit")
	assert_eq(ending, 4321)
	assert_false(still_active)
	assert_eq(_screen.left_for, FrontEndScreen.SCENE)
	assert_null(_screen.run, "leaving closes the level")

func test_front_end_game_over_fire_leaves_only_once_the_gate_opens() -> void:
	_start_front_end_game()
	_finish_level(24, LevelFlowState.Phase.GAME_OVER, 10)
	var page: GameOverPage = _screen._game_over_page
	while page.frame < 74:
		_game_over_tick(10)
	_key(KEY_SPACE, true)
	assert_true(_screen._fire_latched, "Space is fire on the page")
	_game_over_tick(10)
	assert_false(_screen._fire_latched, "the tick consumes the latch")
	assert_false(page.finished(), "fire at update 75 is ignored")
	_key(KEY_ENTER, true)
	_game_over_tick(10)
	var start_page: int = FrontEndSession.start_page
	var still_active: bool = FrontEndSession.active
	_reset_front_end_session()
	FrontEndSession.progress = null
	assert_eq(page.frame, 76)
	assert_true(page.finished(), "fire at update 76 leaves")
	assert_eq(page.sounds, PackedInt32Array([GameOverPage.SOUND_CROAK]), "the croak is requested, but muted")
	assert_eq(start_page, FrontEndPage.Page.HIGH_SCORE_INPUT)
	assert_false(still_active)

func test_direct_launch_game_over_ends_on_black_with_replay_and_return() -> void:
	FrontEndSession.active = false
	_finish_level(24, LevelFlowState.Phase.GAME_OVER, 50)
	var page: GameOverPage = _screen._game_over_page
	assert_not_null(page)
	assert_false(_screen._actions.visible, "the buttons wait for the page")
	for tick: int in GameOverPage.DURATION + GameOverPage.PREDELAY:
		_game_over_tick(50)
	assert_true(page.finished())
	assert_null(_screen._game_over_page)
	assert_false(_screen.playing)
	assert_true(_screen._actions.visible)
	assert_true(_screen._replay.visible)
	assert_true(_screen._back.visible)
	assert_eq(_screen._status.text, "", "the page is the label")
	assert_true(_screen._game_over_view.visible, "the screen stays black")
	assert_false(_screen._game_over_view.shows_sprite())
	assert_eq(_screen._game_over_view.view_rect().size.x, 0)
	assert_eq(_screen._camera.cull_mask, 0, "no world is drawn at zero width")
	var before: GameplayRun = _screen.run
	_game_over_tick(50)
	assert_null(_screen._game_over_page, "the ended page does not reopen")
	_key(KEY_R, true)
	assert_ne(_screen.run, before, "R restarts")
	assert_false(_screen._game_over_view.visible)
	assert_true(_screen._hud.visible)
	assert_eq(_screen.view_rect(), Rect2i())
	assert_ne(_screen._camera.cull_mask, 0)
	assert_true(_screen.playing)

func test_r_restarts_a_direct_launch_during_the_page() -> void:
	FrontEndSession.active = false
	_finish_level(24, LevelFlowState.Phase.GAME_OVER)
	for tick: int in 40:
		_game_over_tick(0)
	assert_not_null(_screen._game_over_page)
	_key(KEY_R, true)
	assert_null(_screen._game_over_page)
	assert_eq(_screen.view_rect(), Rect2i())
	assert_true(_screen._hud.visible)
	assert_true(_screen.playing)

func _finish_level(level: int, phase: LevelFlowState.Phase, score: int = 0) -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	_screen.level_code = FroggerIds.level_code(level)
	var finished: GameplayState = _screen.run.snapshot()
	finished.completed = phase == LevelFlowState.Phase.COMPLETE
	finished.flow.phase = phase
	finished.flow.score = score
	finished.flow.checkpoint_times = PackedInt32Array([30, 60, 90, 120, 150])
	var result := TickResult.new()
	result.final_snapshot = finished
	_screen._accept(result)

func _reset_front_end_session() -> void:
	FrontEndSession.active = false
	FrontEndSession.board = null
	FrontEndSession.score = 0
	FrontEndSession.level = -1
	FrontEndSession.start_page = FrontEndPage.Page.MAIN_MENU
	FrontEndSession.final_score = 0
	FrontEndSession.game_quit = false
	FrontEndSession.cheats = CheatState.new()
	FrontEndSession.pause_cheats = PauseCheats.new()

func test_front_end_jungle1_completion_is_recorded_like_any_level() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(LevelProgress.LEVEL_JUNGLE1, 7, 0, 4, 0, 1)]
	var none: Array[HighScoreRow] = []
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.store = null
	FrontEndSession.board = HighScoreBoard.create(none, none)
	FrontEndSession.score = 200
	FrontEndSession.active = true
	_finish_level(LevelProgress.LEVEL_JUNGLE1, LevelFlowState.Phase.COMPLETE, 900)
	var board: HighScoreBoard = FrontEndSession.board
	_reset_front_end_session()
	assert_eq(board.run_scores[LevelProgress.LEVEL_JUNGLE1], 700)
	assert_eq(board.run_times_of(LevelProgress.LEVEL_JUNGLE1), PackedInt32Array([1, 2, 3, 4, 5]),
		"the checkpoint times are kept, not the statue's zeros")
	assert_eq(_screen._complete_page.variant, LevelCompletePage.Kind.ZONE_COMPLETE, "the page stands in for the P16 ending")

func test_jungle1_fire_follows_the_ending_to_name_entry() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(LevelProgress.LEVEL_JUNGLE1, 7, 0, 4, 0, 1)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.store = null
	FrontEndSession.board = null
	FrontEndSession.active = true
	_finish_level(LevelProgress.LEVEL_JUNGLE1, LevelFlowState.Phase.COMPLETE, 900)
	var reached: int = _screen.settle_level_complete(FrontEndFlow.Event.ZONE_COMPLETE)
	var start_page: int = FrontEndSession.start_page
	var ending: int = FrontEndSession.final_score
	var still_active: bool = FrontEndSession.active
	_reset_front_end_session()
	assert_eq(reached, FrontEndPage.Page.HIGH_SCORE_INPUT)
	assert_eq(start_page, FrontEndPage.Page.HIGH_SCORE_INPUT)
	assert_eq(ending, 900)
	assert_false(still_active)

func test_leaving_after_game_over_still_reaches_name_entry() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(24, 1, 0, 5, 0, 2)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.store = null
	FrontEndSession.board = null
	FrontEndSession.active = true
	_finish_level(24, LevelFlowState.Phase.GAME_OVER, 4321)
	_screen.leave_front_end_level()
	var page: int = FrontEndSession.start_page
	var quit: bool = FrontEndSession.game_quit
	var ending: int = FrontEndSession.final_score
	var still_active: bool = FrontEndSession.active
	_reset_front_end_session()
	assert_eq(page, FrontEndPage.Page.HIGH_SCORE_INPUT)
	assert_false(quit, "a game over is not a quit")
	assert_eq(ending, 4321)
	assert_false(still_active)

func test_leaving_an_unfinished_level_is_a_quit() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(24, 1, 0, 5, 0, 2)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.store = null
	FrontEndSession.board = null
	FrontEndSession.active = true
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	_screen.leave_front_end_level()
	var page: int = FrontEndSession.start_page
	var quit: bool = FrontEndSession.game_quit
	_reset_front_end_session()
	assert_eq(page, FrontEndPage.Page.HIGH_SCORE_INPUT)
	assert_true(quit)

func test_leaving_a_completed_level_returns_to_the_level_select_focused_on_the_next() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(24, 1, 0, 5, 0, 2), LevelStack.Row.new(25, 1, 0, 5, 1, 2)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.progress.arcade_flags[1] = 0
	FrontEndSession.store = null
	FrontEndSession.board = null
	FrontEndSession.level = 24
	FrontEndSession.active = true
	_finish_level(24, LevelFlowState.Phase.COMPLETE)
	_screen.leave_front_end_level()
	var page: int = FrontEndSession.start_page
	var still_active: bool = FrontEndSession.active
	var level: int = FrontEndSession.level
	var flags: int = FrontEndSession.progress.flags_of(25)
	_reset_front_end_session()
	assert_eq(page, FrontEndPage.Page.LEVEL_SELECT)
	assert_true(still_active)
	assert_eq(level, 25, "triangle focuses the stack on the next level")
	assert_eq(flags, LevelProgress.SELECTABLE | LevelProgress.ZONE_ACCESSIBLE, "a closed next level opens")

func test_escape_keeps_an_already_completed_next_level_completed() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(24, 1, 0, 5, 0, 2), LevelStack.Row.new(25, 1, 0, 5, 1, 2)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.progress.arcade_flags[1] = LevelProgress.COMPLETED | LevelProgress.SELECTABLE | LevelProgress.ZONE_ACCESSIBLE
	FrontEndSession.store = null
	FrontEndSession.board = null
	FrontEndSession.active = true
	_finish_level(24, LevelFlowState.Phase.COMPLETE)
	_screen.settle_level_complete(FrontEndFlow.Event.BACK)
	var flags: int = FrontEndSession.progress.flags_of(25)
	_reset_front_end_session()
	assert_eq(flags, LevelProgress.COMPLETED | LevelProgress.SELECTABLE | LevelProgress.ZONE_ACCESSIBLE)

func test_restart_key_is_ignored_in_a_front_end_game() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	var before: GameplayRun = _screen.run
	FrontEndSession.active = true
	_key(KEY_R, true)
	var during: GameplayRun = _screen.run
	_reset_front_end_session()
	assert_same(during, before, "R does not restart a front-end level")
	_key(KEY_R, true)
	assert_ne(_screen.run, before, "a direct launch still restarts")

func _attract_demo(duration: int, bytes: PackedByteArray) -> SourceDemoFile:
	var demo := SourceDemoFile.new()
	demo.duration = duration
	demo.start_grid_x = 2
	demo.start_grid_z = 1
	demo.input_bytes = bytes
	return demo

func _attract_level() -> LevelDefinition:
	var level: LevelDefinition = TerrainScenario.builtin("normal").level
	level.flow_enabled = true
	level.level_time = 900
	return level

func _open_attract(duration: int, bytes: PackedByteArray) -> void:
	_screen.switches_scene = false
	FrontEndSession.attract = null
	FrontEndSession.attract_level = 24
	FrontEndSession.attract_return = false
	assert_eq(_screen.open_attract_run(_attract_level(), _attract_demo(duration, bytes), AttractTimer.new()), "")

func _reset_attract_session() -> void:
	FrontEndSession.attract = null
	FrontEndSession.attract_level = -1
	FrontEndSession.attract_return = false
	FrontEndSession.attract_intro = false
	FrontEndSession.attract_option = 0
	FrontEndSession.progress = null
	FrontEndSession.level_chosen = false
	_reset_front_end_session()

func _filled(count: int, value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(count)
	bytes.fill(value)
	return bytes

func test_attract_demo_hides_the_hud_and_plays_the_recorded_commands() -> void:
	_open_attract(200, _filled(200, 0x80))
	assert_true(_screen.is_attract())
	assert_false(_screen._hud.visible, "the HUD panels hide in a demo")
	assert_false(_screen._actions.visible)
	assert_eq(_screen.run.snapshot().frog.cell, Vector2i(2, 1), "the run starts at the demo spawn")
	assert_eq(_screen.run.snapshot().frog.lives, DemoSetup.DEMO_LIVES)
	_key(KEY_UP, true)
	_key(KEY_SPACE, true)
	_key(KEY_R, true)
	_key(KEY_ESCAPE, true)
	assert_eq(_screen._held, 0, "live keys never reach the run")
	assert_true(_screen.playing, "Space does not pause a demo")
	assert_eq(_screen.left_for, "", "Escape does not leave a demo")
	assert_null(_screen._pause_page, "Escape does not pause a demo")
	var consumed: int = -1
	for tick: int in 40:
		var result: TickResult = _screen.step_attract()
		assert_eq(result.error, "")
		if result.consumed_demo_byte >= 0:
			consumed = result.consumed_demo_byte
	assert_eq(consumed, 0x80, "the session's recorded byte drives the run")
	assert_eq(_screen.attract_session.elapsed_ticks, 40)
	assert_gt(_screen.attract_session.input_cursor, 0)
	_reset_attract_session()

func test_attract_demo_fades_out_over_its_last_thirty_ticks_and_returns_to_the_menu() -> void:
	_open_attract(70, _filled(100, 0x80))
	assert_eq(_screen.attract_timer.phase, AttractTimer.Phase.PLAYING)
	assert_false(_screen._main_menu.fire_allowed, "fire waits for the fly-on")
	for tick: int in AttractTimer.FLY_TIME:
		_screen.step_attract()
	assert_true(_screen._main_menu.fire_allowed)
	for tick: int in 39 - AttractTimer.FLY_TIME:
		_screen.step_attract()
	assert_eq(_screen.attract_timer.phase, AttractTimer.Phase.PLAYING)
	assert_false(_screen._loading.visible)
	_screen.step_attract()
	assert_eq(_screen.attract_session.duration - _screen.attract_session.elapsed_ticks, AttractTimer.DEMO_END_TICKS)
	assert_eq(_screen.attract_timer.phase, AttractTimer.Phase.FADE_OUT)
	assert_false(_screen._main_menu.fire_allowed, "fire is refused during the fly-off")
	for tick: int in AttractTimer.FADE_UNITS - 1:
		_screen.step_attract()
		assert_true(_screen.playing, "the game keeps running through the fade")
	assert_eq(_screen.attract_timer.phase, AttractTimer.Phase.FADE_OUT)
	assert_true(_screen._fade.visible)
	_screen.step_attract()
	var phase: int = _screen.attract_timer.phase
	var level: int = FrontEndSession.attract_level
	var returning: bool = FrontEndSession.attract_return
	_reset_attract_session()
	assert_eq(phase, AttractTimer.Phase.FINISHED)
	assert_eq(level, -1)
	assert_true(returning, "the finished demo hands back to the main menu")
	assert_eq(_screen.left_for, FrontEndScreen.SCENE)
	assert_null(_screen.run)

func test_finished_attract_demo_advances_the_cycle() -> void:
	var levels := PackedInt32Array([24, AttractCycle.INTRO, 25])
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(24, 1, 0, 5, 0, 2), LevelStack.Row.new(25, 1, 0, 5, 1, 2)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	var twin: AttractCycle = AttractCycle.from_rows(levels, levels)
	var expected: int = twin.finish(FrontEndSession.progress)
	_open_attract(31, _filled(40, 0x80))
	FrontEndSession.attract = AttractCycle.from_rows(levels, levels)
	for tick: int in 31:
		_screen.step_attract()
	var intro: bool = FrontEndSession.attract_intro
	var next: int = FrontEndSession.attract.current_level()
	_reset_attract_session()
	assert_eq(_screen.left_for, FrontEndScreen.SCENE)
	assert_eq(intro, expected == AttractCycle.INTRO)
	assert_eq(next, twin.current_level())

func test_attract_death_restarts_at_the_demo_spawn_without_rewinding_the_recording() -> void:
	var bytes := PackedByteArray([0])
	bytes.append_array(_filled(300, 0x80))
	_open_attract(400, bytes)
	while _screen.attract_session.input_cursor == 0:
		assert_eq(_screen.step_attract().error, "")
	for tick: int in 12:
		assert_eq(_screen.step_attract().error, "")
	assert_ne(_screen.run.snapshot().frog.cell, Vector2i(2, 1), "the recorded hop moved the frog")
	var cursor: int = _screen.attract_session.input_cursor
	_screen.run._state.frog.mode = FrogMode.DYING
	_screen.run._state.frog.death_count = 1
	var result: TickResult = _screen.step_attract()
	var session: DemoPlaybackSession = _screen.attract_session
	var left: String = _screen.left_for
	_reset_attract_session()
	assert_eq(result.error, "")
	assert_false(result.final_snapshot.completed)
	assert_eq(result.final_snapshot.frog.cell, Vector2i(2, 1), "the death restarts at the demo spawn")
	assert_gte(session.input_cursor, cursor, "the recording carries on")
	assert_eq(left, "", "a death never ends the demo")

func test_attract_start_ends_the_demo_and_opens_the_level_select() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(24, 1, 0, 5, 0, 2)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.store = null
	FrontEndSession.board = null
	_open_attract(200, _filled(200, 0x80))
	for tick: int in AttractTimer.FLY_TIME + 1:
		_screen.step_attract()
	assert_true(_screen._main_menu.fire_allowed)
	_screen._on_menu_event(MainMenuView.Kind.START)
	var page: int = FrontEndSession.start_page
	var level: int = FrontEndSession.attract_level
	var returning: bool = FrontEndSession.attract_return
	var active: bool = FrontEndSession.active
	_reset_attract_session()
	assert_eq(page, FrontEndPage.Page.LEVEL_SELECT)
	assert_eq(level, -1)
	assert_false(returning)
	assert_true(active, "Start begins a game")
	assert_eq(_screen.left_for, FrontEndScreen.SCENE)
	assert_null(_screen.run)
	assert_null(_screen.step_attract(), "nothing plays after the demo ends")

func test_attract_options_opens_the_options_page() -> void:
	_open_attract(200, _filled(200, 0x80))
	_screen._on_menu_event(MainMenuView.Kind.OPTIONS)
	var page: int = FrontEndSession.start_page
	var level: int = FrontEndSession.attract_level
	_reset_attract_session()
	assert_eq(page, FrontEndPage.Page.OPTIONS)
	assert_eq(level, -1)
	assert_eq(_screen.left_for, FrontEndScreen.SCENE)

func test_unresolvable_attract_demo_returns_to_the_menu_with_a_diagnostic() -> void:
	_screen.switches_scene = false
	FrontEndSession.attract = null
	FrontEndSession.attract_level = 24
	FrontEndSession.diagnostics = PackedStringArray()
	_screen.open_attract(null)
	assert_engine_error("Demo setup requires valid player data", "the abandoned demo is reported")
	var notes: PackedStringArray = FrontEndSession.diagnostics
	var returning: bool = FrontEndSession.attract_return
	FrontEndSession.diagnostics = PackedStringArray()
	_reset_attract_session()
	assert_eq(_screen.left_for, FrontEndScreen.SCENE)
	assert_true(returning)
	assert_eq(notes.size(), 1)
	assert_false(_screen.is_attract() and _screen.run != null)

func test_typing_no_more_road_splats_in_the_pause_menu_toggles_infinite_lives() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	_open_pause_menu()
	var events: Array[PausePage.Event] = _type("NO MORE ROAD SPLATS")
	assert_true(PausePage.Event.CROAK in events, "the cheat croaks")
	assert_true(PausePage.Event.CHEAT_INFINITE_LIVES in events)
	assert_true(FrontEndSession.cheats.infinite_lives)
	assert_eq(_screen._hud._help_text, "INFINITE LIVES ON")
	assert_false(_screen.run.snapshot().cheats.infinite_lives, "the run sees the cheat at the resume")
	_key(KEY_ESCAPE, true)
	for tick: int in 11:
		_screen._process(GameplayHost.PERIOD)
	assert_null(_screen._pause_page)
	assert_true(_screen.playing)
	assert_true(_screen.run.snapshot().cheats.infinite_lives)
	_open_pause_menu()
	for tick: int in 20:
		_screen.step_pause()
	events = _type("NO MORE ROAD SPLATS")
	assert_true(PausePage.Event.CHEAT_INFINITE_LIVES in events)
	assert_false(FrontEndSession.cheats.infinite_lives)
	assert_eq(_screen._hud._help_text, "INFINITE LIVES OFF")
	_screen.restart()
	assert_false(_screen.run.snapshot().cheats.infinite_lives, "a direct launch restarts with the session cheats")

func test_session_cheats_seed_a_direct_launch_restart() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	FrontEndSession.cheats.no_death_on_timeout = true
	assert_eq(_screen.restart(), "")
	assert_true(_screen.run.snapshot().cheats.no_death_on_timeout)
	FrontEndSession.cheats = CheatState.new()

func test_typing_show_me_more_zones_please_opens_the_zones_and_saves() -> void:
	var path: String = "user://test_pause_cheats_progress_%d.cfg" % Time.get_ticks_usec()
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(LevelProgress.LEVEL_CAVES1, 0, 0, 1, 0, 1), LevelStack.Row.new(24, 1, 1, 5, 0, 1)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.progress.set_flags(LevelProgress.LEVEL_CAVES1, 0)
	FrontEndSession.store = ProgressStore.new()
	FrontEndSession.store_path = path
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	_open_pause_menu()
	var events: Array[PausePage.Event] = _type("SHOW ME MORE ZONES PLEASE")
	var flags: int = FrontEndSession.progress.flags_of(LevelProgress.LEVEL_CAVES1)
	var written: bool = FileAccess.file_exists(path)
	FrontEndSession.store = null
	FrontEndSession.store_path = ProgressStore.DEFAULT_PATH
	FrontEndSession.progress = null
	if written:
		DirAccess.remove_absolute(path)
	assert_true(PausePage.Event.CHEAT_ALL_ZONES in events)
	assert_true(PausePage.Event.CROAK in events)
	assert_eq(flags, LevelProgress.SELECTABLE | LevelProgress.ZONE_ACCESSIBLE)
	assert_true(written, "the unlocked flags are saved")
	assert_eq(_screen._hud._help_text, "ALL ZONES OPEN")

func test_letters_typed_during_play_set_the_gate_and_a_wrong_letter_resets_the_cursor() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	var cheats: PauseCheats = FrontEndSession.pause_cheats
	_key(KEY_N, true)
	_key(KEY_N, false)
	assert_true(cheats.gate, "a letter during play sets the gate")
	assert_true(_screen.playing)
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	for tick: int in 9:
		_screen._process(GameplayHost.PERIOD)
	assert_true(cheats.gate, "the stale gate reaches the first menu tick")
	_screen.step_pause()
	assert_false(cheats.gate)
	assert_eq(cheats.cursors[PauseCheats.Cheat.INFINITE_LIVES], 0, "nothing is down at the menu tick")
	_type("NO")
	assert_eq(cheats.cursors[PauseCheats.Cheat.INFINITE_LIVES], 2)
	_type("X")
	assert_eq(cheats.cursors[PauseCheats.Cheat.INFINITE_LIVES], 0, "a wrong letter resets the cursor")
	_key(KEY_N, true)
	_key(KEY_META, true)
	_screen.step_pause()
	assert_eq(cheats.cursors[PauseCheats.Cheat.INFINITE_LIVES], 0, "Cmd forgets the keys down")

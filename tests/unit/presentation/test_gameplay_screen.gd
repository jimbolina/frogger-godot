extends GutTest
## Dedicated play preserves host transactions, pause boundaries and fresh sessions.

var _screen: GameplayScreen

func before_each() -> void:
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

func test_pause_joins_pending_work_and_clears_held_input() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	assert_true(_screen._host.submit(scenario.command_at(0)))
	_screen._held = TickCommand.NORTH
	_screen.set_paused(true)
	assert_false(_screen._host.pending())
	assert_false(_screen.playing)
	assert_eq(_screen._held, 0)
	assert_eq(_screen.run.snapshot().tick_index, 1)
	_screen._process(10.0)
	assert_eq(_screen.run.snapshot().tick_index, 1)

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
	assert_eq(_screen._status.text, "Paused — Space to resume")

func test_failed_launch_has_no_stale_run_or_replay_action() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	assert_false(_screen.open_data(null, "ORG1").is_empty())
	assert_null(_screen.run)
	assert_null(_screen._hud._state)
	assert_true(_screen._actions.visible)
	assert_false(_screen._replay.visible)

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
	assert_false(_screen.playing, "Space still pauses")

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

func test_front_end_game_over_leads_to_name_entry() -> void:
	var rows: Array[LevelStack.Row] = [LevelStack.Row.new(24, 1, 0, 5, 0, 2)]
	FrontEndSession.progress = LevelProgress.create(LevelStack.create(rows, []))
	FrontEndSession.store = null
	FrontEndSession.active = true
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	_screen.level_code = FroggerIds.level_code(24)
	var finished: GameplayState = _screen.run.snapshot()
	finished.completed = true
	finished.flow.phase = LevelFlowState.Phase.GAME_OVER
	var result := TickResult.new()
	result.final_snapshot = finished
	_screen._accept(result)
	FrontEndSession.active = false
	var page: int = FrontEndPage.Page.GAME
	for event: int in _screen._advance_events:
		page = FrontEndFlow.next_page(page, event, PackedStringArray())
	assert_eq(page, FrontEndPage.Page.HIGH_SCORE_INPUT)
	assert_eq(_screen._advance.text, "Continue")

func _finish_level(level: int, phase: LevelFlowState.Phase, score: int = 0) -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	_screen.level_code = FroggerIds.level_code(level)
	var finished: GameplayState = _screen.run.snapshot()
	finished.completed = true
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

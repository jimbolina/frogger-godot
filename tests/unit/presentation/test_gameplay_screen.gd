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

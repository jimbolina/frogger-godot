extends GutTest
## Retail cheat switches default off, copy detached and seed a run from its start.

func test_defaults_are_off_and_copy_is_detached() -> void:
	var cheats := CheatState.new()
	assert_false(cheats.infinite_lives)
	assert_false(cheats.no_death_on_timeout)
	cheats.infinite_lives = true
	var duplicate: CheatState = cheats.copy()
	assert_true(duplicate.infinite_lives)
	assert_false(duplicate.no_death_on_timeout)
	duplicate.no_death_on_timeout = true
	assert_false(cheats.no_death_on_timeout)

func test_gameplay_state_copy_carries_detached_cheats() -> void:
	var state := GameplayState.new()
	assert_false(state.cheats.infinite_lives)
	state.cheats.infinite_lives = true
	var duplicate: GameplayState = state.copy(false)
	assert_true(duplicate.cheats.infinite_lives)
	assert_ne(duplicate.cheats, state.cheats)

func test_run_start_seeds_cheats_and_null_turns_both_off() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	var initial: RunStart = scenario.initial
	initial.cheats = CheatState.new()
	initial.cheats.no_death_on_timeout = true
	var run: GameplayRun = GameplayRun.create(scenario.level, initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_true(run.snapshot().cheats.no_death_on_timeout)
	initial.cheats.no_death_on_timeout = false
	assert_true(run.snapshot().cheats.no_death_on_timeout, "the run owns a copy")
	initial.cheats = null
	assert_eq(run.reset(initial), "")
	assert_false(run.snapshot().cheats.no_death_on_timeout)
	assert_false(run.snapshot().cheats.infinite_lives)

func test_set_cheats_replaces_committed_switches_and_rejects_null() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var cheats := CheatState.new()
	cheats.infinite_lives = true
	assert_eq(run.set_cheats(cheats), "")
	cheats.infinite_lives = false
	assert_true(run.snapshot().cheats.infinite_lives)
	assert_ne(run.set_cheats(null), "")
	assert_true(run.snapshot().cheats.infinite_lives)
	var result: TickResult = run.step(scenario.command_at(0))
	assert_eq(result.error, "")
	if result.error.is_empty():
		assert_true(result.final_snapshot.cheats.infinite_lives)
	assert_ne(GameplayRun.new().set_cheats(CheatState.new()), "")

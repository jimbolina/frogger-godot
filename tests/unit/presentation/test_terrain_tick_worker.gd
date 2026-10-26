extends GutTest
## Worker ownership, rejection and presentation handoff stay independent of host frame frequency.

func test_worker_detaches_commands_results_and_rejects_overlapping_submissions() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("buffer")
	var run: TerrainRun = TerrainRun.create(scenario.level, scenario.initial)
	var direct: TerrainRun = TerrainRun.create(scenario.level, scenario.initial)
	var worker := TerrainTickWorker.new()
	assert_eq(worker.start(run), OK)
	for tick: int in scenario.tick_limit:
		var command: TickCommand = scenario.command_at(tick)
		var expected: TickResult = direct.step(command, false)
		assert_true(worker.submit(command))
		assert_false(worker.submit(command))
		command.tick_index = -1
		var result: TickResult = worker.finish()
		assert_eq(JSON.stringify(TerrainTrace.facts(result, true)), JSON.stringify(TerrainTrace.facts(expected, true)))
		result.final_snapshot.frog.position_16 = Vector3i(999, 999, 999)
	assert_true(worker.submit(TickCommand.new()))
	assert_ne(worker.finish().error, "")
	assert_null(worker.poll())
	worker.close()
	assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), JSON.stringify(TerrainTrace.facts(direct.snapshot(), true)))

func test_viewer_drains_before_step_and_reset_and_drawing_never_submits() -> void:
	var viewer := TerrainViewer.new()
	viewer.auto_open = false
	add_child_autofree(viewer)
	viewer.set_process(false)
	viewer.threaded_playback = true
	assert_eq(viewer.open_scenario(TerrainScenario.builtin("normal")), "")
	viewer.playing = true
	viewer._process(1.0 / 30.0)
	assert_true(viewer._worker.pending)
	viewer._finish_pending()
	assert_eq(viewer._current.tick_index, 1)
	for fraction: float in [0.0, 0.25, 0.5, 1.0]:
		viewer.draw_state(fraction)
	assert_eq(viewer._current.tick_index, 1)
	assert_eq(viewer.step_scenario().error, "")
	assert_eq(viewer._current.tick_index, 2)
	viewer._process(1.0 / 30.0)
	assert_eq(viewer.reset_scenario(), "")
	assert_null(viewer._worker)
	assert_eq(viewer._current.tick_index, 0)

extends GutTest
## Pacing, sampling and worker backpressure are independent of viewer drawing.

func test_pacer_retains_fractional_time_drops_stalls_and_samples_at_boundaries() -> void:
	var host := GameplayHost.new()
	assert_false(host.advance(GameplayHost.PERIOD * 0.5, true))
	assert_true(host.advance(GameplayHost.PERIOD, true))
	host.consume_period()
	assert_almost_eq(host.elapsed, GameplayHost.PERIOD * 0.5, 0.000001)
	assert_false(host.advance(10.0, false))
	assert_almost_eq(host.elapsed, GameplayHost.PERIOD * 0.5, 0.000001)
	assert_true(host.advance(10.0, true))
	host.consume_period()
	assert_eq(host.elapsed, 0.0)
	assert_eq(host.sample(0, TickCommand.NORTH).pressed_mask, TickCommand.NORTH)
	assert_eq(host.sample(1, TickCommand.NORTH).pressed_mask, 0)
	assert_eq(host.sample(2, 0).pressed_mask, 0)
	assert_eq(host.sample(3, TickCommand.NORTH).pressed_mask, TickCommand.NORTH)

func test_host_preserves_pending_command_and_requires_acceptance_before_sync_step() -> void:
	var host := GameplayHost.new()
	assert_false(host.submit(TickCommand.new()))
	assert_false(host.step(TickCommand.new(), false).error.is_empty())
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	host.open(GameplayRun.create(scenario.level, scenario.initial))
	var command: TickCommand = scenario.command_at(0)
	assert_true(host.submit(command))
	command.tick_index = 77
	assert_false(host.submit(command))
	assert_eq(host.pending_command.tick_index, 0)
	assert_false(host.advance(GameplayHost.PERIOD, true))
	assert_false(host.step(command, false).error.is_empty())
	var result: TickResult = host.finish()
	assert_eq(result.error, "")
	assert_eq(result.final_snapshot.tick_index, 1)
	assert_null(host.poll())
	host.close()
	assert_null(host.worker)

extends GutTest
## Guard timing and reset rejection preserve the complete owned transaction.

func _scenario() -> TerrainScenario:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	var guard := ExplorationGuard.new()
	guard.world_bounds = Rect2i(-512, -512, 1024, 1024)
	scenario.level.tick_guard = guard
	return scenario

func _zone(cell: Vector2i) -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_index = 7
	zone.source_offset = 2468
	zone.bounds = PackedInt32Array([cell.x, cell.y, cell.x, cell.y])
	return zone

func _state(run: TerrainRun) -> String:
	return JSON.stringify(TerrainTrace.facts(run.snapshot(), true))

func test_zone_query_uses_moved_cell_instead_of_control_destination() -> void:
	var scenario: TerrainScenario = _scenario()
	(scenario.level.tick_guard as ExplorationGuard).zones.append(_zone(Vector2i(1, 2)))
	var run: TerrainRun = TerrainRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	for tick: int in 3:
		assert_eq(run.step(scenario.command_at(tick)).error, "", "Destination alone must not trigger a zone")
	var before: String = _state(run)
	var failed: TickResult = run.step(scenario.command_at(3))
	assert_string_contains(failed.error, "ZONE[7]")
	assert_string_contains(failed.error, "2468")
	assert_eq(_state(run), before)
	assert_null(failed.control_snapshot)
	assert_null(failed.move_snapshot)
	assert_null(failed.final_snapshot)
	assert_true(failed.events.is_empty())
	assert_true(failed.entity_contacts.is_empty())
	assert_true(failed.rng_consumers.is_empty())

func test_world_boundary_rejects_actual_movement_and_copies_caller_definition() -> void:
	var scenario: TerrainScenario = _scenario()
	(scenario.level.tick_guard as ExplorationGuard).world_bounds = Rect2i(-512, -512, 1024, 512)
	var run: TerrainRun = TerrainRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	(scenario.level.tick_guard as ExplorationGuard).world_bounds = Rect2i(-512, -512, 1024, 1024)
	for tick: int in 3:
		assert_eq(run.step(scenario.command_at(tick)).error, "")
	var before: String = _state(run)
	var failed: TickResult = run.step(scenario.command_at(3))
	assert_string_contains(failed.error, "Exploration boundary")
	assert_eq(_state(run), before)
	assert_eq(run.snapshot().world_position.z, -1)

func test_spawn_and_failed_reset_check_both_guards_without_publishing_state() -> void:
	var scenario: TerrainScenario = _scenario()
	(scenario.level.tick_guard as ExplorationGuard).zones.append(_zone(Vector2i(2, 1)))
	var run: TerrainRun = TerrainRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	assert_eq(run.step(scenario.command_at(0)).error, "")
	var before: String = _state(run)
	var start := RunStart.new()
	start.spawn_cell = Vector2i(2, 1)
	assert_string_contains(run.reset(start), "active camera zone")
	assert_eq(_state(run), before)
	scenario.level.spawn_cell = Vector2i(2, 1)
	assert_string_contains(TerrainRun.create(scenario.level).error, "active camera zone")
	(scenario.level.tick_guard as ExplorationGuard).zones.clear()
	(scenario.level.tick_guard as ExplorationGuard).world_bounds = Rect2i(-512, -512, 512, 1024)
	assert_string_contains(TerrainRun.create(scenario.level).error, "Exploration boundary")

func test_null_guard_preserves_existing_movement() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	var run: TerrainRun = TerrainRun.create(scenario.level, scenario.initial)
	for tick: int in 6:
		assert_eq(run.step(scenario.command_at(tick)).error, "")
	assert_eq(run.snapshot().cell, Vector2i(1, 2))

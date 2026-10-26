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

func _state(run: GameplayRun) -> String:
	return JSON.stringify(TerrainTrace.facts(run.snapshot(), true))

func test_zone_query_uses_moved_cell_instead_of_control_destination() -> void:
	var scenario: TerrainScenario = _scenario()
	(scenario.level.tick_guard as ExplorationGuard).zones.append(_zone(Vector2i(1, 2)))
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
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
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	(scenario.level.tick_guard as ExplorationGuard).world_bounds = Rect2i(-512, -512, 1024, 1024)
	for tick: int in 3:
		assert_eq(run.step(scenario.command_at(tick)).error, "")
	var before: String = _state(run)
	var failed: TickResult = run.step(scenario.command_at(3))
	assert_string_contains(failed.error, "Exploration boundary")
	assert_eq(_state(run), before)
	assert_eq(run.snapshot().frog.world_position.z, -1)

func test_spawn_and_failed_reset_check_both_guards_without_publishing_state() -> void:
	var scenario: TerrainScenario = _scenario()
	(scenario.level.tick_guard as ExplorationGuard).zones.append(_zone(Vector2i(2, 1)))
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	assert_eq(run.step(scenario.command_at(0)).error, "")
	var before: String = _state(run)
	var start := RunStart.new()
	start.spawn_cell = Vector2i(2, 1)
	assert_string_contains(run.reset(start), "active camera zone")
	assert_eq(_state(run), before)
	scenario.level.spawn_cell = Vector2i(2, 1)
	assert_string_contains(GameplayRun.create(scenario.level).error, "active camera zone")
	(scenario.level.tick_guard as ExplorationGuard).zones.clear()
	(scenario.level.tick_guard as ExplorationGuard).world_bounds = Rect2i(-512, -512, 512, 1024)
	assert_string_contains(GameplayRun.create(scenario.level).error, "Exploration boundary")

func test_null_guard_preserves_existing_movement() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	for tick: int in 6:
		assert_eq(run.step(scenario.command_at(tick)).error, "")
	assert_eq(run.snapshot().frog.cell, Vector2i(1, 2))

class MutatingGuard:
	extends TickGuard
	var phases: Array[Phase] = []

	func copy() -> TickGuard:
		return MutatingGuard.new()

	func check(phase: Phase, candidate: TickGuardCandidate) -> String:
		phases.append(phase)
		if candidate.state != null:
			candidate.state.frog.position_16 = Vector3i(99, 99, 99)
			candidate.state.attachment.current_entity_index = 999
			candidate.state.requests.sound_requests = 999
			candidate.state.diagnostics.resource_id = 999
		return ""

func test_generic_guard_receives_detached_composed_state_at_each_boundary() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	var original := MutatingGuard.new()
	scenario.level.tick_guard = original
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	assert_eq(run.step(scenario.command_at(0)).error, "")
	var state: GameplayState = run.snapshot()
	assert_ne(state.frog.position_16, Vector3i(99, 99, 99))
	assert_eq(state.attachment.current_entity_index, -1)
	assert_ne(state.requests.sound_requests, 999)
	assert_ne(state.diagnostics.resource_id, 999)
	assert_true(original.phases.is_empty())
	var guard: MutatingGuard = run._tick_guard as MutatingGuard
	assert_eq(guard.phases, [TickGuard.Phase.SETUP, TickGuard.Phase.RESET_WORLD,
		TickGuard.Phase.RESET_POSE, TickGuard.Phase.ENTITY_UPDATE,
		TickGuard.Phase.MOVEMENT, TickGuard.Phase.FINAL])

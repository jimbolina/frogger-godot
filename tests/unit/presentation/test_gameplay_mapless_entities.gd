extends GutTest
## Map-less sandbox entities fall back to placeholder markers when no player data is supplied.

var _screen: GameplayScreen

func before_each() -> void:
	_screen = GameplayScreen.new()
	_screen.auto_open = false
	add_child_autofree(_screen)
	_screen.set_process(false)

func test_resources_without_data_leave_every_slot_unresolved() -> void:
	var spawner := SandboxSpawner.new(SandboxLevel.build())
	assert_eq(spawner.add("STATIC", Vector2i(10, 4)).error, "")
	var origins: EntityModelOrigins = spawner.model_origins(null)
	assert_eq(origins.size(), 1)
	assert_false(origins.resolvable(0))
	var resources: MaplessEntityResources = MaplessEntityResources.resolve(spawner.entity_collision().entities, origins)
	assert_eq(resources.meshes.size(), 1)
	assert_null(resources.meshes[0])
	assert_null(resources.files[0])
	assert_string_contains(" ".join(resources.diagnostics), "placeholders")

func test_spawned_entity_without_data_draws_a_placeholder_while_stepping() -> void:
	var spawner := SandboxSpawner.new(SandboxLevel.build())
	assert_eq(spawner.add("STATIC", Vector2i(10, 4)).error, "")
	assert_eq(spawner.add("MOVING", Vector2i(4, 8), SandboxSpawner.Preset.LINE).error, "")
	var start: RunStart = SandboxSpawner.run_start(SandboxLevel.SPAWN_CELL, SandboxLevel.SPAWN_DIRECTION)
	assert_eq(_screen.open_run(spawner.level_definition(), start, spawner.model_origins(null)), "")
	assert_eq(_screen.last_error, "")
	assert_eq(_screen.placeholder_count(), 2)
	assert_eq(_screen.entity_model_count(), 0)
	assert_false(_screen.entity_model_diagnostics.is_empty())
	for tick: int in 10:
		var command := TickCommand.new()
		command.tick_index = tick
		assert_eq(_screen.step_command(command).error, "", str(tick))
		_screen.draw_state(0.5)
	assert_eq(_screen.run.snapshot().tick_index, 10)
	assert_eq(_screen.restart(), "")
	assert_eq(_screen.placeholder_count(), 2)

func test_respawning_rebuilds_placeholders_for_the_new_table() -> void:
	var spawner := SandboxSpawner.new(SandboxLevel.build())
	assert_eq(spawner.add("STATIC", Vector2i(10, 4)).error, "")
	var start: RunStart = SandboxSpawner.run_start(SandboxLevel.SPAWN_CELL, SandboxLevel.SPAWN_DIRECTION)
	assert_eq(_screen.open_run(spawner.level_definition(), start, spawner.model_origins(null)), "")
	assert_eq(_screen.placeholder_count(), 1)
	spawner.clear()
	assert_eq(_screen.open_run(spawner.level_definition(), SandboxSpawner.run_start_from(_screen.run.snapshot()), spawner.model_origins(null)), "")
	assert_eq(_screen.placeholder_count(), 0)
	_screen.draw_state(1.0)

func test_runs_without_origins_keep_existing_behaviour() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(_screen.open_run(scenario.level, scenario.initial), "")
	assert_eq(_screen.placeholder_count(), 0)
	assert_true(_screen.entity_model_diagnostics.is_empty())
	_screen.draw_state(1.0)

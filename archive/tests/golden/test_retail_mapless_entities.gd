extends RetailTest
## Sandbox entities borrowed from supported levels resolve real models without a map.

var _data: GameData
var _templates: SandboxEntityTemplates
var _screen: GameplayScreen

func before_all() -> void:
	if not retail_skip_reason().is_empty():
		return
	_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(_data)
	_templates = SandboxEntityTemplates.from_data(_data, assets.model, assets.action_lengths)

func after_all() -> void:
	if _data != null:
		_data.close()

func before_each() -> void:
	_screen = GameplayScreen.new()
	_screen.auto_open = false
	add_child_autofree(_screen)
	_screen.set_process(false)

func _open(spawner: SandboxSpawner) -> void:
	var start: RunStart = SandboxSpawner.run_start(SandboxLevel.SPAWN_CELL, SandboxLevel.SPAWN_DIRECTION)
	assert_eq(_screen.open_run(spawner.level_definition(), start, spawner.model_origins(_data)), "")

func test_spawned_retail_entities_get_model_nodes() -> void:
	assert_eq(_templates.error, "")
	var spawner := SandboxSpawner.new(SandboxLevel.build(), _templates)
	var log: SandboxSpawner.Result = spawner.add("MOVING", Vector2i(4, 8), SandboxSpawner.Preset.LINE)
	var turtle: SandboxSpawner.Result = spawner.add("SUB_TURTLE", Vector2i(4, 10), SandboxSpawner.Preset.LOOP)
	var switch: SandboxSpawner.Result = spawner.add("VOL_COLOUR_SWITCH", Vector2i(14, 20))
	for result: SandboxSpawner.Result in [log, turtle, switch]:
		assert_eq(result.error, "")
		if not result.error.is_empty():
			return
	assert_true(spawner.model_origins(_data).resolvable(0))
	_open(spawner)
	assert_eq(_screen.entity_model_count(), 3, " ".join(_screen.entity_model_diagnostics))
	assert_eq(_screen.placeholder_count(), 0)
	for slot: int in 3:
		assert_not_null(_screen._entity_models[slot], str(slot))
		assert_true(_screen._entity_models[slot].get_parent() == _screen, str(slot))
	for tick: int in 20:
		var command := TickCommand.new()
		command.tick_index = tick
		assert_eq(_screen.step_command(command).error, "", str(tick))
		_screen.draw_state(0.5)
	assert_eq(_screen.entity_model_count(), 3)

func test_data_free_platform_beside_retail_entity_keeps_a_placeholder() -> void:
	var spawner := SandboxSpawner.new(SandboxLevel.build(), _templates)
	assert_eq(spawner.add("MOVING", Vector2i(4, 8)).error, "")
	var origins: EntityModelOrigins = spawner.model_origins(_data)
	origins.themes[0] = -1
	var start: RunStart = SandboxSpawner.run_start(SandboxLevel.SPAWN_CELL, SandboxLevel.SPAWN_DIRECTION)
	assert_eq(_screen.open_run(spawner.level_definition(), start, origins), "")
	assert_eq(_screen.entity_model_count(), 0)
	assert_eq(_screen.placeholder_count(), 1)
	_screen.draw_state(1.0)

func test_hive_and_cave_sprites_configure_without_a_map() -> void:
	var spawner := SandboxSpawner.new(SandboxLevel.build(), _templates)
	assert_eq(spawner.add("FOR_HIVE", Vector2i(8, 20)).error, "")
	assert_eq(spawner.add("FIREFLY", Vector2i(20, 20), SandboxSpawner.Preset.LOOP).error, "")
	_open(spawner)
	assert_false(" ".join(_screen.entity_model_diagnostics).contains("swarm"), " ".join(_screen.entity_model_diagnostics))
	assert_not_null(_screen._swarm_view._material)
	assert_eq(_screen._sprite_definitions.size(), 2)
	assert_eq(_screen.placeholder_count(), 0)
	for tick: int in 10:
		var command := TickCommand.new()
		command.tick_index = tick
		assert_eq(_screen.step_command(command).error, "", str(tick))
		_screen.draw_state(1.0)

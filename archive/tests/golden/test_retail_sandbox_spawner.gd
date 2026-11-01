extends RetailTest
## Data-backed sandbox spawning from supported-level templates, runs and checkpoint limits.

const UNSPAWNABLE: PackedStringArray = ["FOR_SWAYING_BRANCH", "ORG_BABY_FROG", "ORG_LOG_SNAKE", "GEN_TOP_LEFT", "GEN_BOTTOM_RIGHT", "SUB_LAWNMOWER"]

var _data: GameData
var _templates: SandboxEntityTemplates

func before_all() -> void:
	if not retail_skip_reason().is_empty():
		return
	_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(_data)
	_templates = SandboxEntityTemplates.from_data(_data, assets.model, assets.action_lengths)

func after_all() -> void:
	if _data != null:
		_data.close()

func _spawner() -> SandboxSpawner:
	return SandboxSpawner.new(SandboxLevel.build(), _templates)

func _run(spawner: SandboxSpawner, ticks: int, label: String) -> void:
	var level: LevelDefinition = spawner.level_definition()
	assert_eq(level.entity_collision.validate(), "", label)
	var run: GameplayRun = GameplayRun.create(level, SandboxSpawner.run_start(SandboxLevel.SPAWN_CELL, SandboxLevel.SPAWN_DIRECTION))
	assert_eq(run.error, "", label)
	if not run.error.is_empty():
		return
	for tick: int in ticks:
		var command := TickCommand.new()
		command.tick_index = run.snapshot().tick_index
		var result: TickResult = run.step(command)
		assert_eq(result.error, "", "%s tick %d" % [label, tick])
		if not result.error.is_empty():
			return

func test_templates_index_supported_levels_with_data_frog_and_rewards() -> void:
	assert_eq(_templates.error, "")
	assert_eq(_templates.level_errors, {} as Dictionary[String, String])
	assert_eq(_templates.rewards.size(), 24)
	assert_eq(_templates.frog_collision.validate(), "")
	assert_eq(_templates.frog_collision.actions.size(), _templates.frog_action_lengths.size())
	assert_true(_templates.form_names("MOVING").size() > 1)
	assert_eq(_templates.level_for("SUB_TURTLE"), "ORG1")
	assert_eq(_templates.level_for("VOL_FALLING_PLATFORM"), "VOL3")
	assert_eq(_templates.level_for("FOR_SWAYING_BRANCH"), "")

func test_every_spawnable_kind_runs_alone_on_the_arena() -> void:
	var spawner: SandboxSpawner = _spawner()
	for entity_name: String in SandboxSpawner.kind_names():
		var availability: SandboxSpawner.Availability = spawner.availability(entity_name)
		assert_eq(availability.available, not UNSPAWNABLE.has(entity_name), "%s %s" % [entity_name, availability.reason])
		if not availability.available:
			assert_string_contains(spawner.add(entity_name, Vector2i(16, 4)).error, availability.reason)
			continue
		var single: SandboxSpawner = _spawner()
		var preset: SandboxSpawner.Preset = SandboxSpawner.Preset.LINE if EntityBehaviorCatalog.resolve(entity_name).layout == EntityBehavior.Layout.PATH else SandboxSpawner.Preset.STATIC
		var result: SandboxSpawner.Result = single.add(entity_name, Vector2i(14, 4), preset)
		assert_eq(result.error, "", entity_name)
		if not result.error.is_empty():
			continue
		assert_false(result.placement.level_code.is_empty(), entity_name)
		assert_eq(result.placement.entity.entity_name, entity_name)
		_run(single, 30, entity_name)

func test_scripted_and_action_driven_kinds_keep_their_executable_data() -> void:
	var spawner: SandboxSpawner = _spawner()
	var turtle: SandboxSpawner.Result = spawner.add("SUB_TURTLE", Vector2i(4, 7), SandboxSpawner.Preset.LOOP)
	var falling: SandboxSpawner.Result = spawner.add("VOL_FALLING_PLATFORM", Vector2i(12, 20))
	var switch: SandboxSpawner.Result = spawner.add("VOL_COLOUR_SWITCH", Vector2i(14, 20))
	var log: SandboxSpawner.Result = spawner.add("MOVING", Vector2i(4, 8), SandboxSpawner.Preset.SPEED)
	for result: SandboxSpawner.Result in [turtle, falling, switch, log]:
		assert_eq(result.error, "")
		if not result.error.is_empty():
			return
	assert_not_null(turtle.placement.entity.script_definition)
	assert_eq(turtle.placement.entity.path_definition.segments.size(), 4)
	assert_false(falling.placement.entity.action_lengths.is_empty())
	assert_true(switch.placement.entity.action_lengths.size() >= 2)
	for target: int in switch.placement.entity.volcano.target_ids:
		assert_eq(target, -1)
	assert_eq(log.placement.entity.path_start.speed, log.placement.speed)
	assert_true(log.placement.speed > 0)
	var level: LevelDefinition = spawner.level_definition()
	assert_eq(level.frog_action_lengths, _templates.frog_action_lengths)
	assert_not_null(level.entity_collision.frog_collision)
	assert_eq(level.rewards.size(), 24)
	_run(spawner, 90, "mixed")
	spawner.remove(falling.placement.unique_id)
	_run(spawner, 10, "after remove")
	spawner.clear()
	_run(spawner, 10, "after clear")

func test_checkpoints_fill_five_distinct_slots_then_refuse() -> void:
	var spawner: SandboxSpawner = _spawner()
	var indices: Dictionary[int, bool] = {}
	for slot: int in 5:
		var result: SandboxSpawner.Result = spawner.add("CHECKPOINT", Vector2i(6 + slot * 2, 26))
		assert_eq(result.error, "", str(slot))
		if not result.error.is_empty():
			return
		var index: int = result.placement.entity.form_id & 32767
		assert_false(indices.has(index))
		indices[index] = true
		var collision: EntityCollisionDefinition = spawner.entity_collision()
		var entity: EntityDefinition = result.placement.entity
		assert_eq(collision.environment.checkpoint_positions[index], Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11]))
	assert_string_contains(spawner.add("CHECKPOINT", Vector2i(20, 28)).error, "already placed")
	assert_eq(spawner.placements.size(), 5)
	_run(spawner, 30, "checkpoints")

func test_only_one_frogger_light_can_be_placed() -> void:
	var spawner: SandboxSpawner = _spawner()
	assert_eq(spawner.add("CAV_FROGGER_LIGHT", Vector2i(10, 2)).error, "")
	assert_string_contains(spawner.add("CAV_FROGGER_LIGHT", Vector2i(12, 2)).error, "one frogger light")
	assert_true(spawner.level_definition().cave_light)

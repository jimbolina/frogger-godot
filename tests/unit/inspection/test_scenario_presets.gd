extends GutTest
## Level starts, capture milestones and overlays come from the preset tables.

func _state(tick: int, cell: Vector2i = Vector2i.ZERO, platform: int = -1, killer: int = -1) -> GameplayState:
	var state := GameplayState.new()
	state.tick_index = tick
	state.frog.cell = cell
	state.attachment.current_entity_index = platform
	state.attachment.death_entity_index = killer
	return state

func _scenario(preset: String, level_code: String = "") -> TerrainScenario:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	scenario.options.exploration_preset = preset
	scenario.level_code = level_code
	return scenario

func test_every_exploration_names_its_level_and_known_probes() -> void:
	for preset: String in ScenarioPresets.EXPLORATIONS:
		assert_true(ScenarioPresets.exploration_level(preset) in ["ORG1", "JUN1"], preset)
		for value: Variant in ScenarioPresets.capture_stages(preset):
			var row: Array = value
			var probe: String = row[1]
			assert_true(probe in ["tick", "cell_y", "idle_cell_y", "platform", "killer"], "%s %s" % [preset, row])
	assert_eq(ScenarioPresets.exploration_level("unknown"), "")
	assert_eq(ScenarioPresets.exploration_level(Org1ExplorationSetup.ROAD_PRESET), "ORG1")
	assert_eq(ScenarioPresets.exploration_level(Jun1ExplorationSetup.PRESET), "JUN1")
	assert_true(ScenarioPresets.exploration_scripted(Org1ExplorationSetup.VISIBILITY_PRESET))
	assert_false(ScenarioPresets.exploration_scripted(Jun1ExplorationSetup.PRESET))

func test_visibility_milestones_extend_the_river_preset() -> void:
	var river: TerrainScenario = _scenario(Org1ExplorationSetup.PRESET)
	var visible: TerrainScenario = _scenario(Org1ExplorationSetup.VISIBILITY_PRESET)
	assert_eq(TerrainCaptureStages.platform(river, _state(19)), ["org1-log"] as Array[String])
	assert_eq(TerrainCaptureStages.platform(visible, _state(19)), ["org1-log"] as Array[String])
	assert_eq(TerrainCaptureStages.platform(river, _state(446)), [] as Array[String])
	assert_eq(TerrainCaptureStages.platform(visible, _state(446)), ["org1-pink-pickup"] as Array[String])
	assert_eq(TerrainCaptureStages.platform(visible, _state(1234)), ["org1-diver-attachment"] as Array[String])
	assert_eq(TerrainCaptureStages.platform(_scenario(Jun1ExplorationSetup.PRESET), _state(12)), ["platform-carry"] as Array[String])
	assert_eq(TerrainCaptureStages.platform(_scenario(""), _state(12)), [] as Array[String])

func test_road_milestones_follow_cell_attachment_and_killer() -> void:
	var road: TerrainScenario = _scenario(Org1ExplorationSetup.ROAD_PRESET)
	assert_eq(TerrainCaptureStages.platform(road, _state(1, Vector2i(10, 1))), ["org1-road-start"] as Array[String])
	assert_eq(TerrainCaptureStages.platform(road, _state(5, Vector2i(10, 4), -1, 30)), ["org1-road-traffic", "org1-road-vehicle-death"] as Array[String])
	assert_eq(TerrainCaptureStages.platform(road, _state(9, Vector2i(10, 7))), ["org1-road-bank"] as Array[String])
	var hopping: GameplayState = _state(9, Vector2i(10, 7))
	hopping.frog.mode = 1
	assert_eq(TerrainCaptureStages.platform(road, hopping), [] as Array[String])
	assert_eq(TerrainCaptureStages.platform(road, _state(20, Vector2i(10, 9), 23)), ["org1-road-river"] as Array[String])
	assert_eq(TerrainCaptureStages.platform(road, _state(20, Vector2i(10, 9), 24)), [] as Array[String])

func test_level_starts_select_contact_frames_and_overlays() -> void:
	assert_true(TerrainCaptureStages.before_contact(_scenario("", "DES2"), _state(4)))
	assert_false(TerrainCaptureStages.before_contact(_scenario("", "des2"), _state(5)))
	assert_true(TerrainCaptureStages.before_contact(_scenario("", "JUN1"), _state(5)))
	assert_true(TerrainCaptureStages.before_contact(_scenario("", "ORG1"), _state(5)))
	assert_eq(TerrainCaptureStages.overlay(_scenario(Org1ExplorationSetup.ROAD_PRESET)).detail, "road")
	assert_eq(TerrainCaptureStages.overlay(_scenario("")).title, "JUN1 BANK / LOG EXPLORATION")
	assert_eq(ScenarioPresets.preferred_entity_id("ORG1"), 12)
	assert_eq(ScenarioPresets.preferred_entity_id("JUN1"), -1)
	assert_true(ScenarioPresets.start_needs_platforms("JUN1"))
	assert_false(ScenarioPresets.start_needs_platforms("DES2"))

func test_jun1_start_applies_only_with_platform_reactions() -> void:
	var scenario: TerrainScenario = _scenario("", "JUN1")
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--entity-reactions=pop"])), "")
	var cell: Vector2i = scenario.initial.spawn_cell
	scenario.apply_level_start()
	assert_eq(scenario.initial.spawn_cell, cell)
	assert_ne(scenario.tick_limit, 90)
	var platforms: TerrainScenario = _scenario("", "JUN1")
	assert_eq(TerrainScenarioArguments.apply(platforms, PackedStringArray(["--entity-reactions=platforms"])), "")
	platforms.apply_level_start()
	assert_eq(platforms.initial.spawn_cell, Vector2i(18, 5))
	assert_eq(platforms.tick_limit, 90)
	assert_eq(platforms.command_at(0).pressed_mask, TickCommand.NORTH)
	assert_eq(platforms.diagnostics[platforms.diagnostics.size() - 1], "JUN1 inspection starts on authored water cell (18,5); no playable safe-bank route is implied")

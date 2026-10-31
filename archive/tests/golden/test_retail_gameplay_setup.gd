extends RetailTest
## Whole-map admission exercises every authored dependency of the playable level set.

func test_all_playable_levels_resolve_and_start_with_supplied_identity() -> void:
	var data: GameData = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))
	assert_eq(data.error, "")
	if not data.is_valid():
		return
	assert_eq(GameplayHudAssets.from_data(data).error, "")
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(data)
	assert_eq(assets.error, "")
	if not assets.error.is_empty():
		data.close()
		return
	for code: String in data.playable_level_codes():
		var number: int = FroggerIds.level_from_code(code)
		var scenario: TerrainScenario = TerrainScenario.builtin("normal")
		var issue: String = scenario.attach_data(data, code, assets)
		assert_eq(issue, "", code)
		if not issue.is_empty():
			continue
		assert_eq(scenario.level.map_index, number, code)
		assert_eq(scenario.level.resource_id, data.map_book_entry(number).map_id(false), code)
		assert_eq(scenario.level.source_id, "pc-retail-v3.0e:" + code)
		assert_eq(scenario.level.entity_collision.entities.size(), scenario.map_scene.map.entities.size(), code)
		assert_eq(scenario.level.camera_zones.size(), scenario.map_scene.map.zones.size(), code)
		assert_eq(scenario.level.spawn_cell, scenario.map_scene.map.general.start_grid, code)
		assert_true(scenario.level.flow_enabled, code)
		assert_null(scenario.level.tick_guard, code)
		if code == "SUB1":
			assert_eq(scenario.level.collision_bounds, Rect2i(-32767, -32767, 65534, 65534))
		var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
		assert_eq(run.error, "", code)
		if not run.error.is_empty():
			continue
		for tick: int in 121:
			var command := TickCommand.new()
			command.tick_index = tick
			var result: TickResult = run.step(command)
			assert_eq(result.error, "", "%s tick %d" % [code, tick])
			if not result.error.is_empty():
				break
	data.close()

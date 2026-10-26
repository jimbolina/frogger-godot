extends GutTest
## Combined Python/frozen-C facts, including retail-derived text usable without assets.

func test_synthetic_zone_lifecycle_matches_frozen_gameplay() -> void:
	var scenario: TerrainScenario = TerrainScenario.from_file("res://tests/golden/fixtures/lifecycle_zones.json")
	assert_eq(scenario.error, "")
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--entity-lifecycle=visibility"])), "")
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/zone_lifecycle.json"))
	var rows: Array = golden.cases[0].expected
	var fast: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	for tick: int in rows.size():
		var result: TickResult = run.step(scenario.command_at(tick))
		assert_eq(result.error, "", "tick %d" % tick)
		if not result.error.is_empty():
			return
		var state: GameplayState = result.final_snapshot
		assert_eq(ZoneLifecycleChecks.compare(rows[tick], state.camera, state.frog.camera_zone_index, state.frog.camera_zone_region_index,
			state.attachment.entity_angle, state.frog.world_position, state.entities), "", "tick %d" % tick)
		var quick: TickResult = fast.step(scenario.command_at(tick), false)
		assert_eq(quick.error, "")
		assert_eq(ZoneLifecycleChecks.canonical(TerrainTrace.facts(quick.final_snapshot, true)), ZoneLifecycleChecks.canonical(TerrainTrace.facts(state, true)))
		var selection: MapGroupVisibilityResult = MapGroupVisibility.query(scenario.level.entity_collision.lifecycle, state.camera)
		assert_eq(Array(selection.groups), Array(state.entities.selected_groups), "same-tick camera")
	assert_eq(run.reset(scenario.initial), "")
	assert_true(run.snapshot().entities.live_order.is_empty())
	assert_eq(run.snapshot().camera.zone_index, -1)
	for tick: int in rows.size():
		assert_eq(run.step(scenario.command_at(tick), false).error, "")
	assert_eq(ZoneLifecycleChecks.canonical(TerrainTrace.facts(run.snapshot(), true)), ZoneLifecycleChecks.canonical(TerrainTrace.facts(fast.snapshot(), true)))

func test_retail_text_zone_lifecycle_corpus() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/pc-retail-v3.0e/zone_lifecycle.json"))
	var probe: CameraZoneInspection = ZoneLifecycleChecks.inspection(golden.cases[0].workload)
	assert_eq(probe.error, "")
	if not probe.error.is_empty():
		return
	var angle: int = 0
	for tick: int in 320:
		if tick == 160:
			angle = 0
		assert_eq(probe.step(), "", "tick %d" % tick)
		var row: Dictionary = golden.cases[0 if tick < 160 else 1].expected[tick % 160]
		angle = (angle + probe.camera.snapshot().entity_angle_delta) & 3
		assert_eq(ZoneLifecycleChecks.compare(row, probe.camera.snapshot(), probe.selected.x, probe.selected.y, angle, probe.world,
			probe.entities.snapshot()), "", "tick %d" % tick)
		assert_eq(ZoneLifecycleChecks._integer(probe.row.polygon_total), ZoneLifecycleChecks._integer(row.polygon_total))

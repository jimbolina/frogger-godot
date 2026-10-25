extends GutTest
## Authored-zone validation and private retail-probe candidate failures.

func test_zone_json_validation_detaches_and_preserves_absent_defaults() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/fixtures/lifecycle_zones.json"))
	var valid: Dictionary = fixture.level.camera_zones[0]
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	assert_eq(TerrainScenarioJson.apply(scenario, {"level": {"camera_zones": [valid]}}), "")
	valid.camera_offsets[0][1] = -999
	assert_eq(scenario.level.camera_zones[0].camera_offsets[0].y, -768)
	assert_eq(TerrainScenarioJson.apply(scenario, {"level": {}}), "")
	assert_eq(scenario.level.camera_zones.size(), 1)
	for invalid: Variant in [null, {}, [null], [{"zone_index": 0}], [valid, valid]]:
		assert_false(TerrainScenarioJson.apply(scenario, {"level": {"camera_zones": invalid}}).is_empty())
	for key: String in ["zone_index", "camera_direction", "bounds", "camera_offsets", "regions"]:
		var malformed: Dictionary = valid.duplicate(true)
		malformed[key] = 0.5
		assert_false(TerrainScenarioJson.apply(scenario, {"level": {"camera_zones": [malformed]}}).is_empty(), key)
	scenario.level.camera = null
	assert_string_contains(TerrainRun.create(scenario.level).error, "integrated camera")

func test_probe_failure_at_sequence_reset_publishes_nothing_and_retries() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/pc-retail-v3.0e/zone_lifecycle.json"))
	var probe: CameraZoneInspection = ZoneLifecycleChecks.inspection(golden.cases[0].workload)
	var clean: CameraZoneInspection = ZoneLifecycleChecks.inspection(golden.cases[0].workload)
	assert_eq(probe.error, "")
	if not probe.error.is_empty():
		return
	for unused: int in 160:
		assert_eq(probe.step(), "")
		assert_eq(clean.step(), "")
	var before_row: String = ZoneLifecycleChecks.canonical(probe.row)
	var before_entities: String = ZoneLifecycleChecks.canonical(TerrainTrace.facts(probe.entities.snapshot()))
	var before_camera: String = ZoneLifecycleChecks.canonical(TerrainTrace.facts(probe.camera.snapshot()))
	var counts: PackedInt32Array = probe.lifecycle.polygon_counts.duplicate()
	probe.lifecycle.polygon_counts.fill(2500)
	assert_string_contains(probe.step(), "2500")
	assert_eq(probe.tick, 160)
	assert_eq(ZoneLifecycleChecks.canonical(probe.row), before_row)
	assert_eq(ZoneLifecycleChecks.canonical(TerrainTrace.facts(probe.entities.snapshot())), before_entities)
	assert_eq(ZoneLifecycleChecks.canonical(TerrainTrace.facts(probe.camera.snapshot())), before_camera)
	probe.lifecycle.polygon_counts = counts
	assert_eq(probe.step(), "")
	assert_eq(clean.step(), "")
	assert_eq(ZoneLifecycleChecks.canonical(probe.row), ZoneLifecycleChecks.canonical(clean.row))
	var detached: EntityRunSnapshot = probe.entities.snapshot()
	detached.live_order.clear()
	detached.entities[0].generation = 900
	assert_eq(ZoneLifecycleChecks.canonical(probe.row), ZoneLifecycleChecks.canonical(clean.row))
	assert_ne(probe.entities.snapshot().entities[0].generation, 900)
	assert_eq(probe.reset(), "")
	assert_eq(probe.tick, 0)
	assert_true(probe.entities.snapshot().live_order.is_empty())

extends "res://tests/support/camera_zone_checks.gd"
## Active zones, camera transitions and aggregate ownership.

class LateGuard extends ExplorationGuard:
	var visits: int = 0
	func check_world(_world: Vector3i) -> String:
		visits += 1
		return "Injected final guard failure" if visits == 2 else ""

func _zone(index: int = 0, bounds: PackedInt32Array = PackedInt32Array([1, 1, 1, 2])) -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_index = index
	zone.bounds = bounds
	for direction: int in 4:
		zone.camera_offsets.append(Vector3i(direction * 30, -800, -700))
		zone.camera_offsets.append(Vector3i(direction * 10, -100, 0))
	return zone

func _command(tick: int, pressed: int = 0) -> TickCommand:
	var command := TickCommand.new()
	command.tick_index = tick
	command.pressed_mask = pressed
	command.held_mask = pressed
	return command

func test_independent_camera_zone_corpus() -> void:
	_check_corpus("res://tests/golden/synthetic/camera_zones.json")

func test_text_only_retail_camera_corpus() -> void:
	_check_corpus("res://tests/golden/pc-retail-v3.0e/camera_zones.json")

func test_failure_after_camera_discards_zone_timers_and_animation_rng() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	scenario.level.camera_zones.append(_zone())
	var run: TerrainRun = TerrainRun.create(scenario.level)
	var before: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
	var late := LateGuard.new()
	run._exploration_guard = late
	var result: TickResult = run.step(_command(0))
	assert_string_contains(result.error, "Injected final")
	assert_eq(late.visits, 2)
	assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), before)
	assert_null(result.camera_snapshot)
	run._exploration_guard = null
	assert_eq(run.step(_command(0)).error, "")
	assert_eq(run.snapshot().camera.zone_index, 0)
	assert_eq(run.snapshot().camera.move_timer, 29)

func test_active_zone_validation_and_nested_ownership() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	var zone: ZoneDefinition = _zone()
	scenario.level.camera_zones.append(zone)
	var trace := TerrainTrace.new()
	trace.configure(scenario)
	var metadata: Dictionary = JSON.parse_string(trace.full_rows[0])
	var omissions: Array = metadata.omitted
	assert_false(omissions.has("zones"))
	assert_true(metadata.has("camera_zones"))
	scenario.level.camera = null
	assert_string_contains(TerrainRun.create(scenario.level).error, "integrated camera")
	scenario.level.camera = GameplayCameraDefinition.new()
	var run: TerrainRun = TerrainRun.create(scenario.level)
	assert_eq(run.error, "")
	zone.bounds[0] = 30
	zone.camera_offsets[0] = Vector3i.ONE
	assert_eq(run.snapshot().camera_zone_index, 0)
	assert_eq(run.step(_command(0)).error, "")
	assert_eq(run.snapshot().camera.next_source_offset, Vector3i(0, -800, -700))
	var detached: RunSnapshot = run.snapshot()
	detached.camera.zone_index = 40
	detached.camera_zone_region_index = 40
	assert_eq(run.snapshot().camera.zone_index, 0)
	assert_eq(run.snapshot().camera_zone_region_index, -1)
	scenario.level.camera_zones.append(zone.copy())
	assert_string_contains(TerrainRun.create(scenario.level).error, "duplicate")
	scenario.level.camera_zones.pop_back()

func test_move_selects_zone_before_camera_and_failed_late_guard_rolls_back() -> void:
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	scenario.level.camera_zones.append(_zone(5, PackedInt32Array([1, 2, 1, 2])))
	scenario.level.exploration_guard = ExplorationGuard.new()
	scenario.level.exploration_guard.world_bounds = Rect2i(-512, -512, 1024, 1024)
	var run: TerrainRun = TerrainRun.create(scenario.level)
	assert_eq(run.error, "")
	for tick: int in 3:
		assert_eq(run.step(_command(tick, TickCommand.NORTH if tick == 0 else 0)).error, "")
	var before: String = JSON.stringify(TerrainTrace.facts(run.snapshot(), true))
	run._exploration_guard.world_bounds = Rect2i(-512, -512, 1024, 512)
	var rejected: TickResult = run.step(_command(3))
	assert_false(rejected.error.is_empty())
	assert_eq(JSON.stringify(TerrainTrace.facts(run.snapshot(), true)), before)
	run._exploration_guard.world_bounds = Rect2i(-512, -512, 1024, 1024)
	var accepted: TickResult = run.step(_command(3))
	assert_eq(accepted.error, "")
	assert_eq(accepted.move_snapshot.camera_zone_index, 5)
	assert_eq(accepted.move_snapshot.camera.zone_index, -1)
	assert_eq(accepted.camera_snapshot.camera.zone_index, 5)
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().camera_zone_index, -1)
	assert_eq(run.snapshot().camera.zone_index, -1)

func test_forced_control_is_ignored_and_semiforced_turn_waits() -> void:
	for semiforced: bool in [false, true]:
		var scenario: TerrainScenario = TerrainScenario.builtin("normal")
		var zone: ZoneDefinition = _zone()
		zone.camera_direction = 0
		zone.camera_flags = 4 if semiforced else 0
		scenario.level.camera_zones.append(zone)
		var run: TerrainRun = TerrainRun.create(scenario.level)
		for tick: int in 30:
			assert_eq(run.step(_command(tick)).error, "")
		var result: TickResult = run.step(_command(30, TickCommand.CAMERA_CLOCKWISE))
		assert_eq(result.error, "")
		assert_eq(run.snapshot().mode, 3 if semiforced else 0)
		assert_eq(run.snapshot().camera.twist_counter, 2 if semiforced else 0)
		if not semiforced:
			assert_eq(run.snapshot().current_input, 128 | 32)

func test_frozen_region_retention_ignores_outer_bounds_until_region_exit() -> void:
	var zone: ZoneDefinition = _zone(12, PackedInt32Array([1, 1, 1, 1]))
	zone.regions.append(PackedInt32Array([1, 1, 3, 3]))
	var zones: Array[ZoneDefinition] = [zone]
	var selected: Vector2i = ZoneQueries.update_camera_match(zones, Vector2i(1, 1))
	assert_eq(selected, Vector2i(12, 0))
	assert_eq(ZoneQueries.update_camera_match(zones, Vector2i(3, 3), selected), selected)
	assert_eq(ZoneQueries.update_camera_match(zones, Vector2i(4, 4), selected, ZoneQueries.NO_UPDATE), selected)
	assert_eq(ZoneQueries.update_camera_match(zones, Vector2i(4, 4), selected), Vector2i(-1, -1))

func test_platform_projection_selects_offsets_and_death_shake_preserves_zone() -> void:
	var camera: GameplayCamera = GameplayCamera.create(GameplayCameraDefinition.new(), Vector3i.ZERO)
	var input := GameplayCameraTick.new()
	input.camera_zone = _zone()
	input.on_entity = true
	input.entity_matrix12 = PlatformMath.yaw(1024)
	assert_eq(camera.step(input), "")
	assert_eq(camera.snapshot().next_source_offset, input.camera_zone.camera_offsets[2])
	assert_eq(camera.transition_attachment(input.entity_matrix12, PackedInt32Array(), false), "")
	input.on_entity = false
	assert_eq(camera.step(input), "")
	var before: GameplayCameraSnapshot = camera.snapshot()
	camera.request_fixed()
	camera.request_death()
	assert_eq(camera.request_shake(128, 45, 20480, 16838, 5758), "")
	input.camera_zone = null
	assert_eq(camera.step(input), "")
	assert_eq(camera.snapshot().zone_index, before.zone_index)
	assert_eq(camera.snapshot().move_timer, 45)
	assert_eq(camera.snapshot().tracked_world, before.tracked_world)
	assert_eq(camera.snapshot().shake_timer, 44)

func test_invalid_zone_step_and_manual_lookup_do_not_mutate() -> void:
	var camera: GameplayCamera = GameplayCamera.create(GameplayCameraDefinition.new(), Vector3i.ZERO)
	var before: String = JSON.stringify(TerrainTrace.facts(camera.snapshot()))
	assert_string_contains(camera.request_turn(1, true), "consumed")
	var input := GameplayCameraTick.new()
	input.camera_zone = _zone()
	input.camera_zone.camera_offsets.clear()
	assert_false(camera.step(input).is_empty())
	assert_eq(JSON.stringify(TerrainTrace.facts(camera.snapshot())), before)

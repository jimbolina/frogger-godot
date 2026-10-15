extends GutTest
## Bounded inspection rejects unsupported positions and zones without mutation.

func _guard() -> ExplorationGuard:
	var guard := ExplorationGuard.new()
	guard.world_bounds = Rect2i(1900, -5376, 404, 512)
	var zone := ZoneDefinition.new()
	zone.source_id = "JUN1.MAP"
	zone.build_id = "pc-retail-v3.0e"
	zone.resource_id = 656
	zone.zone_index = 15
	zone.source_offset = 11200
	zone.bounds = PackedInt32Array([4, 3, 23, 4])
	zone.regions.append(PackedInt32Array([11, 3, 23, 4]))
	guard.zones.append(zone)
	return guard

func test_half_open_world_bounds_and_source_zone_location() -> void:
	var guard: ExplorationGuard = _guard()
	assert_eq(guard.validate(), "")
	assert_eq(guard.check_world(Vector3i(1900, 0, -5376)), "")
	assert_eq(guard.check_world(Vector3i(2303, 0, -4865)), "")
	assert_string_contains(guard.check_world(Vector3i(2304, 0, -5000)), "X[1900,2304)")
	assert_string_contains(guard.check_world(Vector3i(2000, 0, -4864)), "Z[-5376,-4864)")
	assert_eq(guard.check_cell(Vector2i(12, 2)), "")
	assert_eq(guard.check_cell(Vector2i(10, 3)), "")
	var message: String = guard.check_cell(Vector2i(11, 3))
	assert_string_contains(message, "JUN1.MAP")
	assert_string_contains(message, "ZONE[15]")
	assert_string_contains(message, "offset 11200")
	assert_string_contains(guard.check_cell(Vector2i(23, 4)), "active camera zone")

func test_validation_duplicate_unknown_and_copy_detaches_nested_bounds() -> void:
	var guard: ExplorationGuard = _guard()
	var detached: ExplorationGuard = guard.copy()
	guard.zones[0].bounds[0] = 99
	guard.zones[0].regions[0][0] = 99
	assert_eq(detached.zones[0].bounds[0], 4)
	assert_eq(detached.zones[0].regions[0][0], 11)
	guard = _guard()
	guard.zones.append(guard.zones[0].copy())
	assert_string_contains(guard.validate(), "duplicate authored zone")
	guard = _guard()
	guard.zones[0].zone_type = 7
	assert_string_contains(guard.validate(), "ZONE[15]")
	guard = _guard()
	guard.zones[0].regions[0] = PackedInt32Array([1, 2, 3])
	assert_string_contains(guard.validate(), "child bounds")
	guard = _guard()
	guard.world_bounds = Rect2i(0, 0, 0, 1)
	assert_string_contains(guard.validate(), "positive")

func test_animated_admission_rejects_unproved_roots_actions_and_powerups() -> void:
	var guard := ExplorationGuard.new()
	guard.world_bounds = Rect2i(-512, -128, 1024, 608)
	guard.frog_roots.append(PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096]))
	guard.frog_actions = PackedInt32Array([16])
	var state := RunSnapshot.new()
	state.animation = FrogAnimationState.new()
	state.animation.action = 16
	assert_eq(guard.check_frog(state), "")
	state.matrix12[0] = 4095
	assert_string_contains(guard.check_frog(state), "root")
	state.matrix12[0] = 4096
	state.animation.action = 18
	assert_string_contains(guard.check_frog(state), "action")
	state.mode = 2
	assert_eq(guard.check_frog(state), "", "Dying skips primitive collision before death animation")
	state.powerup_flags = 1
	assert_string_contains(guard.check_frog(state), "unpowered")
	var detached: ExplorationGuard = guard.copy()
	guard.frog_roots[0][0] = 2
	guard.frog_actions[0] = 3
	assert_eq(detached.frog_roots[0][0], 4096)
	assert_eq(detached.frog_actions[0], 16)

extends GutTest
## Source polygon allocation affects entity visitation before renderer resource checks.

class RejectFinal extends TickGuard:
	func check(phase: Phase, _candidate: TickGuardCandidate) -> String:
		return "Allocation final rejected" if phase == Phase.FINAL else ""

func _definition(counts: PackedInt32Array) -> EntityLifecycleDefinition:
	var definition := EntityLifecycleDefinition.new()
	definition.polygon_counts = counts
	return definition

func test_expansion_visits_oversized_group_then_stops_at_exact_exhaustion() -> void:
	var result: MapGroupVisibilityResult = MapGroupAllocation.expand(_definition(PackedInt32Array([2000, 600, 500, 1])), PackedInt32Array([0, 1, 2, 3]), PackedInt32Array())
	assert_eq(result.error, "")
	assert_eq(result.groups, PackedInt32Array([0, 1, 2]))
	assert_eq(result.group_timers, PackedInt32Array([2, 0, 2, 0]))

func test_retiring_group_is_charged_without_refresh_and_can_allocate_again() -> void:
	var definition: EntityLifecycleDefinition = _definition(PackedInt32Array([2000, 500, 1]))
	var prior := PackedInt32Array([1, 2, 0])
	var result: MapGroupVisibilityResult = MapGroupAllocation.expand(definition, PackedInt32Array([0, 1, 2]), prior)
	assert_eq(result.groups, PackedInt32Array([0, 1]))
	assert_eq(result.group_timers, PackedInt32Array([0, 2, 0]))
	assert_eq(prior, PackedInt32Array([1, 2, 0]))
	var recreated: MapGroupVisibilityResult = MapGroupAllocation.expand(definition, PackedInt32Array([0]), result.group_timers)
	assert_eq(recreated.group_timers, PackedInt32Array([2, 1, 0]))
	var expired: MapGroupVisibilityResult = MapGroupAllocation.expand(definition, PackedInt32Array(), recreated.group_timers)
	assert_eq(expired.group_timers, PackedInt32Array([1, 0, 0]))

func test_full_pool_still_visits_entities_and_zero_polygon_groups() -> void:
	var counts := PackedInt32Array()
	counts.resize(130)
	counts.fill(1)
	counts[129] = 0
	var timers := PackedInt32Array()
	timers.resize(130)
	for index: int in 128:
		timers[index] = 2
	var result: MapGroupVisibilityResult = MapGroupAllocation.expand(_definition(counts), PackedInt32Array([128, 129]), timers)
	assert_eq(result.groups, PackedInt32Array([128, 129]))
	assert_eq(result.group_timers[128], 0)
	assert_eq(result.group_timers[129], 0)
	assert_eq(result.group_timers[0], 1)

func test_corrupt_candidate_state_is_rejected_without_mutation() -> void:
	var definition: EntityLifecycleDefinition = _definition(PackedInt32Array([1]))
	var invalid := PackedInt32Array([4])
	assert_ne(MapGroupAllocation.expand(definition, PackedInt32Array([0]), invalid).error, "")
	assert_eq(invalid, PackedInt32Array([4]))
	assert_ne(MapGroupAllocation.expand(definition, PackedInt32Array([1]), PackedInt32Array()).error, "")

func test_late_tick_rejection_restores_allocation_and_retry_matches_clean_run() -> void:
	var level: LevelDefinition = TerrainScenario.builtin("normal").level
	level.collision_enabled = true
	level.camera = GameplayCameraDefinition.new()
	level.camera.source_offset = Vector3i(0, -512, -512)
	level.entity_collision = EntityCollisionDefinition.new()
	level.entity_collision.group_base = Vector3i(-4096, 0, -4096)
	level.entity_collision.group_dimensions = Vector2i.ONE
	level.entity_collision.group_size = Vector2i(8192, 8192)
	var lifecycle: EntityLifecycleDefinition = _definition(PackedInt32Array([2500]))
	lifecycle.group_base = Vector3i(-4096, 0, -4096)
	lifecycle.group_dimensions = Vector2i.ONE
	lifecycle.group_size = Vector2i(8192, 8192)
	lifecycle.source_allocation = true
	level.entity_collision.lifecycle = lifecycle
	var run: GameplayRun = GameplayRun.create(level)
	var clean: GameplayRun = GameplayRun.create(level)
	assert_eq(run.error, "")
	assert_eq(clean.error, "")
	if not run.error.is_empty() or not clean.error.is_empty():
		return
	run._tick_guard = RejectFinal.new()
	var command := TickCommand.new()
	var rejected: TickResult = run.step(command)
	assert_eq(rejected.error, "Allocation final rejected")
	assert_true(run.snapshot().entities.map_group_timers.is_empty())
	run._tick_guard = null
	var retry: TickResult = run.step(command)
	var expected: TickResult = clean.step(command)
	assert_eq(retry.error, "")
	assert_eq(expected.error, "")
	if not retry.error.is_empty() or not expected.error.is_empty():
		return
	assert_eq(retry.final_snapshot.entities.map_group_timers, PackedInt32Array([2]))
	assert_eq(TerrainTrace.facts(retry.final_snapshot, true), TerrainTrace.facts(expected.final_snapshot, true))

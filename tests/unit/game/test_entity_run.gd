extends GutTest
## Asset-free entity path attachment, transform and ownership checks.

func _path(start_x: int = 0, end_x: int = 100) -> PathDefinition:
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 100
	segment.start = Vector3i(start_x, 0, 0)
	segment.end = Vector3i(end_x, 0, 0)
	var result := PathDefinition.new()
	result.segments.append(segment)
	return result

func _moving(index: int, path: PathDefinition, speed: int = 10, flags: int = 0) -> EntityDefinition:
	var result := EntityDefinition.new()
	result.entity_name = "MOVING"
	result.entity_index = index
	result.unique_id = 7
	result.flags = flags
	result.path_definition = path
	result.path_start = PathStart.new()
	result.path_start.speed = speed
	return result

func _static(index: int) -> EntityDefinition:
	var result := EntityDefinition.new()
	result.entity_name = "STATIC"
	result.entity_index = index
	result.unique_id = 7
	result.matrix12[9] = 73
	return result

func test_advanced_fork_and_failed_tick_leave_source_and_public_snapshots_detached() -> void:
	var run: EntityRun = EntityRun.create([_moving(0, _path())])
	var saved: EntityRunSnapshot = run.snapshot()
	var fork: EntityRun = run.advanced_copy(0)
	assert_eq(fork.error, "")
	assert_eq(fork.snapshot().entities[0].path.position.x, 10)
	assert_eq(run.snapshot().tick_index, 0)
	saved.entities[0].matrix12[9] = 999
	assert_eq(run.snapshot().entities[0].matrix12[9], 0)
	assert_ne(fork.advanced_copy(99).error, "")
	assert_eq(fork.snapshot().tick_index, 1)
	assert_eq(fork.step(1), "")
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().entities[0].path.position.x, 10)
	assert_eq(fork.snapshot().entities[0].path.position.x, 20)

func test_independent_runners_source_order_and_authored_indices() -> void:
	var shared: PathDefinition = _path()
	var a: EntityDefinition = _moving(2, shared, 10)
	var b: EntityDefinition = _moving(5, shared, 20)
	var run: EntityRun = EntityRun.create([a, b])
	assert_eq(run.error, "")
	assert_eq(run.snapshot().entities[0].entity_index, 2)
	assert_eq(run.snapshot().entities[1].entity_index, 5)
	assert_eq(run.snapshot().entities[0].unique_id, 7)
	assert_eq(run.snapshot().entities[1].unique_id, 7)
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().entities[0].path.position, Vector3i(10, 0, 0))
	assert_eq(run.snapshot().entities[1].path.position, Vector3i(20, 0, 0))
	assert_eq(run.snapshot().entities[0].matrix12[9], 10)
	assert_eq(run.snapshot().entities[1].matrix12[9], 20)

func test_static_stopped_and_stationary_path() -> void:
	var still: EntityDefinition = _static(0)
	var paused: EntityDefinition = _moving(1, _path(), 10, EntityDefinition.NO_MOVEMENT)
	paused.path_start.distance = 30
	var stationary: EntityDefinition = _moving(2, _path(), 0)
	stationary.path_start.distance = 40
	stationary.path_start.flags = PathStart.REPEAT
	var run: EntityRun = EntityRun.create([still, paused, stationary])
	assert_eq(run.error, "")
	assert_eq(run.snapshot().entities[0].matrix12[9], 73)
	assert_false(bool(run.snapshot().entities[1].path.flags & PathStart.ACTIVE))
	assert_true(bool(run.snapshot().entities[2].path.flags & PathStart.ACTIVE))
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().entities[0].matrix12[9], 73)
	assert_eq(run.snapshot().entities[1].path.position, Vector3i(30, 0, 0))
	assert_eq(run.snapshot().entities[2].path.position, Vector3i(40, 0, 0))

func test_backward_boundary_and_orientation() -> void:
	var backwards: EntityDefinition = _moving(0, _path(), 10)
	backwards.path_start.distance = 5
	backwards.path_start.flags = PathStart.BACKWARDS | PathStart.REPEAT
	var world: EntityDefinition = _moving(1, _path(), 10, EntityDefinition.ALIGN_TO_WORLD)
	world.path_start.distance = 90
	var run: EntityRun = EntityRun.create([backwards, world])
	assert_eq(run.error, "")
	assert_eq(run.snapshot().entities[0].matrix12, PackedInt32Array([0, 0, -4096, 0, 4096, 0, 4096, 0, 0, 5, 0, 0]))
	assert_eq(run.snapshot().entities[1].matrix12, PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 90, 0, 0]))
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().entities[0].path.segment_distance, 95)
	assert_eq(run.snapshot().entities[1].path.segment_distance, 0)
	assert_eq(run.snapshot().entities[1].matrix12[9], 0)

func test_degenerate_tangent_and_source_matrix_axes() -> void:
	var zero: EntityDefinition = _moving(0, _path(4, 4))
	var forward: EntityDefinition = _moving(1, _path())
	var run: EntityRun = EntityRun.create([zero, forward])
	assert_eq(run.error, "")
	assert_eq(run.snapshot().entities[0].matrix12, PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0]))
	assert_eq(run.snapshot().entities[1].matrix12, PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 0, 0, 0]))

func test_inputs_and_nested_snapshots_are_detached() -> void:
	var path: PathDefinition = _path()
	var definition: EntityDefinition = _moving(0, path)
	var run: EntityRun = EntityRun.create([definition])
	assert_eq(run.error, "")
	path.segments[0].end = Vector3i(1000, 0, 0)
	var fork: EntityRun = run.copy()
	definition.path_start.speed = 99
	definition.matrix12[9] = 800
	var state: EntityRunSnapshot = run.snapshot()
	state.entities[0].path.position = Vector3i(999, 999, 999)
	state.entities[0].matrix12[9] = 999
	state.entities.clear()
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().entities[0].path.position, Vector3i(10, 0, 0))
	assert_eq(fork.snapshot().tick_index, 0)
	assert_eq(fork.step(0), "")
	assert_eq(fork.step(1), "")
	assert_eq(fork.snapshot().entities[0].path.position, Vector3i(20, 0, 0))
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().entities[0].path.speed, 10)
	assert_eq(fork.snapshot().entities[0].path.position, Vector3i(20, 0, 0))

func test_invalid_definitions_and_failed_create_reset() -> void:
	var bad: EntityDefinition = _moving(0, _path())
	bad.flags = EntityDefinition.LOCAL_ALIGN
	var run: EntityRun = EntityRun.create([bad])
	assert_false(run.error.is_empty())
	assert_eq(run.snapshot(), null)
	assert_false(run.reset().is_empty())
	bad.flags = EntityDefinition.PROJECT_ON_LAND
	assert_false(EntityRun.create([bad]).error.is_empty())
	bad.flags = 128
	assert_false(EntityRun.create([bad]).error.is_empty())
	bad.flags = 0
	bad.path_start.distance = 101
	assert_false(EntityRun.create([bad]).error.is_empty())
	bad.path_start.distance = 0
	bad.entity_name = "UNKNOWN"
	assert_false(EntityRun.create([bad]).error.is_empty())
	var first: EntityDefinition = _static(2)
	var duplicate: EntityDefinition = _static(2)
	assert_false(EntityRun.create([first, duplicate]).error.is_empty())
	duplicate.entity_index = 1
	assert_false(EntityRun.create([first, duplicate]).error.is_empty())

func test_failed_step_and_reset_preserve_all_cursors() -> void:
	var run: EntityRun = EntityRun.create([_moving(0, _path(), 10), _moving(1, _path(), 20)])
	assert_eq(run.error, "")
	assert_eq(run.step(0), "")
	var before: EntityRunSnapshot = run.snapshot()
	assert_false(run.step(0).is_empty())
	assert_eq(run.snapshot().tick_index, before.tick_index)
	assert_eq(run.snapshot().entities[0].path.segment_distance, before.entities[0].path.segment_distance)
	assert_eq(run.snapshot().entities[1].path.segment_distance, before.entities[1].path.segment_distance)
	run._definitions[1].path_start.distance = 101
	assert_false(run.reset().is_empty())
	assert_eq(run.snapshot().tick_index, before.tick_index)
	assert_eq(run.snapshot().entities[0].path.segment_distance, before.entities[0].path.segment_distance)
	assert_eq(run.snapshot().entities[1].path.segment_distance, before.entities[1].path.segment_distance)
	assert_eq(run.step(1), "")
	assert_eq(run.snapshot().entities[0].path.segment_distance, 20)
	assert_eq(run.snapshot().entities[1].path.segment_distance, 40)

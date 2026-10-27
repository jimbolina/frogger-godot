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
	result.behavior = EntityBehaviorCatalog.resolve(result.entity_name)
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
	result.behavior = EntityBehaviorCatalog.resolve(result.entity_name)
	result.entity_index = index
	result.unique_id = 7
	result.matrix12[9] = 73
	return result

func test_advanced_fork_and_failed_tick_leave_source_and_public_snapshots_detached() -> void:
	var run: EntityRun = EntityRun.create([_moving(0, _path())])
	var saved: EntityRunSnapshot = run.snapshot()
	var fork: EntityRun = run.begin_candidate(0)
	assert_eq(fork.error, "")
	assert_eq(fork.snapshot().entities[0].path.position.x, 10)
	assert_eq(run.snapshot().tick_index, 0)
	saved.entities[0].matrix12[9] = 999
	assert_eq(run.snapshot().entities[0].matrix12[9], 0)
	assert_ne(fork.begin_candidate(99).error, "")
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
	bad.behavior = EntityBehaviorCatalog.resolve(bad.entity_name)
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

func test_candidate_commit_consumes_candidate_and_detaches_observations() -> void:
	var run: EntityRun = EntityRun.create([_moving(0, _path())])
	var candidate: EntityRun = run.begin_candidate(0)
	var observation: EntityRunSnapshot = candidate.snapshot()
	run.commit_candidate(candidate)
	assert_null(candidate.snapshot())
	assert_ne(candidate.reset(), "")
	observation.entities[0].matrix12[9] = 999
	assert_eq(run.snapshot().tick_index, 1)
	assert_eq(run.snapshot().entities[0].matrix12[9], 10)
	assert_eq(run.step(1), "")
	assert_eq(run.snapshot().entities[0].matrix12[9], 20)

func test_resolved_behavior_is_independent_of_diagnostic_name_and_setup_mutation() -> void:
	var definition: EntityDefinition = _moving(0, _path())
	definition.entity_name = "diagnostic alias"
	var run: EntityRun = EntityRun.create([definition])
	assert_eq(run.error, "")
	definition.behavior.layout = EntityBehavior.Layout.MATRIX
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().entities[0].path.position.x, 10)

func test_script_path_pause_is_transactional_and_resume_uses_next_path_tick() -> void:
	var definition: EntityDefinition = _moving(0, _path())
	var script := EntityScriptDefinition.new()
	script.root_id = 1
	script.names[1] = "SCRIPT_TURTLE"
	script.programs[1] = PackedInt32Array([15, 0, 0, 2, 16, 6])
	definition.script_definition = script
	var run: EntityRun = EntityRun.create([definition])
	assert_eq(run.error, "")
	var context := EntityUpdateContext.new()
	context.has_path = true
	context.path_flags = 123
	var random: SourceRandom = SourceRandom.create(1)
	var candidate: EntityRun = run.begin_candidate(0)
	assert_eq(candidate.update_candidate_script(0, context, random).error, "")
	assert_eq(context.path_flags, 123, "Caller context stays detached")
	assert_true(bool(run.snapshot().entities[0].path.flags & PathStart.ACTIVE))
	assert_false(bool(candidate.snapshot().entities[0].path.flags & PathStart.ACTIVE))
	assert_eq(run.snapshot().entities[0].path.position.x, 0)
	run.commit_candidate(candidate)
	for tick: int in [1, 2]:
		candidate = run.begin_candidate(tick)
		assert_eq(candidate.update_candidate_script(0, context, random).error, "")
		assert_eq(candidate.snapshot().entities[0].path.position.x, 10)
		run.commit_candidate(candidate)
	assert_true(bool(run.snapshot().entities[0].path.flags & PathStart.ACTIVE))
	assert_eq(run.step(3), "")
	assert_eq(run.snapshot().entities[0].path.position.x, 20)

func test_selective_reset_preserves_unselected_paths_and_global_clock() -> void:
	var checkpoint: EntityDefinition = _moving(0, _path())
	checkpoint.form_flags = 8
	var death: EntityDefinition = _moving(1, _path())
	death.form_flags = 16
	var retained: EntityDefinition = _moving(2, _path())
	var run: EntityRun = EntityRun.create([checkpoint, death, retained])
	assert_eq(run.step(0), "")
	assert_eq(run.reset_in_level(true), "")
	var state: EntityRunSnapshot = run.snapshot()
	assert_eq(state.tick_index, 1)
	assert_eq(state.entities[0].path.segment_distance, 0)
	assert_eq(state.entities[1].path.segment_distance, 10)
	assert_eq(state.entities[2].path.segment_distance, 10)
	assert_eq(state.entities[0].generation, 1)
	assert_eq(state.entities[1].generation, 0)
	assert_eq(run.step(1), "")
	assert_eq(run.reset_in_level(false), "")
	state = run.snapshot()
	assert_eq(state.tick_index, 2)
	assert_eq(state.entities[0].path.segment_distance, 10)
	assert_eq(state.entities[1].path.segment_distance, 0)
	assert_eq(state.entities[2].path.segment_distance, 20)
	assert_eq(state.entities[1].generation, 1)

func test_selective_reset_retains_runtime_pause_and_candidate_isolation() -> void:
	var definition: EntityDefinition = _moving(0, _path())
	definition.form_flags = 16
	var run: EntityRun = EntityRun.create([definition])
	assert_eq(run.step(0), "")
	var candidate: EntityRun = run.copy()
	var target: EntitySnapshot = candidate.entity_snapshot(0)
	target.entity_flags |= EntityDefinition.NO_MOVEMENT
	candidate.apply_tongue_target(target)
	assert_eq(candidate.reset_in_level(false), "")
	assert_eq(candidate.snapshot().entities[0].path.flags & PathStart.ACTIVE, 0)
	assert_eq(candidate.snapshot().entities[0].path.segment_distance, 0)
	assert_eq(run.snapshot().entities[0].path.segment_distance, 10)
	assert_ne(run.snapshot().entities[0].path.flags & PathStart.ACTIVE, 0)

func test_selective_reset_recreates_static_script_and_pose_only_when_selected() -> void:
	var selected: EntityDefinition = _static(0)
	selected.form_flags = 8
	var retained: EntityDefinition = _static(1)
	var script := EntityScriptDefinition.new()
	script.root_id = 1
	script.programs[1] = PackedInt32Array([5])
	script.names[1] = "test"
	selected.script_definition = script
	retained.script_definition = script
	var run: EntityRun = EntityRun.create([selected, retained])
	for slot: int in 2:
		var target: EntitySnapshot = run.entity_snapshot(slot)
		target.matrix12[9] = 900
		target.script_state.timer = 44
		run.apply_tongue_target(target)
	assert_eq(run.reset_in_level(true), "")
	assert_eq(run.snapshot().entities[0].matrix12[9], 73)
	assert_eq(run.snapshot().entities[0].script_state.timer, 0)
	assert_eq(run.snapshot().entities[1].matrix12[9], 900)
	assert_eq(run.snapshot().entities[1].script_state.timer, 44)

func test_collected_checkpoint_recreation_omits_animation_and_collision() -> void:
	var checkpoint: EntityDefinition = _static(0)
	checkpoint.form_id = 0
	checkpoint.form_flags = 8 | 16
	checkpoint.behavior.kind = EntityBehavior.Kind.CHECKPOINT
	checkpoint.behavior.execution = EntityBehavior.Execution.CONTACT
	checkpoint.action_lengths = PackedInt32Array([4, 4, 4])
	var run: EntityRun = EntityRun.create([checkpoint])
	assert_eq(run.error, "")
	assert_not_null(run.snapshot().entities[0].animation)
	var environment := EntityEnvironmentState.new()
	environment.collected = 1
	var candidate: EntityRun = run.copy()
	assert_eq(candidate.reset_in_level(true, environment), "")
	var recreated: EntitySnapshot = candidate.snapshot().entities[0]
	assert_null(recreated.animation)
	assert_eq(recreated.live_flags, 0)
	assert_true(recreated.custom_state.model_hidden)
	assert_eq(recreated.entity_flags & (EntityDefinition.NO_COLLISION | EntityDefinition.NO_DISPLAY | EntityDefinition.HIDDEN), EntityDefinition.NO_COLLISION | EntityDefinition.NO_DISPLAY | EntityDefinition.HIDDEN)
	assert_not_null(run.snapshot().entities[0].animation)
	assert_eq(run.snapshot().entities[0].entity_flags & EntityDefinition.NO_COLLISION, 0)
	environment.collected = 0
	assert_eq(candidate.reset_in_level(false, environment), "")
	assert_not_null(candidate.snapshot().entities[0].animation)
	assert_eq(candidate.snapshot().entities[0].entity_flags & (EntityDefinition.NO_COLLISION | EntityDefinition.NO_DISPLAY | EntityDefinition.HIDDEN), 0)

func test_selective_croc_retirement_releases_checkpoint_coverage() -> void:
	var checkpoint: EntityDefinition = _static(0)
	checkpoint.form_id = 3
	checkpoint.behavior.kind = EntityBehavior.Kind.CHECKPOINT
	checkpoint.behavior.execution = EntityBehavior.Execution.CONTACT
	var croc: EntityDefinition = _static(1)
	croc.form_flags = 16
	croc.behavior.kind = EntityBehavior.Kind.CROC_HEAD
	croc.behavior.execution = EntityBehavior.Execution.CONTACT
	var run: EntityRun = EntityRun.create([checkpoint, croc])
	var environment := EntityEnvironmentState.new()
	environment.covered = 8
	environment.collision_disabled = 8
	run.apply_checkpoint_collision(8)
	var target: EntitySnapshot = run.entity_snapshot(1)
	target.custom_state.checkpoint_index = 3
	run.apply_tongue_target(target)
	assert_eq(run.reset_in_level(false, environment), "")
	assert_eq(environment.covered, 0)
	assert_eq(environment.collision_disabled, 0)
	assert_eq(run.snapshot().entities[0].entity_flags & EntityDefinition.NO_COLLISION, 0)

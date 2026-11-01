extends GutTest
## Source lawnmower creation, prior-pose visits, land projection and selective reset.

func _definition(flags: int = 0) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 3
	definition.entity_name = "SUB_LAWNMOWER"
	definition.behavior = EntityBehaviorCatalog.resolve(definition.entity_name)
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.flags = flags
	definition.form_flags = 24
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 200
	segment.start = Vector3i(-100, 0, 0)
	segment.end = Vector3i(100, 0, 0)
	definition.path_definition = PathDefinition.new()
	definition.path_definition.segments.append(segment)
	definition.path_start = PathStart.new()
	definition.path_start.speed = 10
	definition.path_start.flags = PathStart.ACTIVE
	return definition

func _lifecycle() -> EntityLifecycleDefinition:
	var result := EntityLifecycleDefinition.new()
	result.group_base = Vector3i(-4096, 0, -4096)
	result.group_dimensions = Vector2i.ONE
	result.group_size = Vector2i(8192, 8192)
	result.polygon_counts = PackedInt32Array([0])
	return result

func _camera() -> GameplayCameraSnapshot:
	var result := GameplayCameraSnapshot.new()
	result.source_world = Vector3i(0, -500, -500)
	result.axis_x_12 = Vector3i(4096, 0, 0)
	result.axis_y_12 = Vector3i(0, 2896, -2896)
	result.axis_z_12 = Vector3i(0, 2896, 2896)
	return result

func _environment() -> EntityEnvironmentState:
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	return environment

func _sloped_grid(square_count: int = 1) -> GridDefinition:
	var grid := GridDefinition.new()
	grid.dimensions = Vector2i(2, 2)
	grid.base = Vector2i(-256, -256)
	for index: int in 4:
		var stack := GridStackDefinition.new()
		stack.first_square_index = grid.squares.size()
		stack.square_count = square_count
		grid.stacks.append(stack)
		for layer: int in square_count:
			var square := GridSquareDefinition.new()
			var x: int = -256 + (index % 2) * 256
			var z: int = -256 + (index >> 1) * 256
			square.vertices = [Vector3i(x, -(x >> 2) - 64, z + 256), Vector3i(x + 256, -((x + 256) >> 2) - 64, z + 256), Vector3i(x, -(x >> 2) - 64, z), Vector3i(x + 256, -((x + 256) >> 2) - 64, z)]
			grid.squares.append(square)
	return grid

func test_setup_reads_path_info_alone_and_runs_a_contact_update() -> void:
	var behavior: EntityBehavior = EntityBehaviorCatalog.resolve("SUB_LAWNMOWER")
	assert_eq(behavior.kind, EntityBehavior.Kind.SUB_LAWNMOWER)
	assert_eq(behavior.layout, EntityBehavior.Layout.PATH)
	assert_false(behavior.immortal)
	assert_true(behavior.group_moving)
	assert_false(behavior.tongueable)
	assert_true(behavior.has_form_contact())
	behavior.execution = EntityBehavior.Execution.UPDATE
	assert_true(behavior.has_custom_update())

func test_visit_keeps_the_prior_pose_while_the_path_runs_through_the_chop() -> void:
	var run: EntityRun = EntityRun.create([_definition()], _lifecycle())
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	assert_eq(run.apply_visibility(_camera()), "")
	var created: EntitySnapshot = run.snapshot().entities[0]
	assert_true(created.live)
	assert_eq(created.custom_state.mode, EntityLawnmower.Mode.MOWING)
	assert_eq(created.matrix12[9], -100)
	var random: SourceRandom = SourceRandom.create(1)
	for tick: int in 3:
		var candidate: EntityRun = run.begin_candidate(tick, -1, true)
		assert_eq(candidate.error, "")
		var before: PackedInt32Array = candidate.snapshot().entities[0].matrix12
		assert_true(candidate.begin_update(0, -1))
		assert_eq(candidate.snapshot().entities[0].matrix12, before, "The visit keeps the prior pose")
		assert_eq(before[9], -100 + tick * 10)
		var result: EntityCustomResult = candidate.update_custom(3, _environment(), random, Vector3i.ZERO, tick == 0)
		assert_eq(result.error, "")
		random = result.random
		assert_eq(result.path_active_request, -1, "The mower never pauses its path")
		assert_eq(result.entity.matrix12[9], -90 + tick * 10)
		if tick == 1:
			assert_eq(result.frog_matrix12, PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 38, 0, 0]), "Chop uses the pose before this tick's path step")
		else:
			assert_true(result.frog_matrix12.is_empty())
		run.commit_candidate(candidate)
	assert_eq(run.snapshot().entities[0].custom_state.mode, EntityLawnmower.Mode.DO_NOTHING)
	assert_eq(run.reset_in_level(false, _environment()), "")
	assert_false(run.snapshot().entities[0].live, "Frog death retires the mortal mower")
	assert_eq(run.apply_visibility(_camera()), "")
	var reset: EntitySnapshot = run.snapshot().entities[0]
	assert_true(reset.live)
	assert_eq(reset.custom_state.mode, EntityLawnmower.Mode.MOWING)
	assert_true(reset.custom_state.moving_sound.is_empty())
	assert_eq(reset.path.position, Vector3i(-100, 0, 0))

func test_projected_mower_closes_on_the_first_terrain_layer() -> void:
	var definition: EntityDefinition = _definition(EntityDefinition.PROJECT_ON_LAND)
	var run: EntityRun = EntityRun.create([definition])
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var grid: GridDefinition = _sloped_grid()
	var candidate: EntityRun = run.begin_candidate(0, -1, false, grid)
	assert_eq(candidate.error, "")
	var path: PathSnapshot = candidate.snapshot().entities[0].path
	assert_eq(candidate.snapshot().entities[0].matrix12, run.snapshot().entities[0].matrix12, "The step retains the mower's own pose")
	var result: EntityCustomResult = candidate.update_custom(3, _environment(), SourceRandom.create(1), Vector3i.ZERO, false, [], null, grid)
	assert_eq(result.error, "")
	var expected: PackedInt32Array = EntityTransform.moving_on_land(path, definition.flags, grid)
	assert_eq(result.entity.matrix12, expected)
	assert_ne(expected, EntityTransform.moving(path, definition.flags))
	var failed: EntityCustomResult = run.begin_candidate(0, -1, false, grid).update_custom(3, _environment(), SourceRandom.create(1), Vector3i.ZERO, false, [], null, _sloped_grid(0))
	assert_eq(failed.error, "Lawnmower projected path requires a valid first terrain square")
	assert_null(failed.entity)

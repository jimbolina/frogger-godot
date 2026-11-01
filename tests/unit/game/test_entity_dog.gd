extends GutTest
## Source dog wait, random fall, bite ordering and private candidate ownership.

func _definition() -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 0
	definition.behavior = EntityBehaviorCatalog.resolve("SUB_DOG")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	definition.authored_delay = 2
	definition.action_lengths = PackedInt32Array([8, 12, 10])
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 1000
	segment.end = Vector3i(0, 0, 1000)
	definition.path_definition = PathDefinition.new()
	definition.path_definition.segments.append(segment)
	definition.path_start = PathStart.new()
	definition.path_start.flags = PathStart.ACTIVE
	return definition

func _state() -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.custom_state = EntityCustomState.new()
	entity.custom_state.timer = 2
	entity.path = PathSnapshot.new()
	entity.path.tangent = Vector3i(0, 0, 4096)
	entity.animation = EntityAnimationState.create([8, 12, 10])
	return entity

func _update(entity: EntitySnapshot, seed: int = 1, hit: bool = false, frog: GameplayState = null) -> EntityCustomResult:
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	return EntityCustomUpdate.update(_definition(), entity, environment, SourceRandom.create(seed), Vector3i.ZERO, hit, false, null, null, frog)

func test_wait_uses_postdecrement_and_active_frog_strict_bark_radius() -> void:
	var entity: EntitySnapshot = _state()
	var frog := GameplayState.new()
	frog.frog.flags = FrogFlags.ACTIVE
	for tick: int in 3:
		var result: EntityCustomResult = _update(entity, 1, false, frog)
		assert_eq(result.error, "")
		assert_eq(result.random.draw_count, 0)
		assert_eq(result.entity.custom_state.mode, EntityDog.Mode.WAITING if tick < 2 else EntityDog.Mode.WALKING)
		entity = result.entity
	assert_eq(entity.custom_state.timer, 4294967295)
	assert_eq(TickEvent.trace_lines(entity.requests), ["sound:153:0:0:0"])
	for distance: int in [1023, 1024]:
		entity = _state()
		entity.custom_state.timer = 0
		frog.frog.matrix12[9] = distance
		assert_eq(_update(entity, 1, false, frog).entity.requests.size(), 1 if distance == 1023 else 0)
	frog.frog.flags = 0
	assert_true(_update(entity, 1, false, frog).entity.requests.is_empty())
	frog.frog.flags = FrogFlags.ACTIVE
	for axis: int in 3:
		frog.frog.matrix12[9 + axis] = 32767
	assert_eq(_update(entity, 1, false, frog).entity.requests.size(), 1)

func test_bounce_wait_and_hit_override_fall_in_source_order() -> void:
	var entity: EntitySnapshot = _state()
	entity.custom_state.mode = EntityDog.Mode.WALKING
	entity.path.flags = PathStart.JUST_BOUNCED_END
	var result: EntityCustomResult = _update(entity)
	assert_eq(result.error, "")
	assert_eq(result.entity.custom_state.mode, EntityDog.Mode.WAITING)
	assert_eq(result.entity.custom_state.timer, 2)
	assert_eq(result.path_active_request, 0)
	assert_eq(result.random.draw_count, 1)
	result = _update(entity, 1, true)
	assert_eq(result.entity.custom_state.mode, EntityDog.Mode.BITING)
	assert_eq(result.entity.animation.action, 2)
	assert_eq(result.entity.custom_state.count, 50)
	assert_eq(result.frog_matrix12, PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 0, 0, 192]))
	assert_eq(TickEvent.trace_lines(result.entity.requests), ["sound:154:0:0:0"])
	assert_eq(entity.custom_state.mode, EntityDog.Mode.WALKING)
	assert_eq(entity.animation.action, 0)
	assert_eq(result.death_animation, -1)

func test_fall_and_bite_countdowns_resume_run_on_fiftieth_tick() -> void:
	for mode: int in [EntityDog.Mode.FALLING, EntityDog.Mode.BITING]:
		var entity: EntitySnapshot = _state()
		entity.custom_state.mode = mode
		entity.custom_state.timer = 50
		entity.custom_state.count = 50
		entity.animation.select(1 if mode == EntityDog.Mode.FALLING else 2)
		for tick: int in 50:
			var result: EntityCustomResult = _update(entity)
			assert_eq(result.error, "")
			assert_eq(result.random.draw_count, 0)
			assert_eq(result.entity.custom_state.mode, mode if tick < 49 else EntityDog.Mode.WALKING)
			if tick == 49:
				assert_eq(result.path_active_request, 1)
				assert_eq(result.entity.animation.action, 0)
			entity = result.entity

func test_random_fall_consumes_one_draw_even_on_bounce_and_hit_wins() -> void:
	var entity: EntitySnapshot = _state()
	entity.custom_state.mode = EntityDog.Mode.WALKING
	entity.path.flags = PathStart.JUST_BOUNCED_START
	var fallen: EntityCustomResult = _update(entity, 101)
	assert_eq(fallen.entity.custom_state.mode, EntityDog.Mode.FALLING)
	assert_eq(fallen.entity.custom_state.timer, 50)
	assert_eq(fallen.entity.animation.action, 1)
	assert_eq(fallen.random.draw_count, 1)
	assert_eq(fallen.path_active_request, 0)
	var bitten: EntityCustomResult = _update(entity, 101, true)
	assert_eq(bitten.entity.custom_state.mode, EntityDog.Mode.BITING)
	assert_eq(bitten.entity.animation.action, 2)
	assert_eq(bitten.random.state, fallen.random.state)

func test_creation_stops_path_and_reset_restores_authored_wait() -> void:
	var run: EntityRun = EntityRun.create([_definition()])
	assert_eq(run.error, "")
	assert_eq(run.snapshot().entities[0].custom_state.timer, 2)
	assert_eq(run.snapshot().entities[0].path.flags & PathStart.ACTIVE, 0)
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().entities[0].path.position, Vector3i.ZERO)
	assert_eq(run.reset(), "")
	assert_eq(run.snapshot().entities[0].custom_state.mode, EntityDog.Mode.WAITING)
	assert_eq(run.snapshot().entities[0].custom_state.timer, 2)

func test_invalid_animation_discards_outputs_without_mutating_inputs() -> void:
	var entity: EntitySnapshot = _state()
	entity.animation = EntityAnimationState.create([3])
	var result: EntityCustomResult = _update(entity, 1, true)
	assert_ne(result.error, "")
	assert_null(result.entity)
	assert_true(result.frog_matrix12.is_empty())
	assert_eq(entity.custom_state.timer, 2)

func test_selective_reset_recreates_dog_without_mutating_original_run() -> void:
	var definition: EntityDefinition = _definition()
	definition.form_flags = 16
	var run: EntityRun = EntityRun.create([definition])
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	var random: SourceRandom = SourceRandom.create(1)
	for tick: int in 4:
		assert_eq(run.step(tick), "")
		var result: EntityCustomResult = run.update_custom(0, environment, random, Vector3i.ZERO, false)
		assert_eq(result.error, "")
		random = result.random
	assert_gt(run.snapshot().entities[0].path.segment_distance, 0)
	var candidate: EntityRun = run.copy()
	assert_eq(candidate.reset_in_level(false), "")
	var reset: EntitySnapshot = candidate.snapshot().entities[0]
	assert_eq(reset.path.segment_distance, 0)
	assert_eq(reset.path.flags & PathStart.ACTIVE, 0)
	assert_eq(reset.custom_state.mode, EntityDog.Mode.WAITING)
	assert_eq(reset.custom_state.timer, 2)
	assert_gt(run.snapshot().entities[0].path.segment_distance, 0)
	assert_eq(run.snapshot().entities[0].custom_state.mode, EntityDog.Mode.WALKING)

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
			square.vertices = [Vector3i(x, -((z + 256) >> 2) - 64, z + 256), Vector3i(x + 256, -((z + 256) >> 2) - 64, z + 256), Vector3i(x, -(z >> 2) - 64, z), Vector3i(x + 256, -(z >> 2) - 64, z)]
			grid.squares.append(square)
	return grid

func test_projected_dog_bites_from_its_prior_pose_and_closes_on_the_land() -> void:
	var definition: EntityDefinition = _definition()
	definition.flags = EntityDefinition.PROJECT_ON_LAND
	var entity: EntitySnapshot = _state()
	entity.entity_flags = EntityDefinition.PROJECT_ON_LAND
	entity.custom_state.mode = EntityDog.Mode.WALKING
	entity.path.position = Vector3i(16, 0, 40)
	entity.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 16, -70, 24])
	var grid: GridDefinition = _sloped_grid()
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, environment, SourceRandom.create(1), Vector3i.ZERO, true, false, null, null, null, [], [], 0, grid)
	assert_eq(result.error, "")
	if not result.error.is_empty():
		return
	assert_eq(result.entity.custom_state.mode, EntityDog.Mode.BITING)
	assert_eq(result.frog_matrix12, PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 16, -70, 216]), "The bite reads the pose before the moving update")
	var expected: PackedInt32Array = EntityTransform.moving_on_land(entity.path, EntityDefinition.PROJECT_ON_LAND, grid)
	assert_eq(result.entity.matrix12, expected)
	assert_ne(expected, EntityTransform.moving(entity.path, EntityDefinition.PROJECT_ON_LAND))
	var failed: EntityCustomResult = EntityCustomUpdate.update(definition, entity, environment, SourceRandom.create(1), Vector3i.ZERO, true, false, null, null, null, [], [], 0, _sloped_grid(0))
	assert_eq(failed.error, "Dog projected path requires a valid first terrain square")
	assert_null(failed.entity)
	assert_eq(entity.custom_state.mode, EntityDog.Mode.WALKING)

func test_dog_visit_keeps_its_prior_pose_under_visibility_lifetime() -> void:
	var lifecycle := EntityLifecycleDefinition.new()
	lifecycle.group_base = Vector3i(-4096, 0, -4096)
	lifecycle.group_dimensions = Vector2i.ONE
	lifecycle.group_size = Vector2i(8192, 8192)
	lifecycle.polygon_counts = PackedInt32Array([0])
	var definition: EntityDefinition = _definition()
	definition.path_start.speed = 10
	var run: EntityRun = EntityRun.create([definition], lifecycle)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var camera := GameplayCameraSnapshot.new()
	camera.source_world = Vector3i(0, -500, -500)
	camera.axis_x_12 = Vector3i(4096, 0, 0)
	camera.axis_y_12 = Vector3i(0, 2896, -2896)
	camera.axis_z_12 = Vector3i(0, 2896, 2896)
	assert_eq(run.apply_visibility(camera), "")
	var environment := EntityEnvironmentState.new()
	environment.checkpoint_positions.resize(5)
	var random: SourceRandom = SourceRandom.create(1)
	for tick: int in 4:
		var candidate: EntityRun = run.begin_candidate(tick, -1, true)
		assert_eq(candidate.error, "")
		var before: PackedInt32Array = candidate.snapshot().entities[0].matrix12
		assert_true(candidate.begin_update(0, -1))
		assert_eq(candidate.snapshot().entities[0].matrix12, before)
		var hit: bool = tick == 3
		var result: EntityCustomResult = candidate.update_custom(0, environment, random, Vector3i.ZERO, hit)
		assert_eq(result.error, "")
		random = result.random
		if hit:
			assert_eq(result.frog_matrix12[11], before[11] + 192, "The bite offsets from the pose before this tick's path step")
			assert_ne(result.entity.matrix12[11], before[11])
		run.commit_candidate(candidate)

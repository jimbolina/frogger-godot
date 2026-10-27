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

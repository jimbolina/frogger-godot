extends GutTest
## Cave frogger light radii, fat fire fly bobbing and buzz, firefly callback and distance gate.

func _light(max_squared: int, min_squared: int, die: int) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 4
	definition.behavior = EntityBehavior.new()
	definition.behavior.kind = EntityBehavior.Kind.CAVE_LIGHT
	definition.behavior.execution = EntityBehavior.Execution.UPDATE
	definition.cave = EntityCaveDefinition.new()
	definition.cave.light_max_squared = max_squared
	definition.cave.light_min_squared = min_squared
	definition.cave.light_die = die
	return definition

func _fly(unique_id: int) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 7
	definition.unique_id = unique_id
	definition.behavior = EntityBehavior.new()
	definition.behavior.kind = EntityBehavior.Kind.FAT_FIRE_FLY
	definition.behavior.execution = EntityBehavior.Execution.UPDATE
	definition.matrix12 = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 1000, -200, 3000])
	return definition

func _environment(max_squared: int, min_squared: int) -> EntityEnvironmentState:
	var environment := EntityEnvironmentState.new()
	for index: int in 5:
		environment.checkpoint_positions.append(Vector3i.ZERO)
	environment.light_max_squared = max_squared
	environment.light_min_squared = min_squared
	return environment

func _result(environment: EntityEnvironmentState, random_seed: int = 1) -> EntityCustomResult:
	var result := EntityCustomResult.new()
	result.entity = EntitySnapshot.new()
	result.environment = environment
	result.random = SourceRandom.create(random_seed)
	return result

func _frog(position: Vector3i) -> GameplayState:
	var state := GameplayState.new()
	state.frog.mode = FrogMode.STATIONARY
	state.frog.flags = FrogFlags.ACTIVE
	state.frog.matrix12[9] = position.x
	state.frog.matrix12[10] = position.y
	state.frog.matrix12[11] = position.z
	return state

func test_initialize_seeds_band_with_unsigned_wrap_clamp() -> void:
	var entity := EntitySnapshot.new()
	entity.animation = EntityAnimationState.create([1])
	entity.live_flags = 5
	var environment: EntityEnvironmentState = _environment(0, 0)
	EntityCaveLight.initialize(_light(0x100000, 0x10000, 0), entity, environment)
	assert_eq(environment.light_max_squared, 0x100000)
	assert_eq(environment.light_min_squared, 0)
	assert_null(entity.animation)
	assert_eq(entity.live_flags, 0)
	EntityCaveLight.initialize(_light(0x40000, 0x10000, 0), entity, environment)
	assert_eq(environment.light_max_squared, 0x40000)
	assert_eq(environment.light_min_squared, 1)

func test_update_crops_then_decays_in_one_call() -> void:
	var result: EntityCustomResult = _result(_environment(0x300000, 0x200000))
	assert_eq(EntityCaveLight.update(_light(0x200000, 0x10000, 0x1000), result), "")
	assert_eq(result.environment.light_max_squared, 0x1FF000)
	assert_eq(result.environment.light_min_squared, 0xFF000)

func test_update_stops_at_minimum_radius() -> void:
	var result: EntityCustomResult = _result(_environment(0x50000, 0x1234))
	assert_eq(EntityCaveLight.update(_light(0x200000, 0x50000, 0x1000), result), "")
	assert_eq(result.environment.light_max_squared, 0x50000)
	assert_eq(result.environment.light_min_squared, 0x1234)

func test_update_decay_past_zero_wraps_unsigned() -> void:
	var result: EntityCustomResult = _result(_environment(0x80000, 0))
	assert_eq(EntityCaveLight.update(_light(0x200000, 0x10000, 0x90000), result), "")
	assert_eq(result.environment.light_max_squared, 0xFFFF0000)
	assert_eq(result.environment.light_min_squared, 0xFFEF0000)

func test_update_requires_radii_and_environment() -> void:
	var definition: EntityDefinition = _light(0x200000, 0x10000, 0x1000)
	assert_ne(EntityCaveLight.update(definition, _result(null)), "")
	definition.cave = null
	assert_ne(EntityCaveLight.update(definition, _result(_environment(0, 0))), "")

func test_custom_update_dispatches_light_on_private_environment() -> void:
	var environment: EntityEnvironmentState = _environment(0x300000, 0)
	var result: EntityCustomResult = EntityCustomUpdate.update(_light(0x200000, 0x10000, 0x1000), EntitySnapshot.new(), environment, SourceRandom.create(1), Vector3i.ZERO, false, true)
	assert_eq(result.error, "")
	assert_eq(result.environment.light_max_squared, 0x1FF000)
	assert_eq(environment.light_max_squared, 0x300000)

func test_fat_fire_fly_initializes_identity_at_authored_translation() -> void:
	var entity := EntitySnapshot.new()
	entity.matrix12 = PackedInt32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
	entity.animation = EntityAnimationState.create([1])
	EntityFatFireFly.initialize(_fly(3), entity)
	assert_eq(entity.matrix12, PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 1000, -200, 3000]))
	assert_null(entity.animation)

func test_fat_fire_fly_bobs_and_draws_once() -> void:
	var definition: EntityDefinition = _fly(3)
	var result: EntityCustomResult = _result(_environment(0, 0), 1)
	EntityFatFireFly.initialize(definition, result.entity)
	assert_eq(EntityFatFireFly.update(definition, result, _frog(Vector3i(1000, -129, 3000)), 0), "")
	assert_eq(result.entity.matrix12[10], -200 + (2276 >> 5))
	assert_eq(result.random.draw_count, 1)
	assert_eq(result.entity.requests.size(), 0)
	assert_eq(EntityFatFireFly.update(definition, result, _frog(Vector3i.ZERO), 1), "")
	assert_eq(result.entity.matrix12[10], -200 + (3406 >> 5))
	assert_eq(result.random.draw_count, 2)

func test_fat_fire_fly_buzz_requires_draw_and_distance() -> void:
	var definition: EntityDefinition = _fly(3)
	var near: EntityCustomResult = _result(_environment(0, 0), 11)
	EntityFatFireFly.initialize(definition, near.entity)
	assert_eq(EntityFatFireFly.update(definition, near, _frog(Vector3i(1000, -129, 3000)), 0), "")
	assert_eq(TickEvent.trace_lines(near.entity.requests), ["sound:0:0:0:0"])
	assert_eq(near.random.draw_count, 1)
	var far: EntityCustomResult = _result(_environment(0, 0), 11)
	EntityFatFireFly.initialize(definition, far.entity)
	assert_eq(EntityFatFireFly.update(definition, far, _frog(Vector3i(1000, -129, 6000)), 0), "")
	assert_eq(far.entity.requests.size(), 0)
	assert_eq(far.random.draw_count, 1)

func test_fat_fire_fly_without_movement_skips_bob_and_random() -> void:
	var definition: EntityDefinition = _fly(3)
	var result: EntityCustomResult = _result(_environment(0, 0), 11)
	EntityFatFireFly.initialize(definition, result.entity)
	result.entity.entity_flags |= EntityDefinition.NO_MOVEMENT
	assert_eq(EntityFatFireFly.update(definition, result, _frog(Vector3i(1000, -200, 3000)), 0), "")
	assert_eq(result.entity.matrix12[10], -200)
	assert_eq(result.random.draw_count, 0)
	assert_eq(result.entity.requests.size(), 0)

func test_firefly_callback_scores_and_raises_radii_raw() -> void:
	var frog := Frog.new()
	var state := GameplayState.new()
	var events: Array[TickEvent] = []
	assert_ne(FormCallback.apply(FormCallback.Kind.CAV_FIREFLY_SCORE, frog, state, 3, events), "")
	assert_eq(state.flow.score, 0)
	state.entity_environment = _environment(0xFFFFFFFC, 0x100)
	assert_eq(FormCallback.apply(FormCallback.Kind.CAV_FIREFLY_SCORE, frog, state, 3, events), "")
	assert_eq(state.flow.score, 250)
	assert_eq(state.entity_environment.light_max_squared, 4)
	assert_eq(state.entity_environment.light_min_squared, 0x108)

func test_distance_sound_gate() -> void:
	var entity := Vector3i(100, 0, 0)
	assert_true(EntityDistanceSound.within(entity, _frog(entity), 20))
	assert_true(EntityDistanceSound.within(entity, _frog(Vector3i(499, 0, 0)), 20))
	assert_false(EntityDistanceSound.within(entity, _frog(Vector3i(500, 0, 0)), 20))
	assert_false(EntityDistanceSound.within(entity, _frog(Vector3i(10100, 0, 0)), 20))
	assert_true(EntityDistanceSound.within(Vector3i(65636, 0, 0), _frog(entity), 20))
	var collected: GameplayState = _frog(entity)
	collected.frog.mode = FrogMode.CHECKPOINT_COLLECTED
	assert_false(EntityDistanceSound.within(entity, collected, 20))
	var over: GameplayState = _frog(entity)
	over.flow.phase = LevelFlowState.Phase.GAME_OVER
	assert_false(EntityDistanceSound.within(entity, over, 20))
	var inactive: GameplayState = _frog(entity)
	inactive.frog.flags = 0
	assert_false(EntityDistanceSound.within(entity, inactive, 3162))
	assert_true(EntityDistanceSound.within(entity, inactive, 3163))

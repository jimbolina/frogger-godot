extends GutTest
## Logical global effects and explicit limits of the supported background branches.

func _environment() -> EntityEnvironmentState:
	var environment := EntityEnvironmentState.new()
	for index: int in 5:
		environment.checkpoint_positions.append(Vector3i(1000 + index * 256, -100, 2000))
	return environment

func _entity(name: String) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 55
	definition.entity_name = name
	definition.behavior = EntityBehaviorCatalog.resolve(definition.entity_name)
	definition.behavior.execution = EntityBehavior.Execution.UPDATE
	return definition

func _snapshot() -> EntitySnapshot:
	var state := EntitySnapshot.new()
	state.custom_state = EntityCustomState.new()
	state.entity_flags = EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION
	state.custom_state.model_hidden = true
	return state

func test_fly_wait_appearance_covered_bits_and_source_rng() -> void:
	var definition: EntityDefinition = _entity("ORG_FLY")
	var state: EntitySnapshot = _snapshot()
	var environment: EntityEnvironmentState = _environment()
	var random: SourceRandom = SourceRandom.create(1)
	for tick: int in 61:
		var result: EntityCustomResult = EntityCustomUpdate.update(definition, state, environment, random, Vector3i.ZERO, false, false)
		assert_eq(result.error, "")
		if tick < 60:
			assert_eq(result.environment.covered, 0)
			assert_eq(result.random.draw_count, 0)
		else:
			assert_eq(result.entity.custom_state.mode, 1)
			assert_eq(result.entity.custom_state.timer, 120)
			assert_eq(result.random.state, 1103527590)
			assert_eq(result.entity.custom_state.checkpoint_index, 3)
			assert_eq(result.environment.covered, 8)
			assert_eq(result.entity.matrix12.slice(9), PackedInt32Array([1768, -356, 1950]))
			assert_eq(result.entity.entity_flags, 0)
		state = result.entity
		environment = result.environment
		random = result.random
	for tick: int in 121:
		var result: EntityCustomResult = EntityCustomUpdate.update(definition, state, environment, random, Vector3i.ZERO, false, false)
		assert_eq(result.error, "")
		state = result.entity
		environment = result.environment
		random = result.random
	assert_eq(environment.covered, 0)
	assert_eq(state.custom_state.mode, 0)
	assert_eq(state.custom_state.timer, 60)
	assert_eq(state.entity_flags, EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION)
	assert_eq(random.draw_count, 1)

func test_custom_failure_discards_candidate_and_baby_requires_live_parent() -> void:
	var state: EntitySnapshot = _snapshot()
	state.custom_state.timer = 0
	var environment: EntityEnvironmentState = _environment()
	environment.covered = 32
	var random: SourceRandom = SourceRandom.create(1)
	var result: EntityCustomResult = EntityCustomUpdate.update(_entity("ORG_FLY"), state, environment, random, Vector3i.ZERO, false, false)
	assert_ne(result.error, "")
	assert_null(result.entity)
	assert_eq(state.custom_state.timer, 0)
	assert_eq(environment.covered, 32)
	assert_eq(random.state, 1)
	environment.covered = 1
	result = EntityCustomUpdate.update(_entity("ORG_BABY_FROG"), state, environment, random, Vector3i.ZERO, false, true)
	assert_eq(result.error, "")
	assert_eq(result.entity.custom_state.mode, 5)
	assert_eq(result.entity.custom_state.search_count, 1)
	var next: EntityCustomResult = EntityCustomUpdate.update(_entity("ORG_BABY_FROG"), result.entity, environment, random, Vector3i.ZERO, false, true)
	assert_eq(next.entity.custom_state.search_count, 1)
	assert_ne(EntityCustomUpdate.update(_entity("ORG_BABY_FROG"), next.entity, environment, random, Vector3i.ZERO, false, false).error, "")
	assert_eq(EntityCustomUpdate.update(_entity("CHECKPOINT"), state, environment, random, Vector3i.ZERO, false, true).error, "")

func test_dynamic_collection_exclusion_uses_half_open_corridor_and_copies() -> void:
	var guard := ExplorationGuard.new()
	guard.world_bounds = Rect2i(-512, -128, 1024, 608)
	guard.collectable_indices = PackedInt32Array([53])
	var state := EntityRunSnapshot.new()
	var baby := EntitySnapshot.new()
	baby.entity_index = 53
	baby.matrix12[9] = 1152
	baby.matrix12[11] = 0
	state.entities.append(baby)
	assert_eq(guard.check_entities(state), "")
	baby.matrix12[9] = 1151
	assert_string_contains(guard.check_entities(state), "collection radius")
	baby.live = false
	assert_eq(guard.check_entities(state), "")
	var copied: ExplorationGuard = guard.copy()
	guard.collectable_indices.clear()
	assert_eq(copied.collectable_indices, PackedInt32Array([53]))
	state.entities.clear()
	assert_string_contains(copied.check_entities(state), "missing")

func test_checkpoint_croak_uses_3d_strict_radius_and_ground_cel() -> void:
	var definition: EntityDefinition = _entity("CHECKPOINT")
	var state: EntitySnapshot = _snapshot()
	state.animation = EntityAnimationState.create([4, 3, 5])
	state.animation.cel = 0
	var environment: EntityEnvironmentState = _environment()
	var random: SourceRandom = SourceRandom.create(11)
	for position: Vector3i in [Vector3i(512, 0, 0), Vector3i(0, 512, 0), Vector3i(0, 0, 512)]:
		var far: EntityCustomResult = EntityCustomUpdate.update(definition, state, environment, random, position, false, false)
		assert_eq(far.error, "")
		assert_eq(far.random.draw_count, 0)
		assert_eq(far.entity.animation.action, 0)
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, state, environment, random, Vector3i(511, 0, 0), false, false)
	assert_eq(result.error, "")
	assert_eq(result.random.draw_count, 1)
	assert_eq(result.environment.croak_modes[0], 3)
	assert_eq(result.entity.animation.action, 2)
	assert_eq(result.entity.animation.cel, -1)
	assert_eq(environment.croak_modes[0], 0)
	assert_eq(state.animation.action, 0)
	assert_eq(random.draw_count, 0)
	state.animation.cel = 1
	result = EntityCustomUpdate.update(definition, state, environment, random, Vector3i.ZERO, false, false)
	assert_eq(result.random.draw_count, 0)

func test_checkpoint_modes_survive_instance_recreation_and_failure_is_atomic() -> void:
	var definition: EntityDefinition = _entity("CHECKPOINT")
	var state: EntitySnapshot = _snapshot()
	state.animation = EntityAnimationState.create([4, 3, 5])
	state.animation.cel = 0
	var environment: EntityEnvironmentState = _environment()
	environment.croak_modes[0] = 1
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, state, environment, SourceRandom.create(11), Vector3i.ZERO, false, false)
	assert_eq(result.entity.animation.action, 1)
	assert_eq(result.environment.croak_modes[0], 2)
	result.entity.animation.cel = 2
	result = EntityCustomUpdate.update(definition, result.entity, result.environment, result.random, Vector3i.ZERO, false, false)
	assert_eq(result.entity.animation.action, 0)
	assert_eq(result.environment.croak_modes[0], 0)
	assert_eq(result.random.draw_count, 0)
	environment.croak_modes[0] = 0
	state.animation.lengths = PackedInt32Array([4])
	result = EntityCustomUpdate.update(definition, state, environment, SourceRandom.create(11), Vector3i.ZERO, false, false)
	assert_string_contains(result.error, "requested source action")
	assert_null(result.entity)
	assert_null(result.environment)
	assert_null(result.random)
	assert_eq(state.animation.action, 0)
	assert_eq(environment.croak_modes[0], 0)

func test_fly_chooses_once_and_retries_collected_or_occupied_checkpoint() -> void:
	for collected: bool in [false, true]:
		var state: EntitySnapshot = _snapshot()
		state.custom_state.timer = 0
		var environment: EntityEnvironmentState = _environment()
		environment.collected = 8 if collected else 0
		environment.covered = 0 if collected else 8
		var result: EntityCustomResult = EntityCustomUpdate.update(_entity("ORG_FLY"), state, environment, SourceRandom.create(1), Vector3i.ZERO, false, false)
		assert_eq(result.error, "")
		assert_eq(result.random.draw_count, 1)
		assert_eq(result.entity.custom_state.timer, 60)
		assert_eq(result.entity.custom_state.checkpoint_index, -1)
		assert_eq(result.entity.custom_state.mode, EntityFly.Mode.WAITING)
		assert_eq(result.environment.collected, environment.collected)
		assert_eq(result.environment.covered, environment.covered)

func test_fly_collection_releases_checkpoint_and_target_once() -> void:
	var state: EntitySnapshot = _snapshot()
	state.custom_state.mode = EntityFly.Mode.APPEARED
	state.custom_state.timer = 120
	state.custom_state.checkpoint_index = 3
	state.entity_flags |= EntityDefinition.HIDDEN
	state.live_flags |= EntityLiveFlags.TARGETTED
	var environment: EntityEnvironmentState = _environment()
	environment.covered = 8
	var result: EntityCustomResult = EntityCustomUpdate.update(_entity("ORG_FLY"), state, environment, SourceRandom.create(1), Vector3i.ZERO, false, false)
	assert_eq(result.error, "")
	assert_eq(result.environment.covered, 0)
	assert_eq(result.entity.custom_state.timer, 60)
	assert_eq(result.entity.live_flags & EntityLiveFlags.TARGETTED, 0)
	assert_eq(TickEvent.trace_lines(result.entity.requests), ["sound:5:0:0:0"])

func test_croc_head_warning_collision_bite_and_reset_are_detached() -> void:
	var definition: EntityDefinition = _entity("ORG_CROC_HEAD")
	definition.behavior.execution = EntityBehavior.Execution.CONTACT
	var state: EntitySnapshot = _snapshot()
	state.custom_state.timer = 0
	state.animation = EntityAnimationState.create([30])
	var environment: EntityEnvironmentState = _environment()
	var random: SourceRandom = SourceRandom.create(1)
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, state, environment, random, Vector3i.ZERO, false, false)
	assert_eq(result.error, "")
	assert_eq(result.entity.custom_state.mode, EntityCrocHead.Mode.APPEARING)
	assert_eq(result.entity.custom_state.timer, 60)
	assert_eq(result.environment.covered, 8)
	assert_eq(result.entity.matrix12[0], -3072)
	assert_eq(result.entity.matrix12[10], -200)
	assert_eq(result.entity.matrix12[11], 2050)
	assert_eq(result.entity.entity_flags & EntityDefinition.NO_COLLISION, EntityDefinition.NO_COLLISION)
	assert_eq(environment.covered, 0)
	assert_eq(state.custom_state.timer, 0)
	for tick: int in 60:
		result = EntityCustomUpdate.update(definition, result.entity, result.environment, result.random, Vector3i.ZERO, false, false)
		assert_eq(result.error, "")
	assert_eq(result.entity.custom_state.mode, EntityCrocHead.Mode.APPEARED)
	assert_eq(result.environment.collision_disabled, 8)
	assert_eq(result.entity.matrix12[11], 1950)
	assert_eq(result.entity.matrix12[0], -4096)
	result = EntityCustomUpdate.update(definition, result.entity, result.environment, result.random, Vector3i.ZERO, true, false)
	assert_eq(result.death_animation, FrogAnimationCatalog.BITTEN)
	assert_eq(result.entity.custom_state.mode, EntityCrocHead.Mode.RESET)
	assert_eq(result.entity.custom_state.timer, 60)
	for tick: int in 60:
		result = EntityCustomUpdate.update(definition, result.entity, result.environment, result.random, Vector3i.ZERO, false, false)
	assert_eq(result.entity.custom_state.mode, EntityCrocHead.Mode.WAITING)
	assert_eq(result.environment.covered, 0)
	assert_eq(result.environment.collision_disabled, 0)
	assert_eq(result.entity.custom_state.checkpoint_index, -1)
	assert_eq(result.random.draw_count, 1)

func test_gold_frog_waits_for_simulation_pop_completion() -> void:
	var entity: EntitySnapshot = _snapshot()
	EntityGoldFrog.update(entity, true)
	assert_eq(entity.custom_state.mode, EntityGoldFrog.Mode.JUMPING)
	assert_true(entity.pop_allocated)
	assert_eq(entity.pop_remaining, 32)
	EntityGoldFrog.update(entity, true)
	assert_eq(entity.requests.size(), 1)
	entity.pop_remaining = 0
	EntityGoldFrog.update(entity, false)
	assert_eq(entity.custom_state.mode, EntityGoldFrog.Mode.FINISHED)
	assert_false(entity.pop_allocated)
	assert_true(entity.custom_state.model_hidden)

func test_log_snake_keeps_moving_while_parent_is_not_live() -> void:
	var definition: EntityDefinition = _entity("ORG_LOG_SNAKE")
	definition.radius_squared = 10000
	definition.movement_speed = 512
	var entity: EntitySnapshot = _snapshot()
	var parent := EntitySnapshot.new()
	parent.entity_index = 7
	parent.path = PathSnapshot.new()
	parent.path.position = Vector3i(100, 20, 300)
	parent.matrix12[9] = 100
	parent.matrix12[10] = 20
	parent.matrix12[11] = 300
	var form := FormContactDefinition.new()
	form.radius_squared = 40000
	form.height = -50
	assert_eq(EntityLogSnake.update(definition, entity, parent, form), "")
	assert_eq(entity.custom_state.count, 100)
	assert_eq(entity.custom_state.target, Vector3i(0, -50, 2))
	assert_eq(entity.matrix12.slice(9), PackedInt32Array([100, -30, 302]))
	assert_eq(TickEvent.trace_lines(entity.requests), ["moving:101:512:1024"])
	parent.live = false
	entity.custom_state.target.z = 100
	assert_eq(EntityLogSnake.update(definition, entity, parent, form), "")
	assert_eq(entity.custom_state.direction, 0)
	assert_eq(entity.custom_state.target.z, 98)
	assert_true(entity.custom_state.model_hidden)
	assert_eq(entity.matrix12[11], 302)
	parent.live = true
	assert_eq(EntityLogSnake.update(definition, entity, parent, form), "")
	assert_false(entity.custom_state.model_hidden)
	assert_eq(entity.matrix12[11], 396)
	assert_eq(entity.matrix12[0], -4096)

func test_beaver_follows_authored_neighbor_order_then_waits_and_resets() -> void:
	var definition: EntityDefinition = _entity("ORG_BEAVER")
	definition.path_definition = PathDefinition.new()
	definition.path_definition.entity_indices = PackedInt32Array([7, 6])
	definition.authored_delay = 1
	var state: EntitySnapshot = _snapshot()
	state.custom_state.mode = EntityBeaver.Mode.WAITING_FIRST
	state.path = PathSnapshot.new()
	state.path.tangent = Vector3i(0, 0, 4096)
	state.animation = EntityAnimationState.create([8, 10])
	var first := EntitySnapshot.new()
	first.entity_index = 6
	first.path = PathSnapshot.new()
	var second := EntitySnapshot.new()
	second.entity_index = 7
	second.path = PathSnapshot.new()
	var first_definition := EntityDefinition.new()
	var second_definition := EntityDefinition.new()
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, state, _environment(), SourceRandom.create(1), Vector3i.ZERO, false, false, null, null, null, [first, second], [first_definition, second_definition])
	assert_eq(result.error, "")
	assert_eq(result.entity.custom_state.parent_entity_index, 7)
	assert_eq(result.path_active_request, 0)
	first.path.position = Vector3i(1000, 0, 0)
	second.path.position = Vector3i(1000, 0, 0)
	for tick: int in 3:
		result = EntityCustomUpdate.update(definition, result.entity, result.environment, result.random, Vector3i.ZERO, false, false, null, null, null, [first, second], [first_definition, second_definition])
		assert_eq(result.error, "")
	assert_eq(result.entity.custom_state.mode, EntityBeaver.Mode.SWIMMING)
	assert_eq(result.path_active_request, 1)
	assert_eq(result.entity.custom_state.delay, 65535)
	assert_eq(TickEvent.trace_lines(result.entity.requests), ["moving:19:1024:2048"])
	second.live = false
	result = EntityCustomUpdate.update(definition, result.entity, result.environment, result.random, Vector3i.ZERO, false, false, null, null, null, [first, second], [first_definition, second_definition])
	assert_eq(result.error, "")
	assert_true(result.path_reset_requested)
	assert_eq(result.entity.custom_state.mode, EntityBeaver.Mode.WAITING_FIRST)

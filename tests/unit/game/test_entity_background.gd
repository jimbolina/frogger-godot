extends GutTest
## Logical global effects and explicit limits of the admitted background branches.

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
	state.background = EntityCustomState.new()
	state.entity_flags = EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION
	state.background.model_hidden = true
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
			assert_eq(result.entity.background.mode, 1)
			assert_eq(result.entity.background.timer, 120)
			assert_eq(result.random.state, 1103527590)
			assert_eq(result.entity.background.checkpoint_index, 3)
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
	assert_eq(state.background.mode, 0)
	assert_eq(state.background.timer, 60)
	assert_eq(state.entity_flags, EntityDefinition.HIDDEN | EntityDefinition.NO_COLLISION)
	assert_eq(random.draw_count, 1)

func test_custom_failure_discards_candidate_and_baby_requires_live_parent() -> void:
	var state: EntitySnapshot = _snapshot()
	state.background.timer = 0
	var environment: EntityEnvironmentState = _environment()
	environment.covered = 1
	var random: SourceRandom = SourceRandom.create(1)
	var result: EntityCustomResult = EntityCustomUpdate.update(_entity("ORG_FLY"), state, environment, random, Vector3i.ZERO, false, false)
	assert_ne(result.error, "")
	assert_null(result.entity)
	assert_eq(state.background.timer, 0)
	assert_eq(environment.covered, 1)
	assert_eq(random.state, 1)
	result = EntityCustomUpdate.update(_entity("ORG_BABY_FROG"), state, environment, random, Vector3i.ZERO, false, true)
	assert_eq(result.error, "")
	assert_eq(result.entity.background.mode, 5)
	assert_eq(result.entity.background.search_count, 1)
	var next: EntityCustomResult = EntityCustomUpdate.update(_entity("ORG_BABY_FROG"), result.entity, environment, random, Vector3i.ZERO, false, true)
	assert_eq(next.entity.background.search_count, 1)
	assert_ne(EntityCustomUpdate.update(_entity("ORG_BABY_FROG"), next.entity, environment, random, Vector3i.ZERO, false, false).error, "")
	assert_ne(EntityCustomUpdate.update(_entity("CHECKPOINT"), state, environment, random, Vector3i.ZERO, false, true).error, "")

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

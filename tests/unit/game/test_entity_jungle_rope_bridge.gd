extends GutTest
## Hand-derived frozen Jungle rope-bridge hit counting, unsigned wait and rider drop.

func _definition(fall_delay: int = 2, hops_before: int = 1) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 9
	definition.jungle = EntityJungleDefinition.new()
	definition.jungle.fall_delay = fall_delay
	definition.jungle.hops_before = hops_before
	return definition

func _bridge(definition: EntityDefinition) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.entity_index = definition.entity_index
	entity.matrix12 = definition.matrix12.duplicate()
	entity.animation = EntityAnimationState.create(PackedInt32Array([5]))
	entity.custom_state = EntityCustomState.new()
	entity.entity_flags = EntityDefinition.NO_COLLISION
	EntityJungleRopeBridge.initialize(definition, entity)
	return entity

func _step(definition: EntityDefinition, entity: EntitySnapshot, frog: GameplayState = null, hit: bool = false) -> EntityCustomResult:
	var result := EntityCustomResult.new()
	result.entity = entity
	assert_eq(EntityJungleRopeBridge.update(definition, result, frog, hit), "")
	return result

func test_creation_holds_a_one_shot_animation_with_collision() -> void:
	var entity: EntitySnapshot = _bridge(_definition())
	assert_false(entity.animation.stepping)
	assert_true(entity.animation.one_shot)
	assert_eq(entity.animation.cel, 0)
	assert_eq(entity.entity_flags & EntityDefinition.NO_COLLISION, 0)
	assert_eq([entity.custom_state.mode, entity.custom_state.timer, entity.custom_state.count], [EntityJungleRopeBridge.Mode.WAITING_FOR_HITS, 0, 0])

func test_errors_leave_state_untouched() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _bridge(definition)
	var result := EntityCustomResult.new()
	result.entity = entity
	definition.jungle = null
	assert_ne(EntityJungleRopeBridge.update(definition, result, null, true), "")
	definition.jungle = EntityJungleDefinition.new()
	entity.animation = null
	assert_ne(EntityJungleRopeBridge.update(definition, result, null, true), "")
	assert_eq(entity.custom_state.count, 0)
	assert_eq(entity.custom_state.mode, EntityJungleRopeBridge.Mode.WAITING_FOR_HITS)

func test_hits_wrap_at_eight_bits() -> void:
	var definition: EntityDefinition = _definition(2, 300)
	var entity: EntitySnapshot = _bridge(definition)
	entity.custom_state.count = 255
	_step(definition, entity, null, true)
	assert_eq(entity.custom_state.count, 0)
	assert_eq(entity.custom_state.mode, EntityJungleRopeBridge.Mode.WAITING_FOR_HITS)
	_step(definition, entity)
	assert_eq(entity.custom_state.count, 0)

func test_zero_hop_count_still_waits_for_a_hit() -> void:
	var definition: EntityDefinition = _definition(2, 0)
	var entity: EntitySnapshot = _bridge(definition)
	_step(definition, entity)
	assert_eq(entity.custom_state.mode, EntityJungleRopeBridge.Mode.WAITING_FOR_HITS)
	_step(definition, entity, null, true)
	assert_eq(entity.custom_state.mode, EntityJungleRopeBridge.Mode.WAITING_TO_FALL)

func test_collapse_follows_fall_delay_plus_one_updates_and_drops_only_the_rider() -> void:
	var definition: EntityDefinition = _definition(2, 2)
	var entity: EntitySnapshot = _bridge(definition)
	var frog := GameplayState.new()
	frog.attachment.current_entity_index = definition.entity_index
	_step(definition, entity, frog, true)
	assert_eq(entity.custom_state.mode, EntityJungleRopeBridge.Mode.WAITING_FOR_HITS)
	_step(definition, entity, frog, true)
	assert_eq(entity.custom_state.mode, EntityJungleRopeBridge.Mode.WAITING_TO_FALL)
	assert_eq(entity.custom_state.timer, 2)
	for tick: int in 2:
		var waiting: EntityCustomResult = _step(definition, entity, frog, true)
		assert_false(waiting.frog_fall_requested)
		assert_eq(entity.custom_state.mode, EntityJungleRopeBridge.Mode.WAITING_TO_FALL)
	assert_eq(entity.custom_state.count, 2, "hits are not counted while waiting")
	var result: EntityCustomResult = _step(definition, entity, frog)
	assert_eq(entity.custom_state.mode, EntityJungleRopeBridge.Mode.FALLING)
	assert_eq(entity.custom_state.timer, 65535)
	assert_true(entity.animation.stepping)
	assert_ne(entity.entity_flags & EntityDefinition.NO_COLLISION, 0)
	assert_true(result.frog_fall_requested)
	result = _step(definition, entity, frog, true)
	assert_false(result.frog_fall_requested)
	assert_eq(entity.custom_state.mode, EntityJungleRopeBridge.Mode.FALLING)

func test_collapse_ignores_a_frog_on_another_entity() -> void:
	var definition: EntityDefinition = _definition(0, 1)
	var entity: EntitySnapshot = _bridge(definition)
	var frog := GameplayState.new()
	frog.attachment.current_entity_index = definition.entity_index + 1
	_step(definition, entity, frog, true)
	var result: EntityCustomResult = _step(definition, entity, frog)
	assert_eq(entity.custom_state.mode, EntityJungleRopeBridge.Mode.FALLING)
	assert_false(result.frog_fall_requested)
	assert_false(_step(definition, _bridge(_definition(0, 1)), null, true).frog_fall_requested)

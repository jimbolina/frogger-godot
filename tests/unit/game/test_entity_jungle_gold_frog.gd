extends GutTest
## Frozen Jungle plinth gold frog creation: the statue frog celebrates, plinth frogs stay hidden.

func _frog(op_id: int) -> Array:
	var definition := EntityDefinition.new()
	definition.jungle = EntityJungleDefinition.new()
	definition.jungle.op_id = op_id
	var entity := EntitySnapshot.new()
	entity.animation = EntityAnimationState.create(PackedInt32Array([4, 4, 4, 6, 8, 2]))
	entity.custom_state = EntityCustomState.new()
	entity.entity_flags = EntityDefinition.NO_DISPLAY
	EntityJungleGoldFrog.initialize(definition, entity)
	return [definition, entity]

func test_statue_frog_is_displayed_and_excited() -> void:
	var entity: EntitySnapshot = _frog(8)[1]
	assert_eq(entity.entity_flags & EntityDefinition.NO_DISPLAY, 0)
	assert_eq(entity.animation.action, EntityJungleGoldFrog.Action.EXCITED)
	assert_eq(entity.animation.action, 3)
	assert_eq(entity.animation.cel, -1)
	assert_true(entity.animation.stepping)
	assert_eq(entity.custom_state.mode, EntityJungleGoldFrog.Mode.SITTING)

func test_plinth_frogs_are_hidden_on_a_held_backflip() -> void:
	for op_id: int in [0, 7, 9, -1]:
		var entity: EntitySnapshot = _frog(op_id)[1]
		assert_ne(entity.entity_flags & EntityDefinition.NO_DISPLAY, 0, str(op_id))
		assert_eq(entity.animation.action, EntityJungleGoldFrog.Action.BACKFLIP, str(op_id))
		assert_false(entity.animation.stepping, str(op_id))
		assert_eq(entity.entity_flags & EntityDefinition.NO_COLLISION, 0, str(op_id))

func test_missing_operands_hide_the_frog_and_actions_are_required() -> void:
	var entity := EntitySnapshot.new()
	entity.custom_state = EntityCustomState.new()
	EntityJungleGoldFrog.initialize(EntityDefinition.new(), entity)
	assert_ne(entity.entity_flags & EntityDefinition.NO_DISPLAY, 0)
	assert_eq(EntityJungleGoldFrog.REQUIRED_ACTIONS, 5)

func test_gold_frog_update_is_empty_while_sitting() -> void:
	var pair: Array = _frog(8)
	var definition: EntityDefinition = pair[0]
	definition.behavior.kind = EntityBehavior.Kind.JUN_GOLD_FROG
	definition.behavior.execution = EntityBehavior.Execution.UPDATE
	var entity: EntitySnapshot = pair[1]
	var environment := EntityEnvironmentState.new()
	for index: int in 5:
		environment.checkpoint_positions.append(Vector3i(index, 0, 0))
	var result: EntityCustomResult = EntityCustomUpdate.update(definition, entity, environment, SourceRandom.create(1), Vector3i.ZERO, false, false)
	assert_eq(result.error, "")
	assert_eq(result.entity.animation.action, EntityJungleGoldFrog.Action.EXCITED)
	assert_eq(result.entity.matrix12, entity.matrix12)

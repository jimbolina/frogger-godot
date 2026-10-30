extends GutTest
## Hand-derived frozen Swamp squirt signed delay, truncated 16.16 drop velocity, post-decrement reset and drip sound distance.

func _definition(time_delay: int = 2, drop_time: int = 3, target: Vector3i = Vector3i(990, -100, 2010)) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 4
	definition.swamp = EntitySwampDefinition.new()
	definition.swamp.time_delay = time_delay
	definition.swamp.drop_time = drop_time
	definition.swamp.target = target
	definition.matrix12[9] = 1000
	definition.matrix12[10] = -500
	definition.matrix12[11] = 2000
	return definition

func _squirt(definition: EntityDefinition) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.entity_index = definition.entity_index
	entity.custom_state = EntityCustomState.new()
	EntitySwampSquirt.initialize(definition, entity)
	return entity

func _frog(dz: int) -> GameplayState:
	var frog := GameplayState.new()
	frog.frog.matrix12[9] = 1000
	frog.frog.matrix12[10] = -500
	frog.frog.matrix12[11] = 2000 + dz
	return frog

func _step(definition: EntityDefinition, entity: EntitySnapshot, frog: GameplayState = null) -> void:
	var result := EntityCustomResult.new()
	result.entity = entity
	assert_eq(EntitySwampSquirt.update(definition, result, frog), "")

func _position(entity: EntitySnapshot) -> Vector3i:
	return Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])

func test_creation_copies_the_matrix_and_waits_the_signed_delay() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _squirt(definition)
	assert_eq(entity.matrix12, definition.matrix12)
	assert_eq([entity.custom_state.mode, entity.custom_state.timer, entity.custom_state.velocity_16], [EntitySwampSquirt.Mode.WAITING, 2, Vector3i.ZERO])
	assert_true(entity.custom_state.moving_sound.is_empty())

func test_missing_operands_and_zero_drop_time_are_errors() -> void:
	var definition: EntityDefinition = _definition(0, 0)
	var entity: EntitySnapshot = _squirt(definition)
	var result := EntityCustomResult.new()
	result.entity = entity
	assert_eq(EntitySwampSquirt.update(definition, result, null), "")
	assert_string_contains(EntitySwampSquirt.update(definition, result, null), "zero drop time")
	assert_eq(entity.custom_state.mode, EntitySwampSquirt.Mode.FALL_PREPARE)
	definition.swamp = null
	assert_ne(EntitySwampSquirt.update(definition, result, null), "")

func test_waiting_counts_down_then_prepares_without_moving() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _squirt(definition)
	_step(definition, entity)
	assert_eq([entity.custom_state.mode, entity.custom_state.timer], [EntitySwampSquirt.Mode.WAITING, 1])
	_step(definition, entity)
	assert_eq([entity.custom_state.mode, entity.custom_state.timer], [EntitySwampSquirt.Mode.WAITING, 0])
	_step(definition, entity)
	assert_eq([entity.custom_state.mode, entity.custom_state.timer], [EntitySwampSquirt.Mode.FALL_PREPARE, 0])
	assert_eq(_position(entity), Vector3i(1000, -500, 2000))

func test_negative_delay_prepares_on_the_first_update() -> void:
	var definition: EntityDefinition = _definition(-5)
	var entity: EntitySnapshot = _squirt(definition)
	assert_eq(entity.custom_state.timer, -5)
	_step(definition, entity)
	assert_eq([entity.custom_state.mode, entity.custom_state.timer], [EntitySwampSquirt.Mode.FALL_PREPARE, -5])

func test_prepare_truncates_the_velocity_and_falls_drop_time_plus_one_steps_before_snapping_back() -> void:
	var definition: EntityDefinition = _definition(0)
	var entity: EntitySnapshot = _squirt(definition)
	_step(definition, entity)
	_step(definition, entity)
	assert_eq(entity.custom_state.mode, EntitySwampSquirt.Mode.FALLING)
	assert_eq(entity.custom_state.timer, 3)
	assert_eq(entity.custom_state.velocity_16, Vector3i(-218453, 8738133, 218453))
	assert_eq(_position(entity), Vector3i(1000, -500, 2000))
	entity.matrix12[0] = 1234
	_step(definition, entity)
	assert_eq(_position(entity), Vector3i(996, -367, 2003), "the arithmetic shift floors the negative X step to -4")
	assert_eq([entity.custom_state.mode, entity.custom_state.timer], [EntitySwampSquirt.Mode.FALLING, 2])
	_step(definition, entity)
	_step(definition, entity)
	assert_eq(_position(entity), Vector3i(988, -101, 2009))
	assert_eq([entity.custom_state.mode, entity.custom_state.timer], [EntitySwampSquirt.Mode.FALLING, 0])
	_step(definition, entity)
	assert_eq([entity.custom_state.mode, entity.custom_state.timer], [EntitySwampSquirt.Mode.FALL_PREPARE, -1])
	assert_eq(entity.matrix12, definition.matrix12, "the whole authored matrix is restored")
	_step(definition, entity)
	assert_eq([entity.custom_state.mode, entity.custom_state.timer], [EntitySwampSquirt.Mode.FALLING, 3])

func test_drip_sound_plays_strictly_inside_its_distance_on_each_prepare() -> void:
	var definition: EntityDefinition = _definition(0)
	var entity: EntitySnapshot = _squirt(definition)
	_step(definition, entity, _frog(1535))
	assert_true(entity.requests.is_empty())
	_step(definition, entity, _frog(1536))
	assert_true(entity.requests.is_empty())
	entity.custom_state.mode = EntitySwampSquirt.Mode.FALL_PREPARE
	_step(definition, entity, _frog(1535))
	assert_eq(entity.requests.size(), 1)
	assert_eq(entity.requests[0].sound_id, 114)
	entity.requests.clear()
	for unused: int in 4:
		_step(definition, entity, _frog(0))
	assert_true(entity.requests.is_empty(), "falling plays nothing")
	assert_eq(entity.custom_state.mode, EntitySwampSquirt.Mode.FALL_PREPARE)
	_step(definition, entity, null)
	assert_eq(entity.custom_state.mode, EntitySwampSquirt.Mode.FALLING)
	assert_true(entity.requests.is_empty(), "no active frog plays nothing")

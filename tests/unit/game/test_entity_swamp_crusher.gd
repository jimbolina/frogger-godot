extends GutTest
## Hand-derived frozen Swamp crusher unsigned delay, debounce countdown, arithmetic speed shift and strict direction flips.

func _definition(direction: int = 0, speed: int = 768, distance: int = 5, delay: int = 0) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 6
	definition.swamp = EntitySwampDefinition.new()
	definition.swamp.speed = speed
	definition.swamp.distance = distance
	definition.swamp.direction = direction
	definition.swamp.delay = delay
	definition.matrix12[9] = 100
	definition.matrix12[10] = -40
	definition.matrix12[11] = 200
	return definition

func _crusher(definition: EntityDefinition) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.entity_index = definition.entity_index
	entity.custom_state = EntityCustomState.new()
	EntitySwampCrusher.initialize(definition, entity)
	return entity

func _step(definition: EntityDefinition, entity: EntitySnapshot) -> void:
	var result := EntityCustomResult.new()
	result.entity = entity
	assert_eq(EntitySwampCrusher.update(definition, result), "")

func _crushing(definition: EntityDefinition) -> EntitySnapshot:
	var entity: EntitySnapshot = _crusher(definition)
	_step(definition, entity)
	assert_eq(entity.custom_state.mode, EntitySwampCrusher.CRUSHING)
	return entity

func _trace(definition: EntityDefinition, entity: EntitySnapshot, slot: int, ticks: int) -> Array:
	var values: Array = []
	for unused: int in ticks:
		_step(definition, entity)
		values.append([entity.matrix12[slot], entity.custom_state.direction])
	return values

func test_creation_copies_the_matrix_loads_the_unsigned_delay_and_the_moving_sound() -> void:
	var definition: EntityDefinition = _definition(0, 768, 5, -1)
	var entity: EntitySnapshot = _crusher(definition)
	assert_eq(entity.matrix12, definition.matrix12)
	var custom: EntityCustomState = entity.custom_state
	assert_eq([custom.direction, custom.timer, custom.mode, custom.count], [EntitySwampCrusher.IN, 65535, EntitySwampCrusher.WAITING, 0])
	assert_eq(custom.moving_sound, PackedInt32Array([121, 768, 1280]))
	assert_true(entity.requests.is_empty())

func test_missing_operands_are_an_error() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _crusher(definition)
	definition.swamp = null
	var result := EntityCustomResult.new()
	result.entity = entity
	assert_ne(EntitySwampCrusher.update(definition, result), "")

func test_waiting_post_decrements_and_starts_crushing_after_the_zero_tick_without_moving() -> void:
	var definition: EntityDefinition = _definition(0, 768, 5, 1)
	var entity: EntitySnapshot = _crusher(definition)
	_step(definition, entity)
	assert_eq([entity.custom_state.mode, entity.custom_state.timer], [EntitySwampCrusher.WAITING, 0])
	_step(definition, entity)
	assert_eq([entity.custom_state.mode, entity.custom_state.timer], [EntitySwampCrusher.CRUSHING, 65535])
	assert_eq(entity.matrix12, definition.matrix12)

func test_count_decrements_to_zero_every_update_while_waiting_or_crushing() -> void:
	var definition: EntityDefinition = _definition(0, 768, 5, 3)
	var entity: EntitySnapshot = _crusher(definition)
	entity.custom_state.count = 2
	_step(definition, entity)
	assert_eq(entity.custom_state.count, 1)
	_step(definition, entity)
	_step(definition, entity)
	assert_eq(entity.custom_state.count, 0)
	entity.custom_state.count = 1
	entity.custom_state.mode = EntitySwampCrusher.CRUSHING
	_step(definition, entity)
	assert_eq(entity.custom_state.count, 0)

func test_north_rams_along_z_and_flips_strictly_past_each_bound() -> void:
	var definition: EntityDefinition = _definition(EntitySwampCrusher.NORTH)
	var entity: EntitySnapshot = _crushing(definition)
	assert_eq(_trace(definition, entity, 11, 6), [[203, 0], [206, 1], [203, 1], [200, 1], [197, 0], [200, 0]])
	assert_eq(entity.matrix12[9], 100)
	definition = _definition(EntitySwampCrusher.NORTH, 768, 6)
	entity = _crushing(definition)
	assert_eq(_trace(definition, entity, 11, 3), [[203, 0], [206, 0], [209, 1]])

func test_east_rams_along_x() -> void:
	var definition: EntityDefinition = _definition(EntitySwampCrusher.EAST)
	var entity: EntitySnapshot = _crushing(definition)
	assert_eq(_trace(definition, entity, 9, 5), [[103, 0], [106, 1], [103, 1], [100, 1], [97, 0]])
	assert_eq(entity.matrix12[11], 200)

func test_south_and_west_ram_negatively_and_return_past_the_authored_position() -> void:
	var definition: EntityDefinition = _definition(EntitySwampCrusher.SOUTH)
	var entity: EntitySnapshot = _crushing(definition)
	assert_eq(_trace(definition, entity, 11, 5), [[197, 0], [194, 1], [197, 1], [200, 1], [203, 0]])
	definition = _definition(EntitySwampCrusher.WEST)
	entity = _crushing(definition)
	assert_eq(_trace(definition, entity, 9, 5), [[97, 0], [94, 1], [97, 1], [100, 1], [103, 0]])

func test_speed_shift_is_arithmetic_and_unknown_directions_stay_still() -> void:
	var definition: EntityDefinition = _definition(EntitySwampCrusher.NORTH, -1)
	var entity: EntitySnapshot = _crushing(definition)
	assert_eq(_trace(definition, entity, 11, 2), [[199, 0], [198, 0]])
	definition = _definition(EntitySwampCrusher.NORTH, 255)
	entity = _crushing(definition)
	assert_eq(_trace(definition, entity, 11, 1), [[200, 0]])
	definition = _definition(4)
	entity = _crushing(definition)
	_step(definition, entity)
	assert_eq(entity.matrix12, definition.matrix12)
	assert_eq(entity.custom_state.direction, EntitySwampCrusher.IN)

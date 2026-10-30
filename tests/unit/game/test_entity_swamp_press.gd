extends GutTest
## Hand-derived frozen Swamp press unsigned delay, vertical strict flips and the return-stroke crush sounds.

func _definition(direction: int = 0, speed: int = 512, distance: int = 3, delay: int = 0) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 8
	definition.swamp = EntitySwampDefinition.new()
	definition.swamp.speed = speed
	definition.swamp.distance = distance
	definition.swamp.direction = direction
	definition.swamp.delay = delay
	definition.matrix12[9] = 0
	definition.matrix12[10] = 100
	definition.matrix12[11] = 0
	return definition

func _press(definition: EntityDefinition) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.entity_index = definition.entity_index
	entity.custom_state = EntityCustomState.new()
	EntitySwampPress.initialize(definition, entity)
	return entity

func _frog(dz: int) -> GameplayState:
	var frog := GameplayState.new()
	frog.frog.matrix12[9] = 0
	frog.frog.matrix12[10] = 102
	frog.frog.matrix12[11] = dz
	return frog

func _step(definition: EntityDefinition, entity: EntitySnapshot, frog: GameplayState = null) -> void:
	var result := EntityCustomResult.new()
	result.entity = entity
	assert_eq(EntitySwampPress.update(definition, result, frog), "")

func _trace(definition: EntityDefinition, entity: EntitySnapshot, ticks: int, frog: GameplayState = null) -> Array:
	var values: Array = []
	for unused: int in ticks:
		_step(definition, entity, frog)
		values.append([entity.matrix12[10], entity.custom_state.direction, entity.requests.size()])
	return values

func test_creation_copies_the_matrix_loads_the_unsigned_delay_and_the_moving_sound() -> void:
	var definition: EntityDefinition = _definition(0, 512, 3, -2)
	var entity: EntitySnapshot = _press(definition)
	assert_eq(entity.matrix12, definition.matrix12)
	var custom: EntityCustomState = entity.custom_state
	assert_eq([custom.direction, custom.timer, custom.mode], [EntitySwampPress.MOVING_UP, 65534, EntitySwampPress.WAITING])
	assert_eq(custom.moving_sound, PackedInt32Array([124, 768, 1280]))

func test_missing_operands_are_an_error() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _press(definition)
	definition.swamp = null
	var result := EntityCustomResult.new()
	result.entity = entity
	assert_ne(EntitySwampPress.update(definition, result, null), "")

func test_waiting_post_decrements_before_crushing() -> void:
	var definition: EntityDefinition = _definition(0, 512, 3, 1)
	var entity: EntitySnapshot = _press(definition)
	_step(definition, entity)
	assert_eq([entity.custom_state.mode, entity.custom_state.timer], [EntitySwampPress.WAITING, 0])
	_step(definition, entity)
	assert_eq([entity.custom_state.mode, entity.custom_state.timer], [EntitySwampPress.CRUSHING, 65535])
	assert_eq(entity.matrix12, definition.matrix12)

func test_up_press_rises_then_returns_past_its_height_with_the_crusher_sound_inside_the_distance() -> void:
	var definition: EntityDefinition = _definition(EntitySwampPress.UP)
	var entity: EntitySnapshot = _press(definition)
	_step(definition, entity)
	assert_eq(_trace(definition, entity, 5, _frog(1535)), [[98, 0, 0], [96, 1, 0], [98, 1, 0], [100, 1, 0], [102, 0, 1]])
	assert_eq(entity.requests[0].sound_id, 105)
	entity.requests.clear()
	assert_eq(_trace(definition, entity, 4, _frog(1536)), [[100, 0, 0], [98, 0, 0], [96, 1, 0], [98, 1, 0]])
	assert_eq(_trace(definition, entity, 2, _frog(1536)), [[100, 1, 0], [102, 0, 0]])

func test_down_press_mirrors_the_stroke_and_plays_the_frog_crush_sound_while_carrying() -> void:
	var definition: EntityDefinition = _definition(EntitySwampPress.DOWN)
	var entity: EntitySnapshot = _press(definition)
	_step(definition, entity)
	entity.live_flags = EntityLiveFlags.CARRIES_FROG_1
	assert_eq(_trace(definition, entity, 5, null), [[102, 0, 0], [104, 1, 0], [102, 1, 0], [100, 1, 0], [98, 0, 1]])
	assert_eq(entity.requests[0].sound_id, 123)

func test_unknown_direction_stays_still() -> void:
	var definition: EntityDefinition = _definition(2)
	var entity: EntitySnapshot = _press(definition)
	_step(definition, entity)
	_step(definition, entity, _frog(0))
	assert_eq(entity.matrix12, definition.matrix12)
	assert_eq(entity.custom_state.direction, EntitySwampPress.MOVING_UP)
	assert_true(entity.requests.is_empty())

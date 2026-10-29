extends GutTest
## Hand-derived frozen Jungle plant distance trigger, signed timers, snap sound cadence and cel reset.

func _definition(snap_time: int = 2, snap_delay: int = 3) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 7
	definition.jungle = EntityJungleDefinition.new()
	definition.jungle.snap_time = snap_time
	definition.jungle.snap_delay = snap_delay
	definition.matrix12[9] = 1000
	definition.matrix12[10] = -50
	definition.matrix12[11] = 2000
	return definition

func _plant(definition: EntityDefinition, cels: int = 4) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.entity_index = definition.entity_index
	entity.matrix12 = definition.matrix12.duplicate()
	entity.animation = EntityAnimationState.create(PackedInt32Array([cels]))
	entity.custom_state = EntityCustomState.new()
	EntityJunglePlant.initialize(definition, entity)
	return entity

func _frog(dz: int) -> GameplayState:
	var frog := GameplayState.new()
	frog.frog.matrix12[9] = 1000
	frog.frog.matrix12[10] = -50
	frog.frog.matrix12[11] = 2000 + dz
	return frog

func _step(definition: EntityDefinition, entity: EntitySnapshot, frog: GameplayState) -> void:
	var result := EntityCustomResult.new()
	result.entity = entity
	assert_eq(EntityJunglePlant.update(definition, result, frog), "")

func _sounds(entity: EntitySnapshot) -> int:
	var count: int = 0
	for request: TickEvent in entity.requests:
		assert_eq(request.sound_id, 93)
		count += 1
	entity.requests.clear()
	return count

func test_creation_selects_cel_zero_and_clears_runtime() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _plant(definition)
	assert_eq(entity.animation.cel, 0)
	assert_true(entity.animation.stepping, "creation leaves stepping to the first update")
	assert_false(entity.animation.one_shot)
	assert_eq([entity.custom_state.mode, entity.custom_state.timer, entity.custom_state.count], [EntityJunglePlant.Mode.WAITING, 0, 0])

func test_errors_leave_state_untouched() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _plant(definition)
	var result := EntityCustomResult.new()
	result.entity = entity
	definition.jungle = null
	assert_ne(EntityJunglePlant.update(definition, result, _frog(0)), "")
	definition.jungle = EntityJungleDefinition.new()
	entity.animation = null
	assert_ne(EntityJunglePlant.update(definition, result, _frog(0)), "")
	assert_eq(entity.custom_state.mode, EntityJunglePlant.Mode.WAITING)
	assert_true(entity.requests.is_empty())

func test_waiting_stops_stepping_and_triggers_strictly_inside_the_distance() -> void:
	var definition: EntityDefinition = _definition(5)
	var entity: EntitySnapshot = _plant(definition)
	_step(definition, entity, _frog(356))
	assert_false(entity.animation.stepping)
	assert_eq(entity.custom_state.mode, EntityJunglePlant.Mode.WAITING)
	_step(definition, entity, null)
	assert_eq(entity.custom_state.mode, EntityJunglePlant.Mode.WAITING)
	var inactive: GameplayState = _frog(0)
	inactive.frog.flags &= ~FrogFlags.ACTIVE
	_step(definition, entity, inactive)
	assert_eq(entity.custom_state.mode, EntityJunglePlant.Mode.WAITING)
	_step(definition, entity, _frog(-355))
	assert_eq(entity.custom_state.mode, EntityJunglePlant.Mode.WAITING_TO_SNAP)
	assert_eq(entity.custom_state.timer, 5)

func test_snap_fires_after_snap_time_plus_one_updates_with_a_distance_gated_sound() -> void:
	var definition: EntityDefinition = _definition(2)
	var entity: EntitySnapshot = _plant(definition)
	_step(definition, entity, _frog(0))
	for tick: int in 2:
		_step(definition, entity, _frog(0))
		assert_eq(entity.custom_state.mode, EntityJunglePlant.Mode.WAITING_TO_SNAP)
	_step(definition, entity, _frog(0))
	assert_eq(entity.custom_state.mode, EntityJunglePlant.Mode.SNAPPING)
	assert_true(entity.animation.stepping)
	assert_eq(entity.custom_state.timer, -1)
	assert_eq(entity.custom_state.count, 15)
	assert_eq(_sounds(entity), 1)
	var far: EntitySnapshot = _plant(definition)
	far.custom_state.mode = EntityJunglePlant.Mode.WAITING_TO_SNAP
	_step(definition, far, _frog(900))
	assert_eq(far.custom_state.mode, EntityJunglePlant.Mode.SNAPPING)
	assert_eq(_sounds(far), 0, "the source compares 30 with the root of the frog distance")
	_step(definition, far, _frog(899))
	assert_eq(far.custom_state.count, 14)
	var near: EntitySnapshot = _plant(definition)
	near.custom_state.mode = EntityJunglePlant.Mode.WAITING_TO_SNAP
	_step(definition, near, _frog(-899))
	assert_eq(_sounds(near), 1)

func test_negative_snap_time_wraps_as_a_signed_short() -> void:
	var definition: EntityDefinition = _definition(-32768)
	var entity: EntitySnapshot = _plant(definition)
	entity.custom_state.mode = EntityJunglePlant.Mode.WAITING_TO_SNAP
	entity.custom_state.timer = -32768
	_step(definition, entity, null)
	assert_eq(entity.custom_state.timer, 32767)
	assert_eq(entity.custom_state.mode, EntityJunglePlant.Mode.WAITING_TO_SNAP)

func test_snapping_waits_for_the_last_cel_and_repeats_the_sound_every_sixteen_updates() -> void:
	var definition: EntityDefinition = _definition(0, 1)
	var entity: EntitySnapshot = _plant(definition, 3)
	entity.custom_state.mode = EntityJunglePlant.Mode.SNAPPING
	entity.custom_state.count = 1
	entity.animation.cel = 1
	_step(definition, entity, _frog(0))
	assert_eq(entity.custom_state.mode, EntityJunglePlant.Mode.SNAPPING)
	assert_eq(entity.custom_state.count, 0)
	assert_eq(_sounds(entity), 0)
	entity.animation.advance()
	_step(definition, entity, _frog(0))
	assert_eq(entity.custom_state.mode, EntityJunglePlant.Mode.DELAY_AFTER_SNAPPING)
	assert_eq(entity.custom_state.timer, 1)
	assert_eq(entity.custom_state.count, 15)
	assert_eq(_sounds(entity), 1)
	assert_true(entity.animation.stepping, "the source keeps the flipbook running through the delay")
	_step(definition, entity, _frog(0))
	assert_eq(entity.custom_state.mode, EntityJunglePlant.Mode.DELAY_AFTER_SNAPPING)
	assert_eq(entity.custom_state.count, 14)
	_step(definition, entity, _frog(0))
	assert_eq(entity.custom_state.mode, EntityJunglePlant.Mode.WAITING)
	assert_eq(entity.animation.cel, 0)
	assert_false(entity.animation.stepping)
	assert_eq(entity.custom_state.timer, -1)
	assert_eq(entity.custom_state.count, 13)
	assert_eq(_sounds(entity), 0)

func test_full_cycle_sound_cadence() -> void:
	var definition: EntityDefinition = _definition(0, 40)
	var entity: EntitySnapshot = _plant(definition, 2)
	var sound_ticks := PackedInt32Array()
	for tick: int in 60:
		_step(definition, entity, _frog(0))
		if _sounds(entity) > 0:
			sound_ticks.append(tick)
		entity.animation.advance()
	assert_eq(sound_ticks, PackedInt32Array([1, 17, 33, 45]))

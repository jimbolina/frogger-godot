extends GutTest
## Hand-derived frozen Desert croc-head and crack widths, waits, bites and colours.

func _definition(y: int = 100) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 3
	definition.desert = EntityDesertDefinition.new()
	definition.matrix12[10] = y
	return definition

func _entity(definition: EntityDefinition, cels: int = 4) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.entity_index = definition.entity_index
	entity.matrix12 = definition.matrix12.duplicate()
	entity.animation = EntityAnimationState.create(PackedInt32Array([cels]))
	entity.custom_state = EntityCustomState.new()
	return entity

func _result(entity: EntitySnapshot) -> EntityCustomResult:
	var result := EntityCustomResult.new()
	result.entity = entity
	return result

func _croc(definition: EntityDefinition) -> EntitySnapshot:
	var entity: EntitySnapshot = _entity(definition)
	EntityDesertCrocHead.initialize(definition, entity)
	return entity

func _crack(definition: EntityDefinition, cels: int = 4) -> EntitySnapshot:
	var entity: EntitySnapshot = _entity(definition, cels)
	EntityDesertCrack.initialize(definition, entity)
	return entity

func _sound_ids(entity: EntitySnapshot) -> PackedInt32Array:
	var result := PackedInt32Array()
	for request: TickEvent in entity.requests:
		result.append(request.sound_id)
	return result

func test_croc_errors_leave_state_untouched() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _croc(definition)
	entity.live_flags = EntityLiveFlags.CARRIES_FROG_0
	definition.desert = null
	var result: EntityCustomResult = _result(entity)
	assert_ne(EntityDesertCrocHead.update(definition, result), "")
	definition.desert = EntityDesertDefinition.new()
	entity.animation = null
	assert_ne(EntityDesertCrocHead.update(definition, result), "")
	assert_eq(entity.custom_state.mode, EntityDesertCrocHead.Mode.PAUSE3)
	assert_eq(entity.custom_state.count, 0)
	assert_true(entity.custom_state.deadly)
	assert_eq(entity.matrix12[10], 100)
	assert_eq(result.death_animation, -1)
	assert_true(entity.requests.is_empty())

func test_croc_start_is_unsigned_and_one_shot() -> void:
	var definition: EntityDefinition = _definition(-40)
	var entity: EntitySnapshot = _croc(definition)
	assert_eq(entity.custom_state.target.y, 65496)
	assert_true(entity.animation.one_shot)
	definition.desert.rise_height = 60
	definition.desert.rise_speed = 7
	entity.custom_state.mode = EntityDesertCrocHead.Mode.RISE
	assert_eq(EntityDesertCrocHead.update(definition, _result(entity)), "")
	assert_eq(entity.matrix12[10], 65436)
	assert_eq(entity.custom_state.mode, EntityDesertCrocHead.Mode.PAUSE1)

func test_croc_waits_compare_equal_on_a_32_bit_counter() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _croc(definition)
	for tick: int in 200:
		assert_eq(EntityDesertCrocHead.update(definition, _result(entity)), "")
	assert_eq(entity.custom_state.mode, EntityDesertCrocHead.Mode.PAUSE3)
	assert_eq(entity.custom_state.count, 200)
	entity.custom_state.count = 0xffffffff
	assert_eq(EntityDesertCrocHead.update(definition, _result(entity)), "")
	assert_eq(entity.custom_state.mode, EntityDesertCrocHead.Mode.RISE)
	assert_false(entity.custom_state.deadly)
	definition.desert.pause_delay = 50
	entity.custom_state.mode = EntityDesertCrocHead.Mode.PAUSE2
	entity.custom_state.count = 60
	assert_eq(EntityDesertCrocHead.update(definition, _result(entity)), "")
	assert_eq(entity.custom_state.mode, EntityDesertCrocHead.Mode.PAUSE2)
	assert_eq(entity.custom_state.count, 61)

func test_croc_fall_overshoots_the_start() -> void:
	var definition: EntityDefinition = _definition()
	definition.desert.rise_speed = 30
	var entity: EntitySnapshot = _croc(definition)
	entity.custom_state.mode = EntityDesertCrocHead.Mode.FALL
	entity.custom_state.deadly = false
	entity.matrix12[10] = 90
	assert_eq(EntityDesertCrocHead.update(definition, _result(entity)), "")
	assert_eq(entity.matrix12[10], 120)
	assert_eq(entity.custom_state.mode, EntityDesertCrocHead.Mode.PAUSE3)
	assert_true(entity.custom_state.deadly)

func test_croc_bites_only_while_deadly_and_carrying() -> void:
	var definition: EntityDefinition = _definition()
	definition.desert.submerged_delay = 50
	var entity: EntitySnapshot = _croc(definition)
	var result: EntityCustomResult = _result(entity)
	assert_eq(EntityDesertCrocHead.update(definition, result), "")
	assert_eq(result.death_animation, -1)
	assert_true(entity.requests.is_empty())
	entity.live_flags = EntityLiveFlags.CARRIES_FROG_0
	result = _result(entity)
	assert_eq(EntityDesertCrocHead.update(definition, result), "")
	assert_eq(result.death_animation, FrogAnimationCatalog.BITTEN)
	assert_eq(_sound_ids(entity), PackedInt32Array([63]))
	entity.requests.clear()
	entity.custom_state.mode = EntityDesertCrocHead.Mode.RISE
	entity.custom_state.deadly = false
	result = _result(entity)
	assert_eq(EntityDesertCrocHead.update(definition, result), "")
	assert_eq(result.death_animation, -1)
	assert_true(entity.requests.is_empty())

func test_croc_snap_restarts_animation_and_holds_occupied_voice() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _croc(definition)
	entity.custom_state.mode = EntityDesertCrocHead.Mode.SNAP
	entity.custom_state.moving_sound = PackedInt32Array([1, 2, 3])
	entity.animation.cel = 3
	assert_eq(EntityDesertCrocHead.update(definition, _result(entity)), "")
	assert_eq(entity.animation.cel, -1)
	for tick: int in 9:
		assert_eq(EntityDesertCrocHead.update(definition, _result(entity)), "")
	assert_eq(entity.custom_state.mode, EntityDesertCrocHead.Mode.PAUSE2)
	assert_false(entity.custom_state.deadly)
	assert_true(entity.requests.is_empty())
	assert_eq(entity.custom_state.moving_sound, PackedInt32Array([1, 2, 3]))

func test_crack_errors_leave_state_untouched() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _crack(definition)
	definition.desert = null
	var result: EntityCustomResult = _result(entity)
	assert_ne(EntityDesertCrack.update(definition, result, null, true), "")
	definition.desert = EntityDesertDefinition.new()
	entity.animation = null
	assert_ne(EntityDesertCrack.update(definition, result, null, true), "")
	assert_eq(entity.custom_state.mode, EntityDesertCrack.Mode.WAITING_FOR_HITS)
	assert_eq(entity.custom_state.count, 0)
	assert_eq(entity.custom_state.texture_animation_cel, -1)
	assert_true(entity.requests.is_empty())

func test_crack_creation_holds_cel_zero_with_collision() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _entity(definition)
	entity.entity_flags = EntityDefinition.NO_COLLISION
	EntityDesertCrack.initialize(definition, entity)
	assert_eq(entity.entity_flags & EntityDefinition.NO_COLLISION, 0)
	assert_eq(entity.animation.cel, 0)
	assert_false(entity.animation.stepping)
	assert_eq(entity.custom_state.timer, 0)
	assert_false(entity.custom_state.texture_animation_paused)

func test_crack_hits_wrap_at_eight_bits_and_entries_at_sixteen() -> void:
	var definition: EntityDefinition = _definition()
	definition.desert.hops_before = 300
	var entity: EntitySnapshot = _crack(definition)
	entity.custom_state.count = 255
	assert_eq(EntityDesertCrack.update(definition, _result(entity), null, true), "")
	assert_eq(entity.custom_state.count, 0)
	assert_eq(entity.custom_state.texture_animation_cel, (3 - (300 - 255)) & 65535)
	assert_eq(entity.custom_state.mode, EntityDesertCrack.Mode.WAITING_FOR_HITS)
	assert_eq(_sound_ids(entity), PackedInt32Array([48]))
	assert_eq(EntityDesertCrack.update(definition, _result(entity), null, false), "")
	assert_eq(entity.custom_state.count, 0)

func test_crack_opens_the_tick_after_the_trigger_and_ignores_later_hits() -> void:
	var definition: EntityDefinition = _definition()
	definition.desert.hops_before = 1
	var entity: EntitySnapshot = _crack(definition)
	assert_eq(EntityDesertCrack.update(definition, _result(entity), null, true), "")
	assert_eq(entity.custom_state.texture_animation_cel, 2)
	assert_eq(entity.custom_state.mode, EntityDesertCrack.Mode.WAITING_TO_FALL)
	assert_eq(entity.custom_state.timer, 2)
	assert_false(entity.animation.stepping)
	entity.requests.clear()
	assert_eq(EntityDesertCrack.update(definition, _result(entity), null, true), "")
	assert_eq(entity.custom_state.mode, EntityDesertCrack.Mode.FALLING)
	assert_eq(entity.custom_state.timer, 1)
	assert_eq(entity.custom_state.count, 1)
	assert_true(entity.animation.stepping and entity.animation.one_shot)
	assert_true(entity.requests.is_empty(), "the hole sound keeps its distance gate without a frog")

func test_crack_colour_only_on_sinking_updates() -> void:
	var definition: EntityDefinition = _definition(1000)
	definition.desert.hops_before = 1
	var entity: EntitySnapshot = _crack(definition, 2)
	var frog := GameplayState.new()
	frog.frog.matrix12[10] = 1000
	frog.attachment.current_entity_index = entity.entity_index
	assert_eq(EntityDesertCrack.update(definition, _result(entity), frog, true), "")
	assert_eq(EntityDesertCrack.update(definition, _result(entity), frog, false), "")
	assert_eq(_sound_ids(entity), PackedInt32Array([48, 53]))
	var result: EntityCustomResult = _result(entity)
	assert_eq(EntityDesertCrack.update(definition, result, frog, false), "")
	assert_false(entity.colour_scaled, "flipbook still opening")
	assert_false(result.frog_fall_requested)
	entity.animation.advance()
	result = _result(entity)
	assert_eq(EntityDesertCrack.update(definition, result, frog, false), "")
	assert_true(result.frog_fall_requested)
	assert_ne(entity.entity_flags & EntityDefinition.NO_COLLISION, 0)
	assert_false(entity.colour_scaled, "rider drop tick")
	assert_eq(entity.matrix12[10], 1000)
	result = _result(entity)
	assert_eq(EntityDesertCrack.update(definition, result, frog, false), "")
	assert_false(result.frog_fall_requested)
	assert_eq(entity.matrix12[10], 1020)
	assert_eq(entity.colour_scale, Vector3i(125, 125, 125))
	assert_ne(entity.live_flags & EntityLiveFlags.NO_SCREEN_FADE, 0)
	assert_eq(EntityDesertCrack.update(definition, _result(entity), frog, false), "")
	assert_eq(entity.matrix12[10], 1060)
	assert_eq(entity.custom_state.mode, EntityDesertCrack.Mode.FALLING)
	entity.colour_scaled = false
	assert_eq(EntityDesertCrack.update(definition, _result(entity), frog, false), "")
	assert_eq(entity.custom_state.mode, EntityDesertCrack.Mode.FINISHED)
	assert_eq(entity.matrix12[10], 1060)
	assert_eq(entity.colour_scale, Vector3i(120, 120, 120))
	assert_true(entity.colour_scaled, "the finishing update still writes colour")
	entity.colour_scaled = false
	assert_eq(EntityDesertCrack.update(definition, _result(entity), frog, false), "")
	assert_false(entity.colour_scaled)

func test_crack_colour_floors_at_zero() -> void:
	var definition: EntityDefinition = _definition(-2000)
	var entity: EntitySnapshot = _crack(definition, 1)
	entity.custom_state.mode = EntityDesertCrack.Mode.FALLING
	entity.matrix12[10] = 1023
	entity.custom_state.offset_16.y = 1023 << 16
	assert_eq(EntityDesertCrack.update(definition, _result(entity), null, false), "")
	assert_eq(entity.colour_scale, Vector3i.ZERO)
	assert_true(entity.colour_scaled)

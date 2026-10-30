extends GutTest
## Hand-derived frozen Swamp rat jump arcs, roll, run, splash colours, restart and fixed-point translation.

const START: Vector3i = Vector3i(100, -600, 200)

func _definition() -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 4
	definition.matrix12 = PackedInt32Array([0, -4096, 0, 4096, 0, 0, 0, 0, 4096, 9, 9, 9])
	definition.swamp = EntitySwampDefinition.new()
	definition.swamp.rat_speed = 60
	definition.swamp.rat_targets = [START, Vector3i(400, -600, 200), Vector3i(393, -600, 150), Vector3i(453, 0, 150)] as Array[Vector3i]
	assert_eq(definition.swamp.resolve_rat(), "")
	return definition

func _rat(definition: EntityDefinition) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.entity_index = definition.entity_index
	entity.animation = EntityAnimationState.create(PackedInt32Array([4, 5, 6]))
	entity.live_flags = EntityLiveFlags.ANIMATED | EntityLiveFlags.FLIPBOOK
	entity.custom_state = EntityCustomState.new()
	EntitySwampRat.initialize(definition, entity)
	return entity

func _step(definition: EntityDefinition, entity: EntitySnapshot, ticks: int = 1) -> void:
	for tick: int in ticks:
		var result := EntityCustomResult.new()
		result.entity = entity
		assert_eq(EntitySwampRat.update(definition, result), "")

func _translation(entity: EntitySnapshot) -> Vector3i:
	return Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])

func test_creation_places_the_authored_rotation_at_the_start_target_awaiting_restart() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _rat(definition)
	assert_eq(entity.matrix12, PackedInt32Array([0, -4096, 0, 4096, 0, 0, 0, 0, 4096, 100, -600, 200]))
	var custom: EntityCustomState = entity.custom_state
	assert_eq(custom.mode, EntitySwampRat.Mode.RESTART)
	assert_eq(custom.position_4, Vector3i(1600, -9600, 3200))
	assert_eq(custom.previous_y, -600, "Creation stores the unshifted height; restart replaces it")
	assert_false(custom.splashed)
	assert_eq(definition.matrix12[9], 9, "Creation leaves the definition untouched")

func test_missing_operands_zero_durations_and_short_animations_are_issues() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _rat(definition)
	var result := EntityCustomResult.new()
	result.entity = entity
	definition.swamp.jump2_time = 0
	assert_ne(EntitySwampRat.update(definition, result), "")
	definition = _definition()
	definition.swamp.run_time = 0
	assert_ne(EntitySwampRat.update(definition, result), "")
	definition = _definition()
	entity.animation = EntityAnimationState.create(PackedInt32Array([4, 5]))
	assert_ne(EntitySwampRat.update(definition, result), "")
	definition.swamp = null
	assert_ne(EntitySwampRat.update(definition, result), "")
	assert_eq(entity.custom_state.mode, EntitySwampRat.Mode.RESTART)
	assert_false(entity.colour_scaled)

func test_restart_resets_colours_and_the_first_jump_selects_a_one_shot_jump() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _rat(definition)
	entity.animation.cel = 3
	_step(definition, entity)
	var custom: EntityCustomState = entity.custom_state
	assert_eq(custom.mode, EntitySwampRat.Mode.INIT_FIRST_JUMP)
	assert_eq(custom.previous_y, -9600)
	assert_true(entity.colour_scaled)
	assert_eq(entity.colour_scale, Vector3i(128, 128, 128))
	assert_eq(entity.ambient, Vector3i(255, 255, 255))
	assert_eq([entity.animation.action, entity.animation.cel, entity.animation.one_shot], [0, 3, false])
	assert_eq(_translation(entity), START)
	custom.sine_positions = Vector2i(5, 6)
	custom.count = 9
	_step(definition, entity)
	assert_eq(custom.mode, EntitySwampRat.Mode.JUMP1)
	assert_eq([entity.animation.action, entity.animation.cel, entity.animation.one_shot], [EntitySwampRat.Action.JUMP, -1, true])
	assert_eq([custom.count, custom.sine_positions], [0, Vector2i.ZERO])
	assert_eq(_translation(entity), START)

func test_first_jump_lifts_by_the_previous_sine_sample_and_ends_above_the_target() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _rat(definition)
	_step(definition, entity, 2)
	var custom: EntityCustomState = entity.custom_state
	_step(definition, entity)
	assert_eq(custom.position_4, Vector3i(2080, -9600, 3200), "The first sample is sin(0)")
	assert_eq([custom.previous_y, custom.sine_positions.x, custom.count], [-9600, 204, 1])
	_step(definition, entity)
	assert_eq(custom.position_4, Vector3i(2560, -10816, 3200), "rsin(204) = 1261: (1261 * 250 >> 12) << 4 = 1216")
	assert_eq(_translation(entity), Vector3i(160, -676, 200))
	_step(definition, entity, 4)
	assert_eq(custom.position_4.y, -13600, "rsin(1020) rounds to 4096 and peaks at 250 units")
	_step(definition, entity, 3)
	assert_eq(custom.mode, EntitySwampRat.Mode.JUMP1)
	_step(definition, entity)
	assert_eq(custom.mode, EntitySwampRat.Mode.INIT_ROLL)
	assert_eq([custom.count, custom.sine_positions.x], [10, 2040])
	assert_eq(_translation(entity), Vector3i(400, -679, 200))

func test_roll_lasts_twenty_four_updates_then_runs_in_a_loop() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _rat(definition)
	_step(definition, entity, 12)
	var custom: EntityCustomState = entity.custom_state
	entity.animation.cel = 2
	_step(definition, entity)
	assert_eq([custom.mode, custom.count], [EntitySwampRat.Mode.ROLL, 0])
	assert_eq([entity.animation.action, entity.animation.cel, entity.animation.one_shot], [EntitySwampRat.Action.ROLL, -1, true])
	_step(definition, entity, 23)
	assert_eq([custom.mode, custom.count], [EntitySwampRat.Mode.ROLL, 23])
	_step(definition, entity)
	assert_eq([custom.mode, custom.count], [EntitySwampRat.Mode.RUN, 0])
	assert_eq([entity.animation.action, entity.animation.cel, entity.animation.one_shot], [EntitySwampRat.Action.RUN, -1, false])
	assert_eq(_translation(entity), Vector3i(400, -679, 200))

func test_run_moves_by_truncated_velocity_then_jumps_from_the_reached_height() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _rat(definition)
	_step(definition, entity, 37)
	var custom: EntityCustomState = entity.custom_state
	_step(definition, entity)
	assert_eq(custom.position_4, Vector3i(6396, -10864, 3168))
	assert_eq(_translation(entity), Vector3i(399, -679, 198))
	_step(definition, entity, 23)
	assert_eq([custom.mode, custom.count], [EntitySwampRat.Mode.RUN, 24])
	_step(definition, entity)
	assert_eq([custom.mode, custom.count, custom.previous_y], [EntitySwampRat.Mode.JUMP2, 0, -10864])
	assert_eq(custom.position_4, Vector3i(6300, -10864, 2400))
	assert_eq([entity.animation.action, entity.animation.one_shot], [EntitySwampRat.Action.JUMP, true])

func test_second_jump_splashes_once_at_the_water_height_and_restarts() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _rat(definition)
	_step(definition, entity, 62)
	var custom: EntityCustomState = entity.custom_state
	_step(definition, entity)
	assert_eq(custom.position_4, Vector3i(6348, -10384, 2400))
	assert_eq([custom.previous_y, custom.sine_positions.y], [-10384, 102])
	entity.colour_scale = Vector3i(1, 2, 3)
	_step(definition, entity, 16)
	assert_eq(_translation(entity), Vector3i(444, -317, 150))
	assert_false(custom.splashed)
	assert_eq(entity.colour_scale, Vector3i(1, 2, 3))
	assert_true(entity.requests.is_empty())
	_step(definition, entity)
	assert_eq(_translation(entity), Vector3i(447, -254, 150))
	assert_true(custom.splashed)
	assert_eq(TickEvent.trace_lines(entity.requests), ["splash:447:-254:150"], "The splash sprite sits at the >>4 position")
	assert_eq(entity.colour_scale, Vector3i(128, 128, 128))
	assert_eq(entity.ambient, Vector3i(255, 0, 255))
	entity.ambient = Vector3i(7, 7, 7)
	_step(definition, entity)
	assert_eq(entity.ambient, Vector3i(7, 7, 7), "The splash applies once per jump")
	assert_eq(entity.requests.size(), 1)
	_step(definition, entity)
	assert_eq([custom.mode, custom.count, custom.sine_positions.y], [EntitySwampRat.Mode.RESTART, 20, 2040])
	assert_eq(_translation(entity), Vector3i(453, -120, 150))
	_step(definition, entity)
	assert_eq(custom.mode, EntitySwampRat.Mode.INIT_FIRST_JUMP)
	assert_false(custom.splashed)
	assert_eq(entity.ambient, Vector3i(255, 255, 255))
	assert_eq([custom.position_4, custom.previous_y], [Vector3i(1600, -9600, 3200), -9600])
	assert_eq(_translation(entity), START)
	assert_eq(custom.sine_positions, Vector2i(2040, 2040), "Sine positions clear at the next first jump")

func test_translation_is_the_arithmetic_shift_of_the_fixed_point_position() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _rat(definition)
	entity.custom_state.mode = EntitySwampRat.Mode.ROLL
	entity.custom_state.position_4 = Vector3i(-17, -1, 33)
	_step(definition, entity)
	assert_eq(_translation(entity), Vector3i(-2, -1, 2))
	assert_eq(entity.matrix12.slice(0, 9), PackedInt32Array([0, -4096, 0, 4096, 0, 0, 0, 0, 4096]))

func test_respected_colours_multiply_the_retained_values() -> void:
	var definition: EntityDefinition = _definition()
	var entity: EntitySnapshot = _rat(definition)
	entity.live_flags |= EntityLiveFlags.RESPECT_SCALE_COLOURS | EntityLiveFlags.RESPECT_AMBIENT_COLOURS
	entity.colour_scale = Vector3i(64, 200, 0)
	entity.ambient = Vector3i(128, 64, 2)
	_step(definition, entity)
	assert_eq(entity.colour_scale, Vector3i(64, 200, 0))
	assert_eq(entity.ambient, Vector3i(255, 127, 3))

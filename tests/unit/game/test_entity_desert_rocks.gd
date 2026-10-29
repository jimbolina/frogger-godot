extends GutTest
## Hand-derived Desert falling- and rolling-rock transitions, explosion lifecycle and rejection.

func _rock(delay: int = 1, time: int = 2, cels: int = 3) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 4
	definition.behavior = EntityBehaviorCatalog.resolve("DES_FALLING_ROCK")
	definition.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 256, -512, 128])
	definition.desert = EntityDesertDefinition.new()
	definition.desert.rock_delay = delay
	definition.desert.rock_bounces = 1
	definition.desert.rock_targets_resolved = true
	definition.desert.rock_targets.append(Vector3i(512, 0, 128))
	definition.desert.rock_times.append(time)
	definition.desert.explosion_action_lengths = PackedInt32Array([cels])
	return definition

func _created(definition: EntityDefinition, flags: int = 0) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.entity_flags = flags
	entity.custom_state = EntityCustomState.new()
	EntityDesertFallingRock.initialize(definition, entity)
	return entity

func _frog(position: Vector3i) -> GameplayState:
	var state := GameplayState.new()
	state.frog.mode = FrogMode.STATIONARY
	state.frog.flags = FrogFlags.ACTIVE
	state.frog.matrix12[9] = position.x
	state.frog.matrix12[10] = position.y
	state.frog.matrix12[11] = position.z
	return state

func _tick(definition: EntityDefinition, entity: EntitySnapshot, frog: GameplayState = null) -> EntityCustomResult:
	entity.requests.clear()
	var result := EntityCustomResult.new()
	result.entity = entity
	result.random = SourceRandom.create(1)
	assert_eq(EntityDesertFallingRock.update(definition, result, frog), "")
	if entity.custom_state.overlay_animation != null:
		entity.custom_state.overlay_animation.advance()
	return result

func _translation(entity: EntitySnapshot) -> Vector3i:
	return Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])

func test_explosion_starts_hidden_on_action_zero_and_finishes_on_the_last_cel() -> void:
	var entity := EntitySnapshot.new()
	entity.custom_state = EntityCustomState.new()
	EntityDesertExplosion.start(entity, PackedInt32Array([2, 5]), Vector3i(1, 2, 3))
	var custom: EntityCustomState = entity.custom_state
	assert_true(custom.model_hidden)
	assert_eq(custom.overlay_position, Vector3i(1, 2, 3))
	assert_eq(custom.overlay_animation.action, 0)
	assert_eq(custom.overlay_animation.cel, -1)
	assert_false(EntityDesertExplosion.done(custom))
	custom.overlay_animation.advance()
	assert_false(EntityDesertExplosion.done(custom))
	custom.overlay_animation.advance()
	assert_true(EntityDesertExplosion.done(custom))
	custom.overlay_animation.advance()
	assert_eq(custom.overlay_animation.cel, 1, "one-shot holds its last cel")
	EntityDesertExplosion.finish(custom, false)
	assert_null(custom.overlay_animation)
	assert_true(custom.model_hidden)
	EntityDesertExplosion.finish(custom)
	assert_false(custom.model_hidden)
	assert_false(EntityDesertExplosion.valid(PackedInt32Array()))
	assert_false(EntityDesertExplosion.valid(PackedInt32Array([0, 4])))

func test_falling_rock_cycles_through_explosion_reset_and_relaunch() -> void:
	var definition: EntityDefinition = _rock()
	var entity: EntitySnapshot = _created(definition, EntityDefinition.NO_COLLISION)
	var custom: EntityCustomState = entity.custom_state
	var origin: Vector3i = _translation(entity)
	var modes: Array[int] = []
	var explosion_tick: int = -1
	for tick: int in range(1, 16):
		_tick(definition, entity, _frog(_translation(entity)))
		modes.append(custom.mode)
		if custom.mode == EntityDesertFallingRock.Mode.EXPLODING and explosion_tick < 0:
			explosion_tick = tick
			assert_eq(custom.overlay_position, Vector3i(640, 136, 128), "time + 1 steps overshoot; drawn RADIUS above the integrated landing")
			assert_eq(entity.requests.size(), 0)
		assert_eq(entity.entity_flags, EntityDefinition.NO_COLLISION, "collision is never toggled")
	var delay: int = EntityDesertFallingRock.Mode.DELAY
	var targets: int = EntityDesertFallingRock.Mode.TARGETS
	var explode: int = EntityDesertFallingRock.Mode.EXPLODE
	var exploding: int = EntityDesertFallingRock.Mode.EXPLODING
	assert_eq(modes, [delay, delay, targets, targets, targets, explode, exploding, exploding, exploding, delay, targets, targets, targets, explode, exploding] as Array[int])
	assert_eq(explosion_tick, 7)
	assert_eq(origin, Vector3i(256, -512, 128))

func test_falling_rock_reset_restores_the_map_translation_but_keeps_its_roll() -> void:
	var definition: EntityDefinition = _rock(0, 1, 2)
	var entity: EntitySnapshot = _created(definition)
	var custom: EntityCustomState = entity.custom_state
	while custom.mode != EntityDesertFallingRock.Mode.EXPLODING:
		_tick(definition, entity)
	var landed_roll: int = custom.direction
	assert_eq(landed_roll, (-2 * EntityDesertFallingRock.ROLL_STEP) & 4095)
	assert_eq(EntityTransform.IDENTITY.slice(0, 9), entity.matrix12.slice(0, 9))
	assert_false(custom.shadow_visible)
	_tick(definition, entity)
	_tick(definition, entity)
	assert_eq(custom.mode, EntityDesertFallingRock.Mode.DELAY)
	assert_eq(custom.timer, 0)
	assert_eq(custom.count, 0)
	assert_null(custom.overlay_animation)
	assert_true(custom.model_hidden, "the mesh stays hidden until the next launch")
	assert_eq(_translation(entity), Vector3i(256, -512, 128))
	assert_eq(custom.offset_16, Vector3i(256 << 16, -(512 << 16), 128 << 16))
	_tick(definition, entity)
	assert_eq(custom.mode, EntityDesertFallingRock.Mode.TARGETS)
	assert_false(custom.model_hidden)
	assert_eq(custom.direction, landed_roll, "launch does not reset the roll")
	_tick(definition, entity)
	assert_eq(custom.direction, (landed_roll - EntityDesertFallingRock.ROLL_STEP) & 4095)

func test_rock_sounds_follow_the_distance_gate() -> void:
	var definition: EntityDefinition = _rock(0, 0x7fff)
	definition.desert.rock_bounces = 2
	definition.desert.rock_targets.append(Vector3i(768, 0, 128))
	definition.desert.rock_times[0] = 1
	definition.desert.rock_times.append(1)
	var near: EntitySnapshot = _created(definition)
	var far: EntitySnapshot = _created(definition)
	var heard: Array[int] = []
	for tick: int in 6:
		_tick(definition, near, _frog(_translation(near)))
		_tick(definition, far, _frog(_translation(far) + Vector3i(5000, 0, 0)))
		for request: TickEvent in near.requests:
			heard.append(request.sound_id)
		assert_eq(far.requests.size(), 0)
	assert_eq(heard, [EntityDesertFallingRock.BOUNCE_SOUND, EntityDesertFallingRock.BREAK_SOUND] as Array[int])

func test_no_movement_still_lifts_the_drawn_translation_every_targets_tick() -> void:
	var definition: EntityDefinition = _rock(0, 5)
	var entity: EntitySnapshot = _created(definition, EntityDefinition.NO_MOVEMENT)
	_tick(definition, entity)
	_tick(definition, entity)
	_tick(definition, entity)
	_tick(definition, entity)
	assert_eq(entity.matrix12[10], -512 - 2 * EntityDesertFallingRock.RADIUS)
	assert_eq(entity.custom_state.offset_16.y, -(512 << 16))

func test_invalid_falling_rock_operands_leave_the_entity_unchanged() -> void:
	var cases: Array[EntityDefinition] = []
	var missing: EntityDefinition = _rock()
	missing.desert = null
	cases.append(missing)
	var unresolved: EntityDefinition = _rock()
	unresolved.desert.rock_targets_resolved = false
	cases.append(unresolved)
	var no_explosion: EntityDefinition = _rock()
	no_explosion.desert.explosion_action_lengths = PackedInt32Array()
	cases.append(no_explosion)
	var zero_time: EntityDefinition = _rock()
	zero_time.desert.rock_times[0] = 0
	cases.append(zero_time)
	var too_many: EntityDefinition = _rock()
	too_many.desert.rock_bounces = 2
	cases.append(too_many)
	for definition: EntityDefinition in cases:
		var entity: EntitySnapshot = _created(_rock())
		entity.custom_state.mode = EntityDesertFallingRock.Mode.DELAY
		var before: EntitySnapshot = entity.copy()
		var result := EntityCustomResult.new()
		result.entity = entity
		assert_ne(EntityDesertFallingRock.update(definition, result, null), "")
		assert_eq(entity.matrix12, before.matrix12)
		assert_eq(entity.custom_state.mode, before.custom_state.mode)
		assert_eq(entity.custom_state.timer, before.custom_state.timer)
		assert_eq(entity.custom_state.velocity_16, before.custom_state.velocity_16)
		assert_eq(entity.requests.size(), 0)
	var exploding: EntitySnapshot = _created(_rock())
	exploding.custom_state.mode = EntityDesertFallingRock.Mode.EXPLODING
	var orphan := EntityCustomResult.new()
	orphan.entity = exploding
	assert_ne(EntityDesertFallingRock.update(_rock(), orphan, null), "", "EXPLODING requires its flipbook")

func _rolling(cels: int = 2) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 2
	definition.behavior = EntityBehaviorCatalog.resolve("DES_ROLLING_ROCK")
	definition.desert = EntityDesertDefinition.new()
	definition.desert.explosion_action_lengths = PackedInt32Array([cels])
	return definition

func _runner() -> PathRunner:
	var path := PathDefinition.new()
	path.source_id = "unit"
	path.path_index = 0
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 256
	segment.start = Vector3i(0, 0, 0)
	segment.end = Vector3i(256, 0, 0)
	path.segments.append(segment)
	var start := PathStart.new()
	start.speed = 128
	start.flags = PathStart.ACTIVE | PathStart.REPEAT
	return PathRunner.create(path, start)

func test_rolling_rock_explodes_at_the_previous_translation_and_resumes_on_the_last_cel() -> void:
	var definition: EntityDefinition = _rolling()
	var runner: PathRunner = _runner()
	var entity := EntitySnapshot.new()
	entity.entity_flags = EntityDefinition.NO_COLLISION
	entity.path = runner.snapshot()
	entity.matrix12 = EntityTransform.moving(entity.path, 0)
	EntityDesertRollingRock.initialize(definition, entity)
	var custom: EntityCustomState = entity.custom_state
	assert_eq(entity.entity_flags & EntityDefinition.NO_COLLISION, 0)
	var requests: Array[int] = []
	var modes: Array[int] = []
	for tick: int in 6:
		assert_eq(runner.step(tick), "")
		entity.path = runner.snapshot()
		var result := EntityCustomResult.new()
		result.entity = entity
		assert_eq(EntityDesertRollingRock.update(definition, result), "")
		requests.append(result.path_active_request)
		if result.path_active_request >= 0:
			runner.set_active(result.path_active_request == 1)
		if tick == 1:
			assert_eq(custom.overlay_position, Vector3i(128, 0, 0), "explosion sits where the previous update copied")
			assert_eq(entity.matrix12[9], 0, "the wrapped pose is still evaluated")
			assert_true(custom.model_hidden)
			assert_ne(entity.entity_flags & EntityDefinition.NO_COLLISION, 0)
		if custom.overlay_animation != null:
			custom.overlay_animation.advance()
		modes.append(custom.mode)
	var rolling: int = EntityDesertRollingRock.Mode.ROLLING
	var exploding: int = EntityDesertRollingRock.Mode.EXPLODING
	assert_eq(modes, [rolling, exploding, exploding, rolling, rolling, exploding] as Array[int])
	assert_eq(requests, [-1, 0, -1, 1, -1, 0] as Array[int])
	assert_eq(custom.direction, (-2 * EntityDesertRollingRock.ROLL_STEP) & 4095, "resume restarts the roll from zero")

func test_invalid_rolling_rock_leaves_the_entity_unchanged() -> void:
	var entity := EntitySnapshot.new()
	entity.path = _runner().snapshot()
	EntityDesertRollingRock.initialize(_rolling(), entity)
	var before: EntitySnapshot = entity.copy()
	var result := EntityCustomResult.new()
	result.entity = entity
	assert_ne(EntityDesertRollingRock.update(_rolling(0), result), "")
	var pathless := EntitySnapshot.new()
	EntityDesertRollingRock.initialize(_rolling(), pathless)
	var orphan := EntityCustomResult.new()
	orphan.entity = pathless
	assert_ne(EntityDesertRollingRock.update(_rolling(), orphan), "")
	entity.custom_state.mode = EntityDesertRollingRock.Mode.EXPLODING
	assert_ne(EntityDesertRollingRock.update(_rolling(), result), "", "EXPLODING requires its flipbook")
	entity.custom_state.mode = before.custom_state.mode
	assert_eq(entity.matrix12, before.matrix12)
	assert_eq(entity.custom_state.direction, before.custom_state.direction)
	assert_eq(result.path_active_request, -1)

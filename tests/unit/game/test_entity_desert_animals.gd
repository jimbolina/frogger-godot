extends GutTest
## Desert snake, vulture and tumbleweed validation, random draws, boundaries and runner integration.

func _definition(name: String) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 3
	definition.behavior = EntityBehaviorCatalog.resolve(name)
	return definition

func _entity(lengths: PackedInt32Array) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.custom_state = EntityCustomState.new()
	entity.path = PathSnapshot.new()
	entity.path.flags = PathStart.ACTIVE
	entity.path.tangent = Vector3i(0, 0, 4096)
	if not lengths.is_empty():
		entity.animation = EntityAnimationState.create(lengths)
		entity.animation.cel = 0
	return entity

func _result(entity: EntitySnapshot, random: SourceRandom = null) -> EntityCustomResult:
	var result := EntityCustomResult.new()
	result.entity = entity
	result.random = random if random != null else SourceRandom.create(7)
	return result

func _frog(position: Vector3i) -> GameplayState:
	var frog := GameplayState.new()
	frog.frog.matrix12[9] = position.x
	frog.frog.matrix12[10] = position.y
	frog.frog.matrix12[11] = position.z
	return frog

func _grid(size: Vector2i) -> GridDefinition:
	var grid := GridDefinition.new()
	grid.dimensions = size
	return grid

func _count(entity: EntitySnapshot, kind: TickEvent.Kind) -> int:
	var total: int = 0
	for request: TickEvent in entity.requests:
		if request.kind == kind:
			total += 1
	return total

func test_snake_without_four_actions_reports_and_keeps_state() -> void:
	var entity: EntitySnapshot = _entity(PackedInt32Array([20, 16, 20]))
	entity.path.flags |= PathStart.JUST_BOUNCED_END
	entity.path.position = Vector3i(100, 0, 0)
	entity.custom_state.count = 5
	var before: PackedInt32Array = entity.matrix12.duplicate()
	var result: EntityCustomResult = _result(entity)
	assert_ne(EntityDesertSnake.update(_definition("DES_SNAKE"), result, _frog(Vector3i(100, 0, 512))), "")
	assert_eq(entity.matrix12, before)
	assert_eq(entity.custom_state.count, 5)
	assert_eq([entity.animation.action, entity.animation.cel], [0, 0])
	assert_eq(entity.entity_flags, 0)
	assert_eq(result.path_active_request, -1)
	assert_true(entity.requests.is_empty())
	entity.animation = EntityAnimationState.create(PackedInt32Array([20, 16, 20, 20]))
	entity.path = null
	assert_ne(EntityDesertSnake.update(_definition("DES_SNAKE"), _result(entity), null), "")

func test_snake_initialize_clears_no_movement_and_requests() -> void:
	var entity: EntitySnapshot = _entity(PackedInt32Array([20, 16, 20, 20]))
	entity.entity_flags = EntityDefinition.NO_MOVEMENT | EntityDefinition.NO_COLLISION
	entity.custom_state.requested_action = 1
	entity.custom_state.count = 4
	EntityDesertSnake.initialize(_definition("DES_SNAKE"), entity)
	assert_eq(entity.entity_flags, EntityDefinition.NO_COLLISION)
	assert_eq(entity.custom_state.requested_action, -1)
	assert_eq(entity.custom_state.count, 0)
	assert_eq(entity.custom_state.mode, EntityDesertSnake.Action.NORMAL)

func test_snake_range_boundaries_and_rattle_sounds_draw_nothing() -> void:
	var definition: EntityDefinition = _definition("DES_SNAKE")
	for distance: int in [EntityDesertSnake.BITE_RANGE, EntityDesertSnake.RATTLE_RANGE]:
		var entity: EntitySnapshot = _entity(PackedInt32Array([20, 16, 20, 20]))
		var random: SourceRandom = SourceRandom.create(9)
		assert_eq(EntityDesertSnake.update(definition, _result(entity, random), _frog(Vector3i(0, 0, 512 + distance))), "")
		assert_eq(entity.custom_state.requested_action, -1, "distance %d makes no request" % distance)
		assert_eq(random.draw_count, 0)
	var inactive: GameplayState = _frog(Vector3i(0, 0, 512))
	inactive.frog.flags &= ~FrogFlags.ACTIVE
	var resting: EntitySnapshot = _entity(PackedInt32Array([20, 16, 20, 20]))
	assert_eq(EntityDesertSnake.update(definition, _result(resting), inactive), "")
	assert_eq(resting.custom_state.requested_action, -1)
	var rattling: EntitySnapshot = _entity(PackedInt32Array([20, 16, 20, 20]))
	rattling.animation.action = EntityDesertSnake.Action.RATTLE
	rattling.animation.cel = 19
	assert_eq(EntityDesertSnake.update(definition, _result(rattling), _frog(Vector3i(0, 0, 600))), "")
	assert_eq(_count(rattling, TickEvent.Kind.SOUND), 2, "bite range and the finished rattle each play")
	assert_eq([rattling.animation.action, rattling.animation.cel], [EntityDesertSnake.Action.BITE, -1])
	var outside: EntitySnapshot = _entity(PackedInt32Array([20, 16, 20, 20]))
	outside.animation.action = EntityDesertSnake.Action.RATTLE
	outside.animation.cel = 19
	assert_eq(EntityDesertSnake.update(definition, _result(outside), _frog(Vector3i(0, 0, 512 + 513))), "")
	assert_eq(_count(outside, TickEvent.Kind.SOUND), 0)
	assert_eq(outside.animation.action, EntityDesertSnake.Action.NORMAL)

func test_snake_lane_uses_the_dominant_facing_axis() -> void:
	var along_z := PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 1000, 0, 2000])
	var along_x := PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 1000, 0, 2000])
	assert_true(EntityDesertSnake.in_lane(along_z, _frog(Vector3i(1063, 0, 9000))))
	assert_false(EntityDesertSnake.in_lane(along_z, _frog(Vector3i(1064, 0, 2000))))
	assert_true(EntityDesertSnake.in_lane(along_x, _frog(Vector3i(9000, 0, 1937))))
	assert_false(EntityDesertSnake.in_lane(along_x, _frog(Vector3i(1000, 0, 1936))))
	assert_false(EntityDesertSnake.in_lane(along_z, null))

func test_snake_bounce_holds_a_real_runner_for_twenty_updates() -> void:
	var path := PathDefinition.new()
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = 100
	segment.start = Vector3i(0, 0, 0)
	segment.end = Vector3i(100, 0, 0)
	path.segments.append(segment)
	var start := PathStart.new()
	start.distance = 90
	start.speed = 4
	start.flags = PathStart.ACTIVE
	var runner: PathRunner = PathRunner.create(path, start)
	assert_eq(runner.error, "")
	var definition: EntityDefinition = _definition("DES_SNAKE")
	var entity: EntitySnapshot = _entity(PackedInt32Array([20, 16, 20, 20]))
	EntityDesertSnake.initialize(definition, entity)
	var bounce: int = -1
	var positions: Dictionary[int, Vector3i] = {}
	for tick: int in range(1, 40):
		assert_eq(runner.step(tick - 1), "")
		entity.path = runner.snapshot()
		if entity.path.flags & PathStart.JUST_BOUNCED_END:
			bounce = tick
		var result: EntityCustomResult = _result(entity)
		assert_eq(EntityDesertSnake.update(definition, result, null), "")
		if result.path_active_request >= 0:
			runner.set_active(result.path_active_request == 1)
			entity.path = runner.snapshot()
		entity.animation.advance()
		positions[tick] = Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])
		if bounce > 0 and tick > bounce and tick < bounce + 20:
			assert_true(entity.entity_flags & EntityDefinition.NO_MOVEMENT != 0, "tick %d turning" % tick)
		if bounce > 0 and tick == bounce + 20:
			assert_eq(result.path_active_request, 1)
			assert_eq(entity.entity_flags & EntityDefinition.NO_MOVEMENT, 0)
			assert_eq(entity.animation.action, EntityDesertSnake.Action.NORMAL)
	assert_eq(bounce, 3)
	for tick: int in range(bounce + 1, bounce + 21):
		assert_eq(positions[tick], positions[bounce], "tick %d holds" % tick)
	assert_ne(positions[bounce + 21], positions[bounce])

func test_vulture_without_two_actions_reports_and_keeps_state() -> void:
	var entity: EntitySnapshot = _entity(PackedInt32Array([28]))
	entity.path.tangent = Vector3i(0, 0, 4096)
	var before: PackedInt32Array = entity.matrix12.duplicate()
	assert_ne(EntityDesertVulture.update(_definition("DES_VULTURE"), _result(entity)), "")
	assert_eq(entity.matrix12, before)
	assert_eq(entity.custom_state.mode, 0)
	assert_eq(entity.custom_state.requested_action, -1)
	assert_true(entity.custom_state.moving_sound.is_empty())
	assert_true(entity.requests.is_empty())

func test_vulture_equal_tangent_keeps_request_and_set_restarts_current_action() -> void:
	var definition: EntityDefinition = _definition("DES_VULTURE")
	var entity: EntitySnapshot = _entity(PackedInt32Array([4, 3]))
	var random: SourceRandom = SourceRandom.create(5)
	entity.path.tangent = Vector3i(0, EntityDesertVulture.DIVE_TANGENT, 4096)
	assert_eq(EntityDesertVulture.update(definition, _result(entity, random)), "")
	assert_eq(entity.custom_state.requested_action, -1, "equality requests nothing")
	entity.animation.advance()
	entity.path.tangent.y = -127
	assert_eq(EntityDesertVulture.update(definition, _result(entity, random)), "")
	assert_eq(_count(entity, TickEvent.Kind.MOVING), 1)
	entity.animation.advance()
	entity.path.tangent.y = -129
	assert_eq(EntityDesertVulture.update(definition, _result(entity, random)), "")
	assert_eq(entity.custom_state.requested_action, EntityDesertVulture.Action.NORMAL)
	assert_eq(entity.animation.cel, 2)
	entity.animation.advance()
	assert_eq(EntityDesertVulture.update(definition, _result(entity, random)), "")
	assert_eq([entity.animation.action, entity.animation.cel], [EntityDesertVulture.Action.NORMAL, -1], "NORMAL restarts NORMAL")
	entity.animation.advance()
	entity.requests.clear()
	entity.path.tangent.y = 0
	assert_eq(EntityDesertVulture.update(definition, _result(entity, random)), "")
	assert_eq(entity.custom_state.requested_action, EntityDesertVulture.Action.SWOOP)
	assert_eq(_count(entity, TickEvent.Kind.MOVING), 0, "an owned moving sound is not requested again")
	assert_eq(random.draw_count, 0)

func test_tumbleweed_without_grid_keeps_state_and_random() -> void:
	var entity: EntitySnapshot = _entity(PackedInt32Array())
	entity.custom_state.direction = 100
	var random: SourceRandom = SourceRandom.create(11)
	var before: PackedInt32Array = entity.matrix12.duplicate()
	assert_ne(EntityDesertTumbleWeed.update(_definition("DES_TUMBLE_WEED"), _result(entity, random), null), "")
	assert_eq(entity.custom_state.direction, 100)
	assert_eq(entity.custom_state.count, 0)
	assert_eq(entity.matrix12, before)
	assert_eq(random.draw_count, 0)
	entity.path = null
	assert_ne(EntityDesertTumbleWeed.update(_definition("DES_TUMBLE_WEED"), _result(entity, random), _grid(Vector2i(8, 8))), "")
	assert_eq(random.draw_count, 0)

func test_tumbleweed_initialize_keeps_an_owned_moving_sound() -> void:
	var entity: EntitySnapshot = _entity(PackedInt32Array())
	EntityDesertTumbleWeed.initialize(_definition("DES_TUMBLE_WEED"), entity)
	assert_eq(entity.custom_state.moving_sound, PackedInt32Array([EntityDesertTumbleWeed.SOUND, 512, 1024]))
	assert_true(entity.requests.is_empty())
	var owned: EntitySnapshot = _entity(PackedInt32Array())
	owned.custom_state.moving_sound = PackedInt32Array([1, 2, 3])
	EntityDesertTumbleWeed.initialize(_definition("DES_TUMBLE_WEED"), owned)
	assert_eq(owned.custom_state.moving_sound, PackedInt32Array([1, 2, 3]))

func test_tumbleweed_draws_once_per_hop_and_lands_on_the_path() -> void:
	var definition: EntityDefinition = _definition("DES_TUMBLE_WEED")
	var entity: EntitySnapshot = _entity(PackedInt32Array())
	EntityDesertTumbleWeed.initialize(definition, entity)
	entity.path.position = Vector3i(512, -40, 512)
	var random: SourceRandom = SourceRandom.create(99)
	var grid: GridDefinition = _grid(Vector2i(8, 8))
	var draw_ticks: Array[int] = []
	var hops: Array[int] = []
	for tick: int in range(1, 80):
		var draws: int = random.draw_count
		assert_eq(EntityDesertTumbleWeed.update(definition, _result(entity, random), grid), "")
		if random.draw_count > draws:
			assert_eq(random.draw_count - draws, 1)
			assert_eq(random.consumers[-1], "entity:3:tumble_weed_hop")
			assert_eq(entity.matrix12[10], -40, "a hop starts at the path height")
			assert_between(entity.custom_state.count, 6, 9)
			draw_ticks.append(tick)
			hops.append(entity.custom_state.count)
		elif entity.custom_state.count == 0:
			assert_eq(entity.matrix12[10], -40, "a hop lands on the path height")
		else:
			assert_lt(entity.matrix12[10], -40, "tick %d is airborne" % tick)
	for index: int in range(1, draw_ticks.size()):
		assert_eq(draw_ticks[index] - draw_ticks[index - 1], hops[index - 1] + 1)
	assert_eq(draw_ticks[0], 1)

func test_tumbleweed_shadow_hides_on_the_outer_cells() -> void:
	var definition: EntityDefinition = _definition("DES_TUMBLE_WEED")
	var grid: GridDefinition = _grid(Vector2i(8, 6))
	var cases: Array = [[Vector2i(255, 512), false], [Vector2i(256, 512), true], [Vector2i(6 * 256 + 255, 512), true],
		[Vector2i(7 * 256, 512), false], [Vector2i(512, 4 * 256 + 255), true], [Vector2i(512, 5 * 256), false],
		[Vector2i(-1, 512), false], [Vector2i(512, 255), false]]
	for entry: Array in cases:
		var point: Vector2i = entry[0]
		var visible: bool = entry[1]
		var entity: EntitySnapshot = _entity(PackedInt32Array())
		EntityDesertTumbleWeed.initialize(definition, entity)
		entity.path.position = Vector3i(point.x, 0, point.y)
		assert_eq(EntityDesertTumbleWeed.update(definition, _result(entity), grid), "")
		assert_eq(entity.custom_state.shadow_visible, visible, str(point))

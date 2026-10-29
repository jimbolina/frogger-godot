extends GutTest
## Independent frozen Desert snake, vulture and tumbleweed facts driven through the port updates.

func _facts() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/desert.json"))

func _int(row: Dictionary, key: String) -> int:
	var value: int = row[key]
	return value

func _ints(source: Variant) -> PackedInt32Array:
	var values: Array = source
	var result := PackedInt32Array()
	for value: Variant in values:
		var number: int = value
		result.append(number)
	return result

func _definition(name: String) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 0
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

func _result(entity: EntitySnapshot, random: SourceRandom) -> EntityCustomResult:
	var result := EntityCustomResult.new()
	result.entity = entity
	result.random = random
	return result

func _frog(position: Vector3i, active: bool) -> GameplayState:
	var frog := GameplayState.new()
	frog.frog.matrix12[9] = position.x
	frog.frog.matrix12[10] = position.y
	frog.frog.matrix12[11] = position.z
	if not active:
		frog.frog.flags &= ~FrogFlags.ACTIVE
	return frog

func _sounds(entity: EntitySnapshot, kind: TickEvent.Kind) -> Array:
	var ids: Array = []
	for request: TickEvent in entity.requests:
		if request.kind == kind:
			ids.append(request.sound_id)
	return ids

func _set_path_active(entity: EntitySnapshot, request: int) -> void:
	if request == 1:
		entity.path.flags |= PathStart.ACTIVE
	elif request == 0:
		entity.path.flags &= ~PathStart.ACTIVE

func test_tumbleweed_hops_match_independent_facts() -> void:
	var definition: EntityDefinition = _definition("DES_TUMBLE_WEED")
	for fixture: Dictionary in _facts().tumbleweed_hops:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var grid_data: Dictionary = initial.grid
		var grid := GridDefinition.new()
		grid.base = Vector2i(_int(grid_data, "base_x"), _int(grid_data, "base_z"))
		grid.dimensions = Vector2i(_int(grid_data, "xnum"), _int(grid_data, "znum"))
		var start: PackedInt32Array = _ints(initial.start)
		var step: PackedInt32Array = _ints(initial.step)
		var entity: EntitySnapshot = _entity(PackedInt32Array())
		var direction: Vector3 = Vector3(step[0], 0, step[1]).normalized() * 4096.0
		entity.path.tangent = Vector3i(roundi(direction.x), 0, roundi(direction.z))
		EntityDesertTumbleWeed.initialize(definition, entity)
		assert_eq(entity.custom_state.moving_sound, _ints(expected.create_sound), "creation moving sound")
		assert_false(entity.custom_state.shadow_visible)
		var random: SourceRandom = SourceRandom.create(_int(initial, "seed"))
		for row: Dictionary in expected.rows:
			var tick: int = _int(row, "tick")
			var label: String = "seed %d tick %d" % [_int(initial, "seed"), tick]
			entity.path.position = Vector3i(start[0] + step[0] * tick, _int(initial, "path_y"), start[1] + step[1] * tick)
			var draws: int = random.draw_count
			assert_eq(EntityDesertTumbleWeed.update(definition, _result(entity, random), grid), "", label)
			var custom: EntityCustomState = entity.custom_state
			var drawn: int = _int(row, "drawn")
			assert_eq(random.draw_count - draws, 1 if drawn >= 0 else 0, label + " draws")
			assert_eq(custom.count, _int(row, "count"), label + " count")
			if drawn >= 0:
				assert_eq(custom.count, drawn, label + " drawn")
			assert_eq(custom.velocity_16.y, _int(row, "vy"), label + " vy")
			assert_eq(custom.target.y, _int(row, "height"), label + " height")
			assert_eq(entity.matrix12[9], _int(row, "x"), label + " x")
			assert_eq(entity.matrix12[10], _int(row, "y"), label + " y")
			assert_eq(entity.matrix12[11], _int(row, "z"), label + " z")
			assert_eq(custom.direction, _int(row, "rotation"), label + " rotation")
			var shadow: bool = row.shadow_visible
			assert_eq(custom.shadow_visible, shadow, label + " shadow")
			assert_eq(random.state, _int(row, "seed"), label + " seed")

func test_snake_range_match_independent_facts() -> void:
	var definition: EntityDefinition = _definition("DES_SNAKE")
	var lengths := PackedInt32Array([20, 16, 20, 20])
	for fixture: Dictionary in _facts().snake_range:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = str(initial)
		var matrix: PackedInt32Array = _ints(initial.matrix)
		var entity: EntitySnapshot = _entity(lengths)
		EntityDesertSnake.initialize(definition, entity)
		entity.path.position = Vector3i(matrix[9], matrix[10], matrix[11])
		entity.path.tangent = Vector3i(matrix[2], matrix[5], matrix[8])
		var action: int = _int(initial, "action")
		var finished: bool = initial.anim_finished
		entity.animation.action = action
		entity.animation.cel = lengths[action] - 1 if finished else 0
		var pending: bool = initial.pending
		entity.custom_state.mode = _int(initial, "requested")
		entity.custom_state.requested_action = _int(initial, "requested") if pending else -1
		var position: PackedInt32Array = _ints(initial.frog)
		var active: bool = initial.frog_active
		var frog: GameplayState = _frog(Vector3i(position[0], position[1], position[2]), active)
		var random: SourceRandom = SourceRandom.create(1)
		assert_eq(EntityDesertSnake.update(definition, _result(entity, random), frog), "", label)
		assert_eq(entity.matrix12, matrix, label + " pose")
		assert_eq(EntityFrogDistance.distance(entity.matrix12, EntityDesertSnake.PROBE, frog), _int(expected, "distance"), label + " distance")
		var lane: bool = expected.lane
		assert_eq(EntityDesertSnake.in_lane(entity.matrix12, frog), lane, label + " lane")
		var request: bool = expected.request
		assert_eq(entity.custom_state.requested_action >= 0, request, label + " request")
		assert_eq(entity.custom_state.mode, _int(expected, "requested"), label + " requested")
		var set_action: int = _int(expected, "set_action")
		if set_action >= 0:
			assert_eq([entity.animation.action, entity.animation.cel], [set_action, -1], label + " set")
		else:
			assert_eq([entity.animation.action, entity.animation.cel], [action, lengths[action] - 1 if finished else 0], label + " kept")
		assert_eq(_sounds(entity, TickEvent.Kind.SOUND), Array(_ints(expected.rattle_sounds)), label + " rattle")
		assert_eq(random.draw_count, 0, label + " draws")

func test_snake_turn_match_independent_facts() -> void:
	var definition: EntityDefinition = _definition("DES_SNAKE")
	for fixture: Dictionary in _facts().snake_turn:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var lengths: PackedInt32Array = _ints(initial.lengths)
		var bounces: PackedInt32Array = _ints(initial.bounce_ticks)
		var distance: int = _int(initial, "distance")
		var frog: GameplayState = null if distance == EntityFrogDistance.NO_FROG else _frog(Vector3i(0, 0, EntityDesertSnake.PROBE.z + distance), true)
		var entity: EntitySnapshot = _entity(lengths)
		entity.entity_flags = EntityDefinition.NO_MOVEMENT
		EntityDesertSnake.initialize(definition, entity)
		var pending: int = _int(initial, "pending")
		if pending >= 0:
			entity.custom_state.requested_action = pending
			entity.custom_state.mode = pending
		var unpause_ticks: Array = []
		var set_ticks: Array = []
		for row: Dictionary in expected.rows:
			var tick: int = _int(row, "tick")
			var label: String = "%s tick %d" % [str(initial), tick]
			entity.path.flags &= ~PathStart.JUST_CLEAR_MASK
			var bounced: bool = bounces.has(tick)
			if bounced:
				assert_true(entity.path.flags & PathStart.ACTIVE != 0, label + " paused runner cannot bounce")
				entity.path.flags |= PathStart.JUST_BOUNCED_END
			entity.requests.clear()
			var result: EntityCustomResult = _result(entity, SourceRandom.create(1))
			assert_eq(EntityDesertSnake.update(definition, result, frog), "", label)
			_set_path_active(entity, result.path_active_request)
			var set_action: int = entity.animation.action if entity.animation.cel == -1 and not bounced else -1
			entity.animation.advance()
			var custom: EntityCustomState = entity.custom_state
			assert_eq(entity.animation.action, _int(row, "action"), label + " action")
			assert_eq(entity.animation.cel, _int(row, "cel"), label + " cel")
			assert_eq(custom.count, _int(row, "frame_count"), label + " frame_count")
			var path_active: bool = row.path_active
			assert_eq(entity.path.flags & PathStart.ACTIVE != 0, path_active, label + " path_active")
			var no_movement: bool = row.no_movement
			assert_eq(entity.entity_flags & EntityDefinition.NO_MOVEMENT != 0, no_movement, label + " no_movement")
			var unpaused: bool = row.unpaused
			assert_eq(result.path_active_request == 1, unpaused, label + " unpaused")
			var request: bool = row.request
			assert_eq(custom.requested_action >= 0, request, label + " request")
			assert_eq(custom.mode, _int(row, "requested"), label + " requested")
			assert_eq(set_action, _int(row, "set_action"), label + " set_action")
			if unpaused:
				unpause_ticks.append(tick)
			if set_action >= 0:
				set_ticks.append([tick, set_action])
		assert_eq(unpause_ticks, Array(_ints(expected.unpause_ticks)), str(initial) + " unpause ticks")
		var expected_sets: Array = []
		for pair: Array in expected.set_ticks:
			expected_sets.append(Array(_ints(pair)))
		assert_eq(set_ticks, expected_sets, str(initial) + " set ticks")

func test_vulture_tangent_match_independent_facts() -> void:
	var definition: EntityDefinition = _definition("DES_VULTURE")
	for fixture: Dictionary in _facts().vulture_tangent:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var entity: EntitySnapshot = _entity(_ints(initial.lengths))
		var free: bool = initial.moving_sound_free
		if not free:
			entity.custom_state.moving_sound = _ints(expected.moving_sound)
		var random: SourceRandom = SourceRandom.create(1)
		for row: Dictionary in expected.rows:
			var tick: int = _int(row, "tick")
			var label: String = "free %s tick %d" % [str(free), tick]
			entity.path.tangent = Vector3i(0, _int(row, "tangent_y"), 4096)
			entity.requests.clear()
			if free:
				entity.custom_state.moving_sound.clear()
			assert_eq(EntityDesertVulture.update(definition, _result(entity, random)), "", label)
			var set_action: int = entity.animation.action if entity.animation.cel == -1 else -1
			entity.animation.advance()
			var custom: EntityCustomState = entity.custom_state
			assert_eq(custom.mode, _int(row, "requested"), label + " requested")
			var request: bool = row.request
			assert_eq(custom.requested_action >= 0, request, label + " request")
			assert_eq(entity.animation.action, _int(row, "action"), label + " action")
			assert_eq(entity.animation.cel, _int(row, "cel"), label + " cel")
			assert_eq(set_action, _int(row, "set_action"), label + " set_action")
			var sounds: Array = _sounds(entity, TickEvent.Kind.MOVING)
			var sound: int = _int(row, "sound")
			assert_eq(sounds, [sound] if sound >= 0 else [], label + " sound")
			for request_event: TickEvent in entity.requests:
				if request_event.kind == TickEvent.Kind.MOVING:
					assert_eq(PackedInt32Array([request_event.sound_id, request_event.minimum_distance, request_event.maximum_distance]), _ints(expected.moving_sound), label + " radii")
			if sound >= 0 or not free:
				assert_eq(custom.moving_sound, _ints(expected.moving_sound), label + " owned moving sound")
		assert_eq(random.draw_count, 0)

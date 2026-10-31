extends GutTest
## Independent frozen Desert falling- and rolling-rock facts at source widths.

const FACTS: String = "res://tests/golden/synthetic/desert.json"

func _facts() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FACTS))

func _int(value: Variant) -> int:
	var number: float = value
	return int(number)

func _ints(values: Variant) -> Array[int]:
	var source: Array = values
	var result: Array[int] = []
	for value: Variant in source:
		result.append(_int(value))
	return result

func _vec(values: Variant) -> Vector3i:
	var source: Array[int] = _ints(values)
	return Vector3i(source[0], source[1], source[2])

func _list(vector: Vector3i) -> Array[int]:
	return [vector.x, vector.y, vector.z]

func _slice(matrix: PackedInt32Array, from: int, to: int) -> Array[int]:
	var result: Array[int] = []
	for index: int in range(from, to):
		result.append(matrix[index])
	return result

func _frog(position: Vector3i) -> GameplayState:
	var state := GameplayState.new()
	state.frog.mode = FrogMode.STATIONARY
	state.frog.flags = FrogFlags.ACTIVE
	state.frog.matrix12[9] = position.x
	state.frog.matrix12[10] = position.y
	state.frog.matrix12[11] = position.z
	return state

func _grid(raw: Dictionary) -> GridDefinition:
	var grid := GridDefinition.new()
	grid.base = Vector2i(_int(raw.base_x), _int(raw.base_z))
	grid.dimensions = Vector2i(_int(raw.xnum), _int(raw.znum))
	for stack_value: Variant in raw.stacks:
		var pair: Array[int] = _ints(stack_value)
		var stack := GridStackDefinition.new()
		stack.square_count = pair[0]
		stack.first_square_index = pair[1]
		grid.stacks.append(stack)
	for square_value: Variant in raw.squares:
		var square := GridSquareDefinition.new()
		for height: int in _ints(square_value):
			square.vertices.append(Vector3i(0, height, 0))
		grid.squares.append(square)
	return grid

func _sounds(entity: EntitySnapshot) -> Array[int]:
	var result: Array[int] = []
	for request: TickEvent in entity.requests:
		if request.kind == TickEvent.Kind.SOUND:
			result.append(request.sound_id)
	return result

func _overlay_cel(custom: EntityCustomState) -> int:
	return custom.overlay_animation.cel if custom.overlay_animation != null else -1

func _advance_overlay(entity: EntitySnapshot) -> void:
	if entity.animation != null:
		entity.animation.advance()
	if entity.custom_state.overlay_animation != null:
		entity.custom_state.overlay_animation.advance()

func test_rock_targets_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().rock_targets:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var authored: Array[Vector3i] = []
		var times: Array[int] = []
		for target_value: Variant in initial.targets:
			var target: Array[int] = _ints(target_value)
			authored.append(Vector3i(target[0], target[1], target[2]))
			times.append(target[3])
		var bounces: int = _int(initial.bounces)
		var label: String = "bounces %d flags %d first %s" % [bounces, _int(initial.flags), str(authored[0])]
		assert_eq(_int(expected.flags), EntityDesertDefinition.TARGETS_RESOLVED, label)
		var expected_targets: Array = expected.targets
		var first_error: int = -1
		var wanted: Array[Vector3i] = []
		for index: int in expected_targets.size():
			var row: Dictionary = expected_targets[index]
			assert_eq(_int(row.time), times[index], label)
			wanted.append(Vector3i(_int(row.x), _int(row.y), _int(row.z)))
			var failed: bool = row.error
			if failed and first_error < 0:
				first_error = index
		if _int(initial.flags) == EntityDesertDefinition.TARGETS_RESOLVED:
			assert_eq(authored, wanted, "resolved flags skip projection: %s" % label)
			continue
		var raw_grid: Dictionary = initial.grid
		var resolved: EntityDesertRockTargets = EntityDesertRockTargets.resolve(authored, _grid(raw_grid), bounces)
		if bounces < 1:
			assert_ne(resolved.error, "", "port setup rejects zero bounces: %s" % label)
			continue
		if first_error >= 0:
			assert_string_contains(resolved.error, "target %d" % first_error, label)
			continue
		assert_eq(resolved.error, "", label)
		assert_eq(resolved.targets, wanted, label)

func test_rock_velocity_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().rock_velocity:
		var initial: Dictionary = fixture.input
		var velocity: Vector3i = EntityDesertFallingRock.initial_velocity(_vec(initial.position), _vec(initial.target), _int(initial.time))
		assert_eq(_list(velocity), _ints(fixture.expected), str(initial))

func test_rock_pose_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().rock_pose:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var velocity: Vector3i = _vec(initial.velocity)
		var rotation: int = (_int(initial.rotation) - EntityDesertFallingRock.ROLL_STEP) & 4095
		assert_eq(rotation, _int(expected.rotation), str(initial))
		var axes: PackedInt32Array = EntityTransform.from_forward(Vector3i(velocity.x >> 16, velocity.y >> 16, velocity.z >> 16))
		assert_eq(_slice(axes, 0, 9), _ints(expected.axes), str(initial))
		var matrix: PackedInt32Array = EntityDesertFallingRock.pose(velocity, rotation)
		assert_eq(_slice(matrix, 0, 9), _ints(expected.matrix), str(initial))
		assert_eq(_slice(matrix, 9, 12), [0, 0, 0] as Array[int], str(initial))

func _rock_definition(initial: Dictionary) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 0
	definition.behavior = EntityBehaviorCatalog.resolve("DES_FALLING_ROCK")
	definition.matrix12 = PackedInt32Array(_ints(initial.matrix))
	definition.desert = EntityDesertDefinition.new()
	definition.desert.rock_delay = _int(initial.delay)
	definition.desert.rock_bounces = _int(initial.bounces)
	definition.desert.rock_flags = EntityDesertDefinition.TARGETS_RESOLVED
	definition.desert.rock_targets_resolved = true
	for target_value: Variant in initial.targets:
		var target: Array[int] = _ints(target_value)
		definition.desert.rock_targets.append(Vector3i(target[0], target[1], target[2]))
		definition.desert.rock_times.append(target[3])
	definition.desert.explosion_action_lengths = PackedInt32Array([_int(initial.explosion_cels)])
	return definition

func _rock_row(tick: int, entity: EntitySnapshot) -> Dictionary:
	var custom: EntityCustomState = entity.custom_state
	return {"tick": tick, "state": custom.mode, "t": _slice(entity.matrix12, 9, 12), "matrix": _slice(entity.matrix12, 0, 9),
		"rotation": custom.direction, "bounce_index": custom.count, "timer": custom.timer, "velocity": _list(custom.velocity_16),
		"sounds": _sounds(entity), "model_hidden": custom.model_hidden, "shadow_visible": custom.shadow_visible,
		"overlay_cel": _overlay_cel(custom)}

func _expected_rock_row(raw: Dictionary) -> Dictionary:
	return {"tick": _int(raw.tick), "state": _int(raw.state), "t": _ints(raw.t), "matrix": _ints(raw.matrix),
		"rotation": _int(raw.rotation), "bounce_index": _int(raw.bounce_index), "timer": _int(raw.timer),
		"velocity": _ints(raw.velocity), "sounds": _ints(raw.sounds), "model_hidden": raw.model_hidden == true,
		"shadow_visible": raw.shadow_visible == true, "overlay_cel": _int(raw.overlay_cel)}

func test_rock_arc_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().rock_arc:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var definition: EntityDefinition = _rock_definition(initial)
		var entity := EntitySnapshot.new()
		entity.custom_state = EntityCustomState.new()
		EntityDesertFallingRock.initialize(definition, entity)
		var rows: Array[Dictionary] = [_rock_row(0, entity)]
		for tick: int in range(1, _int(initial.ticks) + 1):
			var frog: GameplayState = _frog(Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11]))
			entity.requests.clear()
			var result := EntityCustomResult.new()
			result.entity = entity
			result.random = SourceRandom.create(1)
			var issue: String = EntityDesertFallingRock.update(definition, result, frog)
			assert_eq(issue, "", "tick %d" % tick)
			if not issue.is_empty():
				break
			_advance_overlay(entity)
			rows.append(_rock_row(tick, entity))
		var expected_rows: Array = expected.rows
		assert_eq(rows.size(), expected_rows.size(), str(initial))
		for index: int in mini(rows.size(), expected_rows.size()):
			var raw_row: Dictionary = expected_rows[index]
			assert_eq(rows[index], _expected_rock_row(raw_row), "matrix %s tick %d" % [str(initial.matrix), index])
		var explode: Array[int] = []
		var resets: Array[int] = []
		for index: int in range(1, rows.size()):
			var state: int = rows[index].state
			var previous: int = rows[index - 1].state
			if state == EntityDesertFallingRock.Mode.EXPLODING and previous == EntityDesertFallingRock.Mode.EXPLODE:
				explode.append(index)
			if state == EntityDesertFallingRock.Mode.DELAY and previous == EntityDesertFallingRock.Mode.EXPLODING:
				resets.append(index)
		assert_eq(explode, _ints(expected.explode_ticks), str(initial))
		assert_eq(resets, _ints(expected.reset_ticks), str(initial))

func _path(initial: Dictionary) -> PathRunner:
	var definition := PathDefinition.new()
	definition.source_id = "synthetic"
	definition.path_index = 0
	for raw_value: Variant in initial.segments:
		var raw: Dictionary = raw_value
		var segment := PathSegmentDefinition.new()
		segment.segment_type = _int(raw.segment_type)
		segment.length = _int(raw.length)
		segment.start = _vec(raw.start)
		segment.end = _vec(raw.end)
		definition.segments.append(segment)
	var raw_start: Dictionary = initial.start
	var start := PathStart.new()
	start.segment_index = _int(raw_start.segment_index)
	start.distance = _int(raw_start.distance)
	start.speed = _int(raw_start.speed)
	start.flags = _int(raw_start.flags)
	return PathRunner.create(definition, start)

func _rolling_row(tick: int, entity: EntitySnapshot) -> Dictionary:
	var custom: EntityCustomState = entity.custom_state
	var exploding: bool = custom.overlay_animation != null
	return {"tick": tick, "mode": custom.mode, "t": _slice(entity.matrix12, 9, 12), "matrix": _slice(entity.matrix12, 0, 9),
		"rotation": custom.direction, "segment_index": entity.path.segment_index, "distance": entity.path.segment_distance,
		"path_active": bool(entity.path.flags & PathStart.ACTIVE),
		"just_repeated": bool(entity.path.flags & (PathStart.JUST_REPEATED_START | PathStart.JUST_REPEATED_END)),
		"no_collision": bool(entity.entity_flags & EntityDefinition.NO_COLLISION), "hidden": custom.model_hidden,
		"explosion_t": _list(custom.overlay_position) if exploding else ([] as Array[int]), "overlay_cel": _overlay_cel(custom)}

func _expected_rolling_row(raw: Dictionary) -> Dictionary:
	var explosion: Array[int] = []
	if raw.explosion_t != null:
		explosion = _ints(raw.explosion_t)
	return {"tick": _int(raw.tick), "mode": _int(raw.mode), "t": _ints(raw.t), "matrix": _ints(raw.matrix),
		"rotation": _int(raw.rotation), "segment_index": _int(raw.segment_index), "distance": _int(raw.distance),
		"path_active": raw.path_active == true, "just_repeated": raw.just_repeated == true,
		"no_collision": raw.no_collision == true, "hidden": raw.hidden == true, "explosion_t": explosion,
		"overlay_cel": _int(raw.overlay_cel)}

func test_rolling_rock_cycle_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().rolling_rock_cycle:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var definition := EntityDefinition.new()
		definition.entity_index = 0
		definition.behavior = EntityBehaviorCatalog.resolve("DES_ROLLING_ROCK")
		definition.desert = EntityDesertDefinition.new()
		definition.desert.explosion_action_lengths = PackedInt32Array([_int(initial.explosion_cels)])
		var runner: PathRunner = _path(initial)
		assert_eq(runner.error, "", str(initial.start))
		if not runner.error.is_empty():
			continue
		var entity := EntitySnapshot.new()
		entity.entity_flags = EntityDefinition.NO_COLLISION
		entity.path = runner.snapshot()
		entity.matrix12 = EntityTransform.moving(entity.path, entity.entity_flags)
		entity.custom_state = EntityCustomState.new()
		EntityDesertRollingRock.initialize(definition, entity)
		var rows: Array[Dictionary] = [_rolling_row(0, entity)]
		for tick: int in range(1, _int(initial.ticks) + 1):
			var issue: String = runner.step(tick - 1)
			if issue.is_empty():
				entity.path = runner.snapshot()
				var result := EntityCustomResult.new()
				result.entity = entity
				result.random = SourceRandom.create(1)
				issue = EntityDesertRollingRock.update(definition, result)
				if issue.is_empty() and result.path_active_request >= 0:
					runner.set_active(result.path_active_request == 1)
					entity.path = runner.snapshot()
			assert_eq(issue, "", "tick %d" % tick)
			if not issue.is_empty():
				break
			_advance_overlay(entity)
			rows.append(_rolling_row(tick, entity))
		var expected_rows: Array = expected.rows
		assert_eq(rows.size(), expected_rows.size(), str(initial.start))
		for index: int in mini(rows.size(), expected_rows.size()):
			var raw_row: Dictionary = expected_rows[index]
			assert_eq(rows[index], _expected_rolling_row(raw_row), "start %s tick %d" % [str(initial.start), index])
		var wraps: Array[int] = []
		var resumes: Array[int] = []
		for index: int in range(1, rows.size()):
			if rows[index].just_repeated:
				wraps.append(index)
			var mode: int = rows[index].mode
			var previous: int = rows[index - 1].mode
			if mode == EntityDesertRollingRock.Mode.ROLLING and previous == EntityDesertRollingRock.Mode.EXPLODING:
				resumes.append(index)
		assert_eq(wraps, _ints(expected.explode_ticks), str(initial.start))
		assert_eq(resumes, _ints(expected.resume_ticks), str(initial.start))

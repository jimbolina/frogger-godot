extends GutTest
## Independent frozen Jungle plant timeline and outro-door bounce-back facts at source widths.

const FACTS: String = "res://tests/golden/synthetic/jungle.json"
const SNAP_SOUND: int = 93

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

func _grid(value: Variant) -> GridDefinition:
	var raw: Dictionary = value
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
		var raw_square: Dictionary = square_value
		var square := GridSquareDefinition.new()
		square.flags = _int(raw_square.flags)
		for height: int in _ints(raw_square.corners):
			square.vertices.append(Vector3i(0, height, 0))
		grid.squares.append(square)
	return grid

func _plant_frog(distance: int) -> GameplayState:
	var state := GameplayState.new()
	state.frog.mode = FrogMode.STATIONARY
	state.frog.flags = FrogFlags.ACTIVE if distance != EntityFrogDistance.NO_FROG else 0
	state.frog.matrix12[11] = distance if distance != EntityFrogDistance.NO_FROG else 0
	return state

func _sounds(entity: EntitySnapshot) -> Array[int]:
	var result: Array[int] = []
	for request: TickEvent in entity.requests:
		if request.kind == TickEvent.Kind.SOUND:
			result.append(request.sound_id)
	return result

func test_plant_timeline_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().plant_timeline:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "plant snap_time %d snap_delay %d cels %d" % [_int(initial.snap_time), _int(initial.snap_delay), _int(initial.cels)]
		var definition := EntityDefinition.new()
		definition.entity_index = 0
		definition.behavior = EntityBehaviorCatalog.resolve("JUN_PLANT")
		definition.jungle = EntityJungleDefinition.new()
		definition.jungle.snap_time = _int(initial.snap_time)
		definition.jungle.snap_delay = _int(initial.snap_delay)
		var entity := EntitySnapshot.new()
		entity.entity_index = 0
		entity.live = true
		entity.matrix12 = definition.matrix12.duplicate()
		entity.animation = EntityAnimationState.create(PackedInt32Array([_int(initial.cels)]))
		entity.custom_state = EntityCustomState.new()
		EntityJunglePlant.initialize(definition, entity)
		var distances: Array[int] = _ints(initial.distances)
		var rows: Array = expected.rows
		assert_eq(rows.size(), distances.size() + 1, label)
		var snap_ticks: Array[int] = []
		var reset_ticks: Array[int] = []
		var sound_ticks: Array[int] = []
		for tick: int in range(0, distances.size() + 1):
			var at: String = "%s tick %d" % [label, tick]
			var sounds: Array[int] = []
			var distance: int = -1
			if tick > 0:
				distance = distances[tick - 1]
				var frog: GameplayState = _plant_frog(distance)
				assert_eq(EntityFrogDistance.distance(entity.matrix12, Vector3i.ZERO, frog), distance, at + " distance fixture")
				var result := EntityCustomResult.new()
				result.entity = entity
				entity.requests.clear()
				var previous: int = entity.custom_state.mode
				assert_eq(EntityJunglePlant.update(definition, result, frog), "", at)
				entity.animation.advance()
				sounds = _sounds(entity)
				if entity.custom_state.mode == EntityJunglePlant.Mode.SNAPPING and previous != EntityJunglePlant.Mode.SNAPPING:
					snap_ticks.append(tick)
				if entity.custom_state.mode == EntityJunglePlant.Mode.WAITING and previous == EntityJunglePlant.Mode.DELAY_AFTER_SNAPPING:
					reset_ticks.append(tick)
				if not sounds.is_empty():
					sound_ticks.append(tick)
			var row: Dictionary = rows[tick]
			assert_eq(_int(row.tick), tick, at)
			assert_eq(distance, _int(row.distance), at + " distance")
			assert_eq(entity.custom_state.mode, _int(row.mode), at + " mode")
			assert_eq(entity.custom_state.timer, _int(row.timer), at + " timer")
			assert_eq(entity.custom_state.count, _int(row.snap_timer), at + " snap timer")
			var stepping: bool = row.stepping
			assert_eq(entity.animation.stepping, stepping, at + " stepping")
			assert_eq(entity.animation.cel, _int(row.cel), at + " cel")
			assert_eq(sounds, _ints(row.sounds), at + " sounds")
		assert_eq(snap_ticks, _ints(expected.snap_ticks), label + " snap ticks")
		assert_eq(reset_ticks, _ints(expected.reset_ticks), label + " reset ticks")
		assert_eq(sound_ticks, _ints(expected.sound_ticks), label + " sound ticks")

func test_door_bounce_back_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().door_bounce_back:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "door cell %s direction %d mode %d" % [str(initial.grid_cell), _int(initial.direction), _int(initial.mode)]
		var grid: GridDefinition = _grid(initial.grid)
		var cell: Array[int] = _ints(initial.grid_cell)
		var frog_t: Array[int] = _ints(initial.frog_t)
		var fr_pos: Array[int] = _ints(initial.fr_pos)
		var state := GameplayState.new()
		state.frog.flags = FrogFlags.ACTIVE
		state.frog.cell = Vector2i(cell[0], cell[1])
		state.frog.square_index = -1
		state.frog.direction = _int(initial.direction)
		state.frog.mode = _int(initial.mode)
		state.frog.target_y = _int(initial.fr_y)
		state.frog.old_y = 12345
		state.frog.remaining_ticks = -1
		state.frog.position_16 = Vector3i(fr_pos[0], fr_pos[1], fr_pos[2])
		state.frog.target_16 = Vector3i(111, 222, 333)
		state.frog.velocity_16 = Vector3i(7, 8, 9)
		state.frog.matrix12[9] = frog_t[0]
		state.frog.matrix12[10] = frog_t[1]
		state.frog.matrix12[11] = frog_t[2]
		state.attachment.forbidden_entity_index = -1
		var entity_index: int = 4
		assert_eq(FormCallback.crusher_bounce_back(grid, state, entity_index), "", label)
		var happened: bool = state.frog.remaining_ticks == FormCallback.CRUSHER_JUMP_TICKS
		var expected_happened: bool = expected.happened
		assert_eq(happened, expected_happened, label + " happened")
		var branch: String = "none" if not happened else "user" if _int(initial.mode) >= FrogMode.THROW_1 else "normal"
		var expected_branch: String = expected.branch
		assert_eq(branch, expected_branch, label + " branch")
		var forbid: bool = state.attachment.forbidden_entity_index == entity_index
		var expected_forbid: bool = expected.forbid
		assert_eq(forbid, expected_forbid, label + " forbid")
		assert_eq(state.frog.flags & ~FrogFlags.ACTIVE, _int(expected.flags_added), label + " flags added")
		if not happened:
			assert_eq(state.frog.cell, Vector2i(cell[0], cell[1]), label + " cell unchanged")
			assert_eq(state.frog.direction, _int(initial.direction), label + " direction unchanged")
			assert_eq(state.frog.mode, _int(initial.mode), label + " mode unchanged")
			assert_eq(state.frog.velocity_16, Vector3i(7, 8, 9), label + " velocity unchanged")
			assert_eq([state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11]], frog_t, label + " translation unchanged")
			continue
		var target_cell: Array[int] = _ints(expected.grid)
		assert_eq(state.frog.cell, Vector2i(target_cell[0], target_cell[1]), label + " grid")
		assert_eq(state.frog.square_index, _int(expected.square), label + " square")
		assert_eq(state.frog.direction, _int(expected.direction), label + " direction")
		assert_eq(state.frog.mode, _int(expected.mode), label + " mode")
		assert_eq(state.frog.remaining_ticks, _int(expected.count), label + " count")
		var target: Array = expected.target
		assert_eq(state.frog.target_16.x, _int(target[0]) << 16, label + " target x")
		assert_eq(state.frog.target_16.z, _int(target[2]) << 16, label + " target z")
		if target[1] == null:
			assert_eq(state.frog.target_16.y, 222, label + " target y unchanged")
		else:
			assert_eq(state.frog.target_16.y, _int(target[1]) << 16, label + " target y")
		assert_eq([state.frog.velocity_16.x, state.frog.velocity_16.y, state.frog.velocity_16.z], _ints(expected.velocity), label + " velocity")
		assert_eq([state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11]], _ints(expected.translation), label + " translation")
		assert_eq(state.frog.old_y, 12345 if expected.old_y == null else _int(expected.old_y), label + " old y")

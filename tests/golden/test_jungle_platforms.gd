extends GutTest
## Independent frozen Jungle rope-bridge timeline and bouncy-mushroom bounce facts at source widths.

const FACTS: String = "res://tests/golden/synthetic/jungle.json"
const HOP_SOUND: int = 6
const MUSHROOM_INDEX: int = 3

## Frog whose sound requests are recorded by id instead of allocating logical voices.
class RecordingFrog extends Frog:
	var sounds: Array[int] = []

	func play_sound(_state: GameplayState, sound_id: int, _pitch_offset: int = 0) -> String:
		sounds.append(sound_id)
		return ""

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

func test_rope_bridge_timeline_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().rope_bridge_timeline:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "bridge fall_delay %d hops_before %d hits %s" % [_int(initial.fall_delay), _int(initial.hops_before), str(initial.hit_ticks)]
		var definition := EntityDefinition.new()
		definition.entity_index = 2
		definition.behavior = EntityBehaviorCatalog.resolve("JUN_ROPE_BRIDGE")
		definition.jungle = EntityJungleDefinition.new()
		definition.jungle.fall_delay = _int(initial.fall_delay)
		definition.jungle.hops_before = _int(initial.hops_before)
		var entity := EntitySnapshot.new()
		entity.entity_index = definition.entity_index
		entity.live = true
		entity.matrix12 = definition.matrix12.duplicate()
		entity.animation = EntityAnimationState.create(PackedInt32Array([_int(initial.cels)]))
		entity.custom_state = EntityCustomState.new()
		entity.entity_flags = EntityDefinition.NO_COLLISION
		EntityJungleRopeBridge.initialize(definition, entity)
		var frog := GameplayState.new()
		var rider: bool = initial.rider
		frog.attachment.current_entity_index = definition.entity_index if rider else -1
		var hits: Array[int] = _ints(initial.hit_ticks)
		var rows: Array = expected.rows
		var ticks: int = _int(initial.ticks)
		assert_eq(rows.size(), ticks + 1, label)
		var fall_tick: int = -1
		for tick: int in range(0, ticks + 1):
			var at: String = "%s tick %d" % [label, tick]
			var hit: bool = tick in hits
			var frog_fall: bool = false
			if tick > 0:
				var result := EntityCustomResult.new()
				result.entity = entity
				var was_falling: bool = entity.custom_state.mode == EntityJungleRopeBridge.Mode.FALLING
				assert_eq(EntityJungleRopeBridge.update(definition, result, frog, hit), "", at)
				entity.animation.advance()
				frog_fall = result.frog_fall_requested
				if entity.custom_state.mode == EntityJungleRopeBridge.Mode.FALLING and not was_falling:
					fall_tick = tick
			var row: Dictionary = rows[tick]
			assert_eq(_int(row.tick), tick, at)
			var expected_hit: bool = row.hit
			assert_eq(hit, expected_hit, at + " hit")
			assert_eq(entity.custom_state.mode, _int(row.state), at + " state")
			assert_eq(entity.custom_state.count, _int(row.hits), at + " hits")
			assert_eq(entity.custom_state.timer, _int(row.current_wait), at + " current wait")
			var no_collision: bool = row.no_collision
			assert_eq(bool(entity.entity_flags & EntityDefinition.NO_COLLISION), no_collision, at + " no collision")
			var stepping: bool = row.stepping
			assert_eq(entity.animation.stepping, stepping, at + " stepping")
			var expected_fall: bool = row.frog_fall
			assert_eq(frog_fall, expected_fall, at + " frog fall")
			assert_eq(entity.animation.cel, _int(row.cel), at + " cel")
		assert_eq(fall_tick, _int(expected.fall_tick), label + " fall tick")

func test_mushroom_bounce_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().mushroom_bounce:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "mushroom at %s direction %d controller %d" % [str(initial.entity_t), _int(initial.direction), _int(initial.controller_n)]
		var grid: GridDefinition = _grid(initial.grid)
		var current := GridSquareDefinition.new()
		current.flags = _int(initial.current_square_flags)
		current.vertices.assign([Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO])
		grid.squares.append(current)
		var frog := RecordingFrog.new()
		frog.grid = grid
		frog.random = SourceRandom.create(1)
		var north: int = _int(initial.controller_n)
		frog.controller_directions = PackedInt32Array([north & 3, (north + 1) & 3, (north + 2) & 3, (north + 3) & 3])
		var frog_pos: Array[int] = _ints(initial.frog_pos)
		var state := GameplayState.new()
		state.frog.flags = _int(initial.frog_flags)
		state.frog.mode = FrogMode.STATIONARY
		state.frog.direction = _int(initial.direction)
		state.frog.position_16 = Vector3i(frog_pos[0], frog_pos[1], frog_pos[2])
		frog.update_world(state)
		state.frog.square_index = grid.squares.size() - 1
		state.frog.target_y = _int(initial.fr_y)
		state.attachment.forbidden_entity_index = -1
		var entity_t: Array[int] = _ints(initial.entity_t)
		var matrix := PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, entity_t[0], 0, entity_t[1]])
		var events: Array[TickEvent] = []
		assert_eq(frog.bounce_from_entity(state, MUSHROOM_INDEX, matrix, events), "", label)
		var centred: Dictionary = expected.centred
		assert_eq([state.frog.position_16.x, state.frog.position_16.y, state.frog.position_16.z], _ints(centred.fr_pos), label + " centred position")
		assert_eq([state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11]], _ints(centred.lw), label + " centred translation")
		var forbid: bool = centred.forbid
		assert_eq(state.attachment.forbidden_entity_index == MUSHROOM_INDEX, forbid, label + " forbid")
		assert_eq(state.frog.direction, _int(expected.direction), label + " direction")
		assert_eq(state.frog.mode, _int(expected.mode), label + " mode")
		var result: String = expected.result
		if result == "cobweb":
			var centred_cell: Array[int] = _ints(centred.grid)
			var user_data: Array[int] = _ints(expected.user_data)
			assert_eq(state.frog.cell, Vector2i(centred_cell[0], centred_cell[1]), label + " cobweb keeps the centred cell")
			assert_eq(state.frog.user_target_cell, Vector2i(user_data[0], user_data[1]), label + " cobweb user data")
			assert_eq(frog.sounds, _ints(expected.sounds), label + " sounds")
			continue
		assert_eq(result, "jump", label)
		var cell: Array[int] = _ints(expected.grid)
		assert_eq(state.frog.cell, Vector2i(cell[0], cell[1]), label + " grid")
		var inside: bool = expected.inside
		assert_eq(grid.stack_at(state.frog.cell) != null, inside, label + " inside")
		assert_eq(state.frog.square_index, -1 if expected.square == null else _int(expected.square), label + " square")
		assert_eq(state.frog.flags, _int(expected.flags), label + " flags")
		var to_land: bool = expected.to_land
		assert_eq(bool(state.frog.flags & FrogFlags.JUMP_TO_LAND), to_land, label + " to land")
		var target: Array[int] = _ints(expected.target)
		assert_eq([state.frog.target_16.x, state.frog.target_16.z], [target[0] << 16, target[1] << 16], label + " target")
		assert_eq(state.frog.target_y, _int(expected.fr_y), label + " fr_y")
		assert_eq(state.frog.old_y, _int(expected.old_y), label + " old y")
		assert_eq(state.frog.remaining_ticks, _int(expected.count), label + " count")
		assert_eq([state.frog.velocity_16.x, state.frog.velocity_16.y, state.frog.velocity_16.z], _ints(expected.velocity), label + " velocity")
		assert_eq(frog.sounds, _ints(expected.sounds), label + " sounds")
		assert_eq(state.requests.last_animation_request, FrogAnimationCatalog.HOP, label + " hop animation")
		assert_true(_has_kind(events, TickEvent.Kind.SCORE_5_REQUEST), label + " five points")

func _has_kind(events: Array[TickEvent], kind: TickEvent.Kind) -> bool:
	for event: TickEvent in events:
		if event.kind == kind:
			return true
	return false

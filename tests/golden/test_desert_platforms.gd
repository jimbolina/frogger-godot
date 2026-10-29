extends GutTest
## Independent frozen Desert croc-head and crack timelines at source widths.

const CROC_CELS: int = 12

func _facts() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/synthetic/desert.json"))

func _int(row: Dictionary, key: String) -> int:
	var value: int = row[key]
	return value

func _bool(row: Dictionary, key: String) -> bool:
	var value: bool = row[key]
	return value

func _ints(row: Dictionary, key: String) -> PackedInt32Array:
	var values: Array = row[key]
	var result := PackedInt32Array()
	for item: Variant in values:
		var value: int = item
		result.append(value)
	return result

func _definition(name: String, y: int) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = 0
	definition.behavior = EntityBehaviorCatalog.resolve(name)
	definition.desert = EntityDesertDefinition.new()
	definition.matrix12[10] = y
	return definition

func _entity(definition: EntityDefinition, lengths: PackedInt32Array) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.entity_index = definition.entity_index
	entity.live = true
	entity.matrix12 = definition.matrix12.duplicate()
	entity.animation = EntityAnimationState.create(lengths)
	entity.live_flags = EntityLiveFlags.ANIMATED | EntityLiveFlags.FLIPBOOK
	entity.custom_state = EntityCustomState.new()
	return entity

func _sounds(entity: EntitySnapshot, kind: TickEvent.Kind) -> PackedInt32Array:
	var result := PackedInt32Array()
	for request: TickEvent in entity.requests:
		if request.kind == kind:
			result.append(request.sound_id)
	return result

func test_croc_timeline_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().croc_timeline:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = str(initial)
		var definition: EntityDefinition = _definition("DES_CROC_HEAD", _int(initial, "start_y"))
		var desert: EntityDesertDefinition = definition.desert
		desert.rise_height = _int(initial, "rise_height")
		desert.rise_speed = _int(initial, "rise_speed")
		desert.snap_delay = _int(initial, "snap_delay")
		desert.pause_delay = _int(initial, "pause_delay")
		desert.snap_flag = _int(initial, "snap_flag")
		desert.submerged_delay = _int(initial, "submerged_delay")
		var entity: EntitySnapshot = _entity(definition, PackedInt32Array([CROC_CELS]))
		EntityDesertCrocHead.initialize(definition, entity)
		assert_true(entity.animation.one_shot, label)
		assert_eq(entity.custom_state.target.y, _int(expected, "start_position"), label)
		if not _bool(initial, "moving_sound_free"):
			entity.custom_state.moving_sound = PackedInt32Array([1, 512, 1024])
		var carry: PackedInt32Array = _ints(initial, "carry_ticks")
		var rows: Array = expected.rows
		var kill_tick: int = -1
		var munch_count: int = 0
		var snap_ticks := PackedInt32Array()
		for tick: int in range(1, _int(initial, "ticks") + 1):
			var result := EntityCustomResult.new()
			result.entity = entity
			entity.requests.clear()
			entity.live_flags = (entity.live_flags & ~EntityLiveFlags.CARRIES_FROG) | (EntityLiveFlags.CARRIES_FROG_0 if tick in carry else 0)
			var previous_cel: int = entity.animation.cel
			assert_eq(EntityDesertCrocHead.update(definition, result), "", label)
			var snap_action: bool = previous_cel != -1 and entity.animation.cel == -1
			entity.animation.advance()
			var killed: bool = result.death_animation == FrogAnimationCatalog.BITTEN
			var munch: PackedInt32Array = _sounds(entity, TickEvent.Kind.SOUND)
			var moving: PackedInt32Array = _sounds(entity, TickEvent.Kind.MOVING)
			if killed and kill_tick < 0:
				kill_tick = tick
			munch_count += munch.size()
			if not moving.is_empty():
				snap_ticks.append(tick)
			var row: Dictionary = rows[tick - 1]
			var at: String = "%s tick %d" % [label, tick]
			assert_eq(_int(row, "tick"), tick, at)
			assert_eq(entity.custom_state.mode, _int(row, "mode"), at + " mode")
			assert_eq(entity.matrix12[10], _int(row, "y"), at + " y")
			assert_eq(entity.custom_state.count, _int(row, "wait"), at + " wait")
			assert_eq(entity.custom_state.deadly, _bool(row, "deadly"), at + " deadly")
			assert_eq(tick in carry, _bool(row, "carried"), at + " carried")
			assert_eq(killed, _bool(row, "kill"), at + " kill")
			assert_eq(munch, _ints(row, "munch"), at + " munch")
			assert_eq(snap_action, _bool(row, "snap_action"), at + " snap action")
			assert_eq(moving[0] if not moving.is_empty() else -1, _int(row, "snap_sound"), at + " snap sound")
		assert_eq(rows.size(), _int(initial, "ticks"), label)
		assert_eq(kill_tick, _int(expected, "kill_tick"), label)
		var kill_animation: String = expected.kill_animation
		assert_eq(kill_animation, "BITTEN", label)
		assert_eq(munch_count, _int(expected, "munch_count"), label)
		assert_eq(snap_ticks, _ints(expected, "snap_sound_ticks"), label)

func test_crack_timeline_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().crack_timeline:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = str(initial)
		var definition: EntityDefinition = _definition("DES_CRACK", _int(initial, "y"))
		definition.desert.hops_before = _int(initial, "hops_before")
		var entity: EntitySnapshot = _entity(definition, PackedInt32Array([_int(initial, "cels")]))
		entity.entity_flags = EntityDefinition.NO_COLLISION
		EntityDesertCrack.initialize(definition, entity)
		assert_eq(entity.entity_flags & EntityDefinition.NO_COLLISION, 0, label)
		assert_false(entity.custom_state.texture_animation_paused, label)
		var frog := GameplayState.new()
		frog.frog.matrix12[9] = entity.matrix12[9]
		frog.frog.matrix12[10] = entity.matrix12[10]
		frog.frog.matrix12[11] = entity.matrix12[11]
		frog.attachment.current_entity_index = entity.entity_index
		var hits: PackedInt32Array = _ints(initial, "hit_ticks")
		var rows: Array = expected.rows
		var flipbook_start: int = -1
		var fall_tick: int = -1
		var finished_tick: int = -1
		var cel_entry: int = entity.custom_state.texture_animation_cel
		for tick: int in range(1, _int(initial, "ticks") + 1):
			var result := EntityCustomResult.new()
			result.entity = entity
			entity.requests.clear()
			entity.colour_scaled = false
			var was_stepping: bool = entity.animation.stepping
			var was_finished: bool = entity.custom_state.mode == EntityDesertCrack.Mode.FINISHED
			assert_eq(EntityDesertCrack.update(definition, result, frog, tick in hits), "", label)
			entity.animation.advance()
			if entity.animation.stepping and not was_stepping:
				flipbook_start = tick
			if result.frog_fall_requested:
				fall_tick = tick
			if entity.custom_state.mode == EntityDesertCrack.Mode.FINISHED and not was_finished:
				finished_tick = tick
			var row: Dictionary = rows[tick - 1]
			var at: String = "%s tick %d" % [label, tick]
			var expected_entry: int = _int(row, "cel_entry")
			if expected_entry >= 0:
				cel_entry = expected_entry
			assert_eq(_int(row, "tick"), tick, at)
			assert_eq(entity.custom_state.mode, _int(row, "state"), at + " state")
			assert_eq(entity.custom_state.count, _int(row, "hits"), at + " hits")
			assert_eq(entity.custom_state.texture_animation_cel, cel_entry, at + " cel entry")
			assert_eq(_sounds(entity, TickEvent.Kind.SOUND), _ints(row, "sounds"), at + " sounds")
			assert_eq(entity.animation.cel, _int(row, "anim_cel"), at + " anim cel")
			assert_eq(entity.custom_state.timer, _int(row, "wait"), at + " wait")
			assert_eq(bool(entity.entity_flags & EntityDefinition.NO_COLLISION), _bool(row, "no_collision"), at + " no collision")
			assert_eq(result.frog_fall_requested, _bool(row, "frog_fall"), at + " frog fall")
			assert_eq(entity.matrix12[10], _int(row, "y"), at + " y")
			assert_eq(entity.colour_scale.x if entity.colour_scaled else -1, _int(row, "colour"), at + " colour")
		assert_eq(rows.size(), _int(initial, "ticks"), label)
		assert_eq(flipbook_start, _int(expected, "flipbook_start_tick"), label)
		assert_eq(fall_tick, _int(expected, "fall_tick"), label)
		assert_eq(finished_tick, _int(expected, "finished_tick"), label)

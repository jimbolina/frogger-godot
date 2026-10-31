extends GutTest
## Independent frozen Swamp rat cycle, slug action, weir rotation and LOCAL_ALIGN facts at source widths.

const FACTS: String = "res://tests/golden/synthetic/swamp.json"

var _cache: Dictionary = {}

func _facts() -> Dictionary:
	if _cache.is_empty():
		_cache = JSON.parse_string(FileAccess.get_file_as_string(FACTS))
	return _cache

func _int(value: Variant) -> int:
	var number: float = value
	return int(number)

func _ints(values: Variant) -> Array[int]:
	var source: Array = values
	var result: Array[int] = []
	for value: Variant in source:
		result.append(_int(value))
	return result

func _vector(values: Variant) -> Vector3i:
	var items: Array[int] = _ints(values)
	return Vector3i(items[0], items[1], items[2])

func test_rat_cycle_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().rat_cycle:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "rat speed %d" % _int(initial.speed)
		var definition := EntityDefinition.new()
		definition.entity_index = 0
		definition.behavior = EntityBehaviorCatalog.resolve("SWP_RAT")
		definition.action_lengths = PackedInt32Array(_ints(initial.lengths))
		definition.swamp = EntitySwampDefinition.new()
		definition.swamp.rat_speed = _int(initial.speed)
		for target: Variant in initial.targets:
			definition.swamp.rat_targets.append(_vector(target))
		assert_eq(definition.swamp.resolve_rat(), "", label)
		var resolved: Dictionary = expected.resolved
		var swamp: EntitySwampDefinition = definition.swamp
		assert_eq([swamp.run_speed, swamp.jump1_time, swamp.jump1_sine_step, swamp.run_time, swamp.jump2_time, swamp.jump2_sine_step],
			[_int(resolved.run_speed), _int(resolved.jump1_time), _int(resolved.jump1_sine_step), _int(resolved.run_time), _int(resolved.jump2_time), _int(resolved.jump2_sine_step)], label + " timing")
		assert_eq([swamp.jump1_velocity_4, swamp.run_velocity_4, swamp.jump2_velocity_4],
			[_vector(resolved.jump1_velocity_4), _vector(resolved.run_velocity_4), _vector(resolved.jump2_velocity_4)], label + " velocities")
		var entity := EntitySnapshot.new()
		entity.entity_index = 0
		entity.live = true
		entity.matrix12 = definition.matrix12.duplicate()
		entity.animation = EntityAnimationState.create(definition.action_lengths)
		entity.custom_state = EntityCustomState.new()
		EntitySwampRat.initialize(definition, entity)
		var splash_ticks: Array[int] = []
		for row: Dictionary in expected.rows:
			var tick: int = _int(row.tick)
			var at: String = "%s tick %d" % [label, tick]
			if tick > 0:
				var result := EntityCustomResult.new()
				result.entity = entity
				entity.requests.clear()
				var was_splashed: bool = entity.custom_state.splashed
				assert_eq(EntitySwampRat.update(definition, result), "", at)
				entity.animation.advance()
				if entity.custom_state.splashed and not was_splashed:
					splash_ticks.append(tick)
			var custom: EntityCustomState = entity.custom_state
			assert_eq(custom.mode, _int(row.mode), at + " mode")
			assert_eq(custom.count, _int(row.count), at + " count")
			assert_eq(custom.position_4, _vector(row.position_4), at + " position")
			assert_eq(custom.previous_y, _int(row.previous_y), at + " previous y")
			var sines: Array[int] = _ints(row.sine_positions)
			assert_eq(custom.sine_positions, Vector2i(sines[0], sines[1]), at + " sine positions")
			var splashed: bool = row.splashed
			assert_eq(custom.splashed, splashed, at + " splashed")
			assert_eq(entity.animation.action, _int(row.action), at + " action")
			var one_shot: bool = row.one_shot
			assert_eq(entity.animation.one_shot, one_shot, at + " one shot")
			assert_eq(entity.animation.cel, _int(row.cel), at + " cel")
			assert_eq([entity.matrix12[9], entity.matrix12[10], entity.matrix12[11]], _ints(row.translation), at + " translation")
			if row.colour_scale != null:
				assert_true(entity.colour_scaled, at + " colour scaled")
				assert_eq(entity.colour_scale, _vector(row.colour_scale), at + " colour scale")
				assert_eq(entity.ambient, _vector(row.ambient), at + " ambient")
		assert_eq(splash_ticks, _ints(expected.splash_ticks), label + " splash ticks")

func test_slug_action_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().slug_action:
		var initial: Dictionary = fixture.input
		var label: String = "slug motion %d actions %s" % [_int(initial.motion_type), str(initial.lengths)]
		var segment := PathSegmentDefinition.new()
		segment.segment_type = PathSegmentDefinition.LINE
		segment.length = 100
		segment.end = Vector3i(100, 0, 0)
		var path := PathDefinition.new()
		path.segments.append(segment)
		var definition := EntityDefinition.new()
		definition.entity_name = "SWP_SLUG"
		definition.behavior = EntityBehaviorCatalog.resolve("SWP_SLUG")
		definition.entity_index = 0
		definition.unique_id = 7
		definition.path_definition = path
		definition.path_start = PathStart.new()
		definition.path_start.speed = 10
		definition.action_lengths = PackedInt32Array(_ints(initial.lengths))
		definition.swamp = EntitySwampDefinition.new()
		definition.swamp.motion_type = _int(initial.motion_type)
		var run: EntityRun = EntityRun.create([definition])
		assert_eq(run.error, "", label)
		if not run.error.is_empty():
			continue
		var expected: Dictionary = fixture.expected
		assert_eq(run.snapshot().entities[0].animation.action, _int(expected.action), label)

func _table(bank: NameBank, programs: Dictionary) -> ScriptTable:
	var table := ScriptTable.new()
	var highest: int = 0
	for key: String in programs:
		highest = maxi(highest, key.to_int())
	for id: int in range(highest + 1):
		var program := EntityScript.new()
		program.id = id
		program.name = bank.name_of(id)
		var words: Array[int] = [38]
		if programs.has(str(id)):
			words = _ints(programs[str(id)])
		var cursor: int = 0
		while cursor < words.size():
			var command := EntityScript.Command.new()
			command.opcode = words[cursor]
			var width: int = EntityScriptDefinition.WIDTHS[command.opcode]
			command.arguments = PackedInt32Array(words.slice(cursor + 1, cursor + width))
			program.commands.append(command)
			cursor += width
		table.scripts.append(program)
	return table

func test_weir_matrix_and_rotation_match_independent_facts() -> void:
	var weir: Dictionary = _facts().weir_matrix
	for fixture: Dictionary in weir.overrides:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var matrix := PackedInt32Array(_ints(initial.matrix))
		assert_eq(EntitySetup.weir_matrix(matrix), PackedInt32Array(_ints(expected.matrix)), "weir override %s" % str(matrix))
	var library := FrogLordConfigLibrary.new()
	var names: GameNameLists = GameNameListsReader.load_for(library.load_version("pc-retail-v3.0e"), library)
	assert_not_null(names)
	if names == null:
		return
	var bank: NameBank = names.scripts
	var registers: Dictionary = _facts().script_registers
	var programs: Dictionary = registers.programs
	var table: ScriptTable = _table(bank, programs)
	for fixture: Dictionary in weir.rotation:
		var initial: Dictionary = fixture.input
		var root: int = _int(initial.root)
		assert_eq(bank.name_of(root), "SCRIPT_SWP_WEIR_ROTATE")
		var behavior: EntityBehavior = EntityBehaviorCatalog.resolve("SWP_STAT_WEIR")
		var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, bank, root, behavior, PackedByteArray(_ints(initial.payload)))
		assert_eq(setup.error, "", "weir script")
		if setup.definition == null:
			continue
		var authored := PackedInt32Array(_ints(initial.authored))
		var matrix: PackedInt32Array = authored.duplicate()
		var state: EntityScriptState = EntityScriptState.create(root)
		var animation: EntityAnimationState = EntityAnimationState.create(PackedInt32Array())
		var random: SourceRandom = SourceRandom.create(1)
		var expected: Dictionary = fixture.expected
		for row: Dictionary in expected.rows:
			var at: String = "weir tick %d" % _int(row.tick)
			var context := EntityUpdateContext.new()
			context.has_path = false
			context.base_matrix = matrix.duplicate()
			context.authored_matrix = authored.duplicate()
			var result: EntityUpdateResult = EntityScriptRunner.update(setup.definition, state, animation, context, random)
			assert_eq(result.error, "", at)
			if not result.error.is_empty():
				break
			state = result.script_state
			animation = result.animation
			random = result.random
			matrix = result.matrix12
			assert_eq(state.entity_type, 1, at + " matrix entity")
			assert_eq(state.cursor, _int(row.cursor), at + " cursor")
			assert_eq(state.angles, _vector(row.angles), at + " angles")
			assert_eq(state.angular_counts, _vector(row.angle_counts), at + " angle counts")
			assert_eq(matrix, PackedInt32Array(_ints(row.matrix)), at + " matrix")

func test_local_align_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().local_align:
		var initial: Dictionary = fixture.input
		var path := PathSnapshot.new()
		path.position = _vector(initial.position)
		path.tangent = _vector(initial.tangent)
		var previous := PackedInt32Array(_ints(initial.previous))
		var label: String = "local align tangent %s previous m20 %d" % [str(path.tangent), previous[6]]
		var expected: Dictionary = fixture.expected
		assert_eq(EntityTransform.moving_locally_aligned(path, EntityDefinition.LOCAL_ALIGN, previous), PackedInt32Array(_ints(expected.matrix)), label)

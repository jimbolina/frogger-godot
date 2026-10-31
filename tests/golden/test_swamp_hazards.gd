extends GutTest
## Independent frozen Swamp squirt, crusher, press, crusher callback and barrel-script facts at source widths.

## The imported FrogLord name lists of the retail build.
const NAMES: String = "res://assets/tables/names.tres"
const FACTS: String = "res://tests/golden/synthetic/swamp.json"
const ENTITY_INDEX: int = 4

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

func _translation(entity: EntitySnapshot) -> Array[int]:
	return [entity.matrix12[9], entity.matrix12[10], entity.matrix12[11]]

func _sounds(requests: Array[TickEvent]) -> Array[int]:
	var result: Array[int] = []
	for request: TickEvent in requests:
		if request.kind == TickEvent.Kind.SOUND:
			result.append(request.sound_id)
	return result

func _definition(kind: String, matrix: Variant) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.entity_index = ENTITY_INDEX
	definition.behavior = EntityBehaviorCatalog.resolve(kind)
	definition.matrix12 = PackedInt32Array(_ints(matrix))
	definition.swamp = EntitySwampDefinition.new()
	return definition

func _entity(definition: EntityDefinition) -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.entity_index = definition.entity_index
	entity.live = true
	entity.matrix12 = definition.matrix12.duplicate()
	entity.custom_state = EntityCustomState.new()
	return entity

func _frog(position: Variant) -> GameplayState:
	var state := GameplayState.new()
	state.frog.mode = FrogMode.STATIONARY
	if position == null:
		state.frog.flags = 0
		return state
	var at: Array[int] = _ints(position)
	state.frog.flags = FrogFlags.ACTIVE
	state.frog.matrix12[9] = at[0]
	state.frog.matrix12[10] = at[1]
	state.frog.matrix12[11] = at[2]
	return state

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

func _result(entity: EntitySnapshot) -> EntityCustomResult:
	var result := EntityCustomResult.new()
	result.entity = entity
	entity.requests.clear()
	return result

func test_squirt_timeline_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().squirt_timeline:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "squirt delay %d drop %d" % [_int(initial.time_delay), _int(initial.drop_time)]
		var definition: EntityDefinition = _definition("SWP_SQUIRT", initial.matrix)
		definition.swamp.time_delay = _int(initial.time_delay)
		definition.swamp.drop_time = _int(initial.drop_time)
		definition.swamp.target = _vector(initial.target)
		var entity: EntitySnapshot = _entity(definition)
		EntitySwampSquirt.initialize(definition, entity)
		var frog: GameplayState = _frog(initial.frog)
		var sound_ticks: Array[int] = []
		for row: Dictionary in expected.rows:
			var tick: int = _int(row.tick)
			var at: String = "%s tick %d" % [label, tick]
			var sounds: Array[int] = []
			if tick > 0:
				var result: EntityCustomResult = _result(entity)
				assert_eq(EntitySwampSquirt.update(definition, result, frog), "", at)
				sounds = _sounds(entity.requests)
				if not sounds.is_empty():
					sound_ticks.append(tick)
			var custom: EntityCustomState = entity.custom_state
			assert_eq(custom.mode, _int(row.mode), at + " mode")
			assert_eq(custom.timer, _int(row.timer), at + " timer")
			assert_eq(custom.velocity_16, _vector(row.velocity), at + " velocity")
			assert_eq(_translation(entity), _ints(row.translation), at + " translation")
			assert_eq(sounds, _ints(row.sounds), at + " sounds")
		assert_eq(sound_ticks, _ints(expected.sound_ticks), label + " sound ticks")

func test_crusher_timeline_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().crusher_timeline:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "crusher direction %d speed %d delay %d" % [_int(initial.direction), _int(initial.speed), _int(initial.delay)]
		var definition: EntityDefinition = _definition("SWP_CRUSHER", initial.matrix)
		definition.swamp.speed = _int(initial.speed)
		definition.swamp.distance = _int(initial.distance)
		definition.swamp.direction = _int(initial.direction)
		definition.swamp.delay = _int(initial.delay)
		var entity: EntitySnapshot = _entity(definition)
		EntitySwampCrusher.initialize(definition, entity)
		assert_eq(entity.custom_state.moving_sound, PackedInt32Array(_ints(expected.moving_sound)), label + " moving sound")
		var hits: Array[int] = _ints(initial.callback_ticks)
		for row: Dictionary in expected.rows:
			var tick: int = _int(row.tick)
			var at: String = "%s tick %d" % [label, tick]
			if tick > 0:
				if tick in hits:
					entity.custom_state.count = 5
				assert_eq(EntitySwampCrusher.update(definition, _result(entity)), "", at)
			var custom: EntityCustomState = entity.custom_state
			assert_eq(custom.mode, _int(row.mode), at + " mode")
			assert_eq(custom.timer, _int(row.timer), at + " timer")
			assert_eq(custom.direction, _int(row.direction), at + " direction")
			assert_eq(custom.count, _int(row.count), at + " count")
			assert_eq(_translation(entity), _ints(row.translation), at + " translation")

func test_press_timeline_match_independent_facts() -> void:
	for fixture: Dictionary in _facts().press_timeline:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "press direction %d speed %d delay %d" % [_int(initial.direction), _int(initial.speed), _int(initial.delay)]
		var definition: EntityDefinition = _definition("SWP_PRESS", initial.matrix)
		definition.swamp.speed = _int(initial.speed)
		definition.swamp.distance = _int(initial.distance)
		definition.swamp.direction = _int(initial.direction)
		definition.swamp.delay = _int(initial.delay)
		var entity: EntitySnapshot = _entity(definition)
		EntitySwampPress.initialize(definition, entity)
		assert_eq(entity.custom_state.moving_sound, PackedInt32Array(_ints(expected.moving_sound)), label + " moving sound")
		var frog: GameplayState = _frog(initial.frog)
		var carried: Array[int] = _ints(initial.carry_ticks)
		var sound_ticks: Array[int] = []
		for row: Dictionary in expected.rows:
			var tick: int = _int(row.tick)
			var at: String = "%s tick %d" % [label, tick]
			var sounds: Array[int] = []
			if tick > 0:
				entity.live_flags = EntityLiveFlags.CARRIES_FROG_0 if tick in carried else 0
				assert_eq(EntitySwampPress.update(definition, _result(entity), frog), "", at)
				sounds = _sounds(entity.requests)
				if not sounds.is_empty():
					sound_ticks.append(tick)
			var custom: EntityCustomState = entity.custom_state
			assert_eq(custom.mode, _int(row.mode), at + " mode")
			assert_eq(custom.timer, _int(row.timer), at + " timer")
			assert_eq(custom.direction, _int(row.direction), at + " direction")
			assert_eq(_translation(entity), _ints(row.translation), at + " translation")
			assert_eq(sounds, _ints(row.sounds), at + " sounds")
		assert_eq(sound_ticks, _ints(expected.sound_ticks), label + " sound ticks")

func test_swamp_crusher_callback_match_independent_facts() -> void:
	var index: int = 0
	for fixture: Dictionary in _facts().swamp_crusher_callback:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "crusher callback %d velocity %s count %d" % [index, str(initial.velocity), _int(initial.count)]
		index += 1
		var form: Dictionary = initial.form
		var contact := FormContactDefinition.new()
		contact.entity_index = ENTITY_INDEX
		contact.offsets = Vector2i(_int(form.xofs), _int(form.zofs))
		contact.dimensions = Vector2i(_int(form.xnum), _int(form.znum))
		contact.height = _int(form.height)
		contact.max_y = _int(form.max_y)
		contact.grid_flags = PackedInt32Array(_ints(form.grid_flags))
		contact.has_form_data = _int(form.datas) > 0
		contact.callback_kind = FormCallback.Kind.CRUSHER_BOUNCE_BACK
		var collision := EntityCollisionDefinition.new()
		collision.contacts.append(contact)
		var frog := Frog.new()
		frog.grid = _grid(initial.grid)
		frog.theme = FormCallback.SWAMP_THEME
		frog.entity_collision = collision
		var cell: Array[int] = _ints(initial.grid_cell)
		var frog_t: Array[int] = _ints(initial.frog_t)
		var state := GameplayState.new()
		var frog_flags: int = _int(initial.frog_flags)
		state.frog.flags = FrogFlags.ACTIVE | FrogFlags.CONTROL_ACTIVE | frog_flags
		state.frog.cell = Vector2i(cell[0], cell[1])
		state.frog.square_index = -1
		state.frog.direction = _int(initial.direction)
		state.frog.mode = _int(initial.mode)
		state.frog.target_y = _int(initial.fr_y)
		state.frog.old_y = 12345
		state.frog.remaining_ticks = -1
		state.frog.position_16 = _vector(initial.fr_pos)
		state.frog.target_16 = Vector3i(111, 222, 333)
		state.frog.velocity_16 = _vector(initial.velocity)
		state.frog.matrix12[9] = frog_t[0]
		state.frog.matrix12[10] = frog_t[1]
		state.frog.matrix12[11] = frog_t[2]
		state.attachment.forbidden_entity_index = -1
		var definition: EntityDefinition = _definition("SWP_CRUSHER", initial.entity_matrix)
		var entity: EntitySnapshot = _entity(definition)
		entity.custom_state.count = _int(initial.count)
		var events: Array[TickEvent] = []
		assert_eq(EntitySwampCrusherCallback.apply(definition, entity, frog, state, events), "", label)
		assert_eq(entity.custom_state.count, _int(expected.cr_count), label + " cr_count")
		var happened: bool = state.frog.remaining_ticks == FormCallback.CRUSHER_JUMP_TICKS
		var expected_happened: bool = expected.happened
		assert_eq(happened, expected_happened, label + " happened")
		var bounce: String = "none" if not happened else "user" if _int(initial.mode) >= FrogMode.THROW_1 else "normal"
		var expected_bounce: String = expected.bounce
		assert_eq(bounce, expected_bounce, label + " bounce")
		var forbid: bool = state.attachment.forbidden_entity_index == ENTITY_INDEX
		var expected_forbid: bool = expected.forbid
		assert_eq(forbid, expected_forbid, label + " forbid")
		var jump_flags: int = FrogFlags.JUMP_TO_LAND | FrogFlags.JUMP_FROM_COLLPRIM
		assert_eq(state.frog.flags & jump_flags, (frog_flags | _int(expected.flags_added)) & jump_flags, label + " flags added")
		assert_eq(state.frog.velocity_16, _vector(expected.velocity_after), label + " velocity after any kill")
		assert_eq([state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11]], _ints(expected.translation), label + " translation")
		var killed: bool = expected.killed
		assert_eq(bool(state.frog.flags & FrogFlags.MUST_DIE), killed, label + " killed")
		if killed:
			assert_eq(state.frog.death_equate, FrogAnimationCatalog.SQUISHED, label + " death")
		if not happened:
			assert_eq(state.frog.cell, Vector2i(cell[0], cell[1]), label + " cell unchanged")
			assert_eq(state.frog.direction, _int(initial.direction), label + " direction unchanged")
			assert_eq(state.frog.mode, _int(initial.mode), label + " mode unchanged")
			continue
		var target_cell: Array[int] = _ints(expected.grid)
		assert_eq(state.frog.cell, Vector2i(target_cell[0], target_cell[1]), label + " grid")
		assert_eq(state.frog.square_index, _int(expected.square), label + " square")
		assert_eq(state.frog.direction, _int(expected.direction), label + " direction")
		assert_eq(state.frog.mode, _int(expected.mode), label + " mode")
		assert_eq(state.frog.remaining_ticks, _int(expected.frog_count), label + " count")
		var target: Array = expected.target
		assert_eq(state.frog.target_16.x, _int(target[0]) << 16, label + " target x")
		assert_eq(state.frog.target_16.z, _int(target[2]) << 16, label + " target z")
		if target[1] == null:
			assert_eq(state.frog.target_16.y, 222, label + " target y unchanged")
		else:
			assert_eq(state.frog.target_16.y, _int(target[1]) << 16, label + " target y")
		assert_eq(state.frog.old_y, 12345 if expected.old_y == null else _int(expected.old_y), label + " old y")

func _names() -> NameBank:
	var names: GameNameLists = load(NAMES) as GameNameLists
	assert_not_null(names)
	return names.scripts if names != null else null

## Builds a supplied-table stand-in holding the frozen-source programs under their FrogLord ids.
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

func test_script_register_setup_match_independent_facts() -> void:
	var bank: NameBank = _names()
	if bank == null:
		return
	var path_root: int = bank.index_of("SCRIPT_SWP_NUCLEAR_BARLLEL_WAITING")
	var matrix_root: int = bank.index_of("SCRIPT_SWP_BOBBING_WASTE_BARREL")
	var registers: Dictionary = _facts().script_registers
	for fixture: Dictionary in registers.setup:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var layout: String = initial.layout
		var offset: int = _int(initial.offset)
		var count: int = _int(initial.count)
		var payload := PackedByteArray(_ints(initial.payload))
		var label: String = "%s registers offset %d count %d bytes %d" % [layout, offset, count, payload.size()]
		var root: int = path_root if layout == "path" else matrix_root
		var programs: Dictionary = {str(root): [31, offset, count, 38]}
		var behavior: EntityBehavior = EntityBehaviorCatalog.resolve("NUCLEAR_BARREL" if layout == "path" else "DYNAMIC")
		assert_eq(behavior.layout, EntityBehavior.Layout.PATH if layout == "path" else EntityBehavior.Layout.MATRIX, label)
		var setup: EntityScriptSetup = EntityScriptSetup.from_tables(_table(bank, programs), bank, root, behavior, payload)
		var defined: bool = expected.source_defined
		if not defined:
			assert_ne(setup.error, "", label + " reads outside the source register storage or entity data")
			continue
		assert_eq(setup.error, "", label)
		if setup.definition == null:
			continue
		assert_eq(setup.definition.payload_offset, offset, label + " offset")
		assert_eq(setup.definition.payload_registers, PackedInt32Array(_ints(expected.registers)), label + " registers")
		assert_eq(setup.definition.validate(PackedInt32Array(), 0, layout == "path"), "", label + " validates")

func test_script_register_timelines_match_independent_facts() -> void:
	var bank: NameBank = _names()
	if bank == null:
		return
	var registers: Dictionary = _facts().script_registers
	var programs: Dictionary = registers.programs
	var table: ScriptTable = _table(bank, programs)
	for fixture: Dictionary in registers.timeline:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = initial.name
		var behavior_name: String = initial.behavior
		var behavior: EntityBehavior = EntityBehaviorCatalog.resolve(behavior_name)
		var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, bank, _int(initial.root), behavior, PackedByteArray(_ints(initial.payload)))
		assert_eq(setup.error, "", label)
		if setup.definition == null:
			continue
		var has_path: bool = behavior.layout == EntityBehavior.Layout.PATH
		var authored := PackedInt32Array(_ints(initial.authored))
		var matrix: PackedInt32Array = authored.duplicate()
		var state: EntityScriptState = EntityScriptState.create(setup.definition.root_id)
		var animation: EntityAnimationState = EntityAnimationState.create(PackedInt32Array())
		var random: SourceRandom = SourceRandom.create(1)
		var pop_allocated: bool = false
		for row: Dictionary in expected.rows:
			var tick: int = _int(row.tick)
			var at: String = "%s tick %d" % [label, tick]
			var context := EntityUpdateContext.new()
			context.entity_index = ENTITY_INDEX
			context.has_path = has_path
			var carried: bool = row.carried
			context.previous_carry = carried
			context.pop_allocated = pop_allocated
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
			pop_allocated = pop_allocated or result.pop_started
			assert_eq(state.program_id, _int(row.program), at + " program")
			assert_eq(state.cursor, _int(row.cursor), at + " cursor")
			assert_eq(state.timer, _int(row.timer), at + " timer")
			assert_eq(state.registers.slice(0, 6), PackedInt32Array(_ints(row.registers)), at + " registers")
			assert_eq(state.offsets, _vector(row.deviation), at + " deviation")
			assert_eq(state.counts, _vector(row.remaining), at + " remaining")
			assert_eq(state.moving_sound, PackedInt32Array(_ints(row.moving_sound)), at + " moving sound")
			assert_eq(_sounds(result.requests), _ints(row.sounds), at + " sounds")
			var ejections := PackedInt32Array()
			for effect: EntityScriptEffect in result.effects:
				if effect.eject:
					ejections.append_array([effect.grid_delta, effect.jump_duration])
			var expected_ejections := PackedInt32Array()
			for pair: Variant in row.ejections:
				expected_ejections.append_array(_ints(pair))
			assert_eq(ejections, expected_ejections, at + " ejections")
			var pop: bool = row.pop
			assert_eq(result.pop_started, pop, at + " pop")
			assert_eq(result.frog_deaths, PackedInt32Array(_ints(row.deaths)), at + " deaths")
			assert_eq(matrix, PackedInt32Array(_ints(row.matrix)), at + " matrix")
			if row.colours != null:
				assert_eq(state.colours, _vector(row.colours), at + " colours")
				assert_eq(state.ambient, _vector(row.ambient), at + " ambient")
				var no_fade: bool = row.no_fade
				assert_eq(state.no_screen_fade, no_fade, at + " no screen fade")

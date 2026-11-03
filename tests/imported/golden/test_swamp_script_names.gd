extends GutTest
## Independent frozen Swamp weir rotation and barrel-script register facts at
## source widths, resolved through the imported FrogLord script names.

const FACTS: String = "res://tests/golden/synthetic/swamp.json"
const ENTITY_INDEX: int = 4

var _cache: Dictionary = {}


func _facts() -> Dictionary:
	if _cache.is_empty():
		_cache = ImportedNames.facts(FACTS)
	return _cache


func _scripts() -> NameBank:
	var names: GameNameLists = ImportedNames.lists()
	assert_not_null(names, "the imported name lists load")
	return names.scripts if names != null else null


func _sounds(requests: Array[TickEvent]) -> Array[int]:
	var result: Array[int] = []
	for request: TickEvent in requests:
		if request.kind == TickEvent.Kind.SOUND:
			result.append(request.sound_id)
	return result


func test_weir_rotation_match_independent_facts() -> void:
	var bank: NameBank = _scripts()
	if bank == null:
		return
	var weir: Dictionary = _facts().weir_matrix
	var registers: Dictionary = _facts().script_registers
	var programs: Dictionary = registers.programs
	var table: ScriptTable = ImportedNames.table(bank, programs)
	for fixture: Dictionary in weir.rotation:
		var initial: Dictionary = fixture.input
		var root: int = ImportedNames.number(initial.root)
		assert_eq(bank.name_of(root), "SCRIPT_SWP_WEIR_ROTATE")
		var behavior: EntityBehavior = EntityBehaviorCatalog.resolve("SWP_STAT_WEIR")
		var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, bank, root, behavior, PackedByteArray(ImportedNames.numbers(initial.payload)))
		assert_eq(setup.error, "", "weir script")
		if setup.definition == null:
			continue
		var authored := PackedInt32Array(ImportedNames.numbers(initial.authored))
		var matrix: PackedInt32Array = authored.duplicate()
		var state: EntityScriptState = EntityScriptState.create(root)
		var animation: EntityAnimationState = EntityAnimationState.create(PackedInt32Array())
		var random: SourceRandom = SourceRandom.create(1)
		var expected: Dictionary = fixture.expected
		for row: Dictionary in expected.rows:
			var at: String = "weir tick %d" % ImportedNames.number(row.tick)
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
			assert_eq(state.cursor, ImportedNames.number(row.cursor), at + " cursor")
			assert_eq(state.angles, ImportedNames.vector(row.angles), at + " angles")
			assert_eq(state.angular_counts, ImportedNames.vector(row.angle_counts), at + " angle counts")
			assert_eq(matrix, PackedInt32Array(ImportedNames.numbers(row.matrix)), at + " matrix")


func test_script_register_setup_match_independent_facts() -> void:
	var bank: NameBank = _scripts()
	if bank == null:
		return
	var path_root: int = bank.index_of("SCRIPT_SWP_NUCLEAR_BARLLEL_WAITING")
	var matrix_root: int = bank.index_of("SCRIPT_SWP_BOBBING_WASTE_BARREL")
	var registers: Dictionary = _facts().script_registers
	for fixture: Dictionary in registers.setup:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var layout: String = initial.layout
		var offset: int = ImportedNames.number(initial.offset)
		var count: int = ImportedNames.number(initial.count)
		var payload := PackedByteArray(ImportedNames.numbers(initial.payload))
		var label: String = "%s registers offset %d count %d bytes %d" % [layout, offset, count, payload.size()]
		var root: int = path_root if layout == "path" else matrix_root
		var programs: Dictionary = {str(root): [31, offset, count, 38]}
		var behavior: EntityBehavior = EntityBehaviorCatalog.resolve("NUCLEAR_BARREL" if layout == "path" else "DYNAMIC")
		assert_eq(behavior.layout, EntityBehavior.Layout.PATH if layout == "path" else EntityBehavior.Layout.MATRIX, label)
		var setup: EntityScriptSetup = EntityScriptSetup.from_tables(ImportedNames.table(bank, programs), bank, root, behavior, payload)
		var defined: bool = expected.source_defined
		if not defined:
			assert_ne(setup.error, "", label + " reads outside the source register storage or entity data")
			continue
		assert_eq(setup.error, "", label)
		if setup.definition == null:
			continue
		assert_eq(setup.definition.payload_offset, offset, label + " offset")
		assert_eq(setup.definition.payload_registers, PackedInt32Array(ImportedNames.numbers(expected.registers)), label + " registers")
		assert_eq(setup.definition.validate(PackedInt32Array(), 0, layout == "path"), "", label + " validates")


func test_script_register_timelines_match_independent_facts() -> void:
	var bank: NameBank = _scripts()
	if bank == null:
		return
	var registers: Dictionary = _facts().script_registers
	var programs: Dictionary = registers.programs
	var table: ScriptTable = ImportedNames.table(bank, programs)
	for fixture: Dictionary in registers.timeline:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = initial.name
		var behavior_name: String = initial.behavior
		var behavior: EntityBehavior = EntityBehaviorCatalog.resolve(behavior_name)
		var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, bank, ImportedNames.number(initial.root), behavior, PackedByteArray(ImportedNames.numbers(initial.payload)))
		assert_eq(setup.error, "", label)
		if setup.definition == null:
			continue
		var has_path: bool = behavior.layout == EntityBehavior.Layout.PATH
		var authored := PackedInt32Array(ImportedNames.numbers(initial.authored))
		var matrix: PackedInt32Array = authored.duplicate()
		var state: EntityScriptState = EntityScriptState.create(setup.definition.root_id)
		var animation: EntityAnimationState = EntityAnimationState.create(PackedInt32Array())
		var random: SourceRandom = SourceRandom.create(1)
		var pop_allocated: bool = false
		for row: Dictionary in expected.rows:
			var tick: int = ImportedNames.number(row.tick)
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
			assert_eq(state.program_id, ImportedNames.number(row.program), at + " program")
			assert_eq(state.cursor, ImportedNames.number(row.cursor), at + " cursor")
			assert_eq(state.timer, ImportedNames.number(row.timer), at + " timer")
			assert_eq(state.registers.slice(0, 6), PackedInt32Array(ImportedNames.numbers(row.registers)), at + " registers")
			assert_eq(state.offsets, ImportedNames.vector(row.deviation), at + " deviation")
			assert_eq(state.counts, ImportedNames.vector(row.remaining), at + " remaining")
			assert_eq(state.moving_sound, PackedInt32Array(ImportedNames.numbers(row.moving_sound)), at + " moving sound")
			assert_eq(_sounds(result.requests), ImportedNames.numbers(row.sounds), at + " sounds")
			var ejections := PackedInt32Array()
			for effect: EntityScriptEffect in result.effects:
				if effect.eject:
					ejections.append_array([effect.grid_delta, effect.jump_duration])
			var expected_ejections := PackedInt32Array()
			for pair: Variant in row.ejections:
				expected_ejections.append_array(ImportedNames.numbers(pair))
			assert_eq(ejections, expected_ejections, at + " ejections")
			var pop: bool = row.pop
			assert_eq(result.pop_started, pop, at + " pop")
			assert_eq(result.frog_deaths, PackedInt32Array(ImportedNames.numbers(row.deaths)), at + " deaths")
			assert_eq(matrix, PackedInt32Array(ImportedNames.numbers(row.matrix)), at + " matrix")
			if row.colours != null:
				assert_eq(state.colours, ImportedNames.vector(row.colours), at + " colours")
				assert_eq(state.ambient, ImportedNames.vector(row.ambient), at + " ambient")
				var no_fade: bool = row.no_fade
				assert_eq(state.no_screen_fade, no_fade, at + " no screen fade")

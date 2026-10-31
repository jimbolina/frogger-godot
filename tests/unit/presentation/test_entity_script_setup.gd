extends GutTest
## Supplied-name resolution and turtle custom-creation script replacement.

func _names() -> NameBank:
	return SyntheticNames.list("SCRIPT_NONE\nSCRIPT_TURTLE\nSCRIPT_TURTLE_NO_DIVE\n[CallbackNames]\nSCRIPT_CB_HIT_TURTLE\n", false, "Script")

func _table(names: NameBank) -> ScriptTable:
	var table := ScriptTable.new()
	for id: int in 3:
		var script_entry := EntityScript.new()
		script_entry.id = id
		script_entry.name = names.name_of(id)
		var callback := EntityScript.Command.new()
		callback.opcode = 34
		callback.arguments = PackedInt32Array([0, 0, 0, 0])
		var stop := EntityScript.Command.new()
		stop.opcode = 38
		script_entry.commands = [callback, stop]
		table.scripts.append(script_entry)
	return table

func test_turtle_payload_replaces_script_by_name_and_remains_detached() -> void:
	var names: NameBank = _names()
	var table: ScriptTable = _table(names)
	var payload := PackedByteArray()
	payload.resize(24)
	payload.encode_s32(12, 30)
	payload.encode_s32(16, 45)
	payload.encode_s32(20, 1)
	var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, names, 1, EntityBehaviorCatalog.resolve("SUB_TURTLE"), payload)
	assert_eq(setup.error, "")
	assert_eq(setup.definition.root_id, 2)
	assert_eq(setup.definition.payload_registers, PackedInt32Array([30, 45, 1]))
	assert_eq(setup.definition.callbacks[0], EntityScriptDefinition.CallbackKind.HIT_TURTLE)
	assert_eq(setup.definition.programs.size(), 2, "Validate the form script and replacement")
	table.scripts[2].commands.clear()
	payload.encode_s32(20, 0)
	assert_eq(setup.definition.programs[2].size(), 6)
	setup = EntityScriptSetup.from_tables(_table(names), names, 1, EntityBehaviorCatalog.resolve("SUB_TURTLE"), payload)
	assert_eq(setup.definition.root_id, 1)

func test_unknown_name_and_callback_or_bad_payload_reject() -> void:
	var names: NameBank = _names()
	var table: ScriptTable = _table(names)
	var payload := PackedByteArray()
	assert_ne(EntityScriptSetup.from_tables(table, names, 1, EntityBehaviorCatalog.resolve("SUB_TURTLE"), payload).error, "")
	payload.resize(24)
	payload.encode_s32(20, 2)
	assert_ne(EntityScriptSetup.from_tables(table, names, 1, EntityBehaviorCatalog.resolve("SUB_TURTLE"), payload).error, "")
	payload.encode_s32(20, 0)
	table.scripts[1].commands[0].arguments[1] = 9
	assert_ne(EntityScriptSetup.from_tables(table, names, 1, EntityBehaviorCatalog.resolve("SUB_TURTLE"), payload).error, "")
	table.scripts[1].name = "UNKNOWN"
	assert_ne(EntityScriptSetup.from_tables(table, names, 1, EntityBehaviorCatalog.resolve("SUB_TURTLE"), payload).error, "")

func test_supplied_named_program_outside_old_allowlist_uses_dependency_checks() -> void:
	var names: NameBank = _names()
	var table: ScriptTable = _table(names)
	var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, names, 0, EntityBehaviorCatalog.resolve("STATIC"), PackedByteArray())
	assert_eq(setup.error, "")
	assert_eq(setup.definition.names[0], "SCRIPT_NONE")
	assert_eq(setup.definition.validate(PackedInt32Array(), 0, false), "")
	table.scripts[0].commands[0].opcode = 999
	assert_ne(EntityScriptSetup.from_tables(table, names, 0, EntityBehaviorCatalog.resolve("STATIC"), PackedByteArray()).error, "")

func test_start_script_and_helium_callback_copy_named_dependencies() -> void:
	var names: NameBank = SyntheticNames.list("SCRIPT_NONE\nsynthetic_root\nSCRIPT_SKY_HELIUM_BALLOON_RISING\n[CallbackNames]\nSCRIPT_CB_SKY_HELIUM_BALLOON\n", false, "Script")
	var table: ScriptTable = _table(names)
	var stop := EntityScript.Command.new()
	stop.opcode = 38
	table.scripts[2].commands = [stop]
	var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, names, 1, EntityBehaviorCatalog.resolve("STATIC"), PackedByteArray())
	assert_eq(setup.error, "")
	assert_eq(setup.definition.callback_programs[0], 2)
	assert_eq(setup.definition.programs.size(), 2)
	assert_eq(setup.definition.validate(PackedInt32Array(), 0, false), "")
	var detached: EntityScriptDefinition = setup.definition.copy()
	setup.definition.callback_programs[0] = 99
	assert_eq(detached.callback_programs[0], 2)
	var start := EntityScript.Command.new()
	start.opcode = 25
	start.arguments = PackedInt32Array([2])
	table.scripts[1].commands = [start, stop]
	setup = EntityScriptSetup.from_tables(table, names, 1, EntityBehaviorCatalog.resolve("STATIC"), PackedByteArray())
	assert_eq(setup.error, "")
	assert_true(setup.definition.programs.has(2))
	start.arguments[0] = 99
	assert_ne(EntityScriptSetup.from_tables(table, names, 1, EntityBehaviorCatalog.resolve("STATIC"), PackedByteArray()).error, "")

func test_callback_repointing_resolves_names_to_detached_typed_kinds() -> void:
	var names: NameBank = SyntheticNames.list("SCRIPT_NONE\nSCRIPT_TURTLE\nSCRIPT_TURTLE_NO_DIVE\n[CallbackNames]\nSCRIPT_CB_LOG_SPLASH\n", false, "Script")
	var table: ScriptTable = _table(names)
	table.scripts[0].pointer = 0x401000
	var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, names, 0, EntityBehaviorCatalog.resolve("STATIC"), PackedByteArray())
	assert_eq(setup.error, "")
	assert_eq(setup.definition.callbacks[0], EntityScriptDefinition.CallbackKind.LOG_SPLASH)
	var detached: EntityScriptDefinition = setup.definition.copy()
	setup.definition.callbacks[0] = EntityScriptDefinition.CallbackKind.HIT_TURTLE
	assert_eq(detached.callbacks[0], EntityScriptDefinition.CallbackKind.LOG_SPLASH)
	table.scripts[0].commands[0].arguments[1] = 99
	setup = EntityScriptSetup.from_tables(table, names, 0, EntityBehaviorCatalog.resolve("STATIC"), PackedByteArray())
	assert_eq(setup.error, "Unsupported supplied callback name 99 in SCRIPT_NONE at 0x00401000")

func test_moving_turtle_registers_use_frozen_loader_zero_fill() -> void:
	var names: NameBank = _names()
	var table: ScriptTable = _table(names)
	var prepare := EntityScript.Command.new()
	prepare.opcode = 31
	prepare.arguments = PackedInt32Array([12, 3])
	table.scripts[1].commands.push_front(prepare)
	var payload := PackedByteArray()
	payload.resize(12)
	var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, names, 1, EntityBehaviorCatalog.resolve("MOVING"), payload)
	assert_eq(setup.error, "")
	assert_eq(setup.definition.root_id, 1)
	assert_eq(setup.definition.payload_offset, 12)
	assert_eq(setup.definition.payload_registers, PackedInt32Array([0, 0, 0]))
	assert_eq(setup.definition.validate(PackedInt32Array(), 0, true), "")
	payload.resize(24)
	payload.encode_s32(12, 99)
	setup = EntityScriptSetup.from_tables(table, names, 1, EntityBehaviorCatalog.resolve("MOVING"), payload)
	assert_eq(setup.definition.payload_registers, PackedInt32Array([0, 0, 0]))
	payload.resize(12)
	assert_ne(EntityScriptSetup.from_tables(table, names, 1, EntityBehaviorCatalog.resolve("MOVING_TONGUEABLE"), payload).error, "")
	payload.resize(11)
	assert_ne(EntityScriptSetup.from_tables(table, names, 1, EntityBehaviorCatalog.resolve("MOVING"), payload).error, "")

func test_repointed_script_reads_only_supported_bounded_register_payload() -> void:
	var names: NameBank = _names()
	var table: ScriptTable = _table(names)
	var prepare := EntityScript.Command.new()
	prepare.opcode = 31
	prepare.arguments = PackedInt32Array([32, 2])
	table.scripts[2].commands.push_front(prepare)
	var payload := PackedByteArray()
	payload.resize(40)
	payload.encode_s32(32, 17)
	payload.encode_s32(36, 23)
	var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, names, 2, EntityBehaviorCatalog.resolve("DYNAMIC"), payload)
	assert_eq(setup.error, "")
	assert_eq(setup.definition.payload_registers, PackedInt32Array([17, 23]))
	payload.resize(39)
	assert_ne(EntityScriptSetup.from_tables(table, names, 2, EntityBehaviorCatalog.resolve("DYNAMIC"), payload).error, "")

func test_matrix_mechanism_reads_six_signed_registers_and_rejects_truncation() -> void:
	var names: NameBank = _names()
	var table: ScriptTable = _table(names)
	var prepare := EntityScript.Command.new()
	prepare.opcode = 31
	prepare.arguments = PackedInt32Array([32, 6])
	table.scripts[0].commands.insert(0, prepare)
	var payload := PackedByteArray()
	payload.resize(56)
	for index: int in 6:
		payload.encode_s32(32 + index * 4, -300 + index)
	var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, names, 0, EntityBehaviorCatalog.resolve("DYNAMIC"), payload)
	assert_eq(setup.error, "")
	assert_eq(setup.definition.payload_registers, PackedInt32Array([-300, -299, -298, -297, -296, -295]))
	assert_eq(setup.definition.validate(PackedInt32Array(), 0, false), "")
	payload.resize(55)
	assert_ne(EntityScriptSetup.from_tables(table, names, 0, EntityBehaviorCatalog.resolve("DYNAMIC"), payload).error, "")

func test_hippo_payload_replaces_its_own_no_dive_script_by_name() -> void:
	var names: NameBank = SyntheticNames.list("SCRIPT_NONE\nSCRIPT_TURTLE_NO_DIVE\nSCRIPT_JUN_HIPPO\nSCRIPT_JUN_HIPPO_NO_DIVE\n[CallbackNames]\nSCRIPT_CB_HIT_TURTLE\n", false, "Script")
	var table := ScriptTable.new()
	for id: int in 4:
		var script_entry := EntityScript.new()
		script_entry.id = id
		script_entry.name = names.name_of(id)
		var stop := EntityScript.Command.new()
		stop.opcode = 38
		script_entry.commands = [stop]
		table.scripts.append(script_entry)
	var payload := PackedByteArray()
	payload.resize(24)
	payload.encode_s32(12, 60)
	payload.encode_s32(16, 60)
	payload.encode_s32(20, 1)
	var hippo: EntityBehavior = EntityBehaviorCatalog.resolve("JUN_HIPPO")
	var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, names, 2, hippo, payload)
	assert_eq(setup.error, "")
	assert_eq(setup.definition.root_id, 3)
	assert_eq(setup.definition.payload_offset, 12)
	assert_eq(setup.definition.payload_registers, PackedInt32Array([60, 60, 1]))
	assert_true(setup.definition.programs.has(2) and setup.definition.programs.has(3))
	assert_eq(setup.definition.programs.size(), 2)
	payload.encode_s32(20, 0)
	setup = EntityScriptSetup.from_tables(table, names, 2, hippo, payload)
	assert_eq(setup.definition.root_id, 2)
	payload.encode_s32(20, 2)
	assert_eq(EntityScriptSetup.from_tables(table, names, 2, hippo, payload).error, "Unsupported turtle payload type")
	payload.resize(23)
	assert_eq(EntityScriptSetup.from_tables(table, names, 2, hippo, payload).error, "Turtle payload requires PATH_INFO and three register words")
	var unregistered := EntityBehavior.new()
	unregistered.kind = EntityBehavior.Kind.JUN_HIPPO
	assert_eq(EntityScriptSetup.from_tables(table, names, 2, unregistered, payload).error, "Turtle payload requires PATH_INFO and three register words")

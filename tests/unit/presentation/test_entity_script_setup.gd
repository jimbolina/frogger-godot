extends GutTest
## Supplied-name resolution and turtle custom-creation script replacement.

func _names() -> NameBank:
	return NameBank.from_list_config(FrogLordConfig.parse_legacy("SCRIPT_NONE\nSCRIPT_TURTLE\nSCRIPT_TURTLE_NO_DIVE\n[CallbackNames]\nSCRIPT_CB_HIT_TURTLE\n"), false, "Script")

func _table(names: NameBank) -> ScriptTable:
	var table := ScriptTable.new()
	for id: int in 3:
		var script_entry := EntityScript.new()
		script_entry.id = id
		script_entry.name = names.get_name(id)
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
	assert_eq(setup.definition.callbacks[0], "SCRIPT_CB_HIT_TURTLE")
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

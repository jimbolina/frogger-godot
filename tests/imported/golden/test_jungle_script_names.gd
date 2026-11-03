extends GutTest
## Independent frozen Jungle hippo no-dive facts at source widths, resolved
## through the imported FrogLord script names.

const FACTS: String = "res://tests/golden/synthetic/jungle.json"


func _scripts() -> NameBank:
	var names: GameNameLists = ImportedNames.lists()
	assert_not_null(names, "the imported name lists load")
	return names.scripts if names != null else null


func test_hippo_no_dive_match_independent_facts() -> void:
	var bank: NameBank = _scripts()
	if bank == null:
		return
	var dive: int = bank.index_of("SCRIPT_JUN_HIPPO")
	var table := ScriptTable.new()
	for id: int in range(maxi(dive, bank.index_of("SCRIPT_JUN_HIPPO_NO_DIVE")) + 1):
		var program := EntityScript.new()
		program.id = id
		program.name = bank.name_of(id)
		var stop := EntityScript.Command.new()
		stop.opcode = 38
		program.commands = [stop]
		table.scripts.append(program)
	var hippo: EntityBehavior = EntityBehaviorCatalog.resolve("JUN_HIPPO")
	for fixture: Dictionary in ImportedNames.facts(FACTS).hippo_no_dive:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var turtle_type: int = ImportedNames.number(initial.turtle_type)
		var label: String = "hippo turtle_type %d" % turtle_type
		var payload := PackedByteArray()
		payload.resize(24)
		payload.encode_s32(12, 180)
		payload.encode_s32(16, 60)
		payload.encode_u32(20, turtle_type)
		var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, bank, dive, hippo, payload)
		var script_name: String = expected.script
		var script_id: int = ImportedNames.number(expected.script_id)
		assert_eq(bank.index_of(script_name), script_id, label + " FrogLord script id")
		if turtle_type in [0, 1]:
			assert_eq(setup.error, "", label)
			if setup.definition == null:
				continue
			assert_eq(setup.definition.root_id, script_id, label)
			assert_eq(bank.name_of(setup.definition.root_id), script_name, label)
		else:
			assert_eq(script_name, "SCRIPT_JUN_HIPPO", label)
			assert_eq(setup.error, "Unsupported turtle payload type", label + " port rejects types frozen C treats as diving")

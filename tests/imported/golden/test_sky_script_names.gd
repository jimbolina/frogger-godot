extends GutTest
## Independent frozen Sky balloon-script register facts at source widths,
## resolved through the imported FrogLord script names.

const FACTS: String = "res://tests/golden/synthetic/sky.json"


func _scripts() -> NameBank:
	var names: GameNameLists = ImportedNames.lists()
	assert_not_null(names, "the imported name lists load")
	return names.scripts if names != null else null


func test_sky_script_registers_match_independent_facts() -> void:
	var bank: NameBank = _scripts()
	if bank == null:
		return
	var family: Dictionary = ImportedNames.facts(FACTS).sky_script_registers
	var programs: Dictionary = family.programs
	var table: ScriptTable = ImportedNames.table(bank, programs)
	var setups: Array = family.setup
	for fixture: Dictionary in setups:
		var initial: Dictionary = fixture.input
		var expected: Dictionary = fixture.expected
		var label: String = "%s registers" % str(initial.name)
		var behavior: EntityBehavior = EntityBehaviorCatalog.resolve(str(initial.entity))
		assert_eq(behavior.layout, EntityBehavior.Layout.MATRIX, label)
		var setup: EntityScriptSetup = EntityScriptSetup.from_tables(table, bank, ImportedNames.number(initial.root), behavior, PackedByteArray(ImportedNames.numbers(initial.payload)))
		if not expected.source_defined:
			assert_ne(setup.error, "", label + " reads outside the entity data")
			continue
		assert_eq(setup.error, "", label)
		if setup.definition == null:
			continue
		assert_eq(setup.definition.payload_offset, 32, label + " offset")
		assert_eq(setup.definition.payload_registers.size(), ImportedNames.number(expected.count), label + " count")
		assert_eq(setup.definition.payload_registers, PackedInt32Array(ImportedNames.numbers(expected.registers)), label + " values")

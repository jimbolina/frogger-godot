extends GutTest
## The local import's FrogLord name lists hold the base entity types, the
## entity-type overrides and the general forms.

func test_imported_name_lists_include_base_types_and_override() -> void:
	var names: GameNameLists = _imported_names()
	assert_eq(names.errors.size(), 0)
	assert_eq(names.entity_name_for("UNNAMED", names.entities.index_of("STATIC")), "STATIC")
	assert_eq(names.entity_name_for("UNNAMED", names.entities.index_of("MOVING")), "MOVING")
	assert_eq(names.entity_name_for("CAV_SNAIL", names.entities.index_of("STATIC")), "MOVING")
	assert_true(names.forms.get_sub_bank("GENERAL").index_of("GEN_CHECKPOINT_1") >= 0)

func _imported_names() -> GameNameLists:
	var catalog: ImportedAssets = ImportedAssets.open()
	assert_eq(catalog.error, "")
	return catalog.names

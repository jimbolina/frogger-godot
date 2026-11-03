extends GutTest
## The catalog loads the emissive image table from the shippable root, notes a
## missing one, and summarises a FrogLord overlay index's source. The imported
## suite's test_imported_assets_catalog.gd opens the local import.

const BUILD: String = "pc-retail-v3.0e"


func test_the_emissive_image_table_loads_and_the_base_catalog_has_none() -> void:
	var catalog := ImportedAssets.new()
	var table: EmissiveImageTable = catalog.emissive_images()
	assert_not_null(table)
	assert_gt(table.entries.size(), 0)
	assert_same(catalog.emissive_images(), table, "loaded once")
	assert_not_null(table.find("vol_lava6"))
	var base: EmissiveImageTable = AssetCatalog.new().emissive_images()
	assert_not_null(base)
	assert_eq(base.entries.size(), 0)


func test_a_missing_emissive_image_table_is_empty_and_noted() -> void:
	var catalog := ImportedAssets.new()
	catalog.shippable_root = "res://no_such_assets"
	assert_eq(catalog.emissive_images().entries.size(), 0)
	assert_eq(catalog.problems.size(), 1)
	assert_string_contains(catalog.problems[0], "res://no_such_assets/rendering/emissive_images.tres")


func test_a_froglord_overlay_index_summarises_its_source() -> void:
	var catalog := ImportedAssets.new()
	catalog.index = AssetIndex.new()
	catalog.index.source_kind = AssetIndex.SOURCE_FROGLORD_MOD
	catalog.index.source_exe_name = "modded_FROGGER.EXE"
	catalog.index.source_mwd_name = "modded_FROGPSX.MWD"
	catalog.index.froglord_version = 12
	catalog.index.trailer_build = BUILD
	assert_eq(catalog.source_summary(),
		"FrogLord mod modded_FROGGER.EXE + modded_FROGPSX.MWD (FrogLord 12, base pc-retail-v3.0e)")
	catalog.index.fallback_root = "res://assets"
	assert_string_ends_with(catalog.source_summary(), " over res://assets")

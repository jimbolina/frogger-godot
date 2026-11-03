extends GutTest
## Without an argument or launcher settings, AssetLocation opens the local
## import at the committed root, with the committed shippable root.


func test_no_launcher_settings_open_the_local_import() -> void:
	var location: AssetLocation = AssetLocation.resolve(PackedStringArray(), null)
	assert_true(location.is_usable(), location.error)
	assert_eq(location.base_root, ImportedAssets.COMMITTED_ROOT)
	assert_eq(location.origin, AssetLocation.Origin.COMMITTED)
	var catalog: ImportedAssets = location.open()
	assert_true(catalog.is_valid(), catalog.error)
	assert_eq(catalog.root, ImportedAssets.COMMITTED_ROOT)
	assert_eq(catalog.shippable_root, ImportedAssets.SHIPPABLE_ROOT)

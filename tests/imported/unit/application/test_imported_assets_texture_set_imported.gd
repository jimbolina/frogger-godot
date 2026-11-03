extends GutTest
## The local import opens drawing the original textures, with no warnings.


func test_the_default_is_the_original_textures() -> void:
	var assets: ImportedAssets = ImportedAssets.open()
	assert_true(assets.is_valid())
	assert_true(assets.texture_set().is_retail())
	assert_eq(assets.warnings, PackedStringArray())

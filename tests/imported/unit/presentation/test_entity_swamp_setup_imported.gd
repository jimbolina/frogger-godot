extends GutTest
## The local import plays every Swamp level but the multiplayer one.

func test_swamp_levels_are_supported_without_multiplayer() -> void:
	var data: ImportedAssets = ImportedAssets.open()
	for code: String in ["SWP1", "SWP2", "SWP3", "SWP4", "SWP5"]:
		assert_true(data.is_playable_level(FroggerIds.level_from_code(code)), code)
	assert_false(data.is_playable_level(FroggerIds.level_from_code("SWPM")))

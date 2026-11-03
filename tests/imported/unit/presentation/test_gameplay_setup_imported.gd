extends GutTest
## The local import plays exactly the verified single-player levels.

func test_supported_levels_are_limited_to_verified_single_player_scope() -> void:
	var data: ImportedAssets = ImportedAssets.open()
	assert_eq(data.error, "")
	for code: String in ["ORG1", "ORG2", "ORG3", "ORG4", "ORG5", "SUB1", "SUB2", "SUB3", "SUB4", "SUB5", "FOR1", "FOR2", "VOL1", "VOL2", "VOL3", "CAV1", "CAV3", "CAV4", "DES1", "DES2", "DES3", "DES4", "DES5", "JUN1", "SWP1", "SWP2", "SWP3", "SWP4", "SWP5", "SKY1", "SKY2", "SKY3", "SKY4"]:
		assert_true(data.is_playable_level(FroggerIds.level_from_code(code)), code)
	for code: String in ["ORGM", "SUBM", "FOR3", "FOR4", "FOR5", "FORM", "VOL4", "VOL5", "VOLM", "CAV2", "CAV5", "CAVM", "DESM", "JUN2", "SWPM", "SKY5", "SKYM", "ISLAND", "unknown"]:
		assert_false(data.is_playable_level(FroggerIds.level_from_code(code)), code)
	assert_false(data.is_playable_level(-1))
	assert_false(data.is_playable_level(100))

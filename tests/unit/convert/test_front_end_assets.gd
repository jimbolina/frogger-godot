extends GutTest
## FrontEndAssets refuses unusable data with an actionable error and no textures.


func test_missing_data_has_actionable_error() -> void:
	var assets: FrontEndAssets = FrontEndAssets.from_data(null)
	assert_string_contains(assets.error, "valid player data")
	assert_null(assets.texture("opt_start"))
	assert_null(assets.level_texture(24, FrontEndAssets.LevelImage.SCREENSHOT))


func test_invalid_data_has_actionable_error() -> void:
	var data := GameData.new()
	data.error = "archive could not be opened"
	var assets: FrontEndAssets = FrontEndAssets.from_data(data)
	assert_string_contains(assets.error, "valid player data")
	assert_null(assets.texture("newfont"))


func test_names_are_the_english_front_end_set() -> void:
	for image_name: String in ["opt_start", "opt_options", "opt_exit", "select_level", "zone_complete",
			"press_fire", "opt_big_continue", "opt_yes", "opt_no", "opt_paused", "froglogo", "newfont",
			"select1", "select2", "select5", "sel_loading", "ls_gold_frog"]:
		assert_has(FrontEndAssets.NAMES, image_name)
	assert_eq(FrontEndAssets.LEVEL_IMAGES.size(), 4)
	assert_eq(int(FrontEndAssets.LevelImage.STACK_NAME), 4)

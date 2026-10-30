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


func test_water_images_come_from_the_options_bank_first_loaded() -> void:
	assert_eq(FrontEndAssets.WATER_NAMES, PackedStringArray(["opt_env_sky", "opt_bank3"]))
	assert_eq(FrontEndAssets.WATER_BANK, "OPT_VRAM.VLO")
	assert_eq(FrontEndAssets.BANKS[0], FrontEndAssets.WATER_BANK, "later banks keep winning for the other images")
	assert_eq(FrontEndAssets.BANKS[FrontEndAssets.BANKS.size() - 1], "LS_ALL.VLO")


func test_english_loads_only_the_english_banks() -> void:
	assert_eq(FrontEndAssets.banks_for(GameLanguage.Id.ENGLISH), FrontEndAssets.BANKS)
	assert_eq(FrontEndAssets.banks_for(GameLanguage.AUTO), FrontEndAssets.BANKS)


func test_other_languages_add_their_banks_after_the_english_ones() -> void:
	assert_eq(FrontEndAssets.banks_for(GameLanguage.Id.GERMAN), PackedStringArray([
		"OPT_VRAM.VLO", "STARTNTSC.VLO", "FIXE_VRAM.VLO", "OPTE_RAM.VLO", "FIXG_VRAM.VLO", "OPTG_RAM.VLO",
		"LS_ALL.VLO"]))
	assert_eq(FrontEndAssets.banks_for(GameLanguage.Id.ITALIAN)[4], "FIXI_VRAM.VLO")
	assert_eq(FrontEndAssets.banks_for(GameLanguage.Id.SPANISH)[5], "OPTS_RAM.VLO")


func test_unknown_language_is_reported_and_drawn_in_english() -> void:
	var assets: FrontEndAssets = FrontEndAssets.from_data(null, 9)
	assert_eq(assets.language, GameLanguage.Id.ENGLISH)
	assert_string_contains(assets.diagnostics[0], "Language 9 is unknown")
	assert_eq(assets.source_name("opt_start"), "")

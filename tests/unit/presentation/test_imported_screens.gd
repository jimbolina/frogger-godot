extends GutTest
## The screens and their presentation assets open from the committed imported assets alone.

var _data: ImportedAssets

func before_all() -> void:
	_data = ImportedAssets.open()

func test_the_boot_screen_names_the_imported_build() -> void:
	assert_eq(_data.error, "")
	assert_string_contains(BootScreen.status(_data), _data.version_name)
	assert_string_contains(BootScreen.status(ImportedAssets.open("res://no_such_assets")), "cannot be opened")

func test_front_end_hud_and_options_assets_load() -> void:
	var front: FrontEndAssets = FrontEndAssets.from_data(_data)
	assert_eq(front.error, "")
	for image_name: String in FrontEndAssets.NAMES:
		assert_not_null(front.texture(image_name), image_name)
	for image_name: String in FrontEndAssets.WATER_NAMES:
		assert_not_null(front.texture(image_name), image_name)
	var row: LevelSelectEntry = _data.tables.level_select().arcade[0]
	assert_not_null(front.level_texture(row.level, FrontEndAssets.LevelImage.SCREENSHOT))
	var named: int = 0
	for arcade_row: LevelSelectEntry in _data.tables.level_select().arcade:
		var game_name: Texture2D = front.level_texture(arcade_row.level, FrontEndAssets.LevelImage.GAME_NAME)
		if arcade_row.image_pointers[FrontEndAssets.LevelImage.GAME_NAME] == 0:
			assert_null(game_name, str(arcade_row.level))
			assert_eq(arcade_row.levels_in_world, 1, "only a world of one level lacks an in-game name")
			continue
		named += 1
		assert_not_null(game_name, str(arcade_row.level))
		assert_gt(front.level_retail_size(arcade_row.level, FrontEndAssets.LevelImage.GAME_NAME).x, 0.0, str(arcade_row.level))
	assert_gt(named, 0)
	for image_name: String in ["next", "total_time", "total_score", "select4", "opt_sec"]:
		assert_gt(front.retail_size(image_name).x, 0.0, image_name)
	var hud: GameplayHudAssets = GameplayHudAssets.from_data(_data)
	assert_eq(hud.error, "")
	assert_true(hud.textures.has("newfont"))
	assert_not_null(hud.font)
	assert_true(hud.font is FontFile)
	var options: OptionsModels = OptionsModels.from_data(_data)
	assert_eq(options.error, "")
	assert_not_null(options.frog.mesh)

func test_a_playable_level_opens_with_its_audio_and_others_are_refused() -> void:
	var screen := GameplayScreen.new()
	screen.auto_open = false
	add_child_autofree(screen)
	screen.set_process(false)
	var level: int = FroggerIds.level_from_code("ORG1")
	assert_eq(screen.open_data(_data, "ORG1"), "")
	assert_not_null(screen.run)
	assert_eq(screen.last_error, "")
	if screen.music_player() != null:
		assert_eq(screen.music_player().track, _data.tables.music().track_for_level(level))
		screen.music_player().finish_loading()
		assert_not_null(screen.music_player().stream())
	assert_string_contains(screen.open_data(_data, "ORGM"), "Playable levels")
	assert_null(screen.run)
	screen.close_data()

func test_a_command_line_level_opens_the_unaccepted_suburbia_levels() -> void:
	var screen := GameplayScreen.new()
	screen.auto_open = false
	add_child_autofree(screen)
	screen.set_process(false)
	screen.allow_unaccepted_levels = true
	for code: String in ["SUB2", "SUB3", "SUB4", "SUB5"]:
		assert_true(code in _data.unaccepted_level_codes(), code)
		assert_eq(screen.open_data(_data, code), "", code)
		assert_not_null(screen.run, code)
	var refusal: String = screen.open_data(_data, "CAV2")
	assert_string_contains(refusal, "unaccepted levels with a map are")
	assert_string_contains(refusal, "SUB2")
	assert_null(screen.run)
	screen.close_data()

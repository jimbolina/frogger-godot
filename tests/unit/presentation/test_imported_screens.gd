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
	var hud: GameplayHudAssets = GameplayHudAssets.from_data(_data)
	assert_eq(hud.error, "")
	assert_true(hud.textures.has("newfont"))
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

extends GutTest
## The FrogLord setup page says what detection found in the save folder: a
## FrogLord save of pc-retail-v3.0e, the retail pair, nothing yet, or another
## build, which blocks.


func _found(build: String, froglord: bool, error: String = "") -> AssetImporter.Detection:
	var detection := AssetImporter.Detection.new()
	detection.build = build
	detection.error = error
	detection.fingerprint = "0123456789abcdef"
	detection.froglord = froglord
	detection.froglord_version = 7 if froglord else -1
	detection.files = "modded_FROGGER.EXE + modded_FROGPSX.MWD" if froglord else "FROGGER.EXE + FROGPSX.MWD"
	return detection


func _page(found: AssetImporter.Detection) -> SetupFrogLord:
	var page := SetupFrogLord.new()
	page.enabled = true
	page.choose_folder("/FrogLord/save", true, found)
	return page


func test_a_froglord_save_of_the_supported_build_is_named() -> void:
	var page: SetupFrogLord = _page(_found(AssetImporter.SUPPORTED_BUILD, true))
	assert_eq(page.blocker(), "")
	assert_eq(page.found(), "Found a FrogLord 7 save of pc-retail-v3.0e: modded_FROGGER.EXE + modded_FROGPSX.MWD.")


func test_the_retail_pair_is_followed_until_froglord_saves() -> void:
	var page: SetupFrogLord = _page(_found(AssetImporter.SUPPORTED_BUILD, false))
	assert_eq(page.blocker(), "")
	assert_string_contains(page.found(), "not a FrogLord save yet")


func test_an_empty_folder_does_not_block() -> void:
	var nothing := AssetImporter.Detection.new()
	nothing.error = "/FrogLord/save holds neither FROGGER.EXE and FROGPSX.MWD nor FrogLord's files"
	var page: SetupFrogLord = _page(nothing)
	assert_eq(page.blocker(), "")
	assert_string_contains(page.found(), "No FrogLord save yet")


func test_another_build_blocks() -> void:
	var page: SetupFrogLord = _page(_found("pc-retail-v3.0", true, "/FrogLord/save is pc-retail-v3.0; only pc-retail-v3.0e can be imported"))
	assert_string_contains(page.blocker(), "/FrogLord/save is pc-retail-v3.0;")
	assert_string_contains(page.blocker(), "turn FrogLord off")
	page.enabled = false
	assert_eq(page.blocker(), "")
	assert_eq(page.found(), "")


func test_reading_the_launcher_forgets_the_detection() -> void:
	var page: SetupFrogLord = _page(_found(AssetImporter.SUPPORTED_BUILD, true))
	var launcher := LauncherSettings.new()
	launcher.froglord_enabled = true
	launcher.froglord_dir = "/Other"
	page.read(launcher, true)
	assert_null(page.detection, "the view detects the new folder")
	assert_eq(page.folder, "/Other")

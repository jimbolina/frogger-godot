extends RetailTest
## Needs the retail files: the locator finds them and recognises pc-retail-v3.0e.


func test_retail_install_is_recognised() -> void:
	var locator := GameDataLocator.new()
	locator.settings_path = "user://test_retail_settings_unused.cfg"
	var found: GameDataLocator.Located = locator.locate(OS.get_environment(GameDataLocator.ENV_VAR))
	assert_true(found.is_ok(), found.error)
	assert_true(found.source is RetailDirSource)
	assert_eq(found.version.internal_name, "pc-retail-v3.0e")
	assert_eq(found.detection_method, GameVersionDetector.METHOD_CHECKSUM)
	assert_eq(found.exe_crc32, 378672750)


func test_retail_executable_has_no_froglord_trailer() -> void:
	assert_null(FrogLordExeTrailer.read(retail_source().get_exe_bytes()))


func test_mwi_region_is_the_documented_size() -> void:
	var version: GameVersionConfig = FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e")
	assert_eq(retail_source().get_mwi_bytes(version).size(), 48840)

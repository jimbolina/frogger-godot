extends GutTest
## GameDataLocator, the data sources and version detection, on synthetic folders.

const TrailerTest := preload("res://tests/unit/source/test_froglord_exe_trailer.gd")
const ROOT: String = "user://test_locator"

var _locator: GameDataLocator


func before_each() -> void:
	_remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)
	_locator = GameDataLocator.new()
	_locator.use_environment = false
	_locator.settings_path = ROOT.path_join("settings.cfg")


func after_all() -> void:
	_remove_tree(ROOT)


func _write(path: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _modded_exe(version_name: String) -> PackedByteArray:
	return TrailerTest.with_trailer(TrailerTest.fake_program(4096),
		"[BuildInfo]\ngameType=frogger\ngameVersion=%s\nfrogLordVersion=3\n" % version_name)


func _mwd() -> PackedByteArray:
	var mwd: PackedByteArray = "DAWM".to_ascii_buffer()
	mwd.resize(2048)
	return mwd


func test_nothing_configured() -> void:
	var found: GameDataLocator.Located = _locator.locate()
	assert_false(found.is_ok())
	assert_eq(found.error, "no Frogger files found")
	assert_eq(found.attempts.size(), 3)


func test_modded_files_found_through_the_argument() -> void:
	var dir: String = ROOT.path_join("mod")
	_write(dir.path_join("modded_FROGGER.EXE"), _modded_exe("pc-retail-v3.0e"))
	_write(dir.path_join("modded_FROGPSX.MWD"), _mwd())
	var found: GameDataLocator.Located = _locator.locate(dir)
	assert_true(found.is_ok(), found.error)
	assert_true(found.source is FrogLordModSource)
	assert_eq(found.origin, "argument")
	assert_eq(found.version.internal_name, "pc-retail-v3.0e")
	assert_eq(found.detection_method, GameVersionDetector.METHOD_TRAILER)
	assert_string_contains(found.source.describe(), "FrogLord 3")


func test_file_names_match_regardless_of_case() -> void:
	var dir: String = ROOT.path_join("lower")
	_write(dir.path_join("modded_frogger.exe"), _modded_exe("pc-retail-v1.0"))
	_write(dir.path_join("MODDED_FROGPSX.mwd"), _mwd())
	var found: GameDataLocator.Located = _locator.locate(dir)
	assert_true(found.is_ok(), found.error)
	assert_eq(found.version.internal_name, "pc-retail-v1.0")
	assert_eq(found.source.get_exe_path(), dir.path_join("modded_frogger.exe"))
	assert_eq(found.source.get_mwd_path(), dir.path_join("MODDED_FROGPSX.mwd"))


func test_saved_setting_is_used_last() -> void:
	var dir: String = ROOT.path_join("saved")
	_write(dir.path_join("modded_FROGGER.EXE"), _modded_exe("pc-retail-v3.0e-vogons"))
	_write(dir.path_join("modded_FROGPSX.MWD"), _mwd())
	assert_eq(_locator.remember_directory(dir), OK)
	assert_eq(_locator.saved_directory(), dir)
	var found: GameDataLocator.Located = _locator.locate(ROOT.path_join("empty"))
	assert_true(found.is_ok(), found.error)
	assert_eq(found.origin, "saved setting")
	assert_string_contains(found.attempts[0], "neither")


func test_unknown_retail_executable() -> void:
	var dir: String = ROOT.path_join("unknown")
	_write(dir.path_join("FROGGER.EXE"), TrailerTest.fake_program(512))
	_write(dir.path_join("FROGPSX.MWD"), _mwd())
	var found: GameDataLocator.Located = _locator.locate(dir)
	assert_false(found.is_ok())
	assert_string_contains(found.error, "unknown executable")
	assert_eq(found.exe_crc32, Crc32.of_bytes(TrailerTest.fake_program(512)))


func test_trailer_naming_an_unknown_build() -> void:
	var dir: String = ROOT.path_join("future")
	_write(dir.path_join("modded_FROGGER.EXE"), _modded_exe("pc-retail-v9"))
	_write(dir.path_join("modded_FROGPSX.MWD"), _mwd())
	var found: GameDataLocator.Located = _locator.locate(dir)
	assert_false(found.is_ok())
	assert_string_contains(found.error, "pc-retail-v9")


func test_mod_preferred_over_retail_in_the_same_folder() -> void:
	var dir: String = ROOT.path_join("both")
	_write(dir.path_join("FROGGER.EXE"), TrailerTest.fake_program(512))
	_write(dir.path_join("FROGPSX.MWD"), _mwd())
	_write(dir.path_join("modded_FROGGER.EXE"), _modded_exe("pc-retail-v3.0e"))
	_write(dir.path_join("modded_FROGPSX.MWD"), _mwd())
	assert_true(GameDataLocator.open_directory(dir) is FrogLordModSource)


func test_source_reads_the_mwi_region_and_fingerprints() -> void:
	var dir: String = ROOT.path_join("fp")
	_write(dir.path_join("FROGGER.EXE"), TrailerTest.fake_program(512))
	_write(dir.path_join("FROGPSX.MWD"), _mwd())
	var source: GameDataSource = GameDataLocator.open_directory(dir)
	assert_true(source is RetailDirSource)
	assert_true(source.is_complete())
	var version := GameVersionConfig.new()
	version.mwi_offset = 16
	version.mwi_length = 32
	assert_eq(source.get_mwi_bytes(version), TrailerTest.fake_program(512).slice(16, 48))
	version.mwi_length = 5000
	assert_eq(source.get_mwi_bytes(version).size(), 0, "a region past the end yields nothing")
	var before: String = source.fingerprint()
	assert_eq(before.length(), 64)
	_write(dir.path_join("FROGPSX.MWD"), "DAWM!".to_ascii_buffer())
	assert_ne(RetailDirSource.new(dir).fingerprint(), before, "changing the archive changes the fingerprint")


func test_mod_source_lists_the_standalone_index() -> void:
	var dir: String = ROOT.path_join("mwi")
	_write(dir.path_join("modded_FROGGER.EXE"), _modded_exe("pc-retail-v3.0e"))
	_write(dir.path_join("modded_FROGPSX.MWD"), _mwd())
	var source := FrogLordModSource.new(dir)
	assert_eq(source.get_standalone_mwi_path(), "")
	_write(dir.path_join("modded_FROGPSX.MWI"), PackedByteArray([1, 2, 3]))
	assert_true(source.get_standalone_mwi_path().ends_with("modded_FROGPSX.MWI"))
	assert_eq(source.fingerprint_paths().size(), 3)

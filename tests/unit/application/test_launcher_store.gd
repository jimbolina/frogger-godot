extends GutTest
## LauncherStore round trips every launcher setting, gives the defaults for a
## missing file without an error, and falls back to the defaults with an error
## for another version or a value of the wrong type.

const ROOT: String = "user://test_launcher_store"

var _path: String = ROOT.path_join("launcher.cfg")


func before_each() -> void:
	_remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)


func after_all() -> void:
	_remove_tree(ROOT)


func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _write_text(text: String) -> void:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _sample() -> LauncherSettings:
	var settings := LauncherSettings.new()
	settings.game_data_dir = "/Games/Frogger"
	settings.disc_image_path = "/Games/Frogger.cue"
	settings.fingerprint = "0123456789abcdef"
	settings.imported_root = "user://assets/0123456789abcdef"
	settings.froglord_enabled = true
	settings.froglord_dir = "/Games/FrogLord"
	settings.show_setup_on_start = true
	return settings


func test_a_missing_file_gives_the_defaults_without_an_error() -> void:
	var store: LauncherStore = LauncherStore.load_from(ROOT.path_join("absent.cfg"))
	assert_eq(store.error, "")
	assert_false(store.found)
	assert_eq(store.settings.imported_root, "")
	assert_false(store.settings.has_import())
	assert_false(store.settings.froglord_enabled)
	assert_false(store.settings.show_setup_on_start)


func test_settings_round_trip_through_a_temporary_file() -> void:
	var nested: String = ROOT.path_join("nested/launcher.cfg")
	assert_eq(LauncherStore.save(_sample(), nested), "")
	assert_false(FileAccess.file_exists(nested + ".tmp"))
	var store: LauncherStore = LauncherStore.load_from(nested)
	assert_eq(store.error, "")
	assert_true(store.found)
	var expected: LauncherSettings = _sample()
	for section: String in LauncherStore.LAYOUT:
		for field: String in LauncherStore.LAYOUT[section]:
			var actual: Variant = store.settings.get(field)
			var wanted: Variant = expected.get(field)
			assert_eq(var_to_str(actual), var_to_str(wanted), field)
	assert_true(store.settings.has_import())
	var file := ConfigFile.new()
	assert_eq(file.load(nested), OK)
	var version: int = file.get_value("meta", "format_version")
	var root: String = file.get_value("import", "imported_root")
	assert_eq(version, LauncherStore.FORMAT_VERSION)
	assert_eq(root, "user://assets/0123456789abcdef")


func test_a_save_replaces_the_previous_file_whole() -> void:
	assert_eq(LauncherStore.save(_sample(), _path), "")
	var cleared := LauncherSettings.new()
	cleared.game_data_dir = "/Elsewhere"
	assert_eq(LauncherStore.save(cleared, _path), "")
	var store: LauncherStore = LauncherStore.load_from(_path)
	assert_eq(store.settings.game_data_dir, "/Elsewhere")
	assert_eq(store.settings.imported_root, "")
	assert_false(store.settings.froglord_enabled)


func test_a_missing_key_takes_its_default() -> void:
	_write_text("[meta]\nformat_version=1\n[import]\nimported_root=\"user://assets/x\"\n")
	var store: LauncherStore = LauncherStore.load_from(_path)
	assert_eq(store.error, "")
	assert_eq(store.settings.imported_root, "user://assets/x")
	assert_eq(store.settings.fingerprint, "")


func test_another_version_gives_the_defaults_with_an_error() -> void:
	assert_eq(LauncherStore.save(_sample(), _path), "")
	var file := ConfigFile.new()
	assert_eq(file.load(_path), OK)
	file.set_value("meta", "format_version", LauncherStore.FORMAT_VERSION + 1)
	assert_eq(file.save(_path), OK)
	var store: LauncherStore = LauncherStore.load_from(_path)
	assert_string_contains(store.error, "format version %d, expected %d" % [LauncherStore.FORMAT_VERSION + 1, LauncherStore.FORMAT_VERSION])
	assert_false(store.found)
	assert_eq(store.settings.imported_root, "")
	_write_text("[import]\nimported_root=\"user://assets/x\"\n")
	assert_string_contains(LauncherStore.load_from(_path).error, "has no format version")


func test_a_value_of_the_wrong_type_gives_the_defaults_with_an_error() -> void:
	_write_text("[meta]\nformat_version=1\n[import]\nimported_root=\"user://assets/x\"\n[froglord]\nfroglord_enabled=\"yes\"\n")
	var store: LauncherStore = LauncherStore.load_from(_path)
	assert_string_contains(store.error, "froglord/froglord_enabled")
	assert_eq(store.settings.imported_root, "", "nothing of a damaged file is kept")
	_write_text("[meta\nformat_version=((((\n")
	assert_string_contains(LauncherStore.load_from(_path).error, "could not be read")
	assert_engine_error("ConfigFile parse error", "Godot reports the malformed file")

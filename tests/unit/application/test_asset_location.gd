extends GutTest
## AssetLocation picks the base root from the --assets-root= argument, then the
## launcher settings' imported root when it holds an index, then the committed
## assets, and reports when none is usable. The FrogLord overlay is resolved
## separately, and the shippable root stays the committed one.

const SCRATCH: String = "user://asset_location_test"
const IMPORTED: String = SCRATCH + "/assets/0123456789abcdef"
const OTHER: String = SCRATCH + "/other"
const MISSING: String = SCRATCH + "/missing"
const COMMITTED: String = "res://assets"


func before_each() -> void:
	_remove(SCRATCH)
	_stub_index(IMPORTED)
	_stub_index(OTHER)


func after_all() -> void:
	_remove(SCRATCH)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func _stub_index(folder: String) -> void:
	assert_eq(DirAccess.make_dir_recursive_absolute(folder), OK)
	assert_eq(ResourceSaver.save(AssetIndex.new(), folder.path_join(ImportedAssets.INDEX_FILE)), OK)


func _store(imported_root: String) -> LauncherStore:
	var store := LauncherStore.new()
	store.settings.imported_root = imported_root
	return store


func test_the_argument_wins_over_the_launcher_settings_and_the_committed_assets() -> void:
	var location: AssetLocation = AssetLocation.resolve(
		PackedStringArray(["--level=ORG1", "--assets-root=%s/" % OTHER]), _store(IMPORTED))
	assert_true(location.is_usable(), location.error)
	assert_eq(location.base_root, OTHER, "a trailing slash is dropped")
	assert_eq(location.origin, AssetLocation.Origin.ARGUMENT)
	assert_eq(location.shippable_root, COMMITTED)


func test_an_argument_without_an_index_is_not_usable_and_does_not_fall_back() -> void:
	var location: AssetLocation = AssetLocation.resolve(
		PackedStringArray(["--assets-root=" + MISSING]), _store(IMPORTED))
	assert_false(location.is_usable())
	assert_eq(location.base_root, MISSING)
	assert_eq(location.origin, AssetLocation.Origin.ARGUMENT)
	assert_string_contains(location.error, MISSING)
	var catalog: ImportedAssets = location.open()
	assert_false(catalog.is_valid())
	assert_eq(catalog.error, location.error)


func test_the_launcher_imported_root_is_used_when_it_holds_an_index() -> void:
	var location: AssetLocation = AssetLocation.resolve(PackedStringArray(), _store(IMPORTED))
	assert_true(location.is_usable(), location.error)
	assert_eq(location.base_root, IMPORTED)
	assert_eq(location.origin, AssetLocation.Origin.LAUNCHER)
	assert_eq(location.origin_name(), "launcher settings")


func test_a_launcher_root_without_an_index_falls_back_to_the_committed_assets() -> void:
	var location: AssetLocation = AssetLocation.resolve(PackedStringArray(), _store(MISSING))
	assert_true(location.is_usable(), location.error)
	assert_eq(location.base_root, COMMITTED)
	assert_eq(location.origin, AssetLocation.Origin.COMMITTED)
	assert_eq(location.attempts.size(), 2, "\n".join(location.attempts))
	assert_string_contains(location.attempts[0], MISSING)


func test_no_launcher_settings_open_the_committed_assets() -> void:
	for store: LauncherStore in [null, LauncherStore.new(), LauncherStore.load_from(MISSING.path_join("launcher.cfg"))]:
		var location: AssetLocation = AssetLocation.resolve(PackedStringArray(), store)
		assert_true(location.is_usable(), location.error)
		assert_eq(location.base_root, COMMITTED)
		assert_eq(location.origin, AssetLocation.Origin.COMMITTED)
		assert_eq(location.warnings, PackedStringArray())
	var catalog: ImportedAssets = AssetLocation.resolve(PackedStringArray(), null).open()
	assert_true(catalog.is_valid(), catalog.error)
	assert_eq(catalog.root, COMMITTED)
	assert_eq(catalog.shippable_root, COMMITTED)


func test_nothing_usable_is_reported() -> void:
	var location: AssetLocation = AssetLocation.resolve(PackedStringArray(), _store(MISSING), MISSING.path_join("committed"))
	assert_false(location.is_usable())
	assert_eq(location.base_root, "")
	assert_eq(location.origin, AssetLocation.Origin.NONE)
	assert_eq(location.origin_name(), "none")
	assert_string_contains(location.error, "no imported assets")
	assert_string_contains(location.error, MISSING.path_join("committed"))
	assert_false(location.open("a_pack").is_valid())


func test_a_damaged_launcher_file_warns_and_still_resolves() -> void:
	var path: String = SCRATCH.path_join("launcher.cfg")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[meta]\nformat_version=99\n")
	file.close()
	var location: AssetLocation = AssetLocation.resolve(PackedStringArray(), LauncherStore.load_from(path))
	assert_eq(location.base_root, COMMITTED)
	assert_eq(location.warnings.size(), 1)
	assert_string_contains(location.warnings[0], "format version 99")
	var catalog: ImportedAssets = location.open()
	assert_true(catalog.warnings.has(location.warnings[0]))


func test_the_froglord_overlay_is_resolved_separately() -> void:
	var location: AssetLocation = AssetLocation.resolve(PackedStringArray(), null)
	var pointer_path: String = SCRATCH.path_join("froglord/current.cfg")
	assert_false(location.resolve_overlay(pointer_path).exists())
	var pointer := FrogLordPointer.new()
	pointer.index_root = OTHER
	pointer.fingerprint = "fedcba9876543210"
	assert_eq(pointer.write(pointer_path), OK)
	var overlay: FrogLordPointer = location.resolve_overlay(pointer_path)
	assert_true(overlay.exists())
	assert_same(location.overlay, overlay)
	assert_eq(overlay.index_root, OTHER)
	assert_eq(location.base_root, COMMITTED, "the overlay leaves the base root alone")

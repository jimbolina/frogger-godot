extends GutTest
## ProgressStore round trips, defaults and recovery from damaged files.

const ROOT: String = "user://test_progress_store"

var _path: String = ROOT.path_join("progress.cfg")


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


func _sample() -> ProgressStore:
	var store := ProgressStore.new()
	store.level_flags = PackedByteArray([3, 1, 0, 7, 255])
	store.gold_frogs = 0b10110
	store.music_volume = 0
	store.sound_volume = 8
	store.key_bindings = PackedInt32Array([KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE])
	return store


func _assert_defaults(store: ProgressStore) -> void:
	assert_eq(store.level_flags, PackedByteArray())
	assert_eq(store.gold_frogs, 0)
	assert_eq(store.music_volume, ProgressStore.DEFAULT_MUSIC_VOLUME)
	assert_eq(store.sound_volume, ProgressStore.DEFAULT_SOUND_VOLUME)
	assert_eq(store.key_bindings, PackedInt32Array())


func test_defaults_match_the_original_options() -> void:
	var store := ProgressStore.new()
	assert_eq(store.music_volume, 3)
	assert_eq(store.sound_volume, 5)
	assert_eq(ProgressStore.MAX_VOLUME, 8)
	assert_eq(ProgressStore.DEFAULT_PATH, "user://progress.cfg")


func test_round_trip_keeps_every_field() -> void:
	var saved: ProgressStore = _sample()
	assert_eq(saved.save(_path), "")
	var loaded: ProgressStore = ProgressStore.load_from(_path)
	assert_eq(loaded.error, "")
	assert_eq(loaded.level_flags, saved.level_flags)
	assert_eq(loaded.gold_frogs, saved.gold_frogs)
	assert_eq(loaded.music_volume, 0)
	assert_eq(loaded.sound_volume, 8)
	assert_eq(loaded.key_bindings, saved.key_bindings)


func test_save_creates_missing_folders() -> void:
	var nested: String = ROOT.path_join("a/b/progress.cfg")
	assert_eq(_sample().save(nested), "")
	assert_eq(ProgressStore.load_from(nested).gold_frogs, 0b10110)


func test_missing_file_gives_defaults_without_error() -> void:
	var store: ProgressStore = ProgressStore.load_from(ROOT.path_join("absent.cfg"))
	assert_eq(store.error, "")
	_assert_defaults(store)


func test_corrupt_file_gives_defaults_and_names_the_file() -> void:
	_write_text("[meta\nformat_version=((((\n")
	var store: ProgressStore = ProgressStore.load_from(_path)
	assert_engine_error("ConfigFile parse error", "Godot reports the malformed file")
	assert_string_contains(store.error, _path)
	assert_string_contains(store.error, "using defaults")
	_assert_defaults(store)


func test_other_version_gives_defaults_and_names_both_versions() -> void:
	_write_text("[meta]\nformat_version=99\n[progress]\ngold_frogs=5\n")
	var store: ProgressStore = ProgressStore.load_from(_path)
	assert_string_contains(store.error, "format version 99, expected 1")
	_assert_defaults(store)


func test_missing_version_is_rejected() -> void:
	_write_text("[progress]\ngold_frogs=5\n")
	var store: ProgressStore = ProgressStore.load_from(_path)
	assert_string_contains(store.error, "no format version")
	_assert_defaults(store)


func test_wrong_field_types_and_ranges_are_rejected_whole() -> void:
	var cases: PackedStringArray = [
		"[progress]\nlevel_flags=[1, 2]\n",
		"[progress]\ngold_frogs=\"many\"\n",
		"[progress]\ngold_frogs=-1\n",
		"[options]\nmusic_volume=9\n",
		"[options]\nsound_volume=-1\n",
		"[options]\nkey_bindings=\"up\"\n",
	]
	for body: String in cases:
		_write_text("[meta]\nformat_version=1\n[progress]\ngold_frogs=3\n" + body)
		var store: ProgressStore = ProgressStore.load_from(_path)
		assert_ne(store.error, "", body)
		_assert_defaults(store)


func test_overwrite_replaces_the_file_and_leaves_no_temporary() -> void:
	assert_eq(_sample().save(_path), "")
	var second := ProgressStore.new()
	second.level_flags = PackedByteArray([1])
	second.music_volume = 6
	assert_eq(second.save(_path), "")
	var loaded: ProgressStore = ProgressStore.load_from(_path)
	assert_eq(loaded.error, "")
	assert_eq(loaded.level_flags, PackedByteArray([1]))
	assert_eq(loaded.gold_frogs, 0)
	assert_eq(loaded.music_volume, 6)
	assert_false(FileAccess.file_exists(_path + ".tmp"))


func test_stale_temporary_does_not_block_saving() -> void:
	var stale: FileAccess = FileAccess.open(_path + ".tmp", FileAccess.WRITE)
	stale.store_string("garbage")
	stale.close()
	assert_eq(_sample().save(_path), "")
	assert_eq(ProgressStore.load_from(_path).error, "")
	assert_false(FileAccess.file_exists(_path + ".tmp"))


func test_invalid_values_are_not_saved_and_keep_the_previous_file() -> void:
	assert_eq(_sample().save(_path), "")
	var bad := ProgressStore.new()
	bad.sound_volume = 12
	assert_string_contains(bad.save(_path), "sound_volume 12")
	assert_eq(ProgressStore.load_from(_path).gold_frogs, 0b10110)

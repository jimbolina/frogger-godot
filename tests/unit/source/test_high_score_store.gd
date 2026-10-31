extends GutTest
## HighScoreStore round trips, absence and recovery from damaged files.

const ROOT: String = "user://test_high_score_store"
const LEVEL_ROWS: int = 180

var _path: String = ROOT.path_join("high_scores.cfg")


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


func _sample() -> HighScoreStore:
	var store := HighScoreStore.new()
	var names: PackedStringArray = ["AB[", "Q Z", "\"\\x"]
	for rank: int in 10:
		store.main_initials.append(names[rank % 3])
		store.main_scores.append(250000 - rank * 25000)
		for checkpoint: int in 5:
			store.main_times.append(rank * 5 + checkpoint)
	for row: int in LEVEL_ROWS:
		store.level_initials.append("L%02d" % (row % 100))
		store.level_scores.append(row * 7)
		for checkpoint: int in 5:
			store.level_times.append(65535 if checkpoint == 4 else row + checkpoint)
	return store


func _assert_absent(store: HighScoreStore) -> void:
	assert_false(store.present)
	assert_eq(store.main_initials, PackedStringArray())
	assert_eq(store.main_scores, PackedInt32Array())
	assert_eq(store.main_times, PackedInt32Array())
	assert_eq(store.level_initials, PackedStringArray())
	assert_eq(store.level_scores, PackedInt32Array())
	assert_eq(store.level_times, PackedInt32Array())


func _sample_text(replace: String = "", with: String = "") -> String:
	assert_eq(_sample().save(_path), "")
	var text: String = FileAccess.get_file_as_string(_path)
	if not replace.is_empty():
		assert_string_contains(text, replace)
		text = text.replace(replace, with)
	return text


func test_constants_name_the_file_and_version() -> void:
	assert_eq(HighScoreStore.DEFAULT_PATH, "user://high_scores.cfg")
	assert_eq(HighScoreStore.FORMAT_VERSION, 1)
	assert_eq(HighScoreStore.MAX_TIME, 65535)


func test_new_store_holds_no_defaults() -> void:
	_assert_absent(HighScoreStore.new())


func test_round_trip_keeps_every_field() -> void:
	var saved: HighScoreStore = _sample()
	assert_eq(saved.save(_path), "")
	var loaded: HighScoreStore = HighScoreStore.load_from(_path)
	assert_eq(loaded.error, "")
	assert_true(loaded.present)
	assert_eq(loaded.main_initials, saved.main_initials)
	assert_eq(loaded.main_scores, saved.main_scores)
	assert_eq(loaded.main_times, saved.main_times)
	assert_eq(loaded.level_initials, saved.level_initials)
	assert_eq(loaded.level_scores, saved.level_scores)
	assert_eq(loaded.level_times, saved.level_times)


func test_save_creates_missing_folders() -> void:
	var nested: String = ROOT.path_join("a/b/high_scores.cfg")
	assert_eq(_sample().save(nested), "")
	assert_true(HighScoreStore.load_from(nested).present)


func test_missing_file_is_absent_without_error() -> void:
	var store: HighScoreStore = HighScoreStore.load_from(ROOT.path_join("absent.cfg"))
	assert_eq(store.error, "")
	_assert_absent(store)


func test_corrupt_file_is_absent_and_names_the_file() -> void:
	_write_text("[meta\nformat_version=((((\n")
	var store: HighScoreStore = HighScoreStore.load_from(_path)
	assert_engine_error("ConfigFile parse error", "Godot reports the malformed file")
	assert_string_contains(store.error, _path)
	assert_true(store.error.ends_with("using defaults"))
	_assert_absent(store)


func test_other_version_is_rejected_naming_both_versions() -> void:
	_write_text(_sample_text("format_version=1", "format_version=99"))
	var store: HighScoreStore = HighScoreStore.load_from(_path)
	assert_string_contains(store.error, "format version 99, expected 1")
	assert_true(store.error.ends_with("using defaults"))
	_assert_absent(store)


func test_missing_version_is_rejected() -> void:
	_write_text(_sample_text("format_version=1", ""))
	var store: HighScoreStore = HighScoreStore.load_from(_path)
	assert_string_contains(store.error, "no format version")
	_assert_absent(store)


func _write_fields(changes: Dictionary[String, Variant]) -> void:
	var sample: HighScoreStore = _sample()
	var fields: Dictionary[String, Variant] = {
		"main/initials": sample.main_initials, "main/scores": sample.main_scores, "main/times": sample.main_times,
		"levels/initials": sample.level_initials, "levels/scores": sample.level_scores,
		"levels/times": sample.level_times,
	}
	fields.merge(changes, true)
	var file := ConfigFile.new()
	file.set_value("meta", "format_version", 1)
	for key: String in fields:
		if fields[key] != null:
			file.set_value(key.get_slice("/", 0), key.get_slice("/", 1), fields[key])
	assert_eq(file.save(_path), OK)


func test_wrong_field_types_and_ranges_are_rejected_whole() -> void:
	var sample: HighScoreStore = _sample()
	var negative: PackedInt32Array = sample.main_scores.duplicate()
	negative[9] = -1
	var over: PackedInt32Array = sample.level_times.duplicate()
	over[899] = 65536
	var below: PackedInt32Array = sample.main_times.duplicate()
	below[0] = -1
	var wide: PackedStringArray = sample.main_initials.duplicate()
	wide[4] = "ABCD"
	var short: PackedStringArray = sample.level_initials.duplicate()
	short.resize(179)
	var cases: Array[Dictionary] = [
		{"main/scores": negative}, {"levels/times": over}, {"main/times": below},
		{"main/initials": wide}, {"levels/initials": short}, {"main/scores": "many"},
		{"levels/scores": PackedInt64Array(Array(sample.level_scores))}, {"main/initials": Array(sample.main_initials)},
		{"levels/times": null}, {"main/scores": PackedInt32Array([1, 2, 3])},
	]
	for case: Dictionary in cases:
		var changes: Dictionary[String, Variant] = {}
		changes.assign(case)
		_write_fields(changes)
		var store: HighScoreStore = HighScoreStore.load_from(_path)
		assert_ne(store.error, "", str(case.keys()))
		assert_true(store.error.ends_with("using defaults"), store.error)
		_assert_absent(store)


func test_invalid_values_are_not_saved_and_keep_the_previous_file() -> void:
	assert_eq(_sample().save(_path), "")
	var cases: Array[Callable] = [
		func(s: HighScoreStore) -> void: s.main_scores[3] = -5,
		func(s: HighScoreStore) -> void: s.level_times[7] = 70000,
		func(s: HighScoreStore) -> void: s.level_initials[2] = "AB",
		func(s: HighScoreStore) -> void: s.main_initials.remove_at(0),
		func(s: HighScoreStore) -> void: s.level_scores.append(1),
		func(s: HighScoreStore) -> void: s.main_times.resize(49),
	]
	for change: Callable in cases:
		var bad: HighScoreStore = _sample()
		change.call(bad)
		assert_string_contains(bad.save(_path), "high scores not saved")
	assert_string_contains(HighScoreStore.new().save(_path), "0 main initials, expected 10")
	var kept: HighScoreStore = HighScoreStore.load_from(_path)
	assert_true(kept.present)
	assert_eq(kept.main_scores, _sample().main_scores)


func test_overwrite_replaces_the_file_and_leaves_no_temporary() -> void:
	assert_eq(_sample().save(_path), "")
	var second: HighScoreStore = _sample()
	second.main_initials[0] = "NEW"
	second.level_scores[179] = 123456
	assert_eq(second.save(_path), "")
	var loaded: HighScoreStore = HighScoreStore.load_from(_path)
	assert_eq(loaded.error, "")
	assert_eq(loaded.main_initials[0], "NEW")
	assert_eq(loaded.level_scores[179], 123456)
	assert_false(FileAccess.file_exists(_path + ".tmp"))


func test_stale_temporary_does_not_block_saving() -> void:
	var stale: FileAccess = FileAccess.open(_path + ".tmp", FileAccess.WRITE)
	stale.store_string("garbage")
	stale.close()
	assert_eq(_sample().save(_path), "")
	assert_eq(HighScoreStore.load_from(_path).error, "")
	assert_false(FileAccess.file_exists(_path + ".tmp"))


func test_store_copies_from_a_high_score_table() -> void:
	var table := HighScoreTable.new()
	var sample: HighScoreStore = _sample()
	table.main_initials = sample.main_initials
	table.main_scores = sample.main_scores
	table.main_times = sample.main_times
	table.level_initials = sample.level_initials
	table.level_scores = sample.level_scores
	table.level_times = sample.level_times
	var store := HighScoreStore.new()
	store.main_initials = table.main_initials
	store.main_scores = table.main_scores
	store.main_times = table.main_times
	store.level_initials = table.level_initials
	store.level_scores = table.level_scores
	store.level_times = table.level_times
	assert_eq(store.save(_path), "")
	assert_eq(HighScoreStore.load_from(_path).level_initials, table.level_initials)

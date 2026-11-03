extends GutTest
## FrogLordWatch imports a changed save once it has stayed the same for one
## more poll, never twice for the same files, retries an unfinished save when
## it changes or after a few polls, and reports a missing folder or save
## without importing.

const FOLDER: String = "/FrogLord/save"
const BASE: String = "user://assets/0123456789abcdef"


func _watch(pointer: FrogLordPointer = null) -> FrogLordWatch:
	return FrogLordWatch.create(true, FOLDER, BASE, pointer)


func _clean(state: String, unmapped: PackedStringArray = PackedStringArray()) -> AssetImporter.OverlayResult:
	var result := AssetImporter.OverlayResult.new()
	result.source_state = state
	result.index_root = "user://froglord/over-x/fedcba9876543210"
	result.source_summary = "FrogLord mod modded_FROGGER.EXE + modded_FROGPSX.MWD over " + BASE
	result.unmapped = unmapped
	result.report_path = result.index_root.path_join("support_report.tsv")
	return result


func test_off_or_without_a_folder_never_imports() -> void:
	var off: FrogLordWatch = FrogLordWatch.create(false, FOLDER, BASE, null)
	assert_eq(off.phase, FrogLordWatch.Phase.OFF)
	assert_false(off.is_on())
	assert_false(off.poll(true, "a"))
	assert_false(off.poll(true, "a"))
	assert_eq(off.message, "")
	var unchosen: FrogLordWatch = FrogLordWatch.create(true, "", BASE, null)
	assert_eq(unchosen.phase, FrogLordWatch.Phase.NO_FOLDER)
	assert_true(unchosen.warning)
	assert_false(unchosen.poll(true, "a"))
	assert_false(unchosen.poll(true, "a"))


func test_a_new_save_imports_after_one_unchanged_poll() -> void:
	var watch: FrogLordWatch = _watch()
	assert_false(watch.poll(true, "a"), "the first sight only records the files")
	assert_eq(watch.phase, FrogLordWatch.Phase.SETTLING)
	assert_true(watch.poll(true, "a"), "unchanged for one poll: import")
	assert_eq(watch.phase, FrogLordWatch.Phase.IMPORTING)
	assert_false(watch.poll(true, "a"), "no second import while one runs")
	watch.finish(_clean("a"))
	assert_eq(watch.phase, FrogLordWatch.Phase.READY)
	assert_false(watch.warning)
	assert_string_contains(watch.message, "imported")
	assert_false(watch.poll(true, "a"), "the same files are not imported again")
	assert_false(watch.poll(true, "a"))


func test_a_save_still_being_written_waits_until_it_stops_changing() -> void:
	var watch: FrogLordWatch = _watch()
	watch.poll(true, "a")
	assert_true(watch.poll(true, "a"))
	watch.finish(_clean("a"))
	assert_false(watch.poll(true, "b"), "a change settles first")
	assert_eq(watch.phase, FrogLordWatch.Phase.SETTLING)
	assert_string_contains(watch.message, "changed")
	assert_false(watch.poll(true, "c"), "still changing")
	assert_false(watch.poll(true, "d"))
	assert_true(watch.poll(true, "d"), "stable again: import")
	watch.finish(_clean("d"))
	assert_false(watch.poll(true, "d"))


func test_a_pointer_of_the_same_files_counts_as_imported() -> void:
	var pointer := FrogLordPointer.new()
	pointer.index_root = "user://froglord/over-x/fedcba9876543210"
	pointer.data_dir = FOLDER
	pointer.fallback_root = BASE
	pointer.source_state = "a"
	pointer.source_summary = "FrogLord mod"
	assert_eq(pointer.write("user://froglord_watch_test/current.cfg"), OK)
	var read: FrogLordPointer = FrogLordPointer.read("user://froglord_watch_test/current.cfg")
	DirAccess.remove_absolute("user://froglord_watch_test/current.cfg")
	DirAccess.remove_absolute("user://froglord_watch_test")
	var watch: FrogLordWatch = _watch(read)
	assert_false(watch.poll(true, "a"))
	assert_false(watch.poll(true, "a"), "unchanged files need no import at start")
	assert_eq(watch.phase, FrogLordWatch.Phase.READY)
	var other_base: FrogLordWatch = FrogLordWatch.create(true, FOLDER, "res://assets", read)
	other_base.poll(true, "a")
	assert_true(other_base.poll(true, "a"), "an overlay over another base root is imported again")
	var other_folder: FrogLordWatch = FrogLordWatch.create(true, "/elsewhere", BASE, read)
	other_folder.poll(true, "a")
	assert_true(other_folder.poll(true, "a"), "an overlay of another folder is imported again")


func test_a_retry_waits_for_a_change_or_a_few_polls() -> void:
	var watch: FrogLordWatch = _watch()
	watch.poll(true, "a")
	assert_true(watch.poll(true, "a"))
	var retry := AssetImporter.OverlayResult.new()
	retry.retry = "the files changed during the import"
	retry.source_state = "a"
	watch.finish(retry)
	assert_eq(watch.phase, FrogLordWatch.Phase.WAITING)
	assert_true(watch.warning)
	for poll: int in FrogLordWatch.RETRY_POLLS - 1:
		assert_false(watch.poll(true, "a"), "poll %d of the same files" % poll)
	assert_true(watch.poll(true, "a"), "tried again after a few polls")
	watch.finish(retry)
	assert_false(watch.poll(true, "b"))
	assert_true(watch.poll(true, "b"), "a change is tried once it settles")


func test_a_failed_import_is_not_repeated_until_the_files_change() -> void:
	var watch: FrogLordWatch = _watch()
	watch.poll(true, "a")
	assert_true(watch.poll(true, "a"))
	var failed := AssetImporter.OverlayResult.new()
	failed.source_state = "a"
	failed.problems = PackedStringArray(["maps: ORG1 cannot be decoded"])
	watch.finish(failed)
	assert_eq(watch.phase, FrogLordWatch.Phase.FAILED)
	assert_true(watch.warning)
	assert_string_contains(watch.message, "ORG1 cannot be decoded")
	for poll: int in 8:
		assert_false(watch.poll(true, "a"))
	assert_eq(watch.phase, FrogLordWatch.Phase.FAILED)
	assert_false(watch.poll(true, "b"))
	assert_true(watch.poll(true, "b"))


func test_unmapped_rows_are_a_warning_not_a_failure() -> void:
	var watch: FrogLordWatch = _watch()
	watch.poll(true, "a")
	watch.poll(true, "a")
	watch.finish(_clean("a", PackedStringArray(["form\tORG_PROBE\tORG1\tunknown entity"])))
	assert_eq(watch.phase, FrogLordWatch.Phase.READY)
	assert_true(watch.warning)
	assert_eq(watch.unmapped.size(), 1)
	assert_string_contains(watch.message, "1 forms, entities or remaps")
	assert_string_contains(watch.message, "support_report.tsv")


func test_a_missing_folder_or_save_warns_and_recovers() -> void:
	var watch: FrogLordWatch = _watch()
	var first: int = watch.revision
	assert_false(watch.poll(false, ""))
	assert_eq(watch.phase, FrogLordWatch.Phase.NO_FOLDER)
	assert_true(watch.warning)
	assert_string_contains(watch.message, "missing")
	assert_gt(watch.revision, first)
	var shown: int = watch.revision
	assert_false(watch.poll(false, ""))
	assert_eq(watch.revision, shown, "the same message is not repeated")
	assert_false(watch.poll(true, ""))
	assert_eq(watch.phase, FrogLordWatch.Phase.NO_SAVE)
	assert_string_contains(watch.message, "modded_FROGGER.EXE")
	assert_false(watch.poll(true, "a"))
	assert_true(watch.poll(true, "a"), "the save that appears is imported")
	watch.finish(_clean("a"))
	assert_false(watch.poll(false, ""))
	assert_eq(watch.phase, FrogLordWatch.Phase.NO_FOLDER)
	assert_false(watch.poll(true, "a"))
	assert_eq(watch.phase, FrogLordWatch.Phase.READY, "the same files return as imported")


func test_stop_turns_the_watch_off() -> void:
	var watch: FrogLordWatch = _watch()
	watch.poll(true, "a")
	assert_true(watch.poll(true, "a"))
	watch.stop()
	assert_eq(watch.phase, FrogLordWatch.Phase.OFF)
	watch.finish(_clean("a"))
	assert_eq(watch.phase, FrogLordWatch.Phase.OFF, "a late result is ignored")
	assert_false(watch.poll(true, "b"))

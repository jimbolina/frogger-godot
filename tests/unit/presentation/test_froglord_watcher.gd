extends GutTest
## FrogLordWatcher polls its folder through the importer, imports a settled
## save on a worker thread or inline, shows what the watch says without
## blocking, starts only when FrogLord is on and keeps one watcher per process.

const SCRATCH: String = "user://froglord_watcher_test"
const BASE: String = "user://assets/0123456789abcdef"


class FakeImporter:
	extends AssetImporter
	var state: String = "a"
	var imports: Array[PackedStringArray] = []
	var problems := PackedStringArray()
	var unmapped := PackedStringArray()
	var thread_ids := PackedInt64Array()

	func source_state(_froglord_dir: String) -> String:
		return state

	func import_overlay(froglord_dir: String, base_root: String,
			progress: Callable, _cancelled: Callable) -> AssetImporter.OverlayResult:
		imports.append(PackedStringArray([froglord_dir, base_root, overlay_parent, pointer_path]))
		thread_ids.append(OS.get_thread_caller_id())
		if progress.is_valid():
			progress.call(0.5, "Converting maps")
		var result := AssetImporter.OverlayResult.new()
		result.source_state = state
		result.index_root = overlay_parent.path_join("fedcba9876543210")
		result.fallback_root = base_root
		result.problems = problems
		result.unmapped = unmapped
		result.report_path = result.index_root.path_join("support_report.tsv")
		return result


var _folder: String = ""


func before_each() -> void:
	_remove(SCRATCH)
	_folder = SCRATCH.path_join("save")
	assert_eq(DirAccess.make_dir_recursive_absolute(_folder), OK)


func after_each() -> void:
	var running: FrogLordWatcher = FrogLordWatcher.current()
	if running != null:
		running.shut_down()


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


func _watcher(importer: FakeImporter, threaded: bool, folder: String = "") -> FrogLordWatcher:
	var watcher := FrogLordWatcher.new()
	watcher.importer = importer
	watcher.threaded = threaded
	watcher.polls_on_timer = false
	watcher.pointer_path = SCRATCH.path_join("current.cfg")
	watcher.configure(folder if not folder.is_empty() else _folder, BASE)
	add_child_autofree(watcher)
	return watcher


func test_a_settled_save_imports_once_over_the_base_roots_overlay_folder() -> void:
	var importer := FakeImporter.new()
	var watcher: FrogLordWatcher = _watcher(importer, false)
	assert_eq(importer.imports.size(), 0, "entering the tree polls once without importing")
	assert_true(watcher.poll(), "unchanged for one poll: import")
	assert_eq(importer.imports.size(), 1)
	assert_eq(importer.imports[0], PackedStringArray([_folder, BASE, AssetImporter.overlay_parent_for(BASE), watcher.pointer_path]))
	assert_ne(AssetImporter.overlay_parent_for(BASE), AssetImporter.OVERLAY_PARENT, "overlays over another root get their own folder")
	assert_eq(AssetImporter.overlay_parent_for("res://assets"), AssetImporter.OVERLAY_PARENT)
	assert_eq(watcher.watch.phase, FrogLordWatch.Phase.READY)
	assert_not_null(watcher.last_result)
	assert_string_contains(watcher.notice().shown_text(), "imported")
	assert_false(watcher.poll())
	assert_eq(importer.imports.size(), 1, "the same files are not imported again")
	importer.state = "b"
	assert_false(watcher.poll())
	assert_true(watcher.poll())
	assert_eq(importer.imports.size(), 2)


func test_the_import_runs_on_a_worker_thread() -> void:
	var importer := FakeImporter.new()
	var watcher: FrogLordWatcher = _watcher(importer, true)
	assert_true(watcher.poll())
	assert_true(watcher.is_importing())
	assert_false(watcher.poll(), "no second import while one runs")
	for frame: int in 200:
		if not watcher.is_importing():
			break
		await get_tree().process_frame
	assert_false(watcher.is_importing(), "the thread finished")
	assert_eq(importer.imports.size(), 1)
	assert_ne(importer.thread_ids[0], OS.get_main_thread_id(), "imported off the main thread")
	assert_eq(watcher.watch.phase, FrogLordWatch.Phase.READY)
	await get_tree().process_frame
	assert_eq(watcher.progress_label, "Converting maps", "progress reaches the main thread deferred")


func test_problems_and_unmapped_rows_show_as_warnings() -> void:
	var importer := FakeImporter.new()
	importer.unmapped = PackedStringArray(["form\tORG_PROBE\tORG1\tunknown entity"])
	var watcher: FrogLordWatcher = _watcher(importer, false)
	assert_true(watcher.poll())
	assert_eq(watcher.watch.phase, FrogLordWatch.Phase.READY)
	assert_string_contains(watcher.notice().shown_text(), "the port cannot play")
	importer.state = "b"
	importer.problems = PackedStringArray(["maps: ORG1 cannot be decoded"])
	watcher.poll()
	assert_true(watcher.poll())
	assert_eq(watcher.watch.phase, FrogLordWatch.Phase.FAILED)
	assert_string_contains(watcher.notice().shown_text(), "ORG1 cannot be decoded")


func test_a_missing_folder_shows_a_message_and_imports_nothing() -> void:
	var importer := FakeImporter.new()
	var watcher: FrogLordWatcher = _watcher(importer, false, SCRATCH.path_join("missing"))
	assert_false(watcher.poll())
	assert_false(watcher.poll())
	assert_eq(importer.imports.size(), 0)
	assert_eq(watcher.watch.phase, FrogLordWatch.Phase.NO_FOLDER)
	assert_string_contains(watcher.notice().shown_text(), "missing")
	importer.state = ""
	var empty: FrogLordWatcher = _watcher(importer, false)
	assert_false(empty.poll())
	assert_eq(empty.watch.phase, FrogLordWatch.Phase.NO_SAVE)
	assert_eq(importer.imports.size(), 0)


func test_follow_starts_one_watcher_only_when_froglord_is_on() -> void:
	var settings := LauncherSettings.new()
	assert_null(FrogLordWatcher.follow(get_tree(), settings, BASE), "off: none")
	assert_null(FrogLordWatcher.follow(get_tree(), null, BASE))
	assert_null(FrogLordWatcher.current())
	settings.froglord_enabled = true
	settings.froglord_dir = SCRATCH.path_join("missing")
	var first: FrogLordWatcher = FrogLordWatcher.follow(get_tree(), settings, BASE)
	assert_not_null(first)
	first.importer = FakeImporter.new()
	first.polls_on_timer = false
	assert_same(FrogLordWatcher.follow(get_tree(), settings, BASE), first, "the same folder and root keep it")
	await get_tree().process_frame
	assert_same(first.get_parent(), get_tree().root, "it lives under the root, across scene changes")
	assert_eq(first.watch.phase, FrogLordWatch.Phase.NO_FOLDER)
	var moved: FrogLordWatcher = FrogLordWatcher.follow(get_tree(), settings, "res://assets")
	assert_ne(moved, first, "another base root replaces it")
	moved.importer = FakeImporter.new()
	moved.polls_on_timer = false
	settings.froglord_enabled = false
	assert_null(FrogLordWatcher.follow(get_tree(), settings, BASE), "turned off: stopped")
	assert_null(FrogLordWatcher.current())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(first))
	assert_false(is_instance_valid(moved))

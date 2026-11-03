extends RetailTest
## The setup screen's import protocol end to end: ImportProcess starts the game
## again as a headless child on the setup scene in import mode, the child
## imports FROGGER_DATA_DIR into a scratch user:// root and reports through its
## progress file, and the parent follows it to the end; a second child is
## cancelled part way and leaves nothing behind. The import itself is checked
## against the committed assets by test_retail_runtime_import.

const ROOT: String = "user://setup_child_import"
const TIMEOUT_MSEC: int = 240000

var _target: String = ""
var _report: ImportProgress = null
var _fractions: Array[float] = []
var _milliseconds: int = 0
var _start_error: String = ""


func before_all() -> void:
	ImportProcess.remove_tree(ROOT)
	var detection: AssetImporter.Detection = AssetImporterFactory.create().detect(OS.get_environment(GameDataLocator.ENV_VAR))
	_target = ROOT.path_join("assets").path_join(detection.fingerprint)
	var process: ImportProcess = _new_process("run")
	var started: int = Time.get_ticks_msec()
	if not process.start(_command(_target)):
		_start_error = process.error
		return
	_report = _follow(process, -1.0)
	_milliseconds = Time.get_ticks_msec() - started
	gut.p("setup child import: %.1f s, %d progress readings" % [_milliseconds / 1000.0, _fractions.size()])


func after_all() -> void:
	ImportProcess.remove_tree(ROOT)


func _new_process(run_name: String) -> ImportProcess:
	var process := ImportProcess.new()
	process.progress_path = ROOT.path_join("%s_progress.txt" % run_name)
	process.log_path = ROOT.path_join("%s.log" % run_name)
	return process


func _command(target: String) -> ImportCommand:
	var command := ImportCommand.new()
	command.data_dir = OS.get_environment(GameDataLocator.ENV_VAR)
	command.target_root = target
	return command


func _follow(process: ImportProcess, stop_after: float) -> ImportProgress:
	var started: int = Time.get_ticks_msec()
	var report: ImportProgress = process.poll()
	while not report.finished and Time.get_ticks_msec() - started < TIMEOUT_MSEC:
		if stop_after >= 0.0 and report.fraction > stop_after:
			return report
		_fractions.append(report.fraction)
		OS.delay_msec(100)
		report = process.poll()
	return report


func test_the_child_imports_and_reports_to_the_end() -> void:
	assert_eq(_start_error, "")
	assert_not_null(_report)
	if _report == null:
		return
	assert_true(_report.finished, "the child finished within the time limit")
	assert_true(_report.succeeded, "; ".join(_report.problems))
	assert_almost_eq(_report.fraction, 1.0, 0.0001)
	assert_eq(_report.label, "Done")
	var music_noted: bool = false
	for note: String in _report.notes:
		music_noted = music_noted or note.contains("no music")
	assert_true(music_noted, "an import without a disc says it has no music")
	var middle: int = 0
	for fraction: float in _fractions:
		if fraction > 0.05 and fraction < 0.95:
			middle += 1
	assert_gt(middle, 5, "the parent saw the progress move")
	assert_eq(_report.unknown_lines, 0)


func test_the_root_is_complete_and_opens() -> void:
	assert_true(ImportedAssets.has_index(_target))
	assert_false(DirAccess.dir_exists_absolute(_target + ImportProcess.STAGING_SUFFIX))
	var catalog: ImportedAssets = ImportedAssets.open(_target)
	assert_true(catalog.is_valid(), catalog.error)
	assert_true(catalog.playable_level_codes().has("ORG1"))
	catalog.close()


func test_the_recorded_root_is_the_one_the_game_plays_from() -> void:
	var store := LauncherStore.new()
	store.found = true
	store.settings.imported_root = _target
	var location: AssetLocation = AssetLocation.resolve(PackedStringArray(), store, ROOT.path_join("no_committed_assets"))
	assert_true(location.is_usable(), location.error)
	assert_eq(location.base_root, _target)
	assert_eq(location.origin, AssetLocation.Origin.LAUNCHER)


func test_a_cancelled_child_leaves_nothing() -> void:
	var target: String = ROOT.path_join("cancelled")
	var process: ImportProcess = _new_process("cancel")
	assert_true(process.start(_command(target)), process.error)
	var report: ImportProgress = _follow(process, 0.1)
	assert_false(report.finished, "cancelled while it ran")
	assert_true(process.cancel())
	assert_false(process.is_running())
	assert_false(DirAccess.dir_exists_absolute(target))
	assert_false(DirAccess.dir_exists_absolute(target + ImportProcess.STAGING_SUFFIX))

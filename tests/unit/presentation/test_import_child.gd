extends GutTest
## ImportChild, the setup scene's import mode, runs one import in process and
## writes its progress file: progress lines that thin out, the importer's notes
## and problems, and the final record. A fake importer stands in for the real one.

const ROOT: String = "user://test_import_child"


class FakeImporter:
	extends AssetImporter
	var steps: int = 400
	var failures := PackedStringArray()
	var remarks := PackedStringArray()
	var calls: int = 0
	var received := PackedStringArray()

	func run(data_dir: String, disc_path: String, target_root: String,
			progress: Callable, _cancelled: Callable) -> PackedStringArray:
		calls += 1
		received = PackedStringArray([data_dir, disc_path, target_root])
		for step: int in range(steps + 1):
			progress.call(step / float(steps), "Converting maps" if step < steps else "Done")
		notes = remarks.duplicate()
		return failures.duplicate()


var _progress: String = ""


func before_each() -> void:
	ImportProcess.remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)
	_progress = ProjectSettings.globalize_path(ROOT.path_join("nested/progress.txt"))


func after_all() -> void:
	ImportProcess.remove_tree(ROOT)


func _command() -> ImportCommand:
	var command := ImportCommand.new()
	command.data_dir = "/Games/Frogger"
	command.disc_path = "/Discs/FROGGER.mds"
	command.target_root = ROOT.path_join("assets/0123456789abcdef")
	command.progress_path = _progress
	command.user_dir = ProjectSettings.globalize_path("user://")
	return ImportCommand.parse(command.user_arguments())


func _read() -> String:
	return FileAccess.get_file_as_string(_progress)


func test_a_successful_import_writes_progress_notes_and_done() -> void:
	var importer := FakeImporter.new()
	importer.remarks = PackedStringArray(["music: no disc image supplied"])
	var code: int = ImportChild.run(_command(), importer, ProjectSettings.globalize_path("user://"))
	assert_eq(code, 0)
	assert_eq(importer.received, PackedStringArray(["/Games/Frogger", "/Discs/FROGGER.mds", ROOT.path_join("assets/0123456789abcdef")]))
	var text: String = _read()
	var report: ImportProgress = ImportProgress.parse(text)
	assert_true(report.finished)
	assert_true(report.succeeded)
	assert_almost_eq(report.fraction, 1.0, 0.0001)
	assert_eq(report.label, "Done")
	assert_eq(report.notes, PackedStringArray(["music: no disc image supplied"]))
	assert_true(text.ends_with(ImportProgress.done_line(true)), "the final record is last")
	var lines: int = text.count("\n")
	assert_lt(lines, 300, "progress lines thin out")
	assert_gt(lines, 20, "progress is still reported along the way")


func test_a_failed_import_writes_its_problems() -> void:
	var importer := FakeImporter.new()
	importer.steps = 3
	importer.failures = PackedStringArray(["cannot read FROGPSX.MWD"])
	assert_eq(ImportChild.run(_command(), importer, ProjectSettings.globalize_path("user://")), 1)
	var report: ImportProgress = ImportProgress.parse(_read())
	assert_true(report.finished)
	assert_false(report.succeeded)
	assert_eq(report.problems, PackedStringArray(["cannot read FROGPSX.MWD"]))


func test_an_incomplete_command_fails_without_importing() -> void:
	var command: ImportCommand = ImportCommand.parse(PackedStringArray([ImportCommand.IMPORT_FLAG,
		ImportCommand.PROGRESS_ARGUMENT + _progress]))
	var importer := FakeImporter.new()
	assert_eq(ImportChild.run(command, importer, ProjectSettings.globalize_path("user://")), 1)
	assert_eq(importer.calls, 0)
	var report: ImportProgress = ImportProgress.parse(_read())
	assert_false(report.succeeded)
	assert_string_contains(report.problems[0] if not report.problems.is_empty() else "", "--data-dir")


func test_another_user_folder_fails_without_importing() -> void:
	var importer := FakeImporter.new()
	assert_eq(ImportChild.run(_command(), importer, "/somewhere/else"), 1)
	assert_eq(importer.calls, 0)
	var report: ImportProgress = ImportProgress.parse(_read())
	assert_false(report.succeeded)
	assert_string_contains(report.problems[0] if not report.problems.is_empty() else "", "/somewhere/else")


func test_an_earlier_progress_file_is_replaced() -> void:
	DirAccess.make_dir_recursive_absolute(_progress.get_base_dir())
	var stale: FileAccess = FileAccess.open(_progress, FileAccess.WRITE)
	stale.store_string(ImportProgress.problem_line("stale") + ImportProgress.done_line(false))
	stale.close()
	var importer := FakeImporter.new()
	importer.steps = 2
	assert_eq(ImportChild.run(_command(), importer, ProjectSettings.globalize_path("user://")), 0)
	var report: ImportProgress = ImportProgress.parse(_read())
	assert_true(report.succeeded)
	assert_eq(report.problems, PackedStringArray())


func test_without_a_progress_file_the_child_exits_with_two() -> void:
	var command := ImportCommand.new()
	assert_eq(ImportChild.run(command, FakeImporter.new(), ProjectSettings.globalize_path("user://")), 2)


func test_the_parent_cleans_up_what_a_killed_import_left() -> void:
	var target: String = ROOT.path_join("assets/0123456789abcdef")
	DirAccess.make_dir_recursive_absolute(target + ImportProcess.STAGING_SUFFIX + "/maps")
	DirAccess.make_dir_recursive_absolute(target + ImportProcess.RETIRED_SUFFIX + "/maps")
	ImportProcess.clean_up(target)
	assert_false(DirAccess.dir_exists_absolute(target + ImportProcess.STAGING_SUFFIX))
	assert_false(DirAccess.dir_exists_absolute(target + ImportProcess.RETIRED_SUFFIX))
	assert_true(DirAccess.dir_exists_absolute(target + "/maps"), "an earlier root moved aside is put back")
	DirAccess.make_dir_recursive_absolute(target + ImportProcess.RETIRED_SUFFIX)
	ImportProcess.clean_up(target)
	assert_false(DirAccess.dir_exists_absolute(target + ImportProcess.RETIRED_SUFFIX), "a replaced root is removed")
	assert_true(DirAccess.dir_exists_absolute(target))

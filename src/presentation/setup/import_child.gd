class_name ImportChild
extends RefCounted
## The setup scene's import mode: one [AssetImporter] run on the main thread
## of a headless child process, reported line by line in an [ImportProgress]
## file for the setup screen that started it.
##
## The file is truncated first, then every record is appended as a whole line
## with the file opened and closed around it, so the reader never holds it
## against the writer. Progress lines are written when the label changes, the
## fraction moves by [constant MIN_STEP] or [constant MIN_INTERVAL_MSEC] has
## passed. The last line is always the [constant ImportProgress.DONE] record.

## The least change of fraction that is written at once.
const MIN_STEP: float = 0.005
## The longest wait between two progress lines while the import advances.
const MIN_INTERVAL_MSEC: int = 250
## How often a record that could not be appended is tried again.
const WRITE_ATTEMPTS: int = 5

## Records that could not be written.
var write_failures: int = 0

var _path: String = ""
var _last_fraction: float = -1.0
var _last_label: String = ""
var _last_msec: int = 0


## Runs [param command] with [param importer], checking that [param own_user_dir]
## (this process's [code]user://[/code] made absolute) is the folder the setup
## screen named. Returns the process exit code: 0 on success, 1 when the import
## failed, 2 when no progress file could be written.
static func run(command: ImportCommand, importer: AssetImporter, own_user_dir: String) -> int:
	var child := ImportChild.new()
	return child._run(command, importer, own_user_dir)


func _run(command: ImportCommand, importer: AssetImporter, own_user_dir: String) -> int:
	_path = command.progress_path
	if _path.is_empty() or not _truncate():
		printerr("setup import: cannot write the progress file %s" % _path)
		return 2
	var problems := PackedStringArray()
	if not command.error.is_empty():
		problems.append(command.error)
	elif not command.same_user_dir(own_user_dir):
		problems.append("this import's user folder %s is not the setup screen's %s" % [own_user_dir, command.user_dir])
	if problems.is_empty():
		_report(0.0, "Starting")
		problems = importer.run(command.data_dir, command.disc_path, command.target_root, _report, Callable())
	for note: String in importer.notes:
		_append(ImportProgress.note_line(note))
	for problem: String in problems:
		_append(ImportProgress.problem_line(problem))
		printerr("setup import: %s" % problem)
	_append(ImportProgress.done_line(problems.is_empty()))
	return 0 if problems.is_empty() else 1


func _report(fraction: float, label: String) -> void:
	var now: int = Time.get_ticks_msec()
	var moved: bool = fraction >= 1.0 or fraction - _last_fraction >= MIN_STEP
	if label == _last_label and not moved and now - _last_msec < MIN_INTERVAL_MSEC:
		return
	_last_fraction = fraction
	_last_label = label
	_last_msec = now
	_append(ImportProgress.progress_line(fraction, label))


func _truncate() -> bool:
	var folder: String = _path.get_base_dir()
	if not folder.is_empty() and not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return false
	file.close()
	return true


func _append(line: String) -> void:
	for attempt: int in range(WRITE_ATTEMPTS):
		var file: FileAccess = FileAccess.open(_path, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
			file.store_string(line)
			file.close()
			return
		OS.delay_msec(20 * (attempt + 1))
	write_failures += 1

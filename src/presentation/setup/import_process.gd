class_name ImportProcess
extends RefCounted
## Runs a setup import in a child process and follows it: the same executable,
## headless, on the setup scene in import mode ([ImportCommand]).
##
## [method start] spawns the child, [method poll] reads its progress file and
## notices a child that ended without its final record, and [method cancel]
## kills it and removes what it left. A run from source passes the project
## folder with [code]--path[/code], so the child shares the parent's project
## settings and therefore its [code]user://[/code] folder.

## The progress file the child writes.
const PROGRESS_PATH: String = "user://setup/import_progress.txt"
## The engine log of the child.
const LOG_PATH: String = "user://logs/setup_import.log"
## The scene the child runs in import mode.
const SCENE: String = "res://scenes/setup.tscn"
## The suffix of the folder an import writes before it is renamed, as the importer names it.
const STAGING_SUFFIX: String = ".partial"
## The suffix an earlier root is moved to while a new one replaces it, as the importer names it.
const RETIRED_SUFFIX: String = ".old"

## The child's process id, or -1 before [method start].
var pid: int = -1
## The root the running import writes.
var target_root: String = ""
## Where the child writes its progress.
var progress_path: String = PROGRESS_PATH
## Where the child writes its engine log.
var log_path: String = LOG_PATH
## Why [method start] failed, or "".
var error: String = ""

var _ended: bool = false


## Whether this run is from source (an editor build of the engine) rather than an exported game.
static func from_source() -> bool:
	return not OS.has_feature("template")


## Starts importing as [param command] says; false with [member error] when the
## child could not be started. The progress and user folders are filled in.
func start(command: ImportCommand) -> bool:
	error = ""
	_ended = false
	target_root = command.target_root
	clean_up(target_root)
	var progress_file: String = ProjectSettings.globalize_path(progress_path)
	DirAccess.make_dir_recursive_absolute(progress_file.get_base_dir())
	if FileAccess.file_exists(progress_file):
		DirAccess.remove_absolute(progress_file)
	var log_file: String = ProjectSettings.globalize_path(log_path)
	DirAccess.make_dir_recursive_absolute(log_file.get_base_dir())
	command.progress_path = progress_file
	command.user_dir = ProjectSettings.globalize_path("user://")
	var arguments: PackedStringArray = command.arguments(SCENE, from_source(),
		ProjectSettings.globalize_path("res://"), log_file)
	pid = OS.create_process(OS.get_executable_path(), arguments)
	if pid <= 0:
		error = "the import process could not be started (%s)" % OS.get_executable_path()
		pid = -1
		return false
	return true


## Whether the child is still running.
func is_running() -> bool:
	return pid > 0 and not _ended and OS.is_process_running(pid)


## The child's progress so far. When the child has ended without its final
## record, the report is finished and failed, naming the exit code and the log.
func poll() -> ImportProgress:
	var report: ImportProgress = ImportProgress.parse(_read())
	if report.finished or pid <= 0:
		_ended = report.finished
		return report
	if OS.is_process_running(pid):
		return report
	_ended = true
	report = ImportProgress.parse(_read())
	if not report.finished:
		report.finished = true
		report.succeeded = false
		report.problems.append("the import process ended without finishing (exit code %d); its log is %s"
			% [OS.get_process_exit_code(pid), ProjectSettings.globalize_path(log_path)])
	return report


## Stops a running child and removes the folders it left; false when none was running.
func cancel() -> bool:
	if not is_running():
		return false
	OS.kill(pid)
	_ended = true
	clean_up(target_root)
	return true


## Removes the staging folder an interrupted import of [param target] left, and
## puts back an earlier root that was moved aside but not replaced.
static func clean_up(target: String) -> void:
	if target.is_empty():
		return
	remove_tree(target + STAGING_SUFFIX)
	var retired: String = target + RETIRED_SUFFIX
	if not DirAccess.dir_exists_absolute(retired):
		return
	if DirAccess.dir_exists_absolute(target):
		remove_tree(retired)
	else:
		DirAccess.rename_absolute(retired, target)


## Removes the folder [param path] and everything in it; false when something remained.
static func remove_tree(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return true
	var removed: bool = true
	for child: String in DirAccess.get_directories_at(path):
		removed = remove_tree(path.path_join(child)) and removed
	for file_name: String in DirAccess.get_files_at(path):
		removed = DirAccess.remove_absolute(path.path_join(file_name)) == OK and removed
	return DirAccess.remove_absolute(path) == OK and removed


func _read() -> String:
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(progress_path), FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text

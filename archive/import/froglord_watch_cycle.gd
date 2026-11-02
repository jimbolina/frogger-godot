class_name FrogLordWatchCycle
extends RefCounted
## One import of a FrogLord save, or the retail pair, into an overlay that a
## running game can reload.
##
## [method run] imports the resource steps into
## [code]<root_parent>/<key>/[/code], where the key is the first
## [constant KEY_LENGTH] hex digits of [method GameDataSource.fingerprint],
## with [code]res://assets[/code] as the fallback root, writes the overlay's
## [LevelSupportReport] beside it as [constant REPORT_FILE] and, last, the
## [FrogLordPointer]. Earlier key folders are kept, since an open game loads
## maps lazily. Files that are not yet a complete pc-retail-v3.0e pair, or that
## change during the import, give a result to retry.

## The steps run when none are named.
const DEFAULT_STEPS: PackedStringArray = ["names", "tables", "demos", "maps", "catalog"]
## The steps an overlay under [code]user://[/code] may run: their output loads
## without Godot's import.
const ALLOWED_STEPS: PackedStringArray = ["names", "tables", "demos", "maps", "catalog"]
## The folder the overlays and the pointer live in.
const DEFAULT_ROOT_PARENT: String = "user://froglord"
## The root every overlay falls back to.
const FALLBACK_ROOT: String = "res://assets"
## The hex digits of the fingerprint that name an overlay folder.
const KEY_LENGTH: int = 16
## The support report written in the overlay folder.
const REPORT_FILE: String = "support_report.tsv"
## The only build the importer accepts.
const BUILD: String = "pc-retail-v3.0e"


## What one cycle did.
class Result:
	extends RefCounted
	## Why the cycle could not start (no folder, no pair, a bad step list), or "".
	var error: String = ""
	## Why the files could not be imported yet, or ""; the next poll tries again.
	var retry: String = ""
	## The overlay key: the first [constant KEY_LENGTH] hex digits of the fingerprint.
	var fingerprint: String = ""
	## The overlay folder.
	var index_root: String = ""
	## [method ImportedAssets.source_summary] of the overlay.
	var source_summary: String = ""
	## The files the import wrote or rewrote.
	var written: int = 0
	## Problems from the import, the report file, the overlay check or the pointer.
	var problems: PackedStringArray = PackedStringArray()
	## [method LevelSupportReport.summary] of the save.
	var support_summary: String = ""
	## The unmapped rows of the support report, tab-separated.
	var unmapped: PackedStringArray = PackedStringArray()
	## Read problems of the support report.
	var support_problems: PackedStringArray = PackedStringArray()
	## The support report file.
	var report_path: String = ""
	## The overlay folders under the root parent after the cycle.
	var folders: int = 0
	## How long the cycle took.
	var milliseconds: int = 0

	## True when the overlay was imported cleanly and the pointer written.
	func is_ok() -> bool:
		return error.is_empty() and retry.is_empty() and problems.is_empty()

	## One line for the watcher's log.
	func line() -> String:
		var seconds: float = milliseconds / 1000.0
		if not error.is_empty():
			return "froglord: cannot import (%s), %.2f s" % [error, seconds]
		if not retry.is_empty():
			return "froglord: waiting (%s), %.2f s" % [retry, seconds]
		return "froglord: %s (%s) wrote %d files, %d problems, %d unmapped, %.2f s" % [
			source_summary if not source_summary.is_empty() else index_root, fingerprint,
			written, problems.size(), unmapped.size(), seconds]


## The state of the pair the watcher polls in [param data_dir] (FrogLord's
## modded files when present, else the retail ones): each file's name,
## modification time and size, or "" when the folder holds no pair.
static func file_state(data_dir: String) -> String:
	var source: GameDataSource = GameDataLocator.open_directory(data_dir)
	if source == null:
		return ""
	var parts := PackedStringArray()
	for path: String in source.fingerprint_paths():
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		var size: int = file.get_length() if file != null else -1
		parts.append("%s:%d:%d" % [path.get_file(), FileAccess.get_modified_time(path), size])
	return ",".join(parts)


## Imports the pair in [param data_dir] with [param steps] (empty for
## [constant DEFAULT_STEPS]) into an overlay under [param root_parent] and
## points [param pointer_path] at it when the import is clean.
static func run(data_dir: String, steps: PackedStringArray = PackedStringArray(),
		root_parent: String = DEFAULT_ROOT_PARENT, pointer_path: String = FrogLordPointer.DEFAULT_PATH) -> Result:
	var started: int = Time.get_ticks_msec()
	var result := Result.new()
	_import(result, data_dir, steps if not steps.is_empty() else DEFAULT_STEPS, root_parent, pointer_path)
	result.folders = overlay_folders(root_parent).size()
	result.milliseconds = Time.get_ticks_msec() - started
	return result


## The overlay folders under [param root_parent].
static func overlay_folders(root_parent: String) -> PackedStringArray:
	var found := PackedStringArray()
	if not DirAccess.dir_exists_absolute(root_parent):
		return found
	for child: String in DirAccess.get_directories_at(root_parent):
		if child.length() == KEY_LENGTH and child.is_valid_hex_number():
			found.append(child)
	return found


static func _import(result: Result, data_dir: String, steps: PackedStringArray, root_parent: String, pointer_path: String) -> void:
	for step: String in steps:
		if not ALLOWED_STEPS.has(step):
			result.error = "step %s needs Godot's import; a watched overlay runs only %s" % [step, ",".join(ALLOWED_STEPS)]
			return
	if data_dir.is_empty() or not DirAccess.dir_exists_absolute(data_dir):
		result.error = "no folder %s" % data_dir
		return
	var source: GameDataSource = GameDataLocator.open_directory(data_dir)
	if source == null:
		result.error = "%s has neither %s + %s nor %s + %s" % [data_dir,
			FrogLordModSource.EXE_NAME, FrogLordModSource.MWD_NAME, RetailDirSource.EXE_NAME, RetailDirSource.MWD_NAME]
		return
	var library := FrogLordConfigLibrary.new()
	var detection: GameVersionDetector.Result = GameVersionDetector.new(library).detect(source.get_exe_bytes())
	if not detection.is_ok():
		result.retry = "%s: %s" % [source.describe(), detection.error]
		return
	if detection.version.internal_name != BUILD:
		result.retry = "%s is build %s, not %s" % [source.describe(), detection.version.internal_name, BUILD]
		return
	var fingerprint: String = source.fingerprint()
	result.fingerprint = fingerprint.substr(0, KEY_LENGTH)
	result.index_root = root_parent.path_join(result.fingerprint)
	var context := ImportContext.new()
	context.assets_root = result.index_root
	context.fallback_root = FALLBACK_ROOT
	context.data = GameData.open(source, detection.version, library)
	if not context.data.is_valid():
		result.retry = "%s: %s" % [source.describe(), context.data.error]
		context.data.close()
		return
	ImportRun.new().run(context, ImportStep.PHASE_RESOURCES, steps)
	result.written = context.written.size()
	result.problems.append_array(context.problems)
	_report_support(result, context.data)
	context.data.close()
	var after: GameDataSource = GameDataLocator.open_directory(data_dir)
	if after == null or after.fingerprint() != fingerprint:
		result.retry = "the files changed during the import"
		return
	if not result.problems.is_empty():
		return
	var overlay := ImportedAssets.open(FALLBACK_ROOT, "", result.index_root)
	if not overlay.is_valid():
		result.problems.append("the overlay does not open: %s" % overlay.error)
		return
	result.source_summary = overlay.source_summary()
	overlay.close()
	var pointer := FrogLordPointer.new()
	pointer.index_root = result.index_root
	pointer.fingerprint = result.fingerprint
	pointer.source_summary = result.source_summary
	pointer.report_path = result.report_path
	pointer.written_at = int(Time.get_unix_time_from_system())
	var written: Error = pointer.write(pointer_path)
	if written != OK:
		result.problems.append("cannot write %s (%s)" % [pointer_path, error_string(written)])


static func _report_support(result: Result, data: GameData) -> void:
	var report: LevelSupportReport = LevelSupportReport.from_catalog(data)
	result.support_summary = report.summary()
	for row: LevelSupportReport.Row in report.unmapped():
		result.unmapped.append(row.to_tsv())
	result.support_problems = report.problems
	result.report_path = result.index_root.path_join(REPORT_FILE)
	DirAccess.make_dir_recursive_absolute(result.index_root)
	var file: FileAccess = FileAccess.open(result.report_path, FileAccess.WRITE)
	if file == null:
		result.problems.append("cannot write %s" % result.report_path)
		return
	file.store_string("\n".join(report.to_tsv_lines()) + "\n")
	file.close()

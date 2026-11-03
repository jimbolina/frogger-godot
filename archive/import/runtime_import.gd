class_name RuntimeImport
extends AssetImporter
## The importer as the game runs it: one in-process pass of every step in
## [member ImportContext.runtime] mode, with no editor import, and FrogLord
## overlays through [FrogLordWatchCycle].
##
## [method run] writes the root under [code]<target_root>.partial[/code], every
## saved reference and the index naming files under [code]<target_root>[/code],
## and renames the folder to the target only when the run had no problems; an
## earlier root there is moved to [code]<target_root>.old[/code] first and
## removed afterwards. A failed or cancelled run leaves no folder behind.
##
## The steps build nodes for model scenes but never add them to the tree, and
## textures are saved without reading anything back from the RenderingServer.
## Saving meshes and shader materials still queries the RenderingServer, and a
## headless run on a worker thread stalls at the first model whose mesh embeds
## shader materials even while the main loop iterates, so the archive suite
## runs it on the main thread. Do not run it while the game has the same
## target root open, since the new resources take over the paths of loaded
## ones.
##
## [method import_overlay] runs one [FrogLordWatchCycle] over the given base
## root. Its steps save only records (names, tables, demos, maps and the
## index), never meshes or materials, so it may run on a worker thread.

## The suffix of the folder a run writes before it is renamed.
const STAGING_SUFFIX: String = ".partial"
## The suffix an earlier root is moved to while the new one takes its place.
const RETIRED_SUFFIX: String = ".old"
## The hex digits of the source fingerprint that name a root.
const KEY_LENGTH: int = 16
## The relative time each phase and step takes (seconds measured on an M-series
## Mac), for the progress fraction.
const WEIGHTS: Dictionary[String, float] = {
	"raw/textures": 2.0,
	"raw/sfx": 0.1,
	"raw/music": 2.7,
	"resources/names": 0.1,
	"resources/tables": 0.1,
	"resources/textures": 2.6,
	"resources/sfx": 0.1,
	"resources/demos": 0.1,
	"resources/maps": 4.8,
	"resources/models": 3.7,
	"resources/options_models": 0.2,
	"resources/catalog": 0.5,
}
## What each step does, for the progress label.
const LABELS: Dictionary[String, String] = {
	"names": "Reading name lists",
	"tables": "Reading game tables",
	"textures": "Converting textures",
	"sfx": "Converting sound effects",
	"music": "Reading music from the disc",
	"demos": "Reading demos",
	"maps": "Converting maps",
	"models": "Converting models",
	"options_models": "Converting options models",
	"catalog": "Writing the asset index",
}


## A game folder opened and identified.
class Inspected:
	extends RefCounted
	## What detection found.
	var detection := AssetImporter.Detection.new()
	## The files, or null when there are none.
	var source: GameDataSource
	## The detected build, or null.
	var version: GameVersionConfig
	## The FrogLord configurations the build was found in.
	var library: FrogLordConfigLibrary


var _progress: Callable = Callable()
var _total_weight: float = 1.0
var _finished_weight: float = 0.0
var _step_weight: float = 0.0
var _label: String = ""
var _has_disc: bool = false


## FrogLord's configuration files, which name the build's addresses and its
## resources, credited with their MIT licence ([code]LICENSE.md[/code] beside them).
func third_party_notice() -> String:
	var licence: String = FileAccess.get_file_as_string(FrogLordConfigLibrary.DEFAULT_ROOT.path_join("LICENSE.md"))
	return "FrogLord configuration files (build addresses and name lists)\n" \
		+ "https://github.com/Kneesnap/FrogLord\n\n" + licence.strip_edges()


func detect(data_dir: String) -> AssetImporter.Detection:
	return inspect(data_dir).detection


## Opens and identifies the game files in [param data_dir], keeping the open
## source for an import.
static func inspect(data_dir: String) -> Inspected:
	var inspected := Inspected.new()
	var detection: AssetImporter.Detection = inspected.detection
	if data_dir.is_empty() or not DirAccess.dir_exists_absolute(data_dir):
		detection.error = "there is no folder %s" % data_dir
		return inspected
	inspected.source = GameDataLocator.open_directory(data_dir)
	if inspected.source == null:
		detection.error = "%s holds neither %s and %s nor FrogLord's %s and %s" % [data_dir,
			RetailDirSource.EXE_NAME, RetailDirSource.MWD_NAME, FrogLordModSource.EXE_NAME, FrogLordModSource.MWD_NAME]
		return inspected
	detection.fingerprint = inspected.source.fingerprint().substr(0, KEY_LENGTH)
	inspected.library = FrogLordConfigLibrary.new()
	var found: GameVersionDetector.Result = GameVersionDetector.new(inspected.library).detect(inspected.source.get_exe_bytes())
	if not found.is_ok():
		detection.error = "%s is not a known Frogger build: %s" % [inspected.source.describe(), found.error]
		detection.summary = inspected.source.describe()
		return inspected
	inspected.version = found.version
	detection.build = found.version.internal_name
	detection.build_name = found.version.display_name
	detection.summary = "%s (%s), %s, found by %s" % [detection.build_name, detection.build,
		inspected.source.describe(), found.method]
	if detection.build != SUPPORTED_BUILD:
		detection.error = "%s is %s; only %s can be imported" % [inspected.source.describe(), detection.build, SUPPORTED_BUILD]
	return inspected


func detect_froglord(froglord_dir: String) -> AssetImporter.Detection:
	var inspected: Inspected = inspect(froglord_dir)
	var detection: AssetImporter.Detection = inspected.detection
	if inspected.source == null:
		return detection
	detection.files = "%s + %s" % [inspected.source.exe_file_name(), inspected.source.mwd_file_name()]
	if inspected.source is FrogLordModSource:
		detection.froglord = true
		var trailer: FrogLordExeTrailer = (inspected.source as FrogLordModSource).get_trailer()
		if trailer != null and trailer.error.is_empty():
			detection.froglord_version = trailer.froglord_version
	return detection


func source_state(froglord_dir: String) -> String:
	if froglord_dir.is_empty() or not DirAccess.dir_exists_absolute(froglord_dir):
		return ""
	return FrogLordWatchCycle.file_state(froglord_dir)


func import_overlay(froglord_dir: String, base_root: String,
		progress: Callable, cancelled: Callable) -> AssetImporter.OverlayResult:
	var cycle: FrogLordWatchCycle.Result = FrogLordWatchCycle.run(froglord_dir, PackedStringArray(),
		overlay_parent, pointer_path, base_root, progress, cancelled)
	var result := AssetImporter.OverlayResult.new()
	result.error = cycle.error
	result.retry = cycle.retry
	result.key = cycle.fingerprint
	result.index_root = cycle.index_root
	result.fallback_root = cycle.fallback_root
	result.source_state = cycle.source_state
	result.source_summary = cycle.source_summary
	result.problems = cycle.problems
	result.support_summary = cycle.support_summary
	result.unmapped = cycle.unmapped
	result.support_problems = cycle.support_problems
	result.report_path = cycle.report_path
	result.milliseconds = cycle.milliseconds
	return result


func run(data_dir: String, disc_path: String, target_root: String,
		progress: Callable, cancelled: Callable) -> PackedStringArray:
	notes = PackedStringArray()
	var problems := PackedStringArray()
	_progress = progress
	_finished_weight = 0.0
	_step_weight = 0.0
	_total_weight = 0.0
	_has_disc = not disc_path.is_empty()
	for key: String in WEIGHTS:
		_total_weight += _weight(key)
	var target: String = target_root.trim_suffix("/")
	if target.is_empty():
		problems.append("no target folder was given")
		return problems
	var inspected: Inspected = inspect(data_dir)
	if not inspected.detection.is_ok():
		problems.append(inspected.detection.error)
		return problems
	var staging: String = target + STAGING_SUFFIX
	remove_tree(staging)
	var context := ImportContext.new()
	context.runtime = true
	context.assets_root = staging
	context.published_root = target
	context.disc = disc_path
	context.cancelled = cancelled
	context.on_progress = _on_progress
	context.data = GameData.open(inspected.source, inspected.version, inspected.library)
	if not context.data.is_valid():
		problems.append(context.data.error)
		context.data.close()
		return problems
	var steps := ImportRun.new()
	steps.on_step = _on_step
	steps.run(context, ImportStep.PHASE_RAW)
	if context.problems.is_empty():
		steps.run(context, ImportStep.PHASE_RESOURCES)
	context.data.close()
	problems.append_array(context.problems)
	notes.append_array(context.notes)
	if problems.is_empty() and not FileAccess.file_exists(context.catalog_path()):
		problems.append("the import wrote no index at %s" % context.catalog_path())
	if problems.is_empty():
		_publish(staging, target, problems)
	if not problems.is_empty():
		remove_tree(staging)
		return problems
	_report(1.0, "Done")
	return problems


## Removes the folder [param path] and everything in it; returns false when
## something could not be removed.
static func remove_tree(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return true
	var removed: bool = true
	for child: String in DirAccess.get_directories_at(path):
		removed = remove_tree(path.path_join(child)) and removed
	for file_name: String in DirAccess.get_files_at(path):
		removed = DirAccess.remove_absolute(path.path_join(file_name)) == OK and removed
	return DirAccess.remove_absolute(path) == OK and removed


func _publish(staging: String, target: String, problems: PackedStringArray) -> void:
	var retired: String = target + RETIRED_SUFFIX
	remove_tree(retired)
	if DirAccess.dir_exists_absolute(target):
		var moved: Error = DirAccess.rename_absolute(target, retired)
		if moved != OK:
			problems.append("cannot move the earlier import %s aside (%s)" % [target, error_string(moved)])
			return
	var renamed: Error = DirAccess.rename_absolute(staging, target)
	if renamed != OK:
		problems.append("cannot rename %s to %s (%s)" % [staging, target, error_string(renamed)])
		if DirAccess.dir_exists_absolute(retired):
			DirAccess.rename_absolute(retired, target)
		return
	if not remove_tree(retired):
		notes.append("the earlier import %s could not be removed entirely" % retired)


func _on_step(step_name: String, phase: String) -> void:
	_finished_weight += _step_weight
	_step_weight = _weight("%s/%s" % [phase, step_name])
	_label = LABELS[step_name] if LABELS.has(step_name) else step_name
	_report(_finished_weight / _total_weight, _label)


func _weight(key: String) -> float:
	if not WEIGHTS.has(key) or (key == "raw/music" and not _has_disc):
		return 0.0
	return WEIGHTS[key]


func _on_progress(done: int, total: int) -> void:
	if total <= 0:
		return
	_report((_finished_weight + _step_weight * done / float(total)) / _total_weight, _label)


func _report(fraction: float, label: String) -> void:
	if _progress.is_valid():
		_progress.call(clampf(fraction, 0.0, 1.0), label)

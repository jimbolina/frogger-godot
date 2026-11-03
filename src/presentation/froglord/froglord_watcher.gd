class_name FrogLordWatcher
extends Node
## Watches FrogLord's save folder while the game runs, when FrogLord is on in
## the setup, and imports each finished save as an overlay over the base root.
##
## There is one watcher per process, a child of the tree's root started by
## [method follow] from the front end and the game scene, so it lives across
## their scene changes for the whole session, as [FrontEndSession]'s state
## does, and an import keeps running while the player moves between the menu
## and a level. It is not an autoload, so the setup screen, the viewers, the
## import child and the test runs never watch anything.
##
## Every [constant INTERVAL] seconds it reads the folder's
## [method AssetImporter.source_state] and feeds it to a [FrogLordWatch]. When
## that asks for an import, [method AssetImporter.import_overlay] runs on a
## worker thread (its steps save no meshes or materials) into
## [method AssetImporter.overlay_parent_for] the base root and rewrites the
## [FrogLordPointer], which a level following FrogLord reloads from. What the
## watch says is printed (not pushed as an engine warning) and shown in a
## [FrogLordNotice] that never blocks play: a missing folder, a folder without a save, an import, its unmapped
## rows and its problems.

## Seconds between polls of the save folder.
const INTERVAL: float = 1.0

static var _current: FrogLordWatcher = null

## The watch's state.
var watch: FrogLordWatch = FrogLordWatch.new()
## The importer, made through [AssetImporterFactory] on first use unless set.
var importer: AssetImporter = null
## The pointer file a clean import rewrites.
var pointer_path: String = FrogLordPointer.DEFAULT_PATH
## Whether imports run on a worker thread; false runs them inside [method poll].
var threaded: bool = true
## Whether a [Timer] calls [method poll]; tests call it themselves.
var polls_on_timer: bool = true
## The result of the last finished import, or null.
var last_result: AssetImporter.OverlayResult = null
## The progress label the running import last reported, or "".
var progress_label: String = ""

var _thread: Thread = null
var _cancelled: bool = false
var _stopped: bool = false
var _notice: FrogLordNotice = null
var _shown_revision: int = 0


## Keeps the process's watcher in step with [param launcher] over
## [param base_root]: starts one under [param tree]'s root when FrogLord is on,
## keeps a running one that watches the same folder over the same root,
## replaces one that does not and stops it when FrogLord is off. Returns the
## watcher, or null when none runs.
static func follow(tree: SceneTree, launcher: LauncherSettings, base_root: String) -> FrogLordWatcher:
	var enabled: bool = launcher != null and launcher.froglord_enabled and not base_root.is_empty()
	if _current != null and is_instance_valid(_current):
		if enabled and _current.watch.folder == launcher.froglord_dir and _current.watch.base_root == base_root:
			return _current
		_current.shut_down()
	_current = null
	if not enabled:
		return null
	var watcher := FrogLordWatcher.new()
	watcher.name = "FrogLordWatcher"
	watcher.configure(launcher.froglord_dir, base_root)
	tree.root.add_child.call_deferred(watcher)
	_current = watcher
	return watcher


## The running watcher, or null.
static func current() -> FrogLordWatcher:
	return _current if _current != null and is_instance_valid(_current) else null


## Watches [param save_folder] over [param base_root], taking an overlay the
## pointer already names for those files as imported.
func configure(save_folder: String, base_root: String) -> void:
	watch = FrogLordWatch.create(true, save_folder, base_root, FrogLordPointer.read(pointer_path))


func _ready() -> void:
	if _stopped:
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_notice = FrogLordNotice.new()
	add_child(_notice)
	if polls_on_timer:
		var timer := Timer.new()
		timer.wait_time = INTERVAL
		timer.autostart = true
		timer.timeout.connect(poll)
		add_child(timer)
	_present()
	poll()


func _process(_delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		_collect()


func _exit_tree() -> void:
	_join()
	if _current == self:
		_current = null


## Takes one poll of the save folder; returns true when it started an import.
func poll() -> bool:
	if _stopped:
		return false
	if _thread != null:
		if not _thread.is_alive():
			_collect()
		return false
	var exists: bool = not watch.folder.is_empty() and DirAccess.dir_exists_absolute(watch.folder)
	var state: String = _importer().source_state(watch.folder) if exists else ""
	var start: bool = watch.poll(exists, state)
	_present()
	if start:
		_start_import()
	return start


## True while an import runs on the worker thread.
func is_importing() -> bool:
	return _thread != null


## Stops watching: cancels a running import, waits for it and frees the node,
## or frees it as soon as it enters the tree when it has not yet.
func shut_down() -> void:
	_stopped = true
	watch.stop()
	_join()
	if _current == self:
		_current = null
	if is_inside_tree():
		queue_free()


## The notice the watcher shows, or null before it enters the tree.
func notice() -> FrogLordNotice:
	return _notice


func _importer() -> AssetImporter:
	if importer == null:
		importer = AssetImporterFactory.create()
	return importer


func _start_import() -> void:
	var chosen: AssetImporter = _importer()
	chosen.overlay_parent = AssetImporter.overlay_parent_for(watch.base_root)
	chosen.pointer_path = pointer_path
	_cancelled = false
	progress_label = ""
	if not threaded:
		_finish(chosen.import_overlay(watch.folder, watch.base_root, Callable(), _is_cancelled))
		return
	_thread = Thread.new()
	var started: Error = _thread.start(_import_on_thread.bind(chosen, watch.folder, watch.base_root))
	if started != OK:
		_thread = null
		var failed := AssetImporter.OverlayResult.new()
		failed.error = "cannot start the import thread (%s)" % error_string(started)
		_finish(failed)


func _import_on_thread(chosen: AssetImporter, save_folder: String, base_root: String) -> AssetImporter.OverlayResult:
	return chosen.import_overlay(save_folder, base_root, _on_thread_progress, _is_cancelled)


func _on_thread_progress(_fraction: float, label: String) -> void:
	_set_progress.call_deferred(label)


func _set_progress(label: String) -> void:
	progress_label = label


func _is_cancelled() -> bool:
	return _cancelled


func _collect() -> void:
	var outcome: Variant = _thread.wait_to_finish()
	_thread = null
	var result: AssetImporter.OverlayResult = null
	if outcome is AssetImporter.OverlayResult:
		result = outcome
	if result == null:
		result = AssetImporter.OverlayResult.new()
		result.error = "the import thread returned nothing"
	_finish(result)


func _join() -> void:
	if _thread == null:
		return
	_cancelled = true
	_thread.wait_to_finish()
	_thread = null


func _finish(result: AssetImporter.OverlayResult) -> void:
	last_result = result
	watch.finish(result)
	if result.is_ok():
		print("froglord: imported %s into %s over %s in %.2f s; support %s" % [result.source_summary, result.index_root,
			result.fallback_root, result.milliseconds / 1000.0, result.support_summary])
	for row: String in result.unmapped:
		print("froglord: unmapped %s" % row)
	for problem: String in result.support_problems:
		print("froglord: support problem %s" % problem)
	for problem: String in result.problems:
		print("froglord: problem %s" % problem)
	_present()


func _present() -> void:
	if watch.revision == _shown_revision:
		return
	_shown_revision = watch.revision
	if watch.message.is_empty():
		return
	print(watch.message)
	if _notice != null:
		_notice.show_text(watch.message, watch.warning)

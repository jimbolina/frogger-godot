extends GutTest
## The reload watcher signals once for each rewrite of the pointer file and
## never for the state it found when it entered the tree.

const FOLDER: String = "user://asset_reload_watcher_test"
const PATH: String = FOLDER + "/current.cfg"

var _watcher: AssetReloadWatcher


func before_each() -> void:
	_remove(FOLDER)
	_watcher = AssetReloadWatcher.new()
	_watcher.pointer_path = PATH
	add_child_autofree(_watcher)
	watch_signals(_watcher)


func after_all() -> void:
	_remove(FOLDER)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func _write(key: String) -> void:
	var pointer := FrogLordPointer.new()
	pointer.index_root = "user://froglord/" + key
	pointer.fingerprint = key
	assert_eq(pointer.write(PATH), OK)


func test_the_timer_polls_every_second() -> void:
	var timer: Timer = _watcher.get_child(0) as Timer
	assert_not_null(timer)
	assert_eq(timer.wait_time, 1.0)
	assert_false(timer.is_stopped())


func test_no_signal_before_a_change() -> void:
	assert_false(_watcher.poll())
	assert_false(_watcher.poll())
	assert_signal_emit_count(_watcher, "pointer_changed", 0)


func test_each_rewrite_signals_once() -> void:
	_write("0123456789abcdef")
	assert_true(_watcher.poll())
	assert_false(_watcher.poll())
	assert_signal_emit_count(_watcher, "pointer_changed", 1)
	_write("fedcba9876543210")
	assert_true(_watcher.poll())
	assert_false(_watcher.poll())
	assert_signal_emit_count(_watcher, "pointer_changed", 2)


func test_the_state_found_on_entering_is_not_a_change() -> void:
	_write("0123456789abcdef")
	var late := AssetReloadWatcher.new()
	late.pointer_path = PATH
	add_child_autofree(late)
	watch_signals(late)
	assert_false(late.poll())
	assert_signal_emit_count(late, "pointer_changed", 0)

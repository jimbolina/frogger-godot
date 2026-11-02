class_name AssetReloadWatcher
extends Node
## Watches the [FrogLordPointer] file and emits [signal pointer_changed] when
## the FrogLord watcher rewrites it.
##
## Entering the tree records the file's state and starts a one-second
## [Timer] that calls [method poll]. The state is the file's modification
## time and contents, so two writes within one second still differ.

## Emitted once for each change of the pointer file after the first poll.
signal pointer_changed

## Seconds between polls.
const INTERVAL: float = 1.0

## The pointer file watched.
var pointer_path: String = FrogLordPointer.DEFAULT_PATH

var _timer: Timer
var _last_state: String = ""
var _polled: bool = false


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = INTERVAL
	_timer.autostart = true
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)
	poll()


## Reads the pointer file's state and emits [signal pointer_changed] when it
## differs from the previous poll's; the first poll only records it. Returns
## true when it emitted.
func poll() -> bool:
	var state: String = _state()
	var changed: bool = _polled and state != _last_state
	_polled = true
	_last_state = state
	if changed:
		pointer_changed.emit()
	return changed


func _on_timeout() -> void:
	poll()


func _state() -> String:
	var modified: int = FrogLordPointer.modified_time(pointer_path)
	if modified == 0:
		return ""
	return "%d\n%s" % [modified, FileAccess.get_file_as_string(pointer_path)]

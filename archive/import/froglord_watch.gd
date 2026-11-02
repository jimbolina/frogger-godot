extends SceneTree
## Re-imports a FrogLord save into an overlay whenever FrogLord saves it, for
## a game launched with [code]--froglord[/code] to reload.
##
##   godot --headless --path . -s res://archive/import/froglord_watch.gd -- \
##       --data-dir=<folder> [--steps=names,tables,demos,maps,catalog] [--once] \
##       [--interval=1.0]
##
## [code]archive/import/froglord_watch.sh[/code] runs it. Each cycle is a
## [FrogLordWatchCycle] into [code]user://froglord/<key>/[/code], which ends by
## rewriting [constant FrogLordPointer.DEFAULT_PATH]. The watcher imports once
## at start, then polls the modification times and sizes of the pair's files
## every interval; a change that has stayed the same for one more interval
## starts a cycle, and a cycle that finds the files unfinished is tried again
## on the next poll. [code]--once[/code] runs one cycle and exits 1 when it was
## not clean. A missing folder or a bad option exits 2.

var _data_dir: String = ""
var _steps := PackedStringArray()
var _interval: float = 1.0
var _last_wait: String = ""


func _initialize() -> void:
	var options: Dictionary[String, String] = _parse(OS.get_cmdline_user_args())
	_data_dir = _option(options, "data-dir")
	_steps = _option(options, "steps").split(",", false)
	var interval: String = _option(options, "interval")
	if not interval.is_empty():
		if not interval.is_valid_float() or interval.to_float() <= 0.0:
			printerr("froglord: --interval must be a positive number of seconds")
			quit(2)
			return
		_interval = interval.to_float()
	if _data_dir.is_empty():
		printerr("froglord: pass --data-dir=<folder> or set FROGGER_DATA_DIR")
		quit(2)
		return
	if options.has("once"):
		_once.call_deferred()
	else:
		_watch.call_deferred()


func _once() -> void:
	var result: FrogLordWatchCycle.Result = _cycle()
	if not result.error.is_empty():
		quit(2)
		return
	quit(0 if result.is_ok() else 1)


func _watch() -> void:
	print("froglord: watching %s every %.1f s; Ctrl+C stops" % [_data_dir, _interval])
	var previous: String = FrogLordWatchCycle.file_state(_data_dir)
	var handled: String = ""
	var first: FrogLordWatchCycle.Result = _cycle()
	if not first.error.is_empty():
		quit(2)
		return
	if first.retry.is_empty():
		handled = previous
	while true:
		await create_timer(_interval).timeout
		if not DirAccess.dir_exists_absolute(_data_dir):
			printerr("froglord: the folder %s is gone" % _data_dir)
			quit(2)
			return
		var state: String = FrogLordWatchCycle.file_state(_data_dir)
		if state.is_empty():
			_say_waiting("no complete pair in %s" % _data_dir)
		elif state != handled and state == previous:
			var result: FrogLordWatchCycle.Result = _cycle()
			if not result.error.is_empty():
				quit(2)
				return
			if result.retry.is_empty():
				handled = state
		previous = state


func _cycle() -> FrogLordWatchCycle.Result:
	var result: FrogLordWatchCycle.Result = FrogLordWatchCycle.run(_data_dir, _steps)
	if not result.retry.is_empty():
		_say_waiting(result.retry)
		return result
	_last_wait = ""
	if not result.error.is_empty():
		printerr(result.line())
		return result
	print("froglord: support %s" % result.support_summary)
	for row: String in result.unmapped:
		print("froglord: unmapped %s" % row)
	for problem: String in result.support_problems:
		print("froglord: support problem %s" % problem)
	for problem: String in result.problems:
		printerr("froglord: problem %s" % problem)
	print("froglord: support report %s" % result.report_path)
	print(result.line())
	print("froglord: %d overlay folders in %s" % [result.folders, FrogLordWatchCycle.DEFAULT_ROOT_PARENT])
	return result


func _say_waiting(reason: String) -> void:
	if reason == _last_wait:
		return
	_last_wait = reason
	print("froglord: waiting (%s)" % reason)


func _option(options: Dictionary[String, String], key: String) -> String:
	return options[key] if options.has(key) else ""


func _parse(arguments: PackedStringArray) -> Dictionary[String, String]:
	var options: Dictionary[String, String] = {}
	for argument: String in arguments:
		if not argument.begins_with("--"):
			continue
		var body: String = argument.substr(2)
		var split: int = body.find("=")
		if split < 0:
			options[body] = ""
		else:
			options[body.substr(0, split)] = body.substr(split + 1)
	return options

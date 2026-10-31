extends SceneTree
## Headless path inspection through the same rule API used by the viewer.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var scenario_file: String = ViewerArguments.value(arguments, "--scenario-file=")
	var selected: String = ViewerArguments.value(arguments, "--scenario=")
	var scenario: PathScenario = PathScenario.from_file(scenario_file) if not scenario_file.is_empty() else PathScenario.builtin(selected if not selected.is_empty() else "line")
	if not scenario.error.is_empty():
		_fail(scenario.error)
		return
	var limit_text: String = ViewerArguments.value(arguments, "--tick-limit=")
	if not limit_text.is_empty():
		if not limit_text.is_valid_int() or limit_text.to_int() < 0 or limit_text.to_int() > 100000:
			_fail("Path tick limit must be in 0..100000")
			return
		scenario.tick_limit = limit_text.to_int()
	var level_code: String = ViewerArguments.value(arguments, "--level=")
	var path_index_text: String = ViewerArguments.value(arguments, "--path-index=")
	if not level_code.is_empty():
		if not path_index_text.is_valid_int() or path_index_text.to_int() < 0:
			_fail("A level path requires --path-index=0 or greater")
			return
		var found: GameDataLocator.Located = ViewerArguments.locate_data(arguments)
		if not found.is_ok():
			_fail(found.error)
			return
		var data: AssetCatalog = GameData.open(found.source, found.version)
		if not data.is_valid():
			_fail(data.error)
			return
		var attach_error: String = scenario.attach_data(data, level_code, path_index_text.to_int())
		data.close()
		if not attach_error.is_empty():
			_fail(attach_error)
			return
	elif not path_index_text.is_empty():
		_fail("--path-index requires --level")
		return
	var run: PathRunner = PathRunner.create(scenario.definition, scenario.start)
	if not run.error.is_empty():
		_fail(run.error)
		return
	var trace := PathTrace.new()
	trace.configure(scenario)
	trace.append_snapshot(run.snapshot())
	for tick: int in scenario.tick_limit:
		var issue: String = run.step(tick)
		if not issue.is_empty():
			_fail("Path tick %d: %s" % [tick, issue])
			return
		trace.append_snapshot(run.snapshot())
	var output: String = ViewerArguments.value(arguments, "--trace-jsonl=")
	if not output.is_empty():
		var save_error: String = trace.save(output)
		if not save_error.is_empty():
			_fail(save_error)
			return
	print("path_scenario: %s, %d ticks, next tick %d" % [scenario.name, scenario.tick_limit, run.snapshot().tick_index])
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

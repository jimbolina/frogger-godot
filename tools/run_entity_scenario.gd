extends SceneTree
## Headless attached-entity inspection through the same game rule API as the viewer.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var selected: String = ViewerArguments.value(arguments, "--scenario=")
	var scenario: EntityScenario = EntityScenario.builtin(selected if not selected.is_empty() else "shared-path")
	if not scenario.error.is_empty():
		_fail(scenario.error)
		return
	var limit_text: String = ViewerArguments.value(arguments, "--tick-limit=")
	if not limit_text.is_empty():
		if not limit_text.is_valid_int() or limit_text.to_int() < 0 or limit_text.to_int() > 100000:
			_fail("Entity tick limit must be in 0..100000")
			return
		scenario.tick_limit = limit_text.to_int()
	var level_code: String = ViewerArguments.value(arguments, "--level=")
	if not level_code.is_empty():
		var found: GameDataLocator.Located = ViewerArguments.locate_data(arguments)
		if not found.is_ok():
			_fail(found.error)
			return
		var data: AssetCatalog = GameData.open(found.source, found.version)
		if not data.is_valid():
			_fail(data.error)
			data.close()
			return
		var attach_issue: String = scenario.attach_data(data, level_code)
		data.close()
		if not attach_issue.is_empty():
			_fail(attach_issue)
			return
	var run: EntityRun = EntityRun.create(scenario.definitions)
	if not run.error.is_empty():
		_fail(run.error)
		return
	var trace := EntityTrace.new()
	trace.configure(scenario)
	trace.append_snapshot(run.snapshot())
	for tick: int in scenario.tick_limit:
		var issue: String = run.step(tick)
		if not issue.is_empty():
			_fail("Entity tick %d: %s" % [tick, issue])
			return
		trace.append_snapshot(run.snapshot())
	var output: String = ViewerArguments.value(arguments, "--trace-jsonl=")
	if not output.is_empty():
		var save_issue: String = trace.save(output)
		if not save_issue.is_empty():
			_fail(save_issue)
			return
	print("entity_scenario: %s, %d ticks, next tick %d" % [scenario.name, scenario.tick_limit, run.snapshot().tick_index])
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

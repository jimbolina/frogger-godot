extends SceneTree
## Headless single-step scenario driver using exactly the presentation rule API.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var filename: String = ViewerArguments.value(arguments, "--scenario-file=")
	var identifier: String = ViewerArguments.value(arguments, "--scenario=")
	var scenario: TerrainScenario = TerrainScenario.from_file(filename) if not filename.is_empty() else TerrainScenario.builtin(identifier if not identifier.is_empty() else "normal")
	if scenario.error.is_empty():
		scenario.error = TerrainScenarioArguments.apply(scenario, arguments)
	if not scenario.error.is_empty():
		_fail(scenario.error)
		return
	var data: AssetCatalog = null
	if ViewerArguments.uses_assets(arguments):
		data = ImportedAssets.open()
		if not data.is_valid():
			_fail(data.error)
			return
		var setup_error: String = scenario.attach_data(data, ViewerArguments.value(arguments, "--level="))
		if not setup_error.is_empty():
			data.close()
			_fail(setup_error)
			return
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	if data != null:
		data.close()
	if not run.error.is_empty():
		_fail(run.error)
		return
	var trace := TerrainTrace.new()
	trace.configure(scenario)
	var full_output: String = ViewerArguments.value(arguments, "--trace-jsonl=")
	if not full_output.is_empty():
		var issue: String = trace.stream_full(full_output)
		if not issue.is_empty():
			_fail(issue)
			return
	for tick: int in scenario.tick_limit:
		var command: TickCommand = scenario.command_at(tick)
		var result: TickResult = run.step(command)
		if not result.error.is_empty():
			_fail("Tick %d: %s" % [tick, result.error])
			return
		trace.append_result(scenario.scenario_index, command, result)
		if run.snapshot().completed:
			break
	var output: String = ViewerArguments.value(arguments, "--trace-csv=")
	if not output.is_empty():
		var failure: String = trace.save(output)
		if not failure.is_empty():
			_fail(failure)
			return
	if not full_output.is_empty():
		var failure: String = trace.save_full(full_output)
		if not failure.is_empty():
			_fail(failure)
			return
	print("terrain_scenario: %s, %d ticks, next tick %d" % [scenario.identifier, scenario.tick_limit, run.snapshot().tick_index])
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

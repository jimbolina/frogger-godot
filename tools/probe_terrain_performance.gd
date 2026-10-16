extends SceneTree
## Measures live terrain frame pacing and separates simulation from repeated drawing.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var found: GameDataLocator.Located = ViewerArguments.locate_data(arguments)
	if not found.is_ok():
		push_error(found.error)
		quit(1)
		return
	var data: GameData = GameData.open(found.source, found.version)
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	var issue: String = scenario.apply_arguments(arguments)
	if not issue.is_empty():
		push_error(issue)
		data.close()
		quit(1)
		return
	scenario.level_code = "ORG1"
	var viewer := TerrainViewer.new()
	viewer.auto_open = false
	root.add_child(viewer)
	await process_frame
	viewer.set_process(false)
	viewer.configure_input(arguments)
	issue = viewer.open_scenario(scenario)
	if issue.is_empty():
		issue = viewer.open_data(data, true)
	if not issue.is_empty():
		push_error(issue)
		quit(1)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var start: int = Time.get_ticks_usec()
	for tick: int in 90:
		var command := TickCommand.new()
		command.tick_index = tick
		var result: TickResult = viewer.run.step(command, false)
		if not result.error.is_empty():
			push_error(result.error)
			quit(1)
			return
	var simulation_us: float = (Time.get_ticks_usec() - start) / 90.0
	start = Time.get_ticks_usec()
	for unused: int in 90:
		viewer.draw_state(1.0)
	var draw_us: float = (Time.get_ticks_usec() - start) / 90.0
	issue = viewer.reset_scenario()
	if not issue.is_empty():
		push_error(issue)
		quit(1)
		return
	# Use the frozen normal-hop commands on the real host frame clock.
	# Trace recording stays off, as in the user's interactive demo.
	for tick: int in [0, 12, 34, 46]:
		var command := TickCommand.new()
		command.tick_index = tick
		command.pressed_mask = TickCommand.NORTH if tick < 34 else TickCommand.SOUTH
		command.held_mask = command.pressed_mask
		viewer.scenario.commands[tick] = command
	viewer.scenario.tick_limit = 730
	viewer.replay_commands = true
	viewer.playing = true
	viewer.set_process(true)
	start = Time.get_ticks_usec()
	var frames: int = 0
	while Time.get_ticks_usec() - start < 8000000:
		await process_frame
		frames += 1
	viewer.set_process(false)
	var seconds: float = (Time.get_ticks_usec() - start) / 1000000.0
	var ticks: int = viewer.run.snapshot().tick_index
	var returned: bool = ticks >= 52 and viewer._current.current_entity_index == -1 and viewer._current.cell == Vector2i(10, 7) and not bool(viewer._current.flags & 8)
	if not returned and viewer.last_error.is_empty():
		viewer.last_error = "Round trip did not return alive to the bank"
	print(JSON.stringify({"simulation_us_per_tick": simulation_us, "draw_us_per_call": draw_us, "wall_seconds": seconds, "frames": frames, "fps": frames / seconds, "ticks": ticks, "ticks_per_second": ticks / seconds, "returned_alive": returned, "error": viewer.last_error}))
	quit(0 if viewer.last_error.is_empty() else 1)

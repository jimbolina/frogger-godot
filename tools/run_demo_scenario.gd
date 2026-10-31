extends SceneTree
## Isolated demo driver through existing admission, gameplay host and playback ownership.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var output: String = ViewerArguments.value(args, "--output-directory=")
	var level_code: String = ViewerArguments.value(args, "--level=")
	var map_index: int = FroggerIds.level_from_code(level_code)
	var trace := DemoTrace.new()
	var session := DemoPlaybackSession.new()
	var provenance: Dictionary = {"schema": "demo-playback-v1", "level": level_code,
		"map": map_index, "detail": "high", "call_numbering": "local committed logic ticks from zero",
		"reference_validation": "not performed", "gameplay_completion": "not established"}
	var issue: String = ""
	var visual_data: AssetCatalog
	var viewer: TerrainViewer
	var scenario: TerrainScenario
	var demo: SourceDemoFile
	var fixture: String = ViewerArguments.value(args, "--scenario-file=")
	if not fixture.is_empty():
		scenario = TerrainScenario.from_file(fixture)
		if scenario.error.is_empty():
			map_index = scenario.level.map_index
			provenance["map"] = map_index
			provenance["level"] = "synthetic"
		issue = scenario.error
		var demo_path: String = ViewerArguments.value(args, "--demo-file=")
		demo = _synthetic_demo(demo_path)
		if issue.is_empty():
			issue = demo.error
		provenance["source"] = "external synthetic fixture"
	else:
		var data: AssetCatalog = ImportedAssets.open()
		issue = data.error
		if issue.is_empty():
			var setup: DemoSetup = DemoSetup.resolve(data, map_index)
			issue = setup.error
			demo = setup.demo
			provenance.merge({"build": data.version_name, "demo_resource_id": setup.resource_id,
				"demo_resource_name": setup.resource_name})
			if issue.is_empty():
				scenario = TerrainScenario.builtin("normal")
				if data.is_playable_level(map_index):
					scenario.options.reactions = ScenarioOptions.Reaction.PLATFORMS
					scenario.options.lifecycle = ScenarioOptions.Lifecycle.VISIBILITY
				issue = scenario.attach_data(data, level_code)
				if issue.is_empty():
					trace.configure(data, scenario.map_scene)
					if not data.is_playable_level(map_index) and not scenario.map_scene.map.zones.is_empty():
						issue = "Demo requires unsupported retail camera-zone admission"
					elif not data.is_playable_level(map_index) and not scenario.map_scene.map.entities.is_empty():
						issue = "Demo requires complete entity/checkpoint admission for " + level_code
		if ViewerArguments.has_flag(args, "--viewer") and issue.is_empty():
			visual_data = data
		else:
			data.close()
	if demo != null and demo.error.is_empty():
		provenance.merge({"duration": demo.duration, "start_grid": [demo.start_grid_x, demo.start_grid_z],
			"input_bytes": demo.input_bytes.size(), "initialization": "demo start cell, FAST_RESET, 30-tick start timer"})
		session.configure(demo.duration, demo.input_bytes, -1 if scenario != null and scenario.level.flow_enabled else 30)
	if issue.is_empty():
		scenario.level.demo_playback = true
		scenario.initial = DemoSetup.start_for(demo)
		var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
		if ViewerArguments.has_flag(args, "--viewer") and run.error.is_empty():
			viewer = TerrainViewer.new()
			viewer.auto_open = false
			root.add_child(viewer)
			viewer.set_process(false)
			issue = viewer.open_scenario(scenario)
			if issue.is_empty() and visual_data != null:
				issue = viewer.open_data(visual_data)
			if issue.is_empty():
				scenario.level.demo_playback = true
				scenario.initial = DemoSetup.start_for(demo)
				issue = viewer.reset_scenario()
			run = viewer.run
		if issue.is_empty():
			issue = run.error
		var host := GameplayHost.new()
		host.open(run)
		var limit_text: String = ViewerArguments.value(args, "--tick-limit=")
		var limit: int = demo.duration if limit_text.is_empty() else limit_text.to_int()
		var rate: String = ViewerArguments.value(args, "--render-rate=")
		var frame: int = 0
		while issue.is_empty() and session.status not in ["complete", "incomplete"] and session.elapsed_ticks < limit:
			var selected_rate: int = rate.to_int()
			if rate == "irregular":
				var rates: PackedInt32Array = PackedInt32Array([30, 144, 60, 90])
				selected_rate = rates[frame % 4]
			var delta: float = 1.0 / float(selected_rate)
			frame += 1
			if viewer != null:
				await process_frame
			host.begin_frame(delta)
			if not host.advance(delta, true):
				continue
			host.consume_period()
			var command: TickCommand = session.command(session.elapsed_ticks)
			var result: TickResult = host.step(command, false) if viewer == null else viewer.step_command(command, false)
			issue = session.accept(result)
			if issue.is_empty():
				trace.append(result.final_snapshot, result.consumed_demo_byte, map_index, result)
				if not scenario.level.flow_enabled and (result.final_snapshot.frog.death_count > 0 or result.final_snapshot.completed):
					issue = "Demo requires unsupported death/reset level flow"
				elif not scenario.level.flow_enabled and result.final_snapshot.frog.mode in [FrogMode.HIT_CHECKPOINT, FrogMode.CHECKPOINT_COLLECTED]:
					issue = "Demo requires unsupported checkpoint level flow"
		host.close()
		if viewer != null:
			await process_frame
			await RenderingServer.frame_post_draw
			var capture_issue: String = ViewerCapture.save_image(root.get_texture().get_image(), output.path_join("demo.png"))
			if issue.is_empty():
				issue = capture_issue
			viewer.open_data(null)
			viewer.queue_free()
		if visual_data != null:
			visual_data.close()
		if issue.is_empty() and session.status != "complete":
			issue = "tick limit reached"
	if not issue.is_empty():
		session.stop(issue)
	provenance.merge({"status": session.status, "reason": session.reason,
		"elapsed_ticks": session.elapsed_ticks, "consumed_inputs": session.input_cursor,
		"unsupported_capabilities": [session.reason] if session.status == "incomplete" and session.reason != "tick limit reached" else []})
	var save_issue: String = trace.save(output, provenance)
	if not save_issue.is_empty():
		push_error(save_issue)
		quit(1)
		return
	print("demo playback: %s; %s; %d ticks, %d inputs" % [session.status, session.reason, session.elapsed_ticks, session.input_cursor])
	quit(0)

## Decodes a synthetic demo fixture: three little-endian signed integers
## (duration, start X, start Z), then the action bytes.
static func _synthetic_demo(path: String) -> SourceDemoFile:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var demo := SourceDemoFile.new()
	if bytes.size() < 12:
		demo.error = "%s: demo header needs 12 bytes, found %d" % [path, bytes.size()]
		return demo
	demo.duration = bytes.decode_s32(0)
	demo.start_grid_x = bytes.decode_s32(4)
	demo.start_grid_z = bytes.decode_s32(8)
	if demo.duration < 0 or demo.start_grid_x < 0 or demo.start_grid_z < 0:
		demo.error = "%s: negative demo duration or starting grid coordinate" % path
		return demo
	demo.input_bytes = bytes.slice(12)
	return demo

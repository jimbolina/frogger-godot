extends SceneTree
## Measures complete ORG1 routes on the real host clock; never synthesizes frame deltas.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var requested: PackedStringArray = ViewerArguments.value(arguments, "--performance-size=").split("x")
	if requested.size() == 2:
		root.size = Vector2i(requested[0].to_int(), requested[1].to_int())
		root.position = Vector2i.ZERO
	if ViewerArguments.value(arguments, "--window-mode=") == "exclusive":
		root.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	var output: String = ViewerArguments.value(arguments, "--performance-output=")
	var issue: String = ViewerCapture.prepare_folder(output.get_base_dir())
	if not issue.is_empty():
		_fail(issue)
		return
	var found: GameDataLocator.Located = ViewerArguments.locate_data(arguments)
	if not found.is_ok():
		_fail(found.error)
		return
	var started: int = Time.get_ticks_usec()
	var data: GameData = GameData.open(found.source, found.version)
	var scenario: TerrainScenario = TerrainScenario.from_file(ViewerArguments.value(arguments, "--scenario-file="))
	issue = scenario.error
	if issue.is_empty():
		issue = TerrainScenarioArguments.apply(scenario, arguments)
	scenario.level_code = "ORG1"
	if not issue.is_empty():
		data.close()
		_fail(issue)
		return
	var viewer := TerrainViewer.new()
	viewer.auto_open = false
	root.add_child(viewer)
	viewer.set_process(false)
	viewer.configure_input(arguments)
	issue = viewer.open_scenario(scenario)
	if issue.is_empty():
		issue = viewer.open_data(data, true)
	if not issue.is_empty():
		_fail(issue)
		return
	if scenario.map_scene == null or scenario.level.tick_guard == null or viewer._current.entities == null:
		_fail("Performance measurement requires the guarded retail ORG1 world")
		return
	viewer.smoothing = ViewerArguments.value(arguments, "--smoothing=") == "true"
	var mode: String = ViewerArguments.value(arguments, "--performance-mode=")
	if mode == "no-inspector":
		viewer._entity_inspection.hide()
		viewer._label.hide()
	var load_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	viewer.playing = true
	viewer.replay_commands = true
	var previous: int = Time.get_ticks_usec()
	var warm_start: int = previous
	while Time.get_ticks_usec() - warm_start < 5000000:
		await process_frame
		var now: int = Time.get_ticks_usec()
		viewer._process((now - previous) / 1000000.0)
		previous = now
		await RenderingServer.frame_post_draw
		if not viewer.last_error.is_empty():
			_fail(viewer.last_error)
			return
	started = Time.get_ticks_usec()
	issue = viewer.reset_scenario()
	var reset_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	if not issue.is_empty():
		_fail(issue)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	if mode == "no-inspector":
		viewer._entity_inspection.hide()
		viewer._label.hide()
	var resources_before: Dictionary = _resources()
	var frames := PackedFloat64Array()
	var tick_frames := PackedFloat64Array()
	var host_work := PackedFloat64Array()
	var simulation := PackedFloat64Array()
	var tick_intervals := PackedFloat64Array()
	var draw_calls: int = 0
	var primitives: int = 0
	viewer.playing = mode != "paused"
	if EngineDebugger.is_active():
		EngineDebugger.send_message("terrain:measurement_begin", [Engine.get_process_frames()])
	started = Time.get_ticks_usec()
	previous = started
	var previous_draw: int = started
	var previous_tick: int = started
	var duration: float = scenario.tick_limit / 30.0
	if mode == "simulation":
		for tick: int in scenario.tick_limit:
			var before: int = Time.get_ticks_usec()
			var result: TickResult = viewer.run.step(scenario.command_at(tick), false)
			simulation.append((Time.get_ticks_usec() - before) / 1000.0)
			if not result.error.is_empty():
				_fail(result.error)
				return
	else:
		while viewer._current.tick_index < scenario.tick_limit:
			await process_frame
			var now: int = Time.get_ticks_usec()
			var before_tick: int = viewer._current.tick_index
			viewer._process((now - previous) / 1000000.0)
			host_work.append((Time.get_ticks_usec() - now) / 1000.0)
			previous = now
			await RenderingServer.frame_post_draw
			var drawn: int = Time.get_ticks_usec()
			var frame_ms: float = (drawn - previous_draw) / 1000.0
			frames.append(frame_ms)
			if viewer._current.tick_index != before_tick:
				tick_frames.append(frame_ms)
				simulation.append(viewer.last_tick_usec / 1000.0)
				tick_intervals.append((drawn - previous_tick) / 1000.0)
				previous_tick = drawn
			previous_draw = drawn
			draw_calls = maxi(draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			primitives = maxi(primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
			if not viewer.last_error.is_empty():
				_fail(viewer.last_error)
				return
			if mode == "paused" and (drawn - started) / 1000000.0 >= duration:
				break
			if (drawn - started) / 1000000.0 > duration * 5.0 + 30.0:
				_fail("Route timed out or stopped advancing")
				return
	var seconds: float = (Time.get_ticks_usec() - started) / 1000000.0
	if EngineDebugger.is_active():
		EngineDebugger.send_message("terrain:measurement_end", [Engine.get_process_frames()])
	viewer.playing = false
	viewer._close_worker()
	var final: GameplayState = viewer.run.snapshot()
	var diver: bool = scenario.tick_limit == 1255
	var outcome_ok: bool = final.tick_index == scenario.tick_limit and (final.frog.mode == 2 and final.animation.action == FrogAnimationCatalog.DROWN if diver else final.attachment.current_entity_index == -1 and final.frog.cell == Vector2i(10, 7) and final.frog.mode != 2)
	var native_size := Vector2i(root.get_visible_rect().size * root.get_stretch_transform().get_scale())
	var fps: float = frames.size() / seconds
	var frame_stats: Dictionary = _stats(frames)
	var cadence_ok: bool = absf(final.tick_index - seconds * 30.0) <= 1.0
	var p99: float = frame_stats["p99_ms"]
	var accepted: bool = mode == "full" and viewer.smoothing and outcome_ok and cadence_ok and fps > 200.0 and p99 <= 5.0
	var report: Dictionary = {
		"schema": "terrain-performance-v1", "mode": mode, "smoothing": viewer.smoothing,
		"high_detail": not scenario.map_scene.low_poly and viewer.frog_assets != null,
		"entity_count": final.entities.entities.size(), "overlay_visible": viewer._label.visible,
		"inspector_visible": viewer._entity_inspection.visible,
		"profiler_active": EngineDebugger.is_active(), "trace_active": viewer.record_trace,
		"engine": Engine.get_version_info(), "cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"window_size": [root.size.x, root.size.y], "viewport_size": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		"render_target_size": [native_size.x, native_size.y],
		"bars": [(root.size.x - native_size.x) / 2.0, (root.size.y - native_size.y) / 2.0],
		"final_mode": final.frog.mode, "final_action": final.animation.action,
		"vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"window_mode": root.mode, "screen_refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"threaded": viewer.threaded_playback,
		"route": "diver" if diver else "round-trip", "tick_limit": scenario.tick_limit,
		"load_ms": load_ms, "reset_ms": reset_ms, "seconds": seconds, "fps": fps,
		"frames": frame_stats, "tick_frames": _stats(tick_frames), "host_work": _stats(host_work),
		"simulation": _stats(simulation), "ticks": final.tick_index, "ticks_per_second": final.tick_index / seconds,
		"tick_intervals": _stats(tick_intervals),
		"outcome_ok": outcome_ok, "cadence_ok": cadence_ok, "accepted": accepted,
		"draw_calls_max": draw_calls, "primitives_max": primitives,
		"resources_before": resources_before, "resources_after": _resources(),
		"frame_ms": frames, "tick_frame_ms": tick_frames,
	}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write performance report: " + output)
		return
	file.store_string(JSON.stringify(report))
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_fail("Cannot finish performance report: " + output)
		return
	print("terrain_performance: %s %s %.2f FPS p99 %.3f ms ticks %d accepted=%s" % [mode, report["route"], fps, frame_stats["p99_ms"], final.tick_index, accepted])
	quit(0 if outcome_ok or mode == "paused" else 1)

func _stats(samples: PackedFloat64Array) -> Dictionary:
	var sorted: PackedFloat64Array = samples.duplicate()
	sorted.sort()
	var sum: float = 0.0
	var over_5: int = 0
	var over_10: int = 0
	var over_16: int = 0
	for value: float in sorted:
		sum += value
		over_5 += int(value > 5.0)
		over_10 += int(value > 10.0)
		over_16 += int(value > 16.7)
	return {"count": sorted.size(), "mean_ms": sum / maxi(1, sorted.size()),
		"median_ms": _percentile(sorted, 0.5), "p95_ms": _percentile(sorted, 0.95),
		"p99_ms": _percentile(sorted, 0.99), "max_ms": _percentile(sorted, 1.0),
		"over_5_ms": over_5, "over_10_ms": over_10, "over_16_7_ms": over_16}

func _percentile(sorted: PackedFloat64Array, fraction: float) -> float:
	return 0.0 if sorted.is_empty() else sorted[maxi(0, ceili(sorted.size() * fraction) - 1)]

func _resources() -> Dictionary:
	return {"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"video_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

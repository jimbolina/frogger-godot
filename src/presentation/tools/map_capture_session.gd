class_name MapCaptureSession
extends RefCounted
## External map capture and benchmark workflow; the viewer supplies rendering facts.

## Captures a rendered frame after optional animation benchmarking.
static func capture(viewer: MapViewer, folder: String) -> void:
	viewer.set_playing(false)
	var capture_error: String = ViewerCapture.prepare_folder(folder)
	if not capture_error.is_empty():
		push_error(capture_error)
		viewer.get_tree().quit(1)
		return
	for _frame: int in 2:
		await viewer.get_tree().process_frame
		await RenderingServer.frame_post_draw
	var benchmark_fps: float = 0.0
	var benchmark_frames: int = 0
	var benchmark_seconds: float = 0.0
	var benchmark_final_tick: int = viewer.tick
	var original_tick: int = viewer.tick
	var allocations_before: Dictionary = viewer.capture_allocations()
	var allocations_after: Dictionary = allocations_before.duplicate(true)
	if ViewerArguments.has_flag(OS.get_cmdline_user_args(), "--benchmark"):
		viewer.set_playing(true)
		var started: int = Time.get_ticks_usec()
		while benchmark_frames < 120 or Time.get_ticks_usec() - started < 2000000:
			await viewer.get_tree().process_frame
			await RenderingServer.frame_post_draw
			benchmark_frames += 1
		benchmark_seconds = float(Time.get_ticks_usec() - started) / 1000000.0
		benchmark_fps = float(benchmark_frames) / maxf(0.000001, benchmark_seconds)
		benchmark_final_tick = viewer.tick
		viewer.set_playing(false)
		allocations_after = viewer.capture_allocations()
		viewer.seek_tick(original_tick)
		for _frame: int in 2:
			await viewer.get_tree().process_frame
			await RenderingServer.frame_post_draw
	var basename: String = viewer.capture_basename()
	capture_error = ViewerCapture.save_image(viewer.capture_image(), folder.path_join(basename + ".png"))
	if not capture_error.is_empty():
		push_error(capture_error)
		viewer.get_tree().quit(1)
		return
	var benchmark: Dictionary = {"benchmark_fps": benchmark_fps, "benchmark_frame_count": benchmark_frames,
		"benchmark_elapsed_seconds": benchmark_seconds, "benchmark_initial_tick": original_tick,
		"benchmark_final_tick": benchmark_final_tick}
	var metadata: Dictionary = viewer.capture_metadata(benchmark, allocations_before, allocations_after)
	var file: FileAccess = FileAccess.open(folder.path_join(basename + ".json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(metadata, "\t") + "\n")
		file.flush()
		if file.get_error() != OK:
			capture_error = "Cannot write capture metadata '%s': %s" % [folder.path_join(basename + ".json"), error_string(file.get_error())]
		file.close()
	else:
		capture_error = "Cannot create capture metadata '%s': %s. Check write permissions." % [folder.path_join(basename + ".json"), error_string(FileAccess.get_open_error())]
	if not capture_error.is_empty():
		push_error(capture_error)
	print("map capture %s: %s" % [folder.path_join(basename + ".png"), "OK" if capture_error.is_empty() else capture_error])
	viewer.get_tree().quit(0 if capture_error.is_empty() else 1)


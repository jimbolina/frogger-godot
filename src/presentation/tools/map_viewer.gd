class_name MapViewer
extends Node3D
## Map inspection tool. Drag to orbit, right-drag to pan, wheel to zoom.
## Space pauses, Period steps, R resets the camera, F changes filtering.
## Capture mode renders a fixed 640x480 viewport with no UI and quits.
## Manual/custom camera poses use ordinary projection; the selected preset still
## controls the reference group budget and disabled water until reset/preset change.

const BOOT_SCENE: String = "res://scenes/boot.tscn"
const RENDER_SIZE: Vector2i = Vector2i(640, 480)
## Tests may provide scene data without locating retail files.
var auto_open: bool = true
var data: GameData
var _owns_data: bool = false
var scene_data: MapSceneData
var current_mesh: MapMesh
var map_instance: MapMesh.Instance
var playing: bool = false
var tick: int = 0
var linear_filter: bool = false
var camera_preset: String = "default"
var load_build_ms: float = 0.0
var decode_load_ms: float = 0.0
var mesh_build_ms: float = 0.0
var instance_build_ms: float = 0.0
var probe_mesh: ModelMesh

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _ui: CanvasLayer
var _status: Label
var _levels: OptionButton
var _low: CheckButton
var _inspection: CheckButton
var _filter: CheckButton
var _play: Button
var _seek: SpinBox
var _camera_choice: OptionButton
var _updating: bool = false
var _target: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 0.0
var _distance: float = 30.0
var _clock: float = 0.0
var _probe: Node3D
var _probe_name: String = ""
var _projection_distance: int = 256
var _projection_scale: int = 1
var _vertical_ratio: float = 1.0
var _custom_camera: bool = false

func _ready() -> void:
	_build_scene()
	if not auto_open:
		return
	var folder: String = _arg("--screenshot-dir=")
	if not folder.is_empty() and not _external_capture_folder(folder):
		_status.text = "Capture folder '%s' must be an absolute path outside the repository" % folder
		push_error(_status.text)
		get_tree().quit(1)
		return
	camera_preset = _arg("--camera=")
	if camera_preset.is_empty():
		camera_preset = "default"
	if camera_preset not in ["default", "map-slice"]:
		_status.text = "Unknown camera preset"
		if not folder.is_empty():
			get_tree().quit(1)
		return
	linear_filter = _arg("--linear=").to_lower() == "true"
	_filter.set_pressed_no_signal(linear_filter)
	_probe_name = _arg("--probe-model=")
	if _probe_name.is_empty() and ViewerArguments.has_flag(OS.get_cmdline_user_args(), "--probe-model"):
		_probe_name = "GEN_CHECKPOINT_1.XMR"
	var found: GameDataLocator.Located = ViewerArguments.locate_data(OS.get_cmdline_user_args())
	if not found.is_ok():
		_status.text = "No Frogger files found: %s" % found.error
		if not folder.is_empty():
			push_error(_status.text)
			get_tree().quit(1)
		return
	open_data(GameData.open(found.source, found.version), true)
	if not data.is_valid():
		if not folder.is_empty():
			push_error(_status.text)
			get_tree().quit(1)
		return
	var code: String = _arg("--level=").to_upper()
	if code.is_empty():
		code = "SUB1"
	if not load_level_by_code(code, _arg("--low-poly=").to_lower() == "true"):
		if not folder.is_empty():
			get_tree().quit(1)
		return
	if not _apply_cli_camera():
		if not folder.is_empty():
			get_tree().quit(1)
		return
	seek_tick(maxi(0, _arg("--tick=").to_int()))
	if not folder.is_empty():
		_ui.visible = false
		_capture.call_deferred(folder)

## Populates maps from [param game_data], borrowed unless [param take_ownership] is true.
## Replacement/exit closes owned data only; reopening the same object retains ownership.
func open_data(game_data: GameData, take_ownership: bool = false) -> void:
	if data != game_data:
		if _owns_data and data != null:
			data.close()
		_owns_data = take_ownership
	elif take_ownership:
		_owns_data = true
	data = game_data
	if data == null:
		_owns_data = false
	_clear_scene()
	_levels.clear()
	if data == null or not data.is_valid():
		_status.text = data.error if data != null else "No game data open"
		return
	for level: int in mini(60, FroggerIds.LEVEL_CODES.size()):
		var row: MapBookEntry = data.map_book_entry(level)
		if row != null and not row.is_dummy() and row.map_id(false) > 0:
			_levels.add_item(FroggerIds.LEVEL_CODES[level], level)

## Loads one map by its FrogLord level code.
func load_level_by_code(code: String, low_poly: bool = false) -> bool:
	if data == null or not data.is_valid():
		_status.text = "No valid game data open"
		return false
	var level: int = FroggerIds.LEVEL_CODES.find(code.to_upper())
	if level < 0:
		_status.text = "Unknown level %s" % code
		return false
	var started: int = Time.get_ticks_usec()
	var source: MapSceneData = MapSceneData.load_level(data, level, low_poly)
	var decode_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	if not show_scene(source, decode_ms):
		return false
	load_build_ms = float(Time.get_ticks_usec() - started) / 1000.0
	for index: int in _levels.item_count:
		if _levels.get_item_id(index) == level:
			_levels.select(index)
	_low.set_pressed_no_signal(low_poly)
	if not _probe_name.is_empty():
		_show_probe(_probe_name)
	_refresh_status()
	return true

## Displays decoded synthetic or retail data through the same renderer.
func show_scene(source: MapSceneData, source_load_ms: float = 0.0) -> bool:
	if not source.error.is_empty() or source.map == null:
		_status.text = source.error if not source.error.is_empty() else "Missing decoded map"
		return false
	if map_instance != null:
		_world.remove_child(map_instance)
		map_instance.queue_free()
	if _probe != null:
		_world.remove_child(_probe)
		_probe.queue_free()
		_probe = null
	probe_mesh = null
	scene_data = source
	decode_load_ms = source_load_ms
	var build_started: int = Time.get_ticks_usec()
	current_mesh = MapMeshBuilder.new().build(source, linear_filter)
	mesh_build_ms = float(Time.get_ticks_usec() - build_started) / 1000.0
	var instance_started: int = Time.get_ticks_usec()
	map_instance = current_mesh.create_instance()
	_world.add_child(map_instance)
	instance_build_ms = float(Time.get_ticks_usec() - instance_started) / 1000.0
	map_instance.set_inspection_visibility(_inspection.button_pressed)
	map_instance.set_reference_mode(camera_preset == "map-slice")
	map_instance.set_reference_target(source.midpoint)
	map_instance.set_cave_frog(source.midpoint)
	reset_camera()
	seek_tick(0)
	_refresh_status()
	return true

## Uses either GENE defaults or the frozen map_slice inspection camera.
func set_camera_preset(preset: String) -> bool:
	if preset not in ["default", "map-slice"]:
		return false
	camera_preset = preset
	_camera_choice.select(1 if preset == "map-slice" else 0)
	if map_instance != null:
		map_instance.set_reference_mode(preset == "map-slice")
	reset_camera()
	_refresh_status()
	return true

## Restores the selected camera preset without changing animation state.
func reset_camera() -> void:
	if scene_data == null:
		return
	var preset: MapCameraData = MapCameraData.for_scene(scene_data, camera_preset)
	_projection_distance = preset.projection_distance
	_projection_scale = preset.projection_scale
	_vertical_ratio = preset.vertical_ratio
	if map_instance != null:
		map_instance.set_projection_scale(Vector2(1.0, _vertical_ratio))
		map_instance.set_reference_projection(camera_preset == "map-slice")
	_custom_camera = false
	_target = preset.look_target()
	var offset: Vector3 = preset.position() - _target
	_distance = maxf(offset.length(), 0.5)
	if offset.is_zero_approx():
		offset = Vector3(0, 1, 1)
		_distance = 30.0
	_pitch = asin(clampf(offset.normalized().y, -1.0, 1.0))
	_yaw = atan2(offset.x, offset.z)
	_camera.fov = preset.vertical_fov()
	_update_probe_projection()
	_place_camera()

## Pauses or resumes the 30 Hz inspection clock.
func set_playing(value: bool) -> void:
	playing = value
	_clock = 0.0
	_play.text = "Pause" if value else "Play"

## Pauses and seeks deterministic animation state.
func seek_tick(value: int) -> void:
	set_playing(false)
	tick = maxi(value, 0)
	if map_instance != null:
		map_instance.set_tick(tick)
	_refresh_status()

## Pauses and advances one tick without rebuilding geometry.
func step_animation() -> void:
	set_playing(false)
	if map_instance != null:
		map_instance.step()
	tick += 1
	_refresh_status()

## Changes sampling on existing materials.
func set_filtering(value: bool) -> void:
	linear_filter = value
	_filter.set_pressed_no_signal(value)
	if map_instance != null:
		map_instance.set_filtering(value)
	_refresh_status()

## Render size is independent of the desktop window and UI.
func render_size() -> Vector2i:
	return _viewport.size

## Current diagnostics and geometry facts.
func facts_text() -> String:
	return _status.text

func _process(delta: float) -> void:
	if not playing or map_instance == null:
		return
	_clock += delta
	while _clock >= 1.0 / 30.0:
		_clock -= 1.0 / 30.0
		tick += 1
		map_instance.step()
	_refresh_status()

func _place_camera() -> void:
	var horizontal: float = cos(_pitch) * _distance
	_camera.position = _target + Vector3(sin(_yaw) * horizontal, sin(_pitch) * _distance, cos(_yaw) * horizontal)
	_camera.look_at(_target, Vector3.FORWARD if absf(cos(_pitch)) < 0.0001 else Vector3.UP)
	if map_instance != null:
		map_instance.set_camera_position(GameSpace.to_game(_camera.position))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_begin_manual_camera()
			_yaw -= motion.relative.x * 0.008
			_pitch = clampf(_pitch + motion.relative.y * 0.008, -1.5, 1.5)
			_place_camera()
		elif motion.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_begin_manual_camera()
			_target += (-_camera.basis.x * motion.relative.x + _camera.basis.y * motion.relative.y) * _distance * 0.002
			_place_camera()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_begin_manual_camera()
			_distance = clampf(_distance * (0.9 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.5, 1000.0)
			_place_camera()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_ESCAPE: get_tree().change_scene_to_file(BOOT_SCENE)
			KEY_SPACE: set_playing(not playing)
			KEY_PERIOD: step_animation()
			KEY_R: reset_camera()
			KEY_F: set_filtering(not linear_filter)

func _build_scene() -> void:
	_viewport = SubViewport.new()
	_viewport.size = RENDER_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	_camera = Camera3D.new()
	_camera.near = 0.01
	_camera.far = 2000.0
	_camera.current = true
	_world.add_child(_camera)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_world.add_child(world_environment)
	var display := TextureRect.new()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.texture = _viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	_ui = CanvasLayer.new()
	add_child(_ui)
	var panel := VBoxContainer.new()
	panel.position = Vector2(8, 8)
	panel.custom_minimum_size = Vector2(210, 0)
	_ui.add_child(panel)
	_levels = OptionButton.new()
	panel.add_child(_levels)
	_levels.item_selected.connect(_on_level_selected)
	_low = CheckButton.new()
	_low.text = "Low detail"
	panel.add_child(_low)
	_low.toggled.connect(_on_detail_changed)
	_filter = CheckButton.new()
	_filter.text = "Linear filtering (F)"
	panel.add_child(_filter)
	_filter.toggled.connect(set_filtering)
	_inspection = CheckButton.new()
	_inspection.text = "Invisible / unreferenced"
	panel.add_child(_inspection)
	_inspection.toggled.connect(set_inspection_visibility)
	_camera_choice = OptionButton.new()
	_camera_choice.add_item("Default camera")
	_camera_choice.add_item("Map slice reference")
	panel.add_child(_camera_choice)
	_camera_choice.item_selected.connect(_on_camera_selected)
	var reset := Button.new()
	reset.text = "Reset camera (R)"
	reset.pressed.connect(reset_camera)
	panel.add_child(reset)
	_play = Button.new()
	_play.text = "Play (Space)"
	_play.pressed.connect(_on_play)
	panel.add_child(_play)
	var step := Button.new()
	step.text = "Step (.)"
	step.pressed.connect(step_animation)
	panel.add_child(step)
	_seek = SpinBox.new()
	_seek.max_value = 100000
	_seek.prefix = "Tick "
	_seek.value_changed.connect(_on_seek)
	panel.add_child(_seek)
	_status = Label.new()
	_status.custom_minimum_size = Vector2(210, 0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status)
	_status.text = "Choose a map. Drag to orbit; right-drag to pan; wheel to zoom."

func _on_level_selected(index: int) -> void:
	load_level_by_code(FroggerIds.LEVEL_CODES[_levels.get_item_id(index)], _low.button_pressed)

func _on_detail_changed(value: bool) -> void:
	if scene_data != null:
		load_level_by_code(FroggerIds.LEVEL_CODES[scene_data.level], value)

func _on_camera_selected(index: int) -> void:
	set_camera_preset("map-slice" if index == 1 else "default")

func _on_play() -> void:
	set_playing(not playing)

func _on_seek(value: float) -> void:
	if not _updating:
		seek_tick(int(value))

func _refresh_status() -> void:
	_updating = true
	_seek.set_value_no_signal(tick)
	_updating = false
	if current_mesh == null:
		return
	var code: String = FroggerIds.LEVEL_CODES[scene_data.level] if scene_data.level < FroggerIds.LEVEL_CODES.size() else str(scene_data.level)
	_status.text = "%s %s\n%d triangles, %d groups, %d surfaces\nTick %d • %s\n%.1f ms load/build" % [code, "low" if scene_data.low_poly else "high", current_mesh.triangle_count, current_mesh.group_count, current_mesh.surface_count, tick, camera_preset, load_build_ms]
	_status.tooltip_text = "\n".join(_combined_diagnostics())

func _show_probe(name: String) -> void:
	if data == null or scene_data == null:
		return
	var id: int = -1
	for entry: MwiEntry in data.model_entries():
		if entry.display_name().to_upper() == name.to_upper():
			id = entry.index
			break
	if id < 0:
		scene_data.diagnostics.append("Probe model %s is missing" % name)
		return
	var model: MofFile = data.read_model(id, scene_data.diagnostics)
	if model != null and model.kind == MofFile.Kind.ANIMATED:
		scene_data.diagnostics.append("Probe model %s is animated; choose a static .XMR model" % name)
		return
	if model == null or model.static_models.is_empty():
		return
	var lighting := MapLighting.new()
	lighting.configure(scene_data.map.lights)
	var builder := ModelMeshBuilder.new(scene_data.library, scene_data.preferred)
	builder.linear_filter = linear_filter
	builder.lighting = lighting
	probe_mesh = builder.build(model.static_models[0])
	_probe = Node3D.new()
	_probe.position = GameSpace.position(scene_data.midpoint.x, scene_data.midpoint.y, scene_data.midpoint.z)
	for mesh: ArrayMesh in probe_mesh.part_meshes:
		if mesh == null:
			continue
		var part := MeshInstance3D.new()
		part.mesh = mesh
		_probe.add_child(part)
	_world.add_child(_probe)
	_update_probe_projection()

func _capture(folder: String) -> void:
	set_playing(false)
	var capture_error: String = ViewerCapture.prepare_folder(folder)
	if not capture_error.is_empty():
		push_error(capture_error)
		get_tree().quit(1)
		return
	for _frame: int in 2:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var benchmark_fps: float = 0.0
	var benchmark_frames: int = 0
	var benchmark_seconds: float = 0.0
	var benchmark_final_tick: int = tick
	var original_tick: int = tick
	var allocations_before: Dictionary = _allocation_snapshot()
	var allocations_after: Dictionary = allocations_before.duplicate(true)
	if ViewerArguments.has_flag(OS.get_cmdline_user_args(), "--benchmark"):
		set_playing(true)
		var started: int = Time.get_ticks_usec()
		while benchmark_frames < 120 or Time.get_ticks_usec() - started < 2000000:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			benchmark_frames += 1
		benchmark_seconds = float(Time.get_ticks_usec() - started) / 1000000.0
		benchmark_fps = float(benchmark_frames) / maxf(0.000001, benchmark_seconds)
		benchmark_final_tick = tick
		set_playing(false)
		allocations_after = _allocation_snapshot()
		seek_tick(original_tick)
		for _frame: int in 2:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
	var code: String = FroggerIds.LEVEL_CODES[scene_data.level].to_lower()
	var basename: String = "map_%s_%s_%s_tick%d_%s" % [code, "low" if scene_data.low_poly else "high", camera_preset, tick, "linear" if linear_filter else "nearest"]
	capture_error = ViewerCapture.save_image(_viewport.get_texture().get_image(), folder.path_join(basename + ".png"))
	if not capture_error.is_empty():
		push_error(capture_error)
		get_tree().quit(1)
		return
	var rendered: Dictionary[String, int] = _render_counts()
	var resource: int = data.map_book_entry(scene_data.level).map_id(scene_data.low_poly)
	var machine: Dictionary = {"processor_name": OS.get_processor_name(), "processor_count": OS.get_processor_count(), "os": OS.get_name(), "os_version": OS.get_version(), "renderer_device": RenderingServer.get_video_adapter_name()}
	if OS.has_method("get_memory_info"):
		var memory_info: Dictionary = OS.call("get_memory_info")
		machine["memory_info"] = memory_info
	var metadata: Dictionary = {"machine": machine, "level": code, "resource_id": resource, "low_poly": scene_data.low_poly, "camera": camera_preset, "tick": tick, "linear": linear_filter, "render_width": 640, "render_height": 480, "load_build_ms": load_build_ms, "decode_load_ms": decode_load_ms, "mesh_build_ms": mesh_build_ms, "instance_build_ms": instance_build_ms, "allocations_before": allocations_before, "allocations_after": allocations_after, "allocation_growth": allocations_before["mesh_ids"] != allocations_after["mesh_ids"] or allocations_before["material_ids"] != allocations_after["material_ids"] or allocations_before["page_texture_ids"] != allocations_after["page_texture_ids"] or allocations_before["sky_atlas_id"] != allocations_after["sky_atlas_id"], "page_texture_growth": allocations_before["page_texture_ids"] != allocations_after["page_texture_ids"], "triangles": rendered["triangles"], "groups": rendered["groups"], "surfaces": rendered["surfaces"], "available_triangles": current_mesh.triangle_count, "benchmark_fps": benchmark_fps, "benchmark_frame_count": benchmark_frames, "benchmark_elapsed_seconds": benchmark_seconds, "benchmark_initial_tick": original_tick, "benchmark_final_tick": benchmark_final_tick, "static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "peak_static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC_MAX), "resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED), "render_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "render_primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "probe_model": _probe_name, "standalone_index_checked": data.standalone_index_checked, "camera_source_game": _vector_array(GameSpace.to_game(_camera.position)), "camera_target_game": _vector_array(GameSpace.to_game(_target)), "projection_distance": _projection_distance, "nominal_projection": _projection_distance, "effective_projection": _projection_distance * _projection_scale, "projection_scale": _projection_scale, "effective_projection_x": _projection_distance * _projection_scale, "effective_projection_y": _projection_distance * _projection_scale * _vertical_ratio, "clip_scale": [1.0, _vertical_ratio], "custom_camera": _custom_camera, "diagnostics": Array(_combined_diagnostics())}
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
	get_tree().quit(0 if capture_error.is_empty() else 1)

## Capture outputs must use an absolute folder outside the source checkout.
static func _external_capture_folder(folder: String) -> bool:
	return ViewerCapture.external_folder(folder)

static func _arg(prefix: String) -> String:
	return ViewerArguments.value(OS.get_cmdline_user_args(), prefix)


func _render_counts() -> Dictionary[String, int]:
	var totals: Dictionary[String, int] = {"triangles": 0, "groups": 0, "surfaces": 0}
	var meshes: Array[ArrayMesh] = []
	for index: int in map_instance.visible_group_indices():
		if index < current_mesh.groups.size() and current_mesh.groups[index] != null:
			meshes.append(current_mesh.groups[index])
			totals["groups"] += 1
	if current_mesh.sky_mesh != null:
		meshes.append(current_mesh.sky_mesh)
	if probe_mesh != null:
		meshes.append_array(probe_mesh.part_meshes)
	for mesh: ArrayMesh in meshes:
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			@warning_ignore("integer_division")
			var count: int = (indices.size() if not indices.is_empty() else positions.size()) / 3
			totals["triangles"] += count
			totals["surfaces"] += 1
	return totals


## Shows retained invisible and unreferenced geometry for inspection.
func set_inspection_visibility(value: bool) -> void:
	_inspection.set_pressed_no_signal(value)
	if map_instance != null:
		map_instance.set_inspection_visibility(value)
	_refresh_status()

func _exit_tree() -> void:
	_release_scene(false)
	if _owns_data and data != null:
		data.close()
	data = null
	_owns_data = false


func _clear_scene() -> void:
	set_playing(false)
	_seek.set_value_no_signal(0)
	_release_scene()
	_low.set_pressed_no_signal(false)
	_status.text = ""
	_status.tooltip_text = ""


func _release_scene(detach: bool = true) -> void:
	playing = false
	_clock = 0.0
	tick = 0
	for instance: Node3D in [map_instance, _probe]:
		if instance != null:
			if detach:
				_world.remove_child(instance)
			instance.queue_free()
	map_instance = null
	_probe = null
	probe_mesh = null
	current_mesh = null
	scene_data = null
	load_build_ms = 0.0
	decode_load_ms = 0.0
	mesh_build_ms = 0.0
	instance_build_ms = 0.0
	_custom_camera = false
	_target = Vector3.ZERO
	_yaw = 0.0
	_pitch = 0.0
	_distance = 30.0
	_projection_distance = 256
	_projection_scale = 1
	_vertical_ratio = 1.0


func _vector_array(value: Vector3i) -> Array[int]:
	return [value.x, value.y, value.z]

## Sets a bounded inspection pose in raw game units, without a gameplay camera.
## Retains the selected preset's group budget/water mode; reset restores its pose.
func set_camera_pose(source: Vector3i, target: Vector3i, projection: int = 256) -> bool:
	if source == target or projection < 3 or projection > 8192:
		_status.text = "Camera needs distinct source/target and projection distance 3..8192"
		return false
	for point: Vector3i in [source, target]:
		if absi(point.x) > 1000000 or absi(point.y) > 1000000 or absi(point.z) > 1000000:
			_status.text = "Camera coordinates must be within ±1000000 game units"
			return false
	var at: Vector3 = GameSpace.position(source.x, source.y, source.z)
	_target = GameSpace.position(target.x, target.y, target.z)
	var offset: Vector3 = at - _target
	_distance = offset.length()
	_pitch = asin(clampf(offset.normalized().y, -1.0, 1.0))
	_yaw = atan2(offset.x, offset.z)
	_projection_distance = projection
	_projection_scale = 1
	_vertical_ratio = 1.0
	if map_instance != null:
		map_instance.set_projection_scale(Vector2.ONE)
		map_instance.set_reference_projection(false)
	_custom_camera = true
	_camera.fov = rad_to_deg(2.0 * atan(240.0 / float(projection)))
	_update_probe_projection()
	_place_camera()
	_refresh_status()
	return true

## Effective projection distance; the unused GENE perspective is never used.
func projection_distance() -> int:
	return _projection_distance

## Effective X pixel projection including the frozen viewport scale.
func effective_projection_distance() -> int:
	return _projection_distance * _projection_scale

func _apply_cli_camera() -> bool:
	if not _has_arg("--camera-source=") and not _has_arg("--camera-target=") and not _has_arg("--projection="):
		return true
	var source: Vector3i = GameSpace.to_game(_camera.position)
	var target: Vector3i = GameSpace.to_game(_target)
	for prefix: String in ["--camera-source=", "--camera-target="]:
		if not _has_arg(prefix):
			continue
		var values: Array[int] = _parse_vector(_arg(prefix))
		if values.size() != 3:
			_status.text = "%s requires exactly three comma-separated integers" % prefix.trim_suffix("=")
			return false
		var point := Vector3i(values[0], values[1], values[2])
		if prefix == "--camera-source=":
			source = point
		else:
			target = point
	var projection: int = _projection_distance * _projection_scale
	if _has_arg("--projection="):
		var value: String = _arg("--projection=")
		if not value.is_valid_int():
			_status.text = "--projection requires an integer distance"
			return false
		projection = value.to_int()
	return set_camera_pose(source, target, projection)

static func _parse_vector(value: String) -> Array[int]:
	var components: PackedStringArray = value.split(",", true)
	var values: Array[int] = []
	if components.size() != 3:
		return values
	for component: String in components:
		if not component.strip_edges().is_valid_int():
			return []
		var number: int = component.strip_edges().to_int()
		if number < -1000000 or number > 1000000:
			return []
		values.append(number)
	return values

static func _has_arg(prefix: String) -> bool:
	return ViewerArguments.has_prefix(OS.get_cmdline_user_args(), prefix)


func _allocation_snapshot() -> Dictionary:
	var meshes := PackedInt64Array()
	for mesh: ArrayMesh in current_mesh.groups:
		meshes.append(mesh.get_instance_id() if mesh != null else 0)
	if current_mesh.sky_mesh != null:
		meshes.append(current_mesh.sky_mesh.get_instance_id())
	var materials := PackedInt64Array()
	for material: ShaderMaterial in map_instance._material_copies.values():
		materials.append(material.get_instance_id())
	materials.sort()
	var page_ids: PackedInt64Array = scene_data.texture_pages.cached_texture_ids()
	return {"sky_atlas_id": current_mesh.sky_atlas.get_instance_id() if current_mesh.sky_atlas != null else 0, "mesh_ids": meshes, "mesh_count": meshes.size(), "material_ids": materials, "material_count": materials.size(), "page_texture_ids": page_ids, "page_texture_count": page_ids.size(), "resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)}

func _update_probe_projection() -> void:
	if probe_mesh == null:
		return
	for mesh: ArrayMesh in probe_mesh.part_meshes:
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var material: ShaderMaterial = mesh.surface_get_material(surface)
			material.set_shader_parameter("projection_scale", Vector2(1.0, _vertical_ratio))

func _begin_manual_camera() -> void:
	if _custom_camera:
		return
	_projection_distance *= _projection_scale
	_projection_scale = 1
	_vertical_ratio = 1.0
	_custom_camera = true
	if map_instance != null:
		map_instance.set_reference_projection(false)
		map_instance.set_projection_scale(Vector2.ONE)
	_update_probe_projection()


func _combined_diagnostics() -> PackedStringArray:
	var messages := PackedStringArray()
	if scene_data != null:
		for message: String in scene_data.diagnostics:
			if not messages.has(message):
				messages.append(message)
	if map_instance != null:
		for message: String in map_instance.diagnostics:
			if not messages.has(message):
				messages.append(message)
	return messages

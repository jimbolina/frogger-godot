class_name CameraZoneViewer
extends Node3D
## Camera inspection rendering and controls; camera ticks never depend on rendered transforms.
##
## The lit map and log models are drawn under a [SceneLighting] child built from the map's light records (or the
## options screen's lights when the map has none), with the cave light at the
## map's static start on cave maps; the probe and markers stay unshaded.

## When false, [method _ready] opens nothing; tests call [method open] with their own data.
var auto_open: bool = true
var inspection: CameraZoneInspection
var playing: bool = false
## The scene lights, created when a map opens.
var scene_lighting: SceneLighting = null
var _data: AssetCatalog
var _owns_data: bool = false
var _camera: Camera3D
var _probe: MeshInstance3D
var _label: Label
var _map: MapMesh.Instance
var _elapsed: float = 0.0
var _automated: bool = false
var _failure: String = ""
var _entities: CameraZoneEntities
var _entity_markers: EntityInspection
var _last_tick: int = -1

func _ready() -> void:
	if not auto_open:
		return
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	_automated = ViewerArguments.has_flag(arguments, "--run-scenario")
	var lifetime: String = ViewerArguments.value(arguments, "--entity-lifecycle=")
	if lifetime not in ["", "all-attached", "visibility"]:
		_fail("Camera probe entity-lifecycle must be all-attached or visibility")
		return
	var issue: String = open(ImportedAssets.open("res://assets", ViewerArguments.texture_set(arguments)), lifetime == "visibility", true)
	if not issue.is_empty():
		_fail(issue)
		return
	if _automated:
		_capture.call_deferred(arguments)

## Builds the JUN1 inspection from [param data], borrowed unless
## [param take_ownership] is true, with log lifetimes when [param visibility]
## is set; returns the error or "".
func open(data: AssetCatalog, visibility: bool = false, take_ownership: bool = false) -> String:
	_data = data
	_owns_data = take_ownership
	_data.note_renderer(RenderingServer.get_current_rendering_method())
	if not _data.is_valid():
		return _data.error
	inspection = CameraZoneInspection.from_data(_data, visibility)
	if not inspection.error.is_empty():
		return inspection.error
	_map = MapMeshBuilder.new().build(inspection.map_scene).create_instance()
	add_child(_map)
	_light_scene(inspection.map_scene)
	if inspection.entities != null:
		_entities = CameraZoneEntities.new()
		add_child(_entities)
		var model_issue: String = _entities.configure(_data, inspection)
		if not model_issue.is_empty():
			return model_issue
		_entity_markers = EntityInspection.new()
		add_child(_entity_markers)
		_entity_markers.configure(inspection.entity_definitions)
		_entity_markers.visible = true
	_camera = Camera3D.new()
	_camera.near = 0.05
	_camera.far = 1000.0
	_camera.current = true
	add_child(_camera)
	_probe = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	_probe.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.3, 0.8)
	material.no_depth_test = true
	material.render_priority = 127
	_probe.material_override = material
	add_child(_probe)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_label = Label.new()
	_label.position = Vector2(12, 10)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(_label)
	_present()
	return ""

func _light_scene(source: MapSceneData) -> void:
	scene_lighting = SceneLighting.new()
	scene_lighting.name = "SceneLighting"
	add_child(scene_lighting)
	var lighting := MapLighting.new()
	lighting.configure(source.map.lights)
	if lighting.directions.is_empty() and lighting.ambient.is_zero_approx():
		lighting = OptionsModels.options_lighting()
	scene_lighting.apply(SceneLightingBuilder.from_lighting(lighting))
	if source.cave_enabled:
		scene_lighting.set_cave_light(GameSpace.position(source.midpoint.x, source.midpoint.y, source.midpoint.z),
			source.cave_min_r2, source.cave_max_r2)

func _exit_tree() -> void:
	if _owns_data and _data != null:
		_data.close()

func _process(delta: float) -> void:
	if _automated or not playing or inspection == null:
		return
	_elapsed += delta
	while _elapsed >= 1.0 / 30.0 and playing:
		_elapsed -= 1.0 / 30.0
		_advance()

func _unhandled_key_input(event: InputEvent) -> void:
	if _automated or inspection == null or _camera == null or not event is InputEventKey:
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_SPACE:
			playing = not playing and inspection.tick < CameraZoneInspection.TICK_LIMIT
		KEY_PERIOD:
			playing = false
			_advance()
		KEY_R:
			playing = false
			_elapsed = 0.0
			_failure = inspection.reset()
	_present()

func _advance() -> void:
	if inspection.tick >= CameraZoneInspection.TICK_LIMIT:
		playing = false
		return
	_failure = inspection.step()
	if not _failure.is_empty():
		_fail(_failure)
		return
	if inspection.tick == CameraZoneInspection.TICK_LIMIT:
		playing = false
	_present()

func _present() -> void:
	var snapshot: GameplayCameraSnapshot = inspection.camera.snapshot()
	var size := Vector2i(get_viewport().get_visible_rect().size)
	_camera.fov = GameplayProjection.vertical_fov_degrees(size)
	_map.set_projection_scale(GameplayProjection.clip_scale(size))
	_camera.transform = GameplayProjection.camera_transform(snapshot)
	_probe.position = GameSpace.position(inspection.world.x, inspection.world.y, inspection.world.z)
	_label.text = "JUN1 camera inspection — prescribed probe, not a playable route\nSpace: play/pause   Period: step   R: reset\n%s  Tick %d/320  Cell %s\nFrog zone/region %s   Camera zone %d   Transition %d   Twist %d × %d\n%s" % ["PLAYING" if playing else "PAUSED", inspection.tick, inspection.cell, inspection.selected, snapshot.zone_index, snapshot.move_timer, snapshot.twist_counter, snapshot.twist_quadrants, _failure]
	if _entities != null:
		var state: EntityRunSnapshot = inspection.entities.snapshot()
		_entities.present(state, GameplayProjection.clip_scale(size), inspection.tick < _last_tick or (_last_tick <= 160 and inspection.tick == 161))
		_entity_markers.set_snapshot(state)
		_label.text += "\nLog-only visibility probe: %d/11 live; %d groups\n%s\nOther authored entities omitted; no frog contact" % [state.live_order.size(), state.selected_groups.size(), ", ".join(TickEvent.trace_lines(state.lifecycle_events))]
	_last_tick = inspection.tick

func _capture(arguments: PackedStringArray) -> void:
	var output: String = ViewerArguments.value(arguments, "--trace-jsonl=")
	var folder: String = output.get_base_dir()
	var issue: String = ViewerCapture.prepare_folder(folder)
	if not issue.is_empty():
		_fail(issue)
		return
	var stream: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if stream == null:
		_fail("Cannot write camera trace: " + output)
		return
	var zone_facts: Array[Dictionary] = []
	for zone: ZoneDefinition in inspection.zones:
		zone_facts.append(TerrainTrace.facts(zone))
	var metadata: Dictionary = {"schema": "camera-zone-lifecycle-v1" if inspection.entities != null else "camera-zone-inspection-v1", "preset": CameraZoneInspection.PRESET, "tick_limit": 320, "zones": zone_facts, "camera_definition": TerrainTrace.facts(inspection.definition)}
	if inspection.entities != null:
		metadata["diagnostics"] = Array(inspection.diagnostics)
		metadata["lifecycle"] = TerrainTrace.facts(inspection.lifecycle)
		var identities: Array[Dictionary] = []
		for entity: EntityDefinition in inspection.entity_definitions:
			identities.append(TerrainTrace.facts(entity))
		metadata["entities"] = identities
	stream.store_line(JSON.stringify(metadata))
	var rate: int = int(ViewerArguments.value(arguments, "--render-rate="))
	if rate not in [30, 60, 144, 200, 240]:
		stream.close()
		_fail("Camera capture requires a supported render rate")
		return
	var elapsed: float = 0.0
	var capture_folder: String = ViewerArguments.value(arguments, "--screenshot-dir=")
	if not capture_folder.is_empty():
		issue = ViewerCapture.prepare_folder(capture_folder)
		if not issue.is_empty():
			stream.close()
			_fail(issue)
			return
	while inspection.tick < CameraZoneInspection.TICK_LIMIT:
		elapsed += 1.0 / float(rate)
		while elapsed + 0.00000001 >= 1.0 / 30.0 and inspection.tick < CameraZoneInspection.TICK_LIMIT:
			elapsed -= 1.0 / 30.0
			_advance()
			if not _failure.is_empty():
				stream.close()
				return
			stream.store_line(JSON.stringify(inspection.row))
			var lifecycle_event: bool = inspection.entities != null and not inspection.entities.snapshot().lifecycle_events.is_empty()
			if not capture_folder.is_empty() and (lifecycle_event or inspection.tick % 160 in [1, 41, 55, 80, 81, 120, 121, 159]):
				await RenderingServer.frame_post_draw
				issue = ViewerCapture.save_image(get_viewport().get_texture().get_image(), capture_folder.path_join("zone-%03d.png" % inspection.tick))
				if not issue.is_empty():
					stream.close()
					_fail(issue)
					return
		await get_tree().process_frame
	stream.close()
	print("camera_zone_inspection: 320 ticks complete")
	get_tree().quit(0)

func _fail(message: String) -> void:
	_failure = message
	playing = false
	push_error(message)
	if _label == null:
		var canvas := CanvasLayer.new()
		add_child(canvas)
		_label = Label.new()
		_label.position = Vector2(12, 10)
		canvas.add_child(_label)
	_label.text = "Camera inspection failed: " + message
	if _automated:
		get_tree().quit(1)

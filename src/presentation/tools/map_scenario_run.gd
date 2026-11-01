class_name MapScenarioRun
extends RefCounted
## Rendered path and entity scenario runs in the map viewer: argument checks,
## the synthetic stage, the render schedule, the JSONL trace and the captures.

## Validated command-line selections shared by both scenario kinds.
class Settings extends RefCounted:
	var error: String = ""
	var folder: String = ""
	var trace_path: String = ""
	## -1 keeps the scenario's own tick limit.
	var tick_limit: int = -1
	var render_rate: int = 60
	var scenario: String = ""
	var scenario_file: String = ""
	var level_code: String = ""
	var path_index_text: String = ""

## Reads the user [param arguments] for a [param kind] ("Path" or "Entity") run;
## [member Settings.error] names the first invalid selection.
static func parse(arguments: PackedStringArray, kind: String) -> Settings:
	var settings := Settings.new()
	settings.folder = ViewerArguments.value(arguments, "--screenshot-dir=")
	settings.trace_path = ViewerArguments.value(arguments, "--trace-jsonl=")
	settings.scenario = ViewerArguments.value(arguments, "--scenario=")
	settings.scenario_file = ViewerArguments.value(arguments, "--scenario-file=")
	settings.level_code = ViewerArguments.value(arguments, "--level=")
	settings.path_index_text = ViewerArguments.value(arguments, "--path-index=")
	if not ViewerCapture.external_folder(settings.folder) or not ViewerCapture.external_folder(settings.trace_path.get_base_dir()):
		settings.error = kind + " output requires absolute external destinations"
		return settings
	var limit_text: String = ViewerArguments.value(arguments, "--tick-limit=")
	if not limit_text.is_empty():
		if not limit_text.is_valid_int() or limit_text.to_int() < 0 or limit_text.to_int() > 100000:
			settings.error = kind + " tick limit must be in 0..100000"
			return settings
		settings.tick_limit = limit_text.to_int()
	var rate_text: String = ViewerArguments.value(arguments, "--render-rate=")
	settings.render_rate = 60 if rate_text.is_empty() else rate_text.to_int()
	if settings.render_rate not in [30, 60, 144]:
		settings.error = kind + " render rate must be 30, 60 or 144"
		return settings
	if kind == "Path":
		if not settings.level_code.is_empty() and (not settings.path_index_text.is_valid_int() or settings.path_index_text.to_int() < 0):
			settings.error = "A level path requires --path-index=0 or greater"
		elif settings.level_code.is_empty() and not settings.path_index_text.is_empty():
			settings.error = "--path-index requires --level"
	return settings

## Runs the selected path scenario, writes its trace and captures, and quits.
static func run_path(viewer: MapViewer) -> void:
	var settings: Settings = parse(OS.get_cmdline_user_args(), "Path")
	if not settings.error.is_empty():
		_fail(viewer, settings.error)
		return
	var scenario: PathScenario = PathScenario.from_file(settings.scenario_file) if not settings.scenario_file.is_empty() else PathScenario.builtin(settings.scenario if not settings.scenario.is_empty() else "line")
	if not scenario.error.is_empty():
		_fail(viewer, scenario.error)
		return
	if settings.tick_limit >= 0:
		scenario.tick_limit = settings.tick_limit
	var issue: String = ""
	if not settings.level_code.is_empty():
		issue = _open_level(viewer)
		if issue.is_empty():
			issue = scenario.attach_data(viewer.data, settings.level_code, settings.path_index_text.to_int())
		if issue.is_empty() and not viewer.load_level_by_code(settings.level_code):
			issue = viewer.status_text()
		if issue.is_empty() and not viewer.configure_path(settings.path_index_text.to_int(), scenario.start):
			issue = "Cannot start selected map path"
		if not issue.is_empty():
			_fail(viewer, issue)
			return
	else:
		if not viewer.show_scene(synthetic_scene()):
			_fail(viewer, viewer.status_text())
			return
		if not viewer.attach_synthetic_path(scenario.definition, scenario.start):
			_fail(viewer, "Cannot start synthetic path")
			return
	frame_path(viewer, scenario.definition)
	viewer.set_path_visibility(true)
	var trace := PathTrace.new()
	trace.configure(scenario)
	issue = await _render(viewer, settings, "Path", scenario.tick_limit, viewer.path_snapshot, trace.append_snapshot)
	if issue.is_empty():
		issue = trace.save(settings.trace_path)
	if issue.is_empty():
		issue = await _capture(viewer, settings.folder, "path")
	if not issue.is_empty():
		_fail(viewer, issue)
		return
	print("path_viewer: %s, %d ticks, next tick %d" % [scenario.name, scenario.tick_limit, viewer.path_snapshot().tick_index])
	viewer.get_tree().quit(0)

## Runs the selected entity scenario, writes its trace and captures, and quits.
static func run_entity(viewer: MapViewer) -> void:
	var settings: Settings = parse(OS.get_cmdline_user_args(), "Entity")
	if not settings.error.is_empty():
		_fail(viewer, settings.error)
		return
	var scenario: EntityScenario = EntityScenario.builtin(settings.scenario if not settings.scenario.is_empty() else "shared-path")
	if not scenario.error.is_empty():
		_fail(viewer, scenario.error)
		return
	if settings.tick_limit >= 0:
		scenario.tick_limit = settings.tick_limit
	var issue: String = ""
	if not settings.level_code.is_empty():
		issue = _open_level(viewer)
		if issue.is_empty():
			issue = scenario.attach_data(viewer.data, settings.level_code)
		if issue.is_empty() and not viewer.load_level_by_code(settings.level_code):
			issue = viewer.status_text()
		if issue.is_empty() and not viewer.entities_attached():
			issue = "Entity setup did not attach the selected map"
	elif not viewer.show_scene(synthetic_scene()):
		issue = viewer.status_text()
	else:
		frame_path(viewer, scenario.definitions[1].path_definition)
		issue = viewer.set_entity_definitions(scenario.definitions)
	if issue.is_empty():
		issue = viewer.set_form_contacts(scenario.contact_definitions, scenario.probe_world, false)
	if not issue.is_empty():
		_fail(viewer, issue)
		return
	viewer.focus_entity(scenario.contact_entity_index)
	viewer.set_entity_visibility(true)
	var trace := EntityTrace.new()
	trace.configure(scenario)
	issue = await _render(viewer, settings, "Entity", scenario.tick_limit, viewer.entity_snapshot, trace.append_snapshot)
	if issue.is_empty():
		issue = trace.save(settings.trace_path)
	if issue.is_empty():
		issue = await _capture(viewer, settings.folder, "entity")
	if not issue.is_empty():
		_fail(viewer, issue)
		return
	print("entity_viewer: %s, %d ticks, next tick %d" % [scenario.name, scenario.tick_limit, viewer.entity_snapshot().tick_index])
	viewer.get_tree().quit(0)

## A one-triangle stage for synthetic scenarios, away from any player map.
static func synthetic_scene() -> MapSceneData:
	var source := MapSceneData.new()
	source.level = 48
	source.map = MapFile.new()
	source.remap = TextureRemap.new()
	source.map.vertices = [Vector3i(-256, 0, -256), Vector3i(256, 0, -256), Vector3i(0, 0, 256)]
	source.map.general.camera_source_offset = Vector3i(0, -512, -512)
	source.map.general.camera_target_offset = Vector3i.ZERO
	source.map.group_dimensions = Vector2i.ONE
	source.map.group_size = Vector2i(768, 768)
	var polygon := MapPolygon.new()
	polygon.vertex_indices = PackedInt32Array([0, 1, 2])
	polygon.colors = PackedColorArray([Color8(80, 80, 80)])
	polygon.visible = true
	source.map.polygons.append(polygon)
	var group := MapGroup.new()
	group.polygon_indices = PackedInt32Array([0])
	source.map.groups.append(group)
	return source

## Frames sampled path geometry in the viewer's ordinary inspection projection.
static func frame_path(viewer: MapViewer, definition: PathDefinition) -> void:
	var found: bool = false
	var minimum := Vector3i.ZERO
	var maximum := Vector3i.ZERO
	for segment: PathSegmentDefinition in definition.segments:
		for sample_index: int in 17:
			var distance: int = roundi(float(segment.length) * float(sample_index) / 16.0)
			var sample: PathSample = PathEvaluator.sample(segment, distance)
			if not sample.error.is_empty():
				continue
			minimum = sample.position if not found else minimum.min(sample.position)
			maximum = sample.position if not found else maximum.max(sample.position)
			found = true
	if not found:
		return
	@warning_ignore("integer_division")
	var midpoint: Vector3i = Vector3i((minimum.x + maximum.x) / 2, (minimum.y + maximum.y) / 2, (minimum.z + maximum.z) / 2)
	var span: int = maxi(64, maxi(maximum.x - minimum.x, maxi(maximum.y - minimum.y, maximum.z - minimum.z)))
	viewer.set_camera_pose(midpoint + Vector3i(0, -span, -span * 2), midpoint, 256)

static func _open_level(viewer: MapViewer) -> String:
	viewer.open_data(ImportedAssets.open("res://assets", ViewerArguments.texture_set(OS.get_cmdline_user_args())), true)
	viewer.data.note_renderer(RenderingServer.get_current_rendering_method())
	if viewer.data == null or not viewer.data.is_valid():
		return viewer.data.error if viewer.data != null else "No game data"
	return ""

static func _render(viewer: MapViewer, settings: Settings, kind: String, limit: int, snapshot: Callable, record: Callable) -> String:
	record.call(snapshot.call())
	viewer.set_process(false)
	viewer.set_playing(true)
	var frames: int = 0
	var frame_cap: int = ceili(float(limit + 1) * float(settings.render_rate) / 30.0) + settings.render_rate
	while viewer.tick < limit and frames < frame_cap:
		var before: int = viewer.tick
		viewer.advance_clock(1.0 / float(settings.render_rate))
		if viewer.tick > before:
			var observed: Object = snapshot.call()
			var observed_tick: int = observed.get("tick_index") if observed != null else -1
			if viewer.tick != before + 1 or observed_tick != viewer.tick:
				return "%s render schedule advanced more than one tick" % kind
			record.call(observed)
		elif not viewer.playing:
			return "%s update stopped at tick %d" % [kind, viewer.tick]
		frames += 1
		await viewer.get_tree().process_frame
		await RenderingServer.frame_post_draw
	viewer.set_playing(false)
	if viewer.tick != limit:
		return "%s render schedule did not reach tick %d" % [kind, limit]
	return ""

static func _capture(viewer: MapViewer, folder: String, prefix: String) -> String:
	var issue: String = ViewerCapture.prepare_folder(folder)
	if not issue.is_empty():
		return issue
	viewer.set_controls_visible(false)
	await viewer.get_tree().process_frame
	await RenderingServer.frame_post_draw
	issue = ViewerCapture.save_image(viewer.capture_image(), folder.path_join("%s_tick%d.png" % [prefix, viewer.tick]))
	if not issue.is_empty():
		return issue
	viewer.set_controls_visible(true)
	await viewer.get_tree().process_frame
	await RenderingServer.frame_post_draw
	return ViewerCapture.save_image(viewer.get_viewport().get_texture().get_image(), folder.path_join("%s_controls.png" % prefix))

static func _fail(viewer: MapViewer, message: String) -> void:
	push_error(message)
	viewer.get_tree().quit(1)

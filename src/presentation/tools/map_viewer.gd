class_name MapViewer
extends Node3D
## Map inspection tool. Drag to orbit, right-drag to pan, wheel to zoom.
## Space pauses, Period steps, R resets the camera, F changes filtering.
## Capture mode renders a fixed 640x480 viewport with no UI and quits.
## Manual/custom camera poses use ordinary projection; the selected preset still
## controls the reference group budget and disabled water until reset/preset change.

const BOOT_SCENE: String = "res://scenes/boot.tscn"
const RENDER_SIZE: Vector2i = Vector2i(640, 480)
## Tests may provide scene data without opening the imported assets.
var auto_open: bool = true
var data: AssetCatalog
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
var _path_session: PathInspectionSession = PathInspectionSession.new()
var _entity_session: EntityInspectionSession = EntityInspectionSession.new()
var _path_setup: PathSetup
var _path_inspection: PathInspection
var _path_selected: int = -1
var _path_visible: bool = false
var _path_choice: OptionButton
var _path_segment: SpinBox
var _path_distance: SpinBox
var _path_speed: SpinBox
var _path_active: CheckButton
var _path_backwards: CheckButton
var _path_mode: OptionButton
var _path_toggle: CheckButton
var _path_readout: Label
var _entity_setup: EntitySetup
var _entity_inspection: EntityInspection
var _entity_visible: bool = false
var _entity_selected: int = -1
var _entity_toggle: CheckButton
var _entity_choice: OptionButton
var _entity_readout: Label
var _entity_contact_readout: Label
var _form_contacts: Array[FormContactDefinition] = []
var _form_probe_world: Vector3i = Vector3i.ZERO
var _form_probe_spins: Array[SpinBox] = []
var _form_place_button: Button
var _inspection_tabs: TabContainer

func _ready() -> void:
	_build_scene()
	if ViewerArguments.has_flag(OS.get_cmdline_user_args(), "--run-entity-scenario"):
		_run_entity_scenario.call_deferred()
		return
	if ViewerArguments.has_flag(OS.get_cmdline_user_args(), "--run-path-scenario"):
		_run_path_scenario.call_deferred()
		return
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
	open_data(ImportedAssets.open(), true)
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
func open_data(game_data: AssetCatalog, take_ownership: bool = false) -> void:
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
	_release_entities()
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
	_setup_paths()
	_setup_entities()
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
	_update_path_visibility()
	_update_entity_visibility()
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
	_replay_path(tick)
	_replay_entities(tick)
	_refresh_status()

## Pauses and advances one tick without rebuilding geometry.
func step_animation() -> void:
	set_playing(false)
	if map_instance != null:
		map_instance.step()
	tick += 1
	_step_path(tick - 1)
	_step_entities(tick - 1)
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
		_step_path(tick - 1)
		_step_entities(tick - 1)
		if not playing:
			break
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
	var tabs := TabContainer.new()
	tabs.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tabs.offset_left = -230
	tabs.offset_right = -8
	tabs.offset_top = 8
	tabs.offset_bottom = 340
	_ui.add_child(tabs)
	_inspection_tabs = tabs
	var path_panel := VBoxContainer.new()
	path_panel.name = "Path"
	tabs.add_child(path_panel)
	_path_toggle = CheckButton.new()
	_path_toggle.text = "Show path"
	_path_toggle.toggled.connect(set_path_visibility)
	path_panel.add_child(_path_toggle)
	_path_choice = OptionButton.new()
	_path_choice.item_selected.connect(_on_path_selected)
	path_panel.add_child(_path_choice)
	_path_segment = _path_spin(path_panel, "Segment ", 65535)
	_path_distance = _path_spin(path_panel, "Distance ", 2147483647)
	_path_speed = _path_spin(path_panel, "Speed/unit tick ", 2147483647)
	_path_speed.value = 16
	_path_active = CheckButton.new()
	_path_active.text = "Active"
	_path_active.button_pressed = true
	_path_active.toggled.connect(_on_path_controls_changed)
	path_panel.add_child(_path_active)
	_path_backwards = CheckButton.new()
	_path_backwards.text = "Backwards"
	_path_backwards.toggled.connect(_on_path_controls_changed)
	path_panel.add_child(_path_backwards)
	_path_mode = OptionButton.new()
	_path_mode.add_item("Repeat")
	_path_mode.add_item("Bounce")
	_path_mode.add_item("One shot")
	_path_mode.item_selected.connect(_on_path_mode_changed)
	path_panel.add_child(_path_mode)
	_path_readout = Label.new()
	_path_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path_panel.add_child(_path_readout)
	_path_readout.text = "Inspection settings\nNo path selected"
	_set_path_controls_enabled(false)
	var entity_scroll := ScrollContainer.new()
	entity_scroll.name = "Entities"
	entity_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	entity_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tabs.add_child(entity_scroll)
	var entity_panel := VBoxContainer.new()
	entity_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entity_scroll.add_child(entity_panel)
	_entity_toggle = CheckButton.new()
	_entity_toggle.text = "Show entity axes"
	_entity_toggle.toggled.connect(set_entity_visibility)
	entity_panel.add_child(_entity_toggle)
	_entity_choice = OptionButton.new()
	_entity_choice.item_selected.connect(_on_entity_selected)
	entity_panel.add_child(_entity_choice)
	_entity_contact_readout = Label.new()
	_entity_contact_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_entity_contact_readout.text = "FORM point contact · no reaction\nNo contact probe attached"
	entity_panel.add_child(_entity_contact_readout)
	var probe_row := GridContainer.new()
	probe_row.columns = 2
	entity_panel.add_child(probe_row)
	for axis: String in ["X", "Y", "Z"]:
		var spin := SpinBox.new()
		spin.prefix = axis
		spin.min_value = -2147483648.0
		spin.max_value = 2147483647.0
		spin.step = 1.0
		spin.rounded = true
		spin.custom_minimum_size = Vector2(98, 0)
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(_on_form_probe_changed)
		probe_row.add_child(spin)
		_form_probe_spins.append(spin)
	_form_place_button = Button.new()
	_form_place_button.text = "Place probe in first cell"
	_form_place_button.pressed.connect(_place_form_probe_first_cell)
	entity_panel.add_child(_form_place_button)
	_entity_readout = Label.new()
	_entity_readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entity_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_entity_readout.text = "Base-transform inspection\nNo entities attached"
	entity_panel.add_child(_entity_readout)

func _path_spin(parent: Control, prefix: String, maximum: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.prefix = prefix
	spin.max_value = maximum
	spin.value_changed.connect(_on_path_value_changed)
	parent.add_child(spin)
	return spin

func _setup_paths() -> void:
	_release_path()
	_path_choice.clear()
	_path_readout.text = "No paths in this map"
	if scene_data == null or scene_data.map == null or scene_data.map.paths.is_empty():
		return
	var source_id: String = FroggerIds.LEVEL_CODES[scene_data.level] if scene_data.level < FroggerIds.LEVEL_CODES.size() else str(scene_data.level)
	var resource_id: int = -1
	var build_id: String = ""
	if data != null and data.is_valid():
		var row: MapBookEntry = data.map_book_entry(scene_data.level)
		if row != null:
			resource_id = row.map_id(scene_data.low_poly)
		build_id = data.version_name
	if not build_id.is_empty():
		source_id = build_id + ":" + source_id
	_path_setup = PathSetup.from_map(scene_data.map, source_id, resource_id, build_id)
	if not _path_setup.error.is_empty():
		scene_data.diagnostics.append(_path_setup.error)
		return
	for diagnostic: PathSetupDiagnostic in _path_setup.diagnostics:
		scene_data.diagnostics.append(diagnostic.to_text())
	for definition: PathDefinition in _path_setup.definitions:
		_path_choice.add_item("Path %d (%d segments)" % [definition.path_index, definition.segments.size()], definition.path_index)
	if _path_setup.definitions.is_empty():
		_path_readout.text = "No supported paths"
		return
	_path_inspection = PathInspection.new()
	_world.add_child(_path_inspection)
	configure_path(_path_setup.definitions[0].path_index)

## Selects a source path and a copied component start; resets the shared clock.
func configure_path(index: int, start: PathStart = null) -> bool:
	if _path_setup == null:
		return false
	var definition: PathDefinition = null
	for candidate: PathDefinition in _path_setup.definitions:
		if candidate.path_index == index:
			definition = candidate
			break
	if definition == null:
		return false
	var requested: PathStart = start.copy() if start != null else PathStart.new()
	var issue: String = _path_session.configure(definition, requested)
	if not issue.is_empty():
		return false
	_path_selected = index
	if _path_inspection != null:
		_path_inspection.configure(definition)
		_update_path_visibility()
	for item: int in _path_choice.item_count:
		if _path_choice.get_item_id(item) == index:
			_path_choice.select(item)
			break
	_updating = true
	_path_segment.max_value = definition.segments.size() - 1
	_path_segment.set_value_no_signal(requested.segment_index)
	_path_distance.max_value = definition.segments[requested.segment_index].length
	_path_distance.set_value_no_signal(requested.distance)
	_path_speed.set_value_no_signal(requested.speed)
	_path_active.set_pressed_no_signal(bool(requested.flags & PathStart.ACTIVE))
	_path_backwards.set_pressed_no_signal(bool(requested.flags & PathStart.BACKWARDS))
	_path_mode.select(2 if requested.flags & PathStart.ONE_SHOT else (0 if requested.flags & PathStart.REPEAT else 1))
	_updating = false
	_set_path_controls_enabled(true)
	seek_tick(0)
	return true

## Returns a detached observation of the selected path at the current tick.
func path_snapshot() -> PathSnapshot:
	return _path_session.snapshot()

## Controls the optional path overlay without changing simulation state.
func set_path_visibility(value: bool) -> void:
	_path_visible = value
	_path_toggle.set_pressed_no_signal(value)
	_update_path_visibility()

func _update_path_visibility() -> void:
	if _path_inspection != null:
		_path_inspection.visible = _path_visible and camera_preset != "map-slice"

func _replay_path(target_tick: int) -> void:
	if _path_session.runner == null or _path_session.start == null:
		_update_path_readout()
		return
	var problem: String = _path_session.seek(target_tick)
	if not problem.is_empty():
		set_playing(false)
		var committed: PathSnapshot = path_snapshot()
		if committed != null:
			tick = committed.tick_index
			if map_instance != null:
				map_instance.set_tick(tick)
		if scene_data != null:
			scene_data.diagnostics.append("Path %d: %s" % [_path_selected, problem])
	if _path_inspection != null:
		_path_inspection.set_snapshot(path_snapshot())
	_update_path_readout()

func _step_path(previous_tick: int) -> void:
	if _path_session.runner == null:
		return
	var problem: String = _path_session.step(previous_tick)
	if not problem.is_empty():
		set_playing(false)
		var committed: PathSnapshot = path_snapshot()
		if committed != null:
			tick = committed.tick_index
			if map_instance != null:
				map_instance.set_tick(tick)
		if scene_data != null:
			scene_data.diagnostics.append("Path %d: %s" % [_path_selected, problem])
	if _path_inspection != null:
		_path_inspection.set_snapshot(path_snapshot())
	_update_path_readout()

func _update_path_readout() -> void:
	if _path_readout == null:
		return
	var snapshot: PathSnapshot = path_snapshot()
	if snapshot == null:
		_path_readout.text = "Inspection settings\nNo path selected"
		return
	var label: String = "Synthetic path" if _path_selected < 0 else "Path %d" % _path_selected
	_path_readout.text = "Inspection settings\n%s · segment %d · distance %d/%d\nPosition %s · tangent %s\nFlags 0x%X" % [label, snapshot.segment_index, snapshot.segment_distance, snapshot.segment_length, str(snapshot.position), str(snapshot.tangent), snapshot.flags]

func _on_path_selected(item: int) -> void:
	if not _updating:
		configure_path(_path_choice.get_item_id(item))

func _on_path_value_changed(_value: float) -> void:
	_on_path_controls_changed(true)

func _on_path_mode_changed(_index: int) -> void:
	_on_path_controls_changed(true)

func _on_path_controls_changed(_value: bool) -> void:
	if _updating or _path_setup == null or _path_selected < 0:
		return
	var start := PathStart.new()
	start.segment_index = int(_path_segment.value)
	for definition: PathDefinition in _path_setup.definitions:
		if definition.path_index == _path_selected and start.segment_index >= 0 and start.segment_index < definition.segments.size():
			start.distance = mini(int(_path_distance.value), definition.segments[start.segment_index].length)
			break
	start.speed = int(_path_speed.value)
	start.flags = (PathStart.ACTIVE if _path_active.button_pressed else 0) | (PathStart.BACKWARDS if _path_backwards.button_pressed else 0)
	if _path_mode.selected == 0:
		start.flags |= PathStart.REPEAT
	elif _path_mode.selected == 2:
		start.flags |= PathStart.ONE_SHOT
	configure_path(_path_selected, start)

func _release_path(detach: bool = true) -> void:
	_path_setup = null
	_path_session.clear()
	_path_selected = -1
	_path_visible = false
	if _path_toggle != null:
		_path_toggle.set_pressed_no_signal(false)
	if _path_choice != null:
		_path_choice.clear()
	if _path_readout != null:
		_path_readout.text = "Inspection settings\nNo path selected"
	if _path_segment != null:
		_updating = true
		_path_segment.set_value_no_signal(0)
		_path_distance.set_value_no_signal(0)
		_path_speed.set_value_no_signal(16)
		_path_active.set_pressed_no_signal(true)
		_path_backwards.set_pressed_no_signal(false)
		_path_mode.select(0)
		_updating = false
		_set_path_controls_enabled(false)
	if _path_inspection != null:
		if detach and _path_inspection.get_parent() == _world:
			_world.remove_child(_path_inspection)
		_path_inspection.queue_free()
		_path_inspection = null

func _set_path_controls_enabled(value: bool) -> void:
	_path_choice.disabled = not value
	_path_segment.editable = value
	_path_distance.editable = value
	_path_speed.editable = value
	_path_active.disabled = not value
	_path_backwards.disabled = not value
	_path_mode.disabled = not value
	_path_toggle.disabled = not value

func _setup_entities() -> void:
	_release_entities()
	if data == null or not data.is_valid() or scene_data == null or scene_data.map == null:
		return
	var source_id: String = FroggerIds.LEVEL_CODES[scene_data.level]
	var row: MapBookEntry = data.map_book_entry(scene_data.level)
	var resource_id: int = row.map_id(scene_data.low_poly) if row != null else -1
	var build_id: String = data.version_name
	var setup: EntitySetup = EntitySetup.from_map(scene_data.map, data.tables.theme_book(), build_id + ":" + source_id, resource_id, build_id)
	if not setup.error.is_empty():
		scene_data.diagnostics.append(setup.error)
		_entity_readout.text = "Base-transform inspection\n" + setup.error
		return
	for diagnostic: EntitySetupDiagnostic in setup.diagnostics:
		scene_data.diagnostics.append(diagnostic.to_text())
	var issue: String = set_entity_definitions(setup.definitions)
	if not issue.is_empty():
		scene_data.diagnostics.append(issue)
	else:
		_entity_setup = setup
		var contact_setup: FormContactSetup = FormContactSetup.from_data(data, scene_data.level, scene_data.low_poly, setup.definitions)
		if not contact_setup.error.is_empty():
			scene_data.diagnostics.append("FORM contact setup: " + contact_setup.error)
		else:
			var preferred_entity_id: int = MapInspectionDefaults.preferred_entity_id(source_id)
			if preferred_entity_id >= 0:
				for item: int in _entity_choice.item_count:
					if _entity_choice.get_item_id(item) == preferred_entity_id:
						_entity_choice.select(item)
						_on_entity_selected(item)
						break
			var contact_issue: String = set_form_contacts(contact_setup.definitions)
			if not contact_issue.is_empty():
				scene_data.diagnostics.append("FORM contact inspection: " + contact_issue)
			for diagnostic: EntitySetupDiagnostic in contact_setup.diagnostics:
				scene_data.diagnostics.append(diagnostic.to_text())
		_entity_readout.tooltip_text = "\n".join(_entity_diagnostic_text())
		_update_entity_readout()

## Injects detached synthetic definitions without replacing map or path controls.
func set_entity_definitions(definitions: Array[EntityDefinition]) -> String:
	_release_entities()
	var issue: String = _entity_session.configure(definitions)
	if not issue.is_empty():
		return issue
	var copies: Array[EntityDefinition] = _entity_session.definitions
	_entity_inspection = EntityInspection.new()
	_world.add_child(_entity_inspection)
	_entity_inspection.configure(copies)
	_entity_choice.clear()
	for definition: EntityDefinition in copies:
		_entity_choice.add_item("%d · %s" % [definition.entity_index, definition.form_name], definition.entity_index)
	_entity_choice.disabled = copies.is_empty()
	_entity_selected = copies[0].entity_index if not copies.is_empty() else -1
	if not copies.is_empty():
		_entity_choice.select(0)
	_entity_toggle.disabled = copies.is_empty()
	_update_entity_visibility()
	_entity_inspection.set_selected(0 if not copies.is_empty() else -1)
	_replay_entities(tick)
	return ""

## Attaches detached FORM facts to the existing entity slots and starts the probe.
func set_form_contacts(definitions: Array[FormContactDefinition], probe: Vector3i = Vector3i.ZERO, place_first: bool = true) -> String:
	if _entity_session.run == null:
		return "Entity run is not attached"
	var aligned: Array[FormContactDefinition] = []
	for entity: EntityDefinition in _entity_session.definitions:
		var found: FormContactDefinition = null
		for candidate: FormContactDefinition in definitions:
			if candidate != null and candidate.entity_index == entity.entity_index:
				found = candidate
				break
		if found == null:
			return "Missing FORM contact for entity %d" % entity.entity_index
		if found.unique_id != entity.unique_id or found.form_grid_id != entity.form_grid_id or found.form_id != entity.form_id or found.entity_flags != entity.flags:
			return "FORM contact identity differs for entity %d" % entity.entity_index
		aligned.append(found.copy())
	_form_contacts = aligned
	_form_probe_world = probe
	if _entity_inspection != null:
		_entity_inspection.configure_contacts(_form_contacts)
		_entity_inspection.set_selected(_selected_entity_slot())
		_entity_inspection.set_snapshot(entity_snapshot())
	if place_first:
		_place_form_probe_first_cell()
	else:
		_sync_form_probe_spins()
		_update_form_contact()
	return ""

## Returns one detached contact result for the selected entity and fixed probe.
func selected_form_contact() -> FormContactResult:
	var slot: int = _selected_entity_slot()
	var snapshot: EntityRunSnapshot = entity_snapshot()
	if slot < 0 or slot >= _form_contacts.size() or snapshot == null or slot >= snapshot.entities.size():
		return null
	return FormContactQuery.query(_form_contacts[slot], snapshot.entities[slot], _form_probe_world)

func _selected_entity_slot() -> int:
	for index: int in _entity_session.definitions.size():
		if _entity_session.definitions[index].entity_index == _entity_selected:
			return index
	return -1

func _on_form_probe_changed(_value: float) -> void:
	if _form_probe_spins.size() != 3:
		return
	_form_probe_world = Vector3i(int(_form_probe_spins[0].value), int(_form_probe_spins[1].value), int(_form_probe_spins[2].value))
	_update_form_contact()

func _sync_form_probe_spins() -> void:
	if _form_probe_spins.size() != 3:
		return
	_form_probe_spins[0].set_value_no_signal(_form_probe_world.x)
	_form_probe_spins[1].set_value_no_signal(_form_probe_world.y)
	_form_probe_spins[2].set_value_no_signal(_form_probe_world.z)

func _place_form_probe_first_cell() -> void:
	var slot: int = _selected_entity_slot()
	var snapshot: EntityRunSnapshot = entity_snapshot()
	if slot < 0 or slot >= _form_contacts.size() or snapshot == null or slot >= snapshot.entities.size():
		return
	_form_probe_world = EntityScenario._first_cell_world(_form_contacts[slot], snapshot.entities[slot])
	_sync_form_probe_spins()
	_update_form_contact()

func _update_form_contact() -> void:
	if _entity_inspection != null:
		_entity_inspection.set_contact(_form_probe_world, selected_form_contact())
	_update_entity_readout()

## Returns source-located setup messages without exposing mutable map records.
func entity_diagnostics() -> Array[EntitySetupDiagnostic]:
	var detached: Array[EntitySetupDiagnostic] = []
	if _entity_setup != null:
		for diagnostic: EntitySetupDiagnostic in _entity_setup.diagnostics:
			detached.append(diagnostic.copy())
	return detached

func _entity_diagnostic_text() -> PackedStringArray:
	var lines := PackedStringArray()
	if _entity_setup != null:
		for diagnostic: EntitySetupDiagnostic in _entity_setup.diagnostics:
			lines.append(diagnostic.to_text())
	return lines

## Returns a detached observation of every attached entity at the shared tick.
func entity_snapshot() -> EntityRunSnapshot:
	return _entity_session.snapshot()

## Controls marker visibility without changing entity state.
func set_entity_visibility(value: bool) -> void:
	_entity_visible = value
	_entity_toggle.set_pressed_no_signal(value)
	_update_entity_visibility()

func _update_entity_visibility() -> void:
	if _entity_inspection != null:
		_entity_inspection.visible = _entity_visible and camera_preset != "map-slice"

func _replay_entities(target_tick: int) -> void:
	if _entity_session.run == null:
		_update_entity_readout()
		return
	var issue: String = _entity_session.seek(target_tick)
	if not issue.is_empty():
		_entity_failure(issue)
	if _entity_inspection != null:
		_entity_inspection.set_snapshot(entity_snapshot())
	_update_form_contact()

func _step_entities(previous_tick: int) -> void:
	if _entity_session.run == null:
		return
	var issue: String = _entity_session.step(previous_tick)
	if not issue.is_empty():
		_entity_failure(issue)
	if _entity_inspection != null:
		_entity_inspection.set_snapshot(entity_snapshot())
	_update_form_contact()

func _entity_failure(issue: String) -> void:
	set_playing(false)
	var committed: EntityRunSnapshot = entity_snapshot()
	if committed != null:
		tick = committed.tick_index
		if map_instance != null:
			map_instance.set_tick(tick)
	if scene_data != null:
		scene_data.diagnostics.append("Entity run: " + issue)

func _update_entity_readout() -> void:
	if _entity_readout == null:
		return
	var snapshot: EntityRunSnapshot = entity_snapshot()
	if snapshot == null or _entity_selected < 0:
		var count: int = _entity_setup.diagnostics.size() if _entity_setup != null else 0
		_entity_readout.text = "Base-transform inspection\nNo supported entities\n%d diagnostics (hover)" % count
		if _entity_contact_readout != null:
			_entity_contact_readout.text = "FORM point contact · no reaction\nNo contact probe attached"
		return
	for index: int in _entity_session.definitions.size():
		var definition: EntityDefinition = _entity_session.definitions[index]
		if definition.entity_index != _entity_selected:
			continue
		var entity: EntitySnapshot = snapshot.entities[index]
		var path_text: String = "Static transform"
		if entity.path != null:
			path_text = "Path %d · segment %d · distance %d/%d\nSpeed %d · cursor flags 0x%X" % [definition.path_definition.path_index, entity.path.segment_index, entity.path.segment_distance, entity.path.segment_length, entity.path.speed, entity.path.flags]
		var labels := PackedStringArray()
		if definition.flags & EntityDefinition.HIDDEN:
			labels.append("hidden")
		if definition.flags & EntityDefinition.NO_DISPLAY:
			labels.append("no display")
		if definition.flags & EntityDefinition.NO_COLLISION:
			labels.append("no collision")
		if definition.flags & EntityDefinition.NO_MOVEMENT:
			labels.append("no movement")
		if definition.flags & EntityDefinition.ALIGN_TO_WORLD:
			labels.append("world align")
		var flags_text: String = "none" if labels.is_empty() else ", ".join(labels)
		var diagnostic_count: int = _entity_setup.diagnostics.size() if _entity_setup != null else 0
		var title: String = "FORM contact inspection" if not _form_contacts.is_empty() else "Base-transform inspection"
		var hooks: String = "Scripts/callbacks/reactions unexecuted" if not _form_contacts.is_empty() else "Scripts/callbacks unexecuted"
		_entity_readout.text = "%s\n%s · %s · id %d\n%s (0x%X) · tick %d\n%s\nPosition %d, %d, %d\n%s\n%d diagnostics (hover)" % [title, definition.form_name, definition.entity_name, entity.unique_id, flags_text, definition.flags, snapshot.tick_index, path_text, entity.matrix12[9], entity.matrix12[10], entity.matrix12[11], hooks, diagnostic_count]
		var contact: FormContactResult = selected_form_contact()
		if _entity_contact_readout != null:
			_entity_contact_readout.text = "FORM contact inspection · point only\nReactions/scripts unexecuted"
			if contact != null:
				_entity_contact_readout.text += "\nProbe %d, %d, %d: %s" % [_form_probe_world.x, _form_probe_world.y, _form_probe_world.z, contact.status]
				if contact.status == FormContactResult.CONTACT:
					_entity_contact_readout.text += "\nCell %d, %d · flags 0x%X" % [contact.cell.x, contact.cell.y, contact.cell_flags]
				elif not contact.reason.is_empty():
					_entity_contact_readout.text += "\n" + contact.reason
			else:
				_entity_contact_readout.text += "\nNo contact grid attached"
		return

func _on_entity_selected(item: int) -> void:
	_entity_selected = _entity_choice.get_item_id(item)
	if _entity_inspection != null:
		_entity_inspection.set_selected(item)
		_entity_inspection.set_snapshot(entity_snapshot())
	_update_form_contact()

func _release_entities(detach: bool = true) -> void:
	_entity_setup = null
	_entity_session.clear()
	_form_contacts.clear()
	_form_probe_world = Vector3i.ZERO
	_sync_form_probe_spins()
	_entity_selected = -1
	_entity_visible = false
	if _entity_toggle != null:
		_entity_toggle.set_pressed_no_signal(false)
		_entity_toggle.disabled = true
	if _entity_choice != null:
		_entity_choice.clear()
		_entity_choice.disabled = true
	if _entity_readout != null:
		_entity_readout.text = "Base-transform inspection\nNo entities attached"
		_entity_readout.tooltip_text = ""
	if _entity_contact_readout != null:
		_entity_contact_readout.text = "FORM point contact · no reaction\nNo contact probe attached"
	if _entity_inspection != null:
		if detach and _entity_inspection.get_parent() == _world:
			_world.remove_child(_entity_inspection)
		_entity_inspection.queue_free()
		_entity_inspection = null

func _run_path_scenario() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = ViewerArguments.value(arguments, "--screenshot-dir=")
	var trace_path: String = ViewerArguments.value(arguments, "--trace-jsonl=")
	if not _external_capture_folder(folder) or not ViewerCapture.external_folder(trace_path.get_base_dir()):
		_fail_path_run("Path output requires absolute external destinations")
		return
	var scenario_file: String = ViewerArguments.value(arguments, "--scenario-file=")
	var selected: String = ViewerArguments.value(arguments, "--scenario=")
	var scenario: PathScenario = PathScenario.from_file(scenario_file) if not scenario_file.is_empty() else PathScenario.builtin(selected if not selected.is_empty() else "line")
	if not scenario.error.is_empty():
		_fail_path_run(scenario.error)
		return
	var limit_text: String = ViewerArguments.value(arguments, "--tick-limit=")
	if not limit_text.is_empty():
		if not limit_text.is_valid_int() or limit_text.to_int() < 0 or limit_text.to_int() > 100000:
			_fail_path_run("Path tick limit must be in 0..100000")
			return
		scenario.tick_limit = limit_text.to_int()
	var rate_text: String = ViewerArguments.value(arguments, "--render-rate=")
	var render_rate: int = 60 if rate_text.is_empty() else rate_text.to_int()
	if render_rate not in [30, 60, 144]:
		_fail_path_run("Path render rate must be 30, 60 or 144")
		return
	var level_code: String = ViewerArguments.value(arguments, "--level=")
	var path_index_text: String = ViewerArguments.value(arguments, "--path-index=")
	if not level_code.is_empty():
		if not path_index_text.is_valid_int() or path_index_text.to_int() < 0:
			_fail_path_run("A level path requires --path-index=0 or greater")
			return
		open_data(ImportedAssets.open(), true)
		if data == null or not data.is_valid():
			_fail_path_run(data.error if data != null else "No game data")
			return
		var attach_error: String = scenario.attach_data(data, level_code, path_index_text.to_int())
		if not attach_error.is_empty():
			_fail_path_run(attach_error)
			return
		if not load_level_by_code(level_code):
			_fail_path_run(_status.text)
			return
		if not configure_path(path_index_text.to_int(), scenario.start):
			_fail_path_run("Cannot start selected map path")
			return
		_frame_path(scenario.definition)
	elif not path_index_text.is_empty():
		_fail_path_run("--path-index requires --level")
		return
	else:
		if not show_scene(_synthetic_path_scene()):
			_fail_path_run(_status.text)
			return
		_path_setup = PathSetup.new()
		_path_setup.definitions.append(scenario.definition.copy())
		_path_inspection = PathInspection.new()
		_world.add_child(_path_inspection)
		_path_choice.add_item("Synthetic path", scenario.definition.path_index)
		if not configure_path(scenario.definition.path_index, scenario.start):
			_fail_path_run("Cannot start synthetic path")
			return
		_frame_path(scenario.definition)
	set_path_visibility(true)
	var trace := PathTrace.new()
	trace.configure(scenario)
	trace.append_snapshot(path_snapshot())
	set_process(false)
	set_playing(true)
	var frames: int = 0
	var frame_cap: int = ceili(float(scenario.tick_limit + 1) * float(render_rate) / 30.0) + render_rate
	while tick < scenario.tick_limit and frames < frame_cap:
		var before: int = tick
		_process(1.0 / float(render_rate))
		if tick > before:
			if tick != before + 1 or path_snapshot() == null or path_snapshot().tick_index != tick:
				_fail_path_run("Path render schedule advanced more than one tick")
				return
			trace.append_snapshot(path_snapshot())
		elif not playing:
			_fail_path_run("Path update stopped at tick %d" % tick)
			return
		frames += 1
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	set_playing(false)
	if tick != scenario.tick_limit:
		_fail_path_run("Path render schedule did not reach tick %d" % scenario.tick_limit)
		return
	var trace_error: String = trace.save(trace_path)
	if not trace_error.is_empty():
		_fail_path_run(trace_error)
		return
	var capture_error: String = ViewerCapture.prepare_folder(folder)
	if not capture_error.is_empty():
		_fail_path_run(capture_error)
		return
	_ui.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	capture_error = ViewerCapture.save_image(_viewport.get_texture().get_image(), folder.path_join("path_tick%d.png" % tick))
	if not capture_error.is_empty():
		_fail_path_run(capture_error)
		return
	_ui.visible = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	capture_error = ViewerCapture.save_image(get_viewport().get_texture().get_image(), folder.path_join("path_controls.png"))
	if not capture_error.is_empty():
		_fail_path_run(capture_error)
		return
	print("path_viewer: %s, %d ticks, next tick %d" % [scenario.name, scenario.tick_limit, path_snapshot().tick_index])
	get_tree().quit(0)

func _synthetic_path_scene() -> MapSceneData:
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

## Frames sampled synthetic geometry in the ordinary inspection projection.
func _frame_path(definition: PathDefinition) -> void:
	var found: bool = false
	var minimum := Vector3i.ZERO
	var maximum := Vector3i.ZERO
	for segment: PathSegmentDefinition in definition.segments:
		for sample_index: int in 17:
			var distance: int = roundi(float(segment.length) * float(sample_index) / 16.0)
			var sample: PathSample = PathEvaluator.sample(segment, distance)
			if not sample.error.is_empty():
				continue
			if not found:
				minimum = sample.position
				maximum = sample.position
				found = true
			else:
				minimum = Vector3i(mini(minimum.x, sample.position.x), mini(minimum.y, sample.position.y), mini(minimum.z, sample.position.z))
				maximum = Vector3i(maxi(maximum.x, sample.position.x), maxi(maximum.y, sample.position.y), maxi(maximum.z, sample.position.z))
	if not found:
		return
	@warning_ignore("integer_division")
	var midpoint: Vector3i = Vector3i((minimum.x + maximum.x) / 2, (minimum.y + maximum.y) / 2, (minimum.z + maximum.z) / 2)
	var span: int = maxi(64, maxi(maximum.x - minimum.x, maxi(maximum.y - minimum.y, maximum.z - minimum.z)))
	set_camera_pose(midpoint + Vector3i(0, -span, -span * 2), midpoint, 256)

func _fail_path_run(message: String) -> void:
	push_error(message)
	get_tree().quit(1)

func _run_entity_scenario() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = ViewerArguments.value(arguments, "--screenshot-dir=")
	var trace_path: String = ViewerArguments.value(arguments, "--trace-jsonl=")
	if not _external_capture_folder(folder) or not ViewerCapture.external_folder(trace_path.get_base_dir()):
		_fail_path_run("Entity output requires absolute external destinations")
		return
	var selected: String = ViewerArguments.value(arguments, "--scenario=")
	var scenario: EntityScenario = EntityScenario.builtin(selected if not selected.is_empty() else "shared-path")
	if not scenario.error.is_empty():
		_fail_path_run(scenario.error)
		return
	var limit_text: String = ViewerArguments.value(arguments, "--tick-limit=")
	if not limit_text.is_empty():
		if not limit_text.is_valid_int() or limit_text.to_int() < 0 or limit_text.to_int() > 100000:
			_fail_path_run("Entity tick limit must be in 0..100000")
			return
		scenario.tick_limit = limit_text.to_int()
	var rate_text: String = ViewerArguments.value(arguments, "--render-rate=")
	var render_rate: int = 60 if rate_text.is_empty() else rate_text.to_int()
	if render_rate not in [30, 60, 144]:
		_fail_path_run("Entity render rate must be 30, 60 or 144")
		return
	var level_code: String = ViewerArguments.value(arguments, "--level=")
	if not level_code.is_empty():
		open_data(ImportedAssets.open(), true)
		if data == null or not data.is_valid():
			_fail_path_run(data.error if data != null else "No game data")
			return
		var attach_error: String = scenario.attach_data(data, level_code)
		if not attach_error.is_empty():
			_fail_path_run(attach_error)
			return
		if not load_level_by_code(level_code):
			_fail_path_run(_status.text)
			return
		if _entity_session.run == null or _entity_setup == null:
			_fail_path_run("Entity setup did not attach the selected map")
			return
	else:
		if not show_scene(_synthetic_path_scene()):
			_fail_path_run(_status.text)
			return
		_frame_path(scenario.definitions[1].path_definition)
		var attach_issue: String = set_entity_definitions(scenario.definitions)
		if not attach_issue.is_empty():
			_fail_path_run(attach_issue)
			return
	var contact_issue: String = set_form_contacts(scenario.contact_definitions, scenario.probe_world, false)
	if not contact_issue.is_empty():
		_fail_path_run(contact_issue)
		return
	for index: int in _entity_choice.item_count:
		if _entity_choice.get_item_id(index) == scenario.contact_entity_index:
			_entity_choice.select(index)
			_on_entity_selected(index)
			break
	set_entity_visibility(true)
	_inspection_tabs.current_tab = 1
	var trace := EntityTrace.new()
	trace.configure(scenario)
	trace.append_snapshot(entity_snapshot())
	set_process(false)
	set_playing(true)
	var frames: int = 0
	var frame_cap: int = ceili(float(scenario.tick_limit + 1) * float(render_rate) / 30.0) + render_rate
	while tick < scenario.tick_limit and frames < frame_cap:
		var before: int = tick
		_process(1.0 / float(render_rate))
		if tick > before:
			if tick != before + 1 or entity_snapshot() == null or entity_snapshot().tick_index != tick:
				_fail_path_run("Entity render schedule advanced more than one tick")
				return
			trace.append_snapshot(entity_snapshot())
		elif not playing:
			_fail_path_run("Entity update stopped at tick %d" % tick)
			return
		frames += 1
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	set_playing(false)
	if tick != scenario.tick_limit:
		_fail_path_run("Entity render schedule did not reach tick %d" % scenario.tick_limit)
		return
	var save_issue: String = trace.save(trace_path)
	if not save_issue.is_empty():
		_fail_path_run(save_issue)
		return
	var capture_issue: String = ViewerCapture.prepare_folder(folder)
	if not capture_issue.is_empty():
		_fail_path_run(capture_issue)
		return
	_ui.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	capture_issue = ViewerCapture.save_image(_viewport.get_texture().get_image(), folder.path_join("entity_tick%d.png" % tick))
	if not capture_issue.is_empty():
		_fail_path_run(capture_issue)
		return
	_ui.visible = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	capture_issue = ViewerCapture.save_image(get_viewport().get_texture().get_image(), folder.path_join("entity_controls.png"))
	if not capture_issue.is_empty():
		_fail_path_run(capture_issue)
		return
	print("entity_viewer: %s, %d ticks, next tick %d" % [scenario.name, scenario.tick_limit, entity_snapshot().tick_index])
	get_tree().quit(0)

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
	await MapCaptureSession.capture(self, folder)

## Returns the current rendered map image after the caller awaits frame completion.
func capture_image() -> Image:
	return _viewport.get_texture().get_image()

## Names a capture from the selected rendering inputs.
func capture_basename() -> String:
	var code: String = FroggerIds.LEVEL_CODES[scene_data.level].to_lower()
	return "map_%s_%s_%s_tick%d_%s" % [code, "low" if scene_data.low_poly else "high", camera_preset, tick, "linear" if linear_filter else "nearest"]

## Supplies rendering facts to the external capture workflow.
func capture_metadata(benchmark: Dictionary, allocations_before: Dictionary, allocations_after: Dictionary) -> Dictionary:
	var code: String = FroggerIds.LEVEL_CODES[scene_data.level].to_lower()
	var rendered: Dictionary[String, int] = capture_render_counts()
	var resource: int = data.map_book_entry(scene_data.level).map_id(scene_data.low_poly)
	var machine: Dictionary = {"processor_name": OS.get_processor_name(), "processor_count": OS.get_processor_count(), "os": OS.get_name(), "os_version": OS.get_version(), "renderer_device": RenderingServer.get_video_adapter_name()}
	if OS.has_method("get_memory_info"):
		var memory_info: Dictionary = OS.call("get_memory_info")
		machine["memory_info"] = memory_info
	var metadata: Dictionary = {"machine": machine, "level": code, "resource_id": resource, "low_poly": scene_data.low_poly, "camera": camera_preset, "tick": tick, "linear": linear_filter, "render_width": 640, "render_height": 480, "load_build_ms": load_build_ms, "decode_load_ms": decode_load_ms, "mesh_build_ms": mesh_build_ms, "instance_build_ms": instance_build_ms, "allocations_before": allocations_before, "allocations_after": allocations_after, "allocation_growth": allocations_before["mesh_ids"] != allocations_after["mesh_ids"] or allocations_before["material_ids"] != allocations_after["material_ids"] or allocations_before["page_texture_ids"] != allocations_after["page_texture_ids"] or allocations_before["sky_atlas_id"] != allocations_after["sky_atlas_id"], "page_texture_growth": allocations_before["page_texture_ids"] != allocations_after["page_texture_ids"], "triangles": rendered["triangles"], "groups": rendered["groups"], "surfaces": rendered["surfaces"], "available_triangles": current_mesh.triangle_count, "static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "peak_static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC_MAX), "resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED), "render_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "render_primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "probe_model": _probe_name, "camera_source_game": _vector_array(GameSpace.to_game(_camera.position)), "camera_target_game": _vector_array(GameSpace.to_game(_target)), "projection_distance": _projection_distance, "nominal_projection": _projection_distance, "effective_projection": _projection_distance * _projection_scale, "projection_scale": _projection_scale, "effective_projection_x": _projection_distance * _projection_scale, "effective_projection_y": _projection_distance * _projection_scale * _vertical_ratio, "clip_scale": [1.0, _vertical_ratio], "custom_camera": _custom_camera, "diagnostics": Array(_combined_diagnostics())}
	metadata.merge(benchmark)
	return metadata

## Capture outputs must use an absolute folder outside the source checkout.
static func _external_capture_folder(folder: String) -> bool:
	return ViewerCapture.external_folder(folder)

static func _arg(prefix: String) -> String:
	return ViewerArguments.value(OS.get_cmdline_user_args(), prefix)


## Counts the current visible rendering resources.
func capture_render_counts() -> Dictionary[String, int]:
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
	_release_path(detach)
	_release_entities(detach)
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


## Returns resource identities for capture allocation comparisons.
func capture_allocations() -> Dictionary:
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

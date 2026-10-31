class_name TerrainViewer
extends GameplayWorldView
## Synthetic terrain driver. Scene input, clocks and drawing consume the same pure run API.

var auto_open: bool = true
var scenario: TerrainScenario
var run: GameplayRun
var replay_commands: bool = true
## Capture is opt-in so an interactive session does not accumulate an unbounded trace.
var record_trace: bool = false
var trace: TerrainTrace
var last_error: String = ""
var data: AssetCatalog
var _owns_data: bool = false
var _held: int = 0
var _label: Label
var _outcomes: PackedStringArray = PackedStringArray()
var _entity_inspection: EntityInspection
var _last_contacts: Array[FormReactionResult] = []
var _last_primitive_contacts: Array[EntityPrimitiveContact] = []
var _full_trace_destination: String = ""
var _host: GameplayHost = GameplayHost.new()
var _host_step: bool = false
var _overlay_key: Array = []
var threaded_playback: bool = false
var last_tick_usec: int = 0
var _performance_started_usec: int = 0
var _performance_frames: int = 0
var _performance_text: String = "FPS measuring…"

func _ready() -> void:
	_build_scene()
	if auto_open:
		var arguments: PackedStringArray = OS.get_cmdline_user_args()
		configure_input(arguments)
		record_trace = ViewerArguments.has_prefix(arguments, "--trace-csv=") or ViewerArguments.has_prefix(arguments, "--trace-jsonl=")
		_full_trace_destination = ViewerArguments.value(arguments, "--trace-jsonl=")
		var path: String = ViewerArguments.value(arguments, "--scenario-file=")
		var name_arg: String = ViewerArguments.value(arguments, "--scenario=")
		var selected: TerrainScenario = TerrainScenario.from_file(path) if not path.is_empty() else TerrainScenario.builtin(name_arg if not name_arg.is_empty() else "normal")
		if selected.error.is_empty():
			selected.error = TerrainScenarioArguments.apply(selected, arguments)
		open_scenario(selected)
		if ViewerArguments.has_prefix(arguments, "--data-dir=") or not OS.get_environment("FROGGER_DATA_DIR").is_empty():
			var found: GameDataLocator.Located = ViewerArguments.locate_data(arguments)
			if found.is_ok():
				selected.level_code = ViewerArguments.value(arguments, "--level=")
				open_data(GameData.open(found.source, found.version), true)
			else:
				last_error = found.error
		if ViewerArguments.has_flag(arguments, "--run-scenario"):
			_capture_scenario.call_deferred(arguments)

func _exit_tree() -> void:
	_close_worker()
	_clear_entity_visuals()
	if _owns_data and data != null:
		data.close()
	data = null
	_owns_data = false

## Direct map exploration uses live controls; explicit fixtures and captures replay.
func configure_input(arguments: PackedStringArray) -> void:
	threaded_playback = not ViewerArguments.has_flag(arguments, "--run-scenario") and ViewerArguments.value(arguments, "--threaded=") != "false"
	smoothing = ViewerArguments.value(arguments, "--smoothing=") != "false" and not ViewerArguments.has_flag(arguments, "--run-scenario")
	if ViewerArguments.value(arguments, "--smoothing=") == "true":
		smoothing = true
	replay_commands = ViewerArguments.value(arguments, "--level=").is_empty() \
		or ViewerArguments.has_flag(arguments, "--run-scenario") \
		or ViewerArguments.has_prefix(arguments, "--scenario=") \
		or ViewerArguments.has_prefix(arguments, "--scenario-file=")

## Loads optional frog presentation; callers retain borrowed data until this viewer detaches.
func open_data(selected: AssetCatalog, take_ownership: bool = false) -> String:
	_close_worker()
	_projection_size = Vector2i.ZERO
	_clear_entity_visuals()
	if data != selected:
		if _owns_data and data != null:
			data.close()
		_owns_data = take_ownership
	elif take_ownership:
		_owns_data = true
	data = selected
	if selected == null:
		_owns_data = false
	if _frog_model != null:
		remove_child(_frog_model)
		_frog_model.queue_free()
		_frog_model = null
	frog_assets = null
	if scenario != null:
		scenario.frog_assets = null
	if scenario != null and scenario.map_scene != null:
		scenario.map_scene = null
		run = null
		_current = null
		_previous = null
		playing = false
		_map_instance = null
		_label.text = "No terrain source attached"
		_frog.visible = false
		for child: Node in _ground.get_children():
			_ground.remove_child(child)
			child.queue_free()
	if selected == null:
		last_error = ""
		_frog.visible = run != null
		return ""
	frog_assets = TerrainFrogAssets.from_data(data)
	last_error = frog_assets.error
	if not last_error.is_empty():
		_frog.visible = run != null
		return last_error
	if scenario != null:
		last_error = scenario.attach_data(data, scenario.level_code, frog_assets)
		if last_error.is_empty():
			last_error = open_scenario(scenario)
		if not last_error.is_empty():
			return last_error
	build_frog(frog_assets)
	_build_entity_visuals()
	draw_state(1.0)
	return ""

## Replaces the debug scenario and collapses interpolation to its exact initial state.
func open_scenario(selected: TerrainScenario) -> String:
	if selected == null or not selected.error.is_empty():
		last_error = "Missing scenario" if selected == null else selected.error
		playing = false
		return last_error
	var replacement: GameplayRun = GameplayRun.create(selected.level, selected.initial)
	last_error = replacement.error
	if not last_error.is_empty():
		playing = false
		return last_error
	scenario = selected
	_close_worker()
	run = replacement
	_host.open(run)
	trace = TerrainTrace.new()
	trace.configure(selected)
	if not _full_trace_destination.is_empty():
		last_error = trace.stream_full(_full_trace_destination)
		if not last_error.is_empty():
			return last_error
	playing = false
	_host.elapsed = 0.0
	_host.render_elapsed = 0.0
	_overlay_key.clear()
	_held = 0
	_host.sampled_held = 0
	_current = run.snapshot()
	_previous = _current
	_motion.capture(_current, _current)
	_frog_pose_tick = -1
	_entity_pose_tick = -1
	_outcomes.clear()
	_last_contacts.clear()
	_last_primitive_contacts.clear()
	if _ground != null:
		_build_terrain()
		_build_entity_visuals()
		draw_state(1.0)
	return ""

## Advances exactly one command; used by interactive stepping and automated scene tests.
func step_command(command: TickCommand, capture_phases: bool = true) -> TickResult:
	_finish_pending()
	_close_worker()
	if run == null:
		var rejected := TickResult.new()
		rejected.error = "Open a terrain scenario before stepping"
		return rejected
	var result: TickResult = _host.step(command, capture_phases or record_trace)
	last_tick_usec = _host.last_tick_usec
	_accept_result(command, result)
	return result

func _accept_result(command: TickCommand, result: TickResult) -> void:
	last_error = result.error
	if last_error.is_empty():
		_previous = _current
		_current = result.final_snapshot if _host_step else run.snapshot()
		_outcomes = PackedStringArray(TickEvent.trace_lines(result.events))
		_last_contacts.clear()
		for contact: FormReactionResult in result.entity_contacts:
			_last_contacts.append(contact.copy())
		_last_primitive_contacts.clear()
		for contact: EntityPrimitiveContact in result.primitive_contacts:
			_last_primitive_contacts.append(contact.copy())
		var created: PackedInt32Array = _sync_entity_models()
		for slot: int in _entity_models.size():
			var model: AnimatedModelInstance = _entity_models[slot]
			if model != null and not created.has(slot):
				model.player.advance_tick()
		if record_trace:
			trace.append_result(scenario.scenario_index, command, result)
	else:
		playing = false
	if _current.completed:
		playing = false
	if not playing:
		reset_interpolation()
	_motion.capture(_previous, _current)
	_host.render_elapsed = 0.0
	if not _host_step:
		_host.elapsed = 0.0
		draw_state(1.0)

## Replays the authored command at the run's next tick, without polling input.
func step_scenario() -> TickResult:
	_finish_pending()
	return step_command(scenario.command_at(_current.tick_index), record_trace)

## Samples the host's collected button state once at the command boundary.
func step_live() -> TickResult:
	_finish_pending()
	return step_command(_live_command(), record_trace)

func _live_command() -> TickCommand:
	return _host.sample(_current.tick_index, _held)

## Clears scenario state, pending input and presentation clocks without reusing mutable snapshots.
func reset_scenario() -> String:
	return open_scenario(scenario)

## Collapses all presentation histories after pause, seek, teleport or source replacement.
func reset_interpolation() -> void:
	if _current == null:
		return
	_previous = _current
	_motion.capture(_current, _current)
	_host.render_elapsed = 0.0
	if _frog_model != null:
		_frog_model.smoothing_enabled = smoothing
		_frog_model.apply_exact()
	for model: AnimatedModelInstance in _entity_models:
		if model != null:
			model.smoothing_enabled = smoothing
			model.apply_exact()

## Draws only detached state; changing interpolation never advances rules.
func draw_state(fraction: float) -> void:
	if _current == null or _frog == null:
		return
	var update_entities: bool = _entity_pose_tick != _current.tick_index
	var weight: float = clampf(fraction, 0.0, 1.0) if smoothing else 1.0
	super.draw_state(fraction)
	if update_entities and _entity_inspection != null and _current.entities != null:
		var selected_index: int = _selected_contact_index()
		_entity_inspection.set_selected(selected_index)
		_entity_inspection.set_snapshot(_current.entities)
		var hit_contact: FormContactResult = null
		for reaction: FormReactionResult in _last_contacts:
			if reaction.contact != null and scenario.level.entity_collision != null and selected_index >= 0 and reaction.contact.entity_index == scenario.level.entity_collision.entities[selected_index].entity_index:
				hit_contact = reaction.contact
				break
		_entity_inspection.set_contact(_current.frog.world_position, hit_contact)
	if smoothing and _entity_inspection != null and _entity_inspection.visible and _current.entities != null:
		_entity_inspection.draw_motion(_motion, weight)
	var overlay_key: Array = [_current.tick_index, playing, replay_commands, last_error, scenario, _projection_size, _performance_text]
	if overlay_key == _overlay_key:
		return
	_overlay_key = overlay_key
	var presentation: String = "synthetic marker" if _frog_model == null else "high-detail frog"
	_label.text = "TERRAIN INSPECTION %s | %s\n" % [presentation, scenario.identifier] + GameplayStateFacts.frog_lines(_current, _outcomes)
	if scenario.options.entity_reactions:
		if scenario.options.entity_lifecycle and _current.entities != null:
			var selected: PackedInt32Array = _current.entities.selected_groups
			var subjects := PackedStringArray()
			for slot: int in mini(3, _current.entities.entities.size()):
				var subject: EntitySnapshot = _current.entities.entities[slot]
				subjects.append("#%d support=%s live=%s pending=%s gen=%d" % [subject.entity_index, str(subject.lifecycle_supported), str(subject.live), str(subject.destroy_pending), subject.generation])
			_label.text += "live %d | groups %d %s | events %s\n%s\n" % [_current.entities.live_order.size(), selected.size(), selected.slice(0, mini(4, selected.size())), TickEvent.trace_lines(_current.entities.lifecycle_events.slice(0, 3)), "; ".join(subjects)]
		if scenario.options.platforms_enabled:
			_label.text += "platform %d | local cell %s | carrying %s\n" % [_current.attachment.current_entity_index, _current.attachment.entity_cell, _current.attachment.entity_carry_indices]
		var contact_lines := PackedStringArray()
		var nearby_count: int = _last_contacts.size()
		for reaction: FormReactionResult in _last_contacts:
			if reaction.status != FormReactionResult.NONE or (reaction.contact != null and reaction.contact.status == FormContactResult.CONTACT):
				contact_lines.append("%s #%d %s" % [reaction.status, reaction.contact.entity_index if reaction.contact != null else -1, reaction.reason])
		for contact: EntityPrimitiveContact in _last_primitive_contacts:
			if contact.status == EntityPrimitiveQuery.CONTACT:
				contact_lines.append("cuboid #%d | frog part %d point %d" % [contact.entity_index, contact.frog_part_index, contact.hilite_index])
		var visible: PackedStringArray = contact_lines.slice(0, 2)
		_label.text += "entity hits %s | death entity %d | nearby %d\ncontacts %s" % [_current.attachment.entity_hit_indices, _current.attachment.death_entity_index, nearby_count, "; ".join(visible)]
		if contact_lines.size() > visible.size():
			_label.text += " (+%d)" % (contact_lines.size() - visible.size())
		_label.text += "\n"
		_label.tooltip_text = "\n".join(contact_lines) + "\n" + "\n".join(scenario.diagnostics)
	if scenario.level.tick_guard != null:
		var bounds: Rect2i = (scenario.level.tick_guard as ExplorationGuard).world_bounds
		var overlay: Dictionary[String, String] = TerrainCaptureStages.overlay(scenario)
		var title: String = overlay.title
		_label.text = title + "\ntick %d | cell %s | platform %d\n" % [_current.tick_index, _current.frog.cell, _current.attachment.current_entity_index]
		_label.text += "World X[%d,%d), Z[%d,%d)\n" % [bounds.position.x, bounds.end.x, bounds.position.y, bounds.end.y]
		_label.text += "Visibility lifetime | pink frog pickup and riding\n" if scenario.options.entity_lifecycle else "All-attached lifetime | active camera zones unsupported\n"
		_label.text += overlay.instructions
		if overlay.detail == "road":
			_label.text += "death %d | vehicle %d | hits %s\n" % [_current.frog.death_equate, _current.attachment.death_entity_index, _current.attachment.entity_hit_indices]
			for contact: EntityPrimitiveContact in _last_primitive_contacts:
				if contact.status == EntityPrimitiveQuery.CONTACT:
					_label.text += "cuboid #%d | frog part %d point %d\n" % [contact.entity_index, contact.frog_part_index, contact.hilite_index]
	if scenario.level.flow_enabled:
		var checkpoint_count: int = 0
		for checkpoint: int in 5:
			if _current.entity_environment != null and _current.entity_environment.collected & (1 << checkpoint):
				checkpoint_count += 1
		var phase_name: String = LevelFlowState.Phase.keys()[_current.flow.phase]
		var level_name: String = FroggerIds.level_code(scenario.map_scene.level) if scenario.map_scene != null else scenario.level_code
		_label.text = "%s | %s\nScore %d | Time %d | Lives %d | Checkpoints %d/5\n" % [level_name, phase_name, _current.flow.score, ceili(_current.flow.remaining_time / 30.0), _current.frog.lives, checkpoint_count]
	var input_status: String = "REPLAY" if replay_commands else "LIVE"
	input_status += " | running" if playing else " | paused"
	if _current.completed:
		input_status += " | run ended: R resets"
	elif replay_commands and _current.tick_index >= scenario.tick_limit:
		input_status += " | replay finished: Tab selects live input"
	_label.text += input_status + "\n" + _performance_text + "\nSpace play/pause | . step | R reset | I interpolate\nArrows hop | Shift super hop | Ctrl tongue | Q/E camera | Tab replay/live\n" + last_error

func _process(delta: float) -> void:
	if run == null or _current == null:
		return
	var now_usec: int = Time.get_ticks_usec()
	if _performance_started_usec == 0:
		_performance_started_usec = now_usec
	else:
		_performance_frames += 1
		var elapsed_usec: int = now_usec - _performance_started_usec
		if elapsed_usec >= 500000:
			var frame_ms: float = float(elapsed_usec) / float(_performance_frames) / 1000.0
			_performance_text = "FPS %.1f | frame %.1f ms | last simulation tick %.1f ms" % [1000.0 / frame_ms, frame_ms, last_tick_usec / 1000.0]
			_performance_started_usec = now_usec
			_performance_frames = 0
	_host.begin_frame(delta)
	var completed: TickResult = _host.poll()
	if completed != null:
		last_tick_usec = _host.last_tick_usec
		_host_step = true
		_accept_result(_host.pending_command, completed)
		_host_step = false
	if _host.advance(delta, playing):
		_host.consume_period()
		_host_step = true
		if replay_commands and _current.tick_index >= scenario.tick_limit:
			playing = false
			reset_interpolation()
		elif threaded_playback and not record_trace:
			var command: TickCommand = scenario.command_at(_current.tick_index) if replay_commands else _live_command()
			if not _host.submit(command):
				last_error = _host.error
				playing = false
		elif replay_commands:
			step_scenario()
		else:
			step_live()
		_host_step = false
	var fraction: float = (_host.render_elapsed if threaded_playback and not record_trace else _host.elapsed) / GameplayHost.PERIOD
	draw_state(fraction if playing else 1.0)

func _finish_pending() -> void:
	if not _host.pending():
		return
	var result: TickResult = _host.finish()
	last_tick_usec = _host.last_tick_usec
	var was_host: bool = _host_step
	_host_step = true
	_accept_result(_host.pending_command, result)
	_host_step = was_host

func _close_worker() -> void:
	_host.close()

func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or key.echo:
		return
	var action: int = 0
	match key.physical_keycode:
		KEY_UP: action = TickCommand.NORTH
		KEY_RIGHT: action = TickCommand.EAST
		KEY_DOWN: action = TickCommand.SOUTH
		KEY_LEFT: action = TickCommand.WEST
		KEY_SHIFT: action = TickCommand.SUPER_HOP
		KEY_CTRL: action = TickCommand.TONGUE
		KEY_E: action = TickCommand.CAMERA_CLOCKWISE
		KEY_Q: action = TickCommand.CAMERA_ANTICLOCKWISE
	if action != 0:
		if key.pressed:
			_held |= action
		else:
			_held &= ~action
		return
	if not key.pressed or run == null:
		return
	match key.physical_keycode:
		KEY_SPACE:
			_finish_pending()
			playing = not playing and not _current.completed
			reset_interpolation()
			_host.elapsed = 0.0
		KEY_PERIOD:
			_finish_pending()
			playing = false
			if replay_commands:
				step_scenario()
			else:
				step_live()
		KEY_R: reset_scenario()
		KEY_I: smoothing = not smoothing
		KEY_TAB:
			_finish_pending()
			replay_commands = not replay_commands
			_host.sampled_held = 0
			_held = 0
		KEY_ESCAPE: get_tree().change_scene_to_file("res://scenes/boot.tscn")
	draw_state(1.0)

func _build_scene() -> void:
	build_world()
	_entity_inspection = EntityInspection.new()
	add_child(_entity_inspection)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(12, 10)
	_label.size = Vector2(616, 440)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 13)
	layer.add_child(_label)

func _build_terrain() -> void:
	_projection_size = Vector2i.ZERO
	_map_instance = null
	for child: Node in _ground.get_children():
		_ground.remove_child(child)
		child.queue_free()
	if scenario.map_scene != null:
		_map_instance = MapMeshBuilder.new().build(scenario.map_scene).create_instance()
		_ground.add_child(_map_instance)
		_map_instance.set_projection_scale(GameplayProjection.clip_scale(Vector2i(get_viewport().get_visible_rect().size)))
		return
	var layer: int = 0
	for square: GridSquareDefinition in scenario.level.grid.squares:
		var face := MeshInstance3D.new()
		var vertices := PackedVector3Array()
		for index: int in [0, 1, 2, 2, 1, 3]:
			var v: Vector3i = square.vertices[index]
			vertices.append(GameSpace.position(v.x, v.y, v.z))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		face.mesh = mesh
		var tint: Color = Color(0.22, 0.35, 0.44) if square.flags & 1 else Color(0.65, 0.2, 0.16)
		@warning_ignore("integer_division")
		if ((layer % 4) + (layer / 4)) % 2 == 0:
			tint = tint.lightened(0.08)
		face.material_override = _material(tint)
		_ground.add_child(face)
		layer += 1

func _clear_entity_visuals() -> void:
	super._clear_entity_visuals()
	if _entity_inspection != null:
		var empty: Array[EntityDefinition] = []
		_entity_inspection.configure(empty)

func _build_entity_visuals() -> void:
	if scenario == null or not scenario.options.entity_reactions or scenario.level.entity_collision == null:
		_clear_entity_visuals()
		return
	build_entities(scenario.level.entity_collision, scenario.map_scene, data, TerrainCaptureStages.entity_lighting(scenario))
	_entity_inspection.configure(scenario.level.entity_collision.entities)
	_entity_inspection.configure_contacts(scenario.level.entity_collision.contacts)
	_entity_inspection.visible = true
	_entity_pose_tick = -1
	if _current != null:
		draw_state(1.0)

func _selected_contact_index() -> int:
	if scenario == null or scenario.level.entity_collision == null:
		return -1
	for slot: int in scenario.level.entity_collision.entities.size():
		if scenario.level.entity_collision.entities[slot].entity_index == _current.attachment.death_entity_index and (_current.entities == null or not _current.entities.lifecycle_enabled or _current.entities.entities[slot].live):
			return slot
	var nearest: int = -1
	var nearest_distance: int = 0x7fffffffffffffff
	for slot: int in scenario.level.entity_collision.contacts.size():
		if not scenario.level.entity_collision.contacts[slot].unsupported_reason.is_empty() or _current.entities == null or slot >= _current.entities.entities.size():
			continue
		if _current.entities.lifecycle_enabled and not _current.entities.entities[slot].live:
			continue
		var matrix: PackedInt32Array = _current.entities.entities[slot].matrix12
		var dx: int = matrix[9] - _current.frog.world_position.x
		var dz: int = matrix[11] - _current.frog.world_position.z
		var distance: int = dx * dx + dz * dz
		if distance < nearest_distance:
			nearest = slot
			nearest_distance = distance
	return nearest

func _capture_scenario(arguments: PackedStringArray) -> void:
	set_process(false)
	if not last_error.is_empty():
		push_error(last_error)
		get_tree().quit(1)
		return
	var rate_text: String = ViewerArguments.value(arguments, "--render-rate=")
	var render_rate: int = 60 if rate_text.is_empty() else rate_text.to_int()
	if not render_rate in [30, 60, 144, 200, 240]:
		push_error("Render rate must be 30, 60, 144, 200 or 240")
		get_tree().quit(1)
		return
	Engine.max_fps = render_rate
	var irregular: bool = ViewerArguments.value(arguments, "--frame-schedule=") == "irregular"
	var frame_index: int = 0
	var intervals := PackedFloat64Array([1.0 / 240.0, 1.0 / 60.0, 1.0 / 200.0, 1.0 / 30.0, 1.0 / 144.0])
	var folder: String = ViewerArguments.value(arguments, "--screenshot-dir=")
	if not folder.is_empty():
		last_error = ViewerCapture.prepare_folder(folder)
		if not last_error.is_empty():
			push_error(last_error)
			get_tree().quit(1)
			return
	var hit_tick: int = -1
	var centred_tick: int = -1
	var had_lifecycle_creation: bool = false
	var had_global_absence: bool = false
	var captured: Dictionary[String, bool] = {}
	if scenario.options.entity_lifecycle and not folder.is_empty():
		await RenderingServer.frame_post_draw
		last_error = _save_stage(folder, "lifecycle-initial", captured)
	if scenario.options.platforms_enabled and not folder.is_empty():
		await RenderingServer.frame_post_draw
		last_error = _save_stage(folder, "platform-safe-start" if scenario.level.tick_guard != null else "platform-approach", captured)
	if scenario.options.entity_reactions and not scenario.options.entity_lifecycle and not scenario.options.platforms_enabled and not folder.is_empty() and TerrainCaptureStages.before_contact(scenario, _current):
		await RenderingServer.frame_post_draw
		last_error = _save_stage(folder, "before-contact", captured)
	if not last_error.is_empty():
		push_error(last_error)
		get_tree().quit(1)
		return
	playing = true
	while _current.tick_index < scenario.tick_limit and not _current.completed:
		_process(intervals[frame_index % intervals.size()] if irregular else 1.0 / render_rate)
		frame_index += 1
		if not last_error.is_empty():
			push_error(last_error)
			get_tree().quit(1)
			return
		await RenderingServer.frame_post_draw
		if ViewerArguments.has_flag(arguments, "--motion-capture") and not folder.is_empty():
			last_error = ViewerCapture.save_image(get_viewport().get_texture().get_image(), folder.path_join("motion-%06d.png" % frame_index))
			if not last_error.is_empty():
				push_error(last_error)
				get_tree().quit(1)
				return
		if scenario.options.entity_lifecycle and not folder.is_empty() and _current.entities != null:
			var lifecycle_stages: Array[String] = []
			for event: TickEvent in _current.entities.lifecycle_events:
				if event.kind == TickEvent.Kind.CREATE:
					lifecycle_stages.append("lifecycle-create" if event.generation <= 1 else "lifecycle-recreate")
					if had_global_absence:
						lifecycle_stages.append("lifecycle-return")
						had_global_absence = false
					had_lifecycle_creation = true
				elif event.kind == TickEvent.Kind.DESTROY:
					lifecycle_stages.append("lifecycle-destroy")
			for entity: EntitySnapshot in _current.entities.entities:
				if entity.destroy_pending:
					lifecycle_stages.append("lifecycle-pending")
					break
			if had_lifecycle_creation and _current.entities.live_order.is_empty() and not had_global_absence:
				lifecycle_stages.append("lifecycle-absent")
				had_global_absence = true
			for stage: String in lifecycle_stages:
				last_error = _save_stage(folder, stage, captured)
				if not last_error.is_empty():
					break
			if not last_error.is_empty():
				push_error(last_error)
				get_tree().quit(1)
				return
		if scenario.options.platforms_enabled and not folder.is_empty():
			var platform_stages: Array[String] = TerrainCaptureStages.platform(scenario, _current)
			if hit_tick < 0 and _current.attachment.current_entity_index >= 0:
				hit_tick = _current.tick_index
				platform_stages.append("platform-attachment")
			if hit_tick >= 0 and _current.tick_index >= hit_tick + 1:
				platform_stages.append("platform-camera")
			if hit_tick >= 0 and _current.attachment.current_entity_index >= 0 and _current.frog.mode == 0:
				if centred_tick < 0:
					centred_tick = _current.tick_index
				platform_stages.append("platform-centred")
				if _current.tick_index >= centred_tick + 2:
					platform_stages.append("platform-carry")
			if hit_tick >= 0 and _current.attachment.current_entity_index < 0:
				platform_stages.append("platform-departure")
			for stage: String in platform_stages:
				last_error = _save_stage(folder, stage, captured)
				if not last_error.is_empty():
					break
			if not last_error.is_empty():
				push_error(last_error)
				get_tree().quit(1)
				return
		elif scenario.options.entity_reactions and not folder.is_empty():
			if hit_tick < 0 and _current.attachment.death_entity_index >= 0:
				hit_tick = _current.tick_index
				last_error = _save_stage(folder, "hit", captured)
			elif hit_tick < 0 and TerrainCaptureStages.before_contact(scenario, _current):
				last_error = _save_stage(folder, "before-contact", captured)
			if hit_tick >= 0 and _current.tick_index >= hit_tick + 2 and _current.animation != null and _current.animation.action == FrogAnimationCatalog.POP:
				last_error = _save_stage(folder, "pop-animation", captured)
			if hit_tick >= 0 and _current.tick_index >= hit_tick + 8 and _current.camera != null:
				last_error = _save_stage(folder, "death-camera", captured)
			if not last_error.is_empty():
				push_error(last_error)
				get_tree().quit(1)
				return
	playing = false
	var output: String = ViewerArguments.value(arguments, "--trace-csv=")
	if not output.is_empty():
		last_error = trace.save(output)
	var full_output: String = ViewerArguments.value(arguments, "--trace-jsonl=")
	if last_error.is_empty() and not full_output.is_empty():
		last_error = trace.save_full(full_output)
	if last_error.is_empty() and not folder.is_empty():
		await RenderingServer.frame_post_draw
		last_error = ViewerCapture.save_image(get_viewport().get_texture().get_image(), folder.path_join("terrain-" + scenario.identifier + ".png"))
	if not last_error.is_empty():
		push_error(last_error)
	get_tree().quit(0 if last_error.is_empty() else 1)

func _save_stage(folder: String, name: String, captured: Dictionary[String, bool]) -> String:
	if captured.has(name):
		return ""
	captured[name] = true
	return ViewerCapture.save_image(get_viewport().get_texture().get_image(), folder.path_join("entity-" + name + ".png"))

func _update_projection() -> void:
	super._update_projection()
	var size := Vector2i(get_viewport().get_visible_rect().size)
	_label.size = Vector2(maxf(1.0, float(size.x) - 24.0), maxf(1.0, float(size.y) - 40.0))

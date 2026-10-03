class_name TerrainViewer
extends Node3D
## Synthetic terrain driver. Scene input, clocks and drawing consume the same pure run API.

var auto_open: bool = true
var scenario: TerrainScenario
var run: TerrainRun
var playing: bool = false
var smoothing: bool = false
var replay_commands: bool = true
## Capture is opt-in so an interactive session does not accumulate an unbounded trace.
var record_trace: bool = false
var trace: TerrainTrace
var last_error: String = ""
var data: GameData
var frog_assets: TerrainFrogAssets
var _owns_data: bool = false
var _frog_model: AnimatedModelInstance
var _elapsed: float = 0.0
var _held: int = 0
var _sampled_held: int = 0
var _previous: RunSnapshot
var _current: RunSnapshot
var _ground: Node3D
var _frog: MeshInstance3D
var _camera: Camera3D
var _label: Label
var _map_instance: MapMesh.Instance
var _frog_pose_tick: int = -1
var _outcomes: PackedStringArray = PackedStringArray()
var _projection_size: Vector2i = Vector2i.ZERO
var _entity_models: Array[AnimatedModelInstance] = []
var _entity_meshes: Array[ModelMesh] = []
var _entity_files: Array[MofFile] = []
var _entity_generations: Array[int] = []
var _entity_inspection: EntityInspection
var _last_contacts: Array[FormReactionResult] = []

func _ready() -> void:
	_build_scene()
	if auto_open:
		var arguments: PackedStringArray = OS.get_cmdline_user_args()
		configure_input(arguments)
		record_trace = ViewerArguments.has_prefix(arguments, "--trace-csv=") or ViewerArguments.has_prefix(arguments, "--trace-jsonl=")
		var path: String = ViewerArguments.value(arguments, "--scenario-file=")
		var name_arg: String = ViewerArguments.value(arguments, "--scenario=")
		var selected: TerrainScenario = TerrainScenario.from_file(path) if not path.is_empty() else TerrainScenario.builtin(name_arg if not name_arg.is_empty() else "normal")
		if selected.error.is_empty():
			selected.error = selected.apply_arguments(arguments)
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
	_clear_entity_visuals()
	if _owns_data and data != null:
		data.close()
	data = null
	_owns_data = false

## Direct map exploration uses live controls; explicit fixtures and captures replay.
func configure_input(arguments: PackedStringArray) -> void:
	replay_commands = ViewerArguments.value(arguments, "--level=").is_empty() \
		or ViewerArguments.has_flag(arguments, "--run-scenario") \
		or ViewerArguments.has_prefix(arguments, "--scenario=") \
		or ViewerArguments.has_prefix(arguments, "--scenario-file=")

## Loads optional frog presentation; callers retain borrowed data until this viewer detaches.
func open_data(selected: GameData, take_ownership: bool = false) -> String:
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
	_frog_model = AnimatedModelInstance.new()
	add_child(_frog_model)
	_frog_model.setup(frog_assets.mesh, frog_assets.player)
	for mesh: ArrayMesh in frog_assets.mesh.part_meshes:
		if mesh != null:
			for surface: int in mesh.get_surface_count():
				var material: ShaderMaterial = mesh.surface_get_material(surface) as ShaderMaterial
				if material != null:
					material.set_shader_parameter("projection_scale", GameplayProjection.clip_scale(Vector2i(get_viewport().get_visible_rect().size)))
	for index: int in _frog_model.part_nodes.size():
		_frog_model.part_nodes[index].visible = not frog_assets.hidden_parts.has(index)
	_frog.visible = false
	_build_entity_visuals()
	draw_state(1.0)
	return ""

## Replaces the debug scenario and collapses interpolation to its exact initial state.
func open_scenario(selected: TerrainScenario) -> String:
	if selected == null or not selected.error.is_empty():
		last_error = "Missing scenario" if selected == null else selected.error
		playing = false
		return last_error
	var replacement: TerrainRun = TerrainRun.create(selected.level, selected.initial)
	last_error = replacement.error
	if not last_error.is_empty():
		playing = false
		return last_error
	scenario = selected
	run = replacement
	trace = TerrainTrace.new()
	trace.configure(selected)
	playing = false
	_elapsed = 0.0
	_held = 0
	_sampled_held = 0
	_current = run.snapshot()
	_previous = _current
	_frog_pose_tick = -1
	_outcomes.clear()
	_last_contacts.clear()
	if _ground != null:
		_build_terrain()
		_build_entity_visuals()
		draw_state(1.0)
	return ""

## Advances exactly one command; used by interactive stepping and automated scene tests.
func step_command(command: TickCommand) -> TickResult:
	if run == null:
		var rejected := TickResult.new()
		rejected.error = "Open a terrain scenario before stepping"
		return rejected
	var result: TickResult = run.step(command)
	last_error = result.error
	if last_error.is_empty():
		_previous = _current
		_current = run.snapshot()
		_outcomes = PackedStringArray(result.events)
		_last_contacts.clear()
		for contact: FormReactionResult in result.entity_contacts:
			_last_contacts.append(contact.copy())
		var created: PackedInt32Array = _sync_entity_models()
		for slot: int in _entity_models.size():
			var model: AnimatedModelInstance = _entity_models[slot]
			if model != null and not created.has(slot):
				model.advance_tick()
		if record_trace:
			trace.append_result(scenario.scenario_index, command, result)
	else:
		playing = false
	if _current.completed:
		playing = false
	if not playing:
		_previous = _current
	_elapsed = 0.0
	draw_state(1.0)
	return result

## Replays the authored command at the run's next tick, without polling input.
func step_scenario() -> TickResult:
	return step_command(scenario.command_at(run.snapshot().tick_index))

## Samples the host's collected button state once at the command boundary.
func step_live() -> TickResult:
	var command := TickCommand.new()
	command.tick_index = _current.tick_index
	command.pressed_mask = _held & ~_sampled_held
	command.held_mask = _held
	_sampled_held = _held
	return step_command(command)

## Clears scenario state, pending input and presentation clocks without reusing mutable snapshots.
func reset_scenario() -> String:
	return open_scenario(scenario)

## Draws only detached state; changing interpolation never advances rules.
func draw_state(fraction: float) -> void:
	if _current == null or _frog == null:
		return
	_update_projection()
	var weight: float = clampf(fraction, 0.0, 1.0) if smoothing else 1.0
	_frog.position = GameSpace.fixed_position(_previous.position_16).lerp(GameSpace.fixed_position(_current.position_16), weight) + Vector3(0, 0.12, 0)
	if _frog_model != null:
		_frog_model.transform = GameSpace.transform(_current.matrix12)
		_frog_model.position = GameSpace.fixed_position(_previous.position_16).lerp(GameSpace.fixed_position(_current.position_16), weight)
		if _current.animation != null and _frog_pose_tick != _current.tick_index:
			var player: ModelAnimationPlayer = frog_assets.player
			if _frog_pose_tick < 0:
				player.restart()
			else:
				player.advance_tick()
			if player.action_index != _current.animation.action:
				player.set_action(_current.animation.action)
			player.frame = _current.animation.cel
			_frog_model.apply_exact()
			_frog_pose_tick = _current.tick_index
	if _current.camera != null:
		_camera.transform = GameplayProjection.camera_transform(_current.camera)
		_camera.fov = GameplayProjection.vertical_fov_degrees(Vector2i(get_viewport().get_visible_rect().size))
	if _map_instance != null:
		if _map_instance.tick != _current.tick_index - 1:
			if _map_instance.tick == _current.tick_index - 2:
				_map_instance.step()
			else:
				_map_instance.set_tick(_current.tick_index - 1)
		_map_instance.set_camera_position(_current.camera.source_world)
		_map_instance.set_cave_frog(_current.world_position)
	if _entity_inspection != null and _current.entities != null:
		_entity_inspection.set_snapshot(_current.entities)
		var selected_index: int = _selected_contact_index()
		_entity_inspection.set_selected(selected_index)
		var hit_contact: FormContactResult = null
		for reaction: FormReactionResult in _last_contacts:
			if reaction.contact != null and scenario.level.entity_collision != null and selected_index >= 0 and reaction.contact.entity_index == scenario.level.entity_collision.entities[selected_index].entity_index:
				hit_contact = reaction.contact
				break
		_entity_inspection.set_contact(_current.world_position, hit_contact)
	if _current.entities != null:
		for index: int in mini(_entity_models.size(), _current.entities.entities.size()):
			if _entity_models[index] != null:
				_entity_models[index].transform = GameSpace.transform(_current.entities.entities[index].matrix12)
	var camera_facts: String = "none" if _current.camera == null else "%d source %s" % [_current.camera.mode, _current.camera.source_world]
	var presentation: String = "synthetic marker" if _frog_model == null else "high-detail frog"
	_label.text = "TERRAIN INSPECTION %s | %s\ntick %d | mode %d | cell %s | square %d\n" % [presentation, scenario.identifier, _current.tick_index, _current.mode, _current.cell, _current.square_index]
	_label.text += "position16 %s | velocity16 %s\ncount %d | flags 0x%x | buffered %d / %d\n" % [_current.position_16, _current.velocity_16, _current.remaining_ticks, _current.flags, _current.buffered_keys, _current.buffered_input_count]
	_label.text += "destination %s | layer flags 0x%x | source %s\ncamera %s | death %d/%d | completed %s\noutcomes %s\n" % [_current.destination_cell, _current.square_flags, _current.source_id, camera_facts, _current.death_equate, _current.death_count, str(_current.completed), "; ".join(_outcomes)]
	if scenario.entity_reactions:
		if scenario.entity_lifecycle and _current.entities != null:
			var selected: PackedInt32Array = _current.entities.selected_groups
			var subjects := PackedStringArray()
			for slot: int in mini(3, _current.entities.entities.size()):
				var subject: EntitySnapshot = _current.entities.entities[slot]
				subjects.append("#%d support=%s live=%s pending=%s gen=%d" % [subject.entity_index, str(subject.lifecycle_supported), str(subject.live), str(subject.destroy_pending), subject.generation])
			_label.text += "live %d | groups %d %s | events %s\n%s\n" % [_current.entities.live_order.size(), selected.size(), selected.slice(0, mini(4, selected.size())), _current.entities.lifecycle_events.slice(0, 3), "; ".join(subjects)]
		if scenario.platforms_enabled:
			_label.text += "platform %d | local cell %s | carrying %s\n" % [_current.current_entity_index, _current.entity_cell, _current.entity_carry_indices]
		var contact_lines := PackedStringArray()
		var nearby_count: int = _last_contacts.size()
		for reaction: FormReactionResult in _last_contacts:
			if reaction.status != FormReactionResult.NONE or (reaction.contact != null and reaction.contact.status == FormContactResult.CONTACT):
				contact_lines.append("%s #%d %s" % [reaction.status, reaction.contact.entity_index if reaction.contact != null else -1, reaction.reason])
		var visible: PackedStringArray = contact_lines.slice(0, 2)
		_label.text += "entity hits %s | death entity %d | nearby %d\ncontacts %s" % [_current.entity_hit_indices, _current.death_entity_index, nearby_count, "; ".join(visible)]
		if contact_lines.size() > visible.size():
			_label.text += " (+%d)" % (contact_lines.size() - visible.size())
		_label.text += "\n"
		_label.tooltip_text = "\n".join(contact_lines) + "\n" + "\n".join(scenario.diagnostics)
	if scenario.level.exploration_guard != null:
		var bounds: Rect2i = scenario.level.exploration_guard.world_bounds
		_label.text = "JUN1 BANK / LOG EXPLORATION\ntick %d | cell %s | platform %d\n" % [_current.tick_index, _current.cell, _current.current_entity_index]
		_label.text += "World X[%d,%d), Z[%d,%d)\n" % [bounds.position.x, bounds.end.x, bounds.position.y, bounds.end.y]
		_label.text += "All-attached lifetime | active camera zones unsupported\n"
		_label.text += "From reset: Left onto log, then Right after centring.\n"
	var input_status: String = "REPLAY" if replay_commands else "LIVE"
	input_status += " | running" if playing else " | paused"
	if _current.completed:
		input_status += " | run ended: R resets"
	elif replay_commands and _current.tick_index >= scenario.tick_limit:
		input_status += " | replay finished: Tab selects live input"
	_label.text += input_status + "\nSpace play/pause | . step | R reset | I interpolate\nArrows hop | Shift super hop | Q/E camera | Tab replay/live\n" + last_error

func _process(delta: float) -> void:
	if run == null or _current == null:
		return
	if playing:
		_elapsed += delta
		var period: float = 1.0 / TerrainRun.TICKS_PER_SECOND
		if _elapsed >= period:
			# Source human pacer does not bank a burst after a large stall.
			var remainder: float = 0.0 if _elapsed > period * 2.0 else _elapsed - period
			if replay_commands:
				if _current.tick_index < scenario.tick_limit:
					step_scenario()
				else:
					playing = false
					_previous = _current
			else:
				step_live()
			_elapsed = remainder
		draw_state(_elapsed / period)

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
			playing = not playing and not _current.completed
			_previous = _current
			_elapsed = 0.0
		KEY_PERIOD:
			playing = false
			if replay_commands:
				step_scenario()
			else:
				step_live()
		KEY_R: reset_scenario()
		KEY_I: smoothing = not smoothing
		KEY_TAB:
			replay_commands = not replay_commands
			_sampled_held = 0
			_held = 0
		KEY_ESCAPE: get_tree().change_scene_to_file("res://scenes/boot.tscn")
	draw_state(1.0)

func _build_scene() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ground = Node3D.new()
	add_child(_ground)
	_entity_inspection = EntityInspection.new()
	add_child(_entity_inspection)
	_frog = MeshInstance3D.new()
	var marker := SphereMesh.new()
	marker.radius = 0.12
	marker.height = 0.24
	_frog.mesh = marker
	_frog.material_override = _material(Color(0.35, 1.0, 0.3))
	add_child(_frog)
	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.position = Vector3(3.5, 4.5, 5.5)
	_camera.fov = 45.0
	add_child(_camera)
	_camera.look_at(Vector3.ZERO)
	_camera.current = true
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
	for model: AnimatedModelInstance in _entity_models:
		if model != null:
			remove_child(model)
			model.queue_free()
	_entity_models.clear()
	_entity_meshes.clear()
	_entity_files.clear()
	_entity_generations.clear()
	if _entity_inspection != null:
		var empty: Array[EntityDefinition] = []
		_entity_inspection.configure(empty)

func _build_entity_visuals() -> void:
	_clear_entity_visuals()
	if scenario == null or not scenario.entity_reactions or scenario.level.entity_collision == null:
		return
	var definitions: EntityCollisionDefinition = scenario.level.entity_collision
	_entity_inspection.configure(definitions.entities)
	_entity_inspection.configure_contacts(definitions.contacts)
	_entity_inspection.visible = true
	for _entity: EntityDefinition in definitions.entities:
		_entity_models.append(null)
		_entity_meshes.append(null)
		_entity_files.append(null)
		_entity_generations.append(-1)
	if data == null or not data.is_valid() or scenario.map_scene == null:
		return
	var meshes: Dictionary[int, ModelMesh] = {}
	var files: Dictionary[int, MofFile] = {}
	for slot: int in definitions.entities.size():
		var entity: EntityDefinition = definitions.entities[slot]
		if entity.flags & (EntityDefinition.HIDDEN | EntityDefinition.NO_DISPLAY):
			continue
		var form: FormBookEntry = data.tables.theme_book().get_form(scenario.map_scene.map.general.theme, entity.form_id)
		if form == null:
			continue
		var resource: int = data.model_resource_for(form, scenario.map_scene.level)
		if resource < 0:
			continue
		if not meshes.has(resource):
			var file: MofFile = data.read_model(resource, scenario.diagnostics)
			if file == null or not file.error.is_empty() or file.static_models.is_empty():
				continue
			files[resource] = file
			meshes[resource] = ModelMeshBuilder.new(scenario.map_scene.library, scenario.map_scene.preferred).build_animated(file)
		if not meshes.has(resource):
			continue
		_entity_meshes[slot] = meshes[resource]
		_entity_files[slot] = files[resource]
	_sync_entity_models()
	if _current != null:
		_projection_size = Vector2i.ZERO
		draw_state(1.0)

## Reconciles visual lifetimes with the committed run, resetting animation on recreation.
func _sync_entity_models() -> PackedInt32Array:
	var created := PackedInt32Array()
	if _current == null or _current.entities == null:
		return created
	for slot: int in mini(_entity_models.size(), _current.entities.entities.size()):
		var entity: EntitySnapshot = _current.entities.entities[slot]
		var should_live: bool = not _current.entities.lifecycle_enabled or entity.live
		if not should_live:
			if _entity_models[slot] != null:
				remove_child(_entity_models[slot])
				_entity_models[slot].queue_free()
				_entity_models[slot] = null
			_entity_generations[slot] = -1
			continue
		if _entity_files[slot] == null or _entity_meshes[slot] == null:
			continue
		if _entity_models[slot] != null and _entity_generations[slot] == entity.generation:
			continue
		if _entity_models[slot] != null:
			remove_child(_entity_models[slot])
			_entity_models[slot].queue_free()
		var model := AnimatedModelInstance.new()
		add_child(model)
		model.setup(_entity_meshes[slot], ModelAnimationPlayer.new(_entity_files[slot]))
		_set_model_projection(_entity_meshes[slot], GameplayProjection.clip_scale(Vector2i(get_viewport().get_visible_rect().size)))
		_entity_models[slot] = model
		_entity_generations[slot] = entity.generation
		created.append(slot)
	return created

func _selected_contact_index() -> int:
	if scenario == null or scenario.level.entity_collision == null:
		return -1
	for slot: int in scenario.level.entity_collision.entities.size():
		if scenario.level.entity_collision.entities[slot].entity_index == _current.death_entity_index and (_current.entities == null or not _current.entities.lifecycle_enabled or _current.entities.entities[slot].live):
			return slot
	var nearest: int = -1
	var nearest_distance: int = 0x7fffffffffffffff
	for slot: int in scenario.level.entity_collision.contacts.size():
		if not scenario.level.entity_collision.contacts[slot].unsupported_reason.is_empty() or _current.entities == null or slot >= _current.entities.entities.size():
			continue
		if _current.entities.lifecycle_enabled and not _current.entities.entities[slot].live:
			continue
		var matrix: PackedInt32Array = _current.entities.entities[slot].matrix12
		var dx: int = matrix[9] - _current.world_position.x
		var dz: int = matrix[11] - _current.world_position.z
		var distance: int = dx * dx + dz * dz
		if distance < nearest_distance:
			nearest = slot
			nearest_distance = distance
	return nearest

func _material(colour: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/presentation/tools/terrain_debug.gdshader")
	material.set_shader_parameter("tint", colour)
	material.set_shader_parameter("projection_scale", GameplayProjection.clip_scale(Vector2i(get_viewport().get_visible_rect().size)))
	return material

func _capture_scenario(arguments: PackedStringArray) -> void:
	set_process(false)
	if not last_error.is_empty():
		push_error(last_error)
		get_tree().quit(1)
		return
	var rate_text: String = ViewerArguments.value(arguments, "--render-rate=")
	var render_rate: int = 60 if rate_text.is_empty() else rate_text.to_int()
	if not render_rate in [30, 60, 144]:
		push_error("Render rate must be 30, 60 or 144")
		get_tree().quit(1)
		return
	Engine.max_fps = render_rate
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
	if scenario.entity_lifecycle and not folder.is_empty():
		await RenderingServer.frame_post_draw
		last_error = _save_stage(folder, "lifecycle-initial", captured)
	if scenario.platforms_enabled and not folder.is_empty():
		await RenderingServer.frame_post_draw
		last_error = _save_stage(folder, "platform-safe-start" if scenario.level.exploration_guard != null else "platform-approach", captured)
	if scenario.entity_reactions and not scenario.entity_lifecycle and not scenario.platforms_enabled and not folder.is_empty() and scenario.level_code.to_upper() != "DES2":
		await RenderingServer.frame_post_draw
		last_error = _save_stage(folder, "before-contact", captured)
	if not last_error.is_empty():
		push_error(last_error)
		get_tree().quit(1)
		return
	playing = true
	while _current.tick_index < scenario.tick_limit and not _current.completed:
		_process(1.0 / render_rate)
		if not last_error.is_empty():
			push_error(last_error)
			get_tree().quit(1)
			return
		await RenderingServer.frame_post_draw
		if scenario.entity_lifecycle and not folder.is_empty() and _current.entities != null:
			var lifecycle_stages: Array[String] = []
			for event: String in _current.entities.lifecycle_events:
				if event.begins_with("create:"):
					var fields: PackedStringArray = event.split(":")
					lifecycle_stages.append("lifecycle-create" if fields.size() < 3 or fields[2].to_int() <= 1 else "lifecycle-recreate")
					if had_global_absence:
						lifecycle_stages.append("lifecycle-return")
						had_global_absence = false
					had_lifecycle_creation = true
				elif event.begins_with("destroy:"):
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
		if scenario.platforms_enabled and not folder.is_empty():
			var platform_stages: Array[String] = []
			if scenario.level.exploration_guard != null:
				if _current.tick_index == 3:
					platform_stages.append("platform-approach")
				if _current.tick_index == 8:
					platform_stages.append("platform-centring")
				if _current.tick_index == 12:
					platform_stages.append("platform-carry")
				if _current.tick_index == 18:
					platform_stages.append("platform-safe-return")
			if hit_tick < 0 and _current.current_entity_index >= 0:
				hit_tick = _current.tick_index
				platform_stages.append("platform-attachment")
			if hit_tick >= 0 and _current.tick_index >= hit_tick + 1:
				platform_stages.append("platform-camera")
			if hit_tick >= 0 and _current.current_entity_index >= 0 and _current.mode == 0:
				if centred_tick < 0:
					centred_tick = _current.tick_index
				platform_stages.append("platform-centred")
				if _current.tick_index >= centred_tick + 2:
					platform_stages.append("platform-carry")
			if hit_tick >= 0 and _current.current_entity_index < 0:
				platform_stages.append("platform-departure")
			for stage: String in platform_stages:
				last_error = _save_stage(folder, stage, captured)
				if not last_error.is_empty():
					break
			if not last_error.is_empty():
				push_error(last_error)
				get_tree().quit(1)
				return
		elif scenario.entity_reactions and not folder.is_empty():
			if hit_tick < 0 and _current.death_entity_index >= 0:
				hit_tick = _current.tick_index
				last_error = _save_stage(folder, "hit", captured)
			elif hit_tick < 0 and (scenario.level_code.to_upper() != "DES2" or _current.tick_index == 4):
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
	var size := Vector2i(get_viewport().get_visible_rect().size)
	if size == _projection_size:
		return
	_projection_size = size
	_label.size = Vector2(maxf(1.0, float(size.x) - 24.0), maxf(1.0, float(size.y) - 40.0))
	var scale: Vector2 = GameplayProjection.clip_scale(size)
	if _map_instance != null:
		_map_instance.set_projection_scale(scale)
	if frog_assets != null and frog_assets.mesh != null:
		_set_model_projection(frog_assets.mesh, scale)
	for instance: AnimatedModelInstance in _entity_models:
		if instance != null and instance.model_mesh != null:
			_set_model_projection(instance.model_mesh, scale)
	for child: Node in _ground.get_children():
		var face: MeshInstance3D = child as MeshInstance3D
		if face != null:
			var material: ShaderMaterial = face.material_override as ShaderMaterial
			if material != null:
				material.set_shader_parameter("projection_scale", scale)
	var marker: ShaderMaterial = _frog.material_override as ShaderMaterial
	if marker != null:
		marker.set_shader_parameter("projection_scale", scale)

func _set_model_projection(model_mesh: ModelMesh, scale: Vector2) -> void:
	for mesh: ArrayMesh in model_mesh.part_meshes:
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var material: ShaderMaterial = mesh.surface_get_material(surface) as ShaderMaterial
			if material != null:
				material.set_shader_parameter("projection_scale", scale)
	for tracks: Array in model_mesh.texture_tracks:
		for track: ModelMesh.TextureTrack in tracks:
			if track.original != null:
				track.original.set_shader_parameter("projection_scale", scale)
			for material: ShaderMaterial in track.frames:
				material.set_shader_parameter("projection_scale", scale)

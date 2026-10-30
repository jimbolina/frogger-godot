class_name GameplayWorldView
extends Node3D
## Shared world drawing from committed gameplay snapshots, independent of inspection.

## Game units the frog's depth moves toward the camera: its local ordering table
## enters the global one at origin depth plus FROG_GLOBAL_OT_OFFSET (-0x30, FROG.H)
## before the otz shift (FROG.C, MR_ANIM.C).
const FROG_DEPTH_BIAS: float = 48.0

var playing: bool = false
var smoothing: bool = false:
	set(value):
		if smoothing == value:
			return
		smoothing = value
		if _overlay_view != null:
			_overlay_view.smoothing = value
		reset_interpolation()
var frog_assets: TerrainFrogAssets
var _frog_model: AnimatedModelInstance
var _previous: GameplayState
var _current: GameplayState
var _ground: Node3D
var _frog: MeshInstance3D
var _tongue_view: TongueView
var _swarm_view: ForestSwarmView
var _cave_sprite_view: CaveSpriteView
var _overlay_view: EntityOverlayModelView
var _placeholder_view: EntityPlaceholderView = null
var _sprite_definitions: Array[EntityDefinition] = []
var _camera: Camera3D
var _map_instance: MapMesh.Instance
var _frog_pose_tick: int = -1
var _projection_size: Vector2i = Vector2i.ZERO
var _entity_models: Array[AnimatedModelInstance] = []
var _entity_meshes: Array[ModelMesh] = []
var _entity_files: Array[MofFile] = []
var _entity_generations: Array[int] = []
var _entity_pose_tick: int = -1
var _entity_lighting: MapLighting = null
var _motion := TerrainMotion.new()

## Collapses all drawing history without advancing simulation.
func reset_interpolation() -> void:
	if _current == null:
		return
	_previous = _current
	_motion.capture(_current, _current)
	if _frog_model != null:
		_frog_model.smoothing_enabled = smoothing
		_frog_model.apply_exact()
	if _overlay_view != null:
		_overlay_view.reset_interpolation()
	for model: AnimatedModelInstance in _entity_models:
		if model != null:
			model.smoothing_enabled = smoothing
			model.apply_exact()

## Draws only detached state; changing interpolation never advances rules.
func draw_state(fraction: float) -> void:
	if _current == null or _frog == null:
		return
	_update_projection()
	var weight: float = clampf(fraction, 0.0, 1.0) if smoothing else 1.0
	var frog_transform: Transform3D = _motion.frog(weight)
	if _tongue_view != null:
		_tongue_view.draw_state(_current)
	if _swarm_view != null:
		_swarm_view.draw_state(_current)
	if _cave_sprite_view != null:
		_cave_sprite_view.draw_state(_current, _sprite_definitions)
	if _overlay_view != null:
		_overlay_view.draw_state(_current, weight, not playing)
	if _placeholder_view != null:
		_placeholder_view.draw_state(_current, _motion, weight)
	_frog.position = frog_transform.origin + Vector3(0, 0.12, 0)
	if _frog_model != null:
		_frog_model.transform = frog_transform
		if _current.animation != null and _frog_pose_tick != _current.tick_index:
			var player: ModelAnimationPlayer = frog_assets.player
			if _frog_pose_tick < 0:
				player.restart()
			else:
				player.advance_tick()
			if player.action_index != _current.animation.action:
				player.set_action(_current.animation.action)
			player.frame = _current.animation.cel
			_frog_model.capture_pose(not playing)
			_frog_pose_tick = _current.tick_index
		_frog_model.render(weight)
	if _current.camera != null:
		_camera.transform = _motion.camera(weight)
	if _map_instance != null:
		if _map_instance.tick != _current.tick_index - 1:
			if _map_instance.tick == _current.tick_index - 2:
				_map_instance.step()
			else:
				_map_instance.set_tick(_current.tick_index - 1)
		if _current.sky_drift != null:
			var drift_now := Vector3(_current.sky_drift.translation())
			var drift_before: Vector3 = Vector3(_previous.sky_drift.translation()) if _previous.sky_drift != null else drift_now
			_map_instance.set_sky_drift(drift_before.lerp(drift_now, weight))
		_map_instance.set_camera_presentation(Vector3(_camera.position.x, -_camera.position.y, -_camera.position.z) * GameSpace.UNITS_PER_SQUARE)
		_map_instance.set_cave_frog(_current.frog.world_position)
		if _map_instance.source.scene.cave_enabled and _current.entity_environment != null:
			_map_instance.set_cave_radii(_current.entity_environment.light_min_squared, _current.entity_environment.light_max_squared)
	var update_entities: bool = _entity_pose_tick != _current.tick_index
	if _current.entities != null:
		_entity_pose_tick = _current.tick_index
		for index: int in mini(_entity_models.size(), _current.entities.entities.size()):
			if _entity_models[index] != null:
				var entity: EntitySnapshot = _current.entities.entities[index]
				var model: AnimatedModelInstance = _entity_models[index]
				var transform_now: Transform3D = _motion.entity(index, weight)
				if model.transform != transform_now:
					model.transform = transform_now
				if update_entities and _entity_lighting != null:
					model.set_source_lighting(_entity_lighting, entity.colour_scale, entity.ambient, entity.colour_scaled or entity.colour_scale != Vector3i.ZERO, entity.ambient != Vector3i.ZERO)
				if update_entities:
					if entity.custom_state != null:
						model.player.texture_animation_paused = entity.custom_state.texture_animation_paused
						if entity.custom_state.texture_animation_paused and entity.custom_state.texture_animation_cel >= 0:
							model.player.set_texture_cel(entity.custom_state.texture_animation_cel)
					if entity.animation != null and entity.animation.action >= 0:
						if model.player.action_index != entity.animation.action:
							model.player.set_action(entity.animation.action)
						model.player.frame = entity.animation.cel
					model.capture_pose(not playing)
				model.render(weight)
				model.visible = entity.live and not entity.pop_allocated and not bool(entity.entity_flags & (EntityDefinition.HIDDEN | EntityDefinition.NO_DISPLAY)) and (entity.custom_state == null or not entity.custom_state.model_hidden)

## Creates the map, frog and camera drawing roots.
func build_world() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ground = Node3D.new()
	add_child(_ground)
	_frog = MeshInstance3D.new()
	var marker := SphereMesh.new()
	marker.radius = 0.12
	marker.height = 0.24
	_frog.mesh = marker
	_frog.material_override = _material(Color(0.35, 1.0, 0.3))
	add_child(_frog)
	_tongue_view = TongueView.new()
	add_child(_tongue_view)
	_swarm_view = ForestSwarmView.new()
	add_child(_swarm_view)
	_cave_sprite_view = CaveSpriteView.new()
	add_child(_cave_sprite_view)
	_overlay_view = EntityOverlayModelView.new()
	_overlay_view.smoothing = smoothing
	add_child(_overlay_view)
	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.position = Vector3(3.5, 4.5, 5.5)
	_camera.fov = 45.0
	add_child(_camera)
	_camera.look_at(Vector3.ZERO)
	_camera.current = true

func _clear_entity_visuals() -> void:
	if _swarm_view != null:
		_swarm_view.clear()
	if _cave_sprite_view != null:
		_cave_sprite_view.clear()
	if _overlay_view != null:
		_overlay_view.clear()
	if _placeholder_view != null:
		_placeholder_view.clear()
	_sprite_definitions = []
	for model: AnimatedModelInstance in _entity_models:
		if model != null:
			remove_child(model)
			model.queue_free()
	_entity_models.clear()
	_entity_meshes.clear()
	_entity_files.clear()
	_entity_generations.clear()

## Resolves render resources for the validated authored entity definitions.
func build_entities(definitions: EntityCollisionDefinition, scene_data: MapSceneData, selected_data: GameData, use_lighting: bool = true) -> void:
	_clear_entity_visuals()
	_entity_pose_tick = -1
	_entity_lighting = null
	if definitions == null:
		return
	for _entity: EntityDefinition in definitions.entities:
		_entity_models.append(null)
		_entity_meshes.append(null)
		_entity_files.append(null)
		_entity_generations.append(-1)
	if selected_data == null or not selected_data.is_valid() or scene_data == null:
		return
	for entity: EntityDefinition in definitions.entities:
		if entity.behavior.kind == EntityBehavior.Kind.HIVE:
			var issue: String = _swarm_view.configure(scene_data, selected_data)
			if not issue.is_empty():
				scene_data.diagnostics.append(issue)
			break
	for entity: EntityDefinition in definitions.entities:
		if entity.behavior.kind in [EntityBehavior.Kind.FIREFLY, EntityBehavior.Kind.FAT_FIRE_FLY, EntityBehavior.Kind.PICKUP]:
			var sprite_issue: String = _cave_sprite_view.configure(scene_data, selected_data, definitions.entities)
			if not sprite_issue.is_empty():
				scene_data.diagnostics.append(sprite_issue)
			_sprite_definitions = definitions.entities
			break
	if use_lighting:
		_entity_lighting = MapLighting.new()
		_entity_lighting.configure(scene_data.map.lights)
	for entity: EntityDefinition in definitions.entities:
		if EntityOverlayModelView.uses_overlay(entity.behavior.kind):
			var overlay_issue: String = _configure_overlay(selected_data, scene_data, scene_data.level, _entity_lighting, scene_data.diagnostics)
			if not overlay_issue.is_empty():
				scene_data.diagnostics.append(overlay_issue)
			break
	var meshes: Dictionary[int, ModelMesh] = {}
	var files: Dictionary[int, MofFile] = {}
	for slot: int in definitions.entities.size():
		var entity: EntityDefinition = definitions.entities[slot]
		var form: FormBookEntry = selected_data.tables.theme_book().get_form(scene_data.map.general.theme, entity.form_id)
		if form == null or (form.has_flag(FormBookEntry.FLAG_NO_MODEL) and entity.behavior.kind != EntityBehavior.Kind.VOL_COLOUR_SWITCH):
			continue
		var resource: int = EntityModelSelection.resource_for(selected_data, scene_data.level, form, entity)
		if resource < 0:
			continue
		if not meshes.has(resource):
			var file: MofFile = selected_data.read_model(resource, scene_data.diagnostics)
			if file == null or not file.error.is_empty() or file.static_models.is_empty():
				continue
			files[resource] = file
			meshes[resource] = ModelMeshBuilder.new(scene_data.library, scene_data.preferred).build_animated(file)
		if not meshes.has(resource):
			continue
		_entity_meshes[slot] = meshes[resource]
		_entity_files[slot] = files[resource]
	_sync_entity_models()
	if _current != null:
		_projection_size = Vector2i.ZERO
		draw_state(1.0)

## Resolves entity models from per-slot origins without a map, marking unresolved slots; returns diagnostics.
func build_mapless_entities(definitions: EntityCollisionDefinition, origins: EntityModelOrigins) -> PackedStringArray:
	_clear_entity_visuals()
	_entity_pose_tick = -1
	_entity_lighting = null
	if definitions == null:
		return PackedStringArray()
	var resources: MaplessEntityResources = MaplessEntityResources.resolve(definitions.entities, origins)
	var diagnostics: PackedStringArray = resources.diagnostics
	var sprite_slots: Dictionary[int, bool] = {}
	var swarm_ready: bool = false
	var sprites_ready: bool = false
	var overlay_tried: bool = false
	for slot: int in definitions.entities.size():
		var entity: EntityDefinition = definitions.entities[slot]
		_entity_models.append(null)
		_entity_meshes.append(resources.meshes[slot])
		_entity_files.append(resources.files[slot])
		_entity_generations.append(-1)
		if origins == null or not origins.resolvable(slot) or origins.data == null or not origins.data.is_valid():
			continue
		var scene: MapSceneData = resources.scene_for(origins.data, origins.themes[slot])
		if entity.behavior.kind == EntityBehavior.Kind.HIVE and _swarm_view != null and not swarm_ready and scene.error.is_empty():
			var issue: String = _swarm_view.configure(scene, origins.data)
			swarm_ready = issue.is_empty()
			if not swarm_ready:
				diagnostics.append(issue)
		if entity.behavior.kind in [EntityBehavior.Kind.FIREFLY, EntityBehavior.Kind.FAT_FIRE_FLY, EntityBehavior.Kind.PICKUP] and _cave_sprite_view != null and scene.error.is_empty():
			if not sprites_ready:
				var sprite_issue: String = _cave_sprite_view.configure(scene, origins.data, definitions.entities)
				sprites_ready = sprite_issue.is_empty()
				if sprites_ready:
					_sprite_definitions = definitions.entities
				else:
					diagnostics.append(sprite_issue)
			if sprites_ready:
				sprite_slots[slot] = true
		if EntityOverlayModelView.uses_overlay(entity.behavior.kind) and not overlay_tried:
			overlay_tried = true
			var overlay_issue: String = scene.error if not scene.error.is_empty() else _configure_overlay(origins.data, scene, origins.levels[slot], null, diagnostics)
			if not overlay_issue.is_empty():
				diagnostics.append(overlay_issue)
	var wanted: Array[bool] = []
	for slot: int in definitions.entities.size():
		wanted.append(_entity_meshes[slot] == null and not sprite_slots.has(slot))
	if wanted.has(true):
		if _placeholder_view == null:
			_placeholder_view = EntityPlaceholderView.new()
			add_child(_placeholder_view)
		_placeholder_view.configure(wanted, definitions.contacts, GameplayProjection.clip_scale(Vector2i(get_viewport().get_visible_rect().size)))
	_sync_entity_models()
	if _current != null:
		_projection_size = Vector2i.ZERO
		draw_state(1.0)
	return diagnostics

## Number of entity slots drawn as placeholders because no model resolved.
func placeholder_count() -> int:
	return _placeholder_view.marker_count() if _placeholder_view != null else 0

## Number of entity slots currently drawn with a resolved model instance.
func entity_model_count() -> int:
	var count: int = 0
	for model: AnimatedModelInstance in _entity_models:
		if model != null:
			count += 1
	return count

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
		model.smoothing_enabled = smoothing
		_set_model_projection(_entity_meshes[slot], GameplayProjection.clip_scale(Vector2i(get_viewport().get_visible_rect().size)))
		_entity_models[slot] = model
		_entity_generations[slot] = entity.generation
		created.append(slot)
	return created

func _configure_overlay(data: GameData, scene: MapSceneData, level: int, lighting: MapLighting, diagnostics: PackedStringArray) -> String:
	if _overlay_view == null:
		return ""
	var resource: int = EntityModelSelection.explosion_resource_for(data, level)
	if resource < 0:
		return "Desert rock explosion model is not in level %d's model WAD" % level
	var file: MofFile = data.read_model(resource, diagnostics)
	var model_mesh: ModelMesh = null
	if file != null and file.error.is_empty() and not file.static_models.is_empty():
		model_mesh = ModelMeshBuilder.new(scene.library, scene.preferred).build_animated(file)
	var issue: String = _overlay_view.configure(file, model_mesh, lighting)
	if issue.is_empty():
		_overlay_view.set_projection_scale(GameplayProjection.clip_scale(Vector2i(get_viewport().get_visible_rect().size)))
	return issue

func _material(colour: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/presentation/tools/terrain_debug.gdshader")
	material.set_shader_parameter("tint", colour)
	material.set_shader_parameter("projection_scale", GameplayProjection.clip_scale(Vector2i(get_viewport().get_visible_rect().size)))
	return material

func _update_projection() -> void:
	var size := Vector2i(get_viewport().get_visible_rect().size)
	if size == _projection_size:
		return
	_projection_size = size
	_camera.fov = GameplayProjection.vertical_fov_degrees(size)
	_entity_pose_tick = -1
	var scale: Vector2 = GameplayProjection.clip_scale(size)
	if _swarm_view != null:
		_swarm_view.set_projection_scale(scale)
	if _cave_sprite_view != null:
		_cave_sprite_view.set_projection_scale(scale)
	if _overlay_view != null:
		_overlay_view.set_projection_scale(scale)
	if _placeholder_view != null:
		_placeholder_view.set_projection_scale(scale)
	if _tongue_view != null:
		_tongue_view.set_projection_scale(scale)
	if _map_instance != null:
		_map_instance.set_projection_scale(scale)
	if frog_assets != null and frog_assets.mesh != null:
		_set_model_projection(frog_assets.mesh, scale)
		if _frog_model != null:
			_frog_model.refresh_materials()
		_apply_frog_depth_bias()
	for instance: AnimatedModelInstance in _entity_models:
		if instance != null and instance.model_mesh != null:
			_set_model_projection(instance.model_mesh, scale)
			instance.refresh_materials()
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
	_set_model_parameter(model_mesh, "projection_scale", scale)

func _set_model_parameter(model_mesh: ModelMesh, parameter: StringName, value: Variant) -> void:
	for mesh: ArrayMesh in model_mesh.part_meshes:
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var material: ShaderMaterial = mesh.surface_get_material(surface) as ShaderMaterial
			if material != null:
				material.set_shader_parameter(parameter, value)
	for tracks: Array in model_mesh.texture_tracks:
		for track: ModelMesh.TextureTrack in tracks:
			if track.original != null:
				track.original.set_shader_parameter(parameter, value)
			for material: ShaderMaterial in track.frames:
				material.set_shader_parameter(parameter, value)

func _apply_frog_depth_bias() -> void:
	if frog_assets == null or frog_assets.mesh == null:
		return
	_set_model_parameter(frog_assets.mesh, "depth_bias", FROG_DEPTH_BIAS)
	if _frog_model == null:
		return
	for node: MeshInstance3D in _frog_model.part_nodes:
		for surface: int in node.get_surface_override_material_count():
			var material: ShaderMaterial = node.get_surface_override_material(surface) as ShaderMaterial
			if material != null:
				material.set_shader_parameter("depth_bias", FROG_DEPTH_BIAS)

## Attaches the shared high-detail frog rendering assets.
func build_frog(assets: TerrainFrogAssets) -> void:
	frog_assets = assets
	_apply_frog_depth_bias()
	_frog_model = AnimatedModelInstance.new()
	add_child(_frog_model)
	_frog_model.setup(frog_assets.mesh, frog_assets.player)
	_frog_model.smoothing_enabled = smoothing
	for mesh: ArrayMesh in frog_assets.mesh.part_meshes:
		if mesh != null:
			for surface: int in mesh.get_surface_count():
				var material: ShaderMaterial = mesh.surface_get_material(surface) as ShaderMaterial
				if material != null:
					material.set_shader_parameter("projection_scale", GameplayProjection.clip_scale(Vector2i(get_viewport().get_visible_rect().size)))
	_apply_frog_depth_bias()
	for index: int in _frog_model.part_nodes.size():
		_frog_model.part_nodes[index].visible = not frog_assets.hidden_parts.has(index)
	_frog.visible = false

## Captures a committed state and reconciles authored entity lifetimes.
func accept_state(state: GameplayState) -> void:
	_previous = _current if _current != null else state
	_current = state
	var created: PackedInt32Array = _sync_entity_models()
	for slot: int in _entity_models.size():
		if _entity_models[slot] != null and not created.has(slot):
			_entity_models[slot].player.advance_tick()
	_motion.capture(_previous, _current)

## Instantiates a decoded map without advancing simulation.
func build_map(scene_data: MapSceneData) -> void:
	_projection_size = Vector2i.ZERO
	for child: Node in _ground.get_children():
		_ground.remove_child(child)
		child.queue_free()
	_map_instance = MapMeshBuilder.new().build(scene_data).create_instance()
	_ground.add_child(_map_instance)
	_map_instance.set_projection_scale(GameplayProjection.clip_scale(Vector2i(get_viewport().get_visible_rect().size)))

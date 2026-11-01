class_name GameplayWorldView
extends Node3D
## Shared world drawing from committed gameplay snapshots, independent of inspection.

## Game units the frog's depth moves toward the camera: its local ordering table
## enters the global one at origin depth plus FROG_GLOBAL_OT_OFFSET (-0x30, FROG.H)
## before the otz shift (FROG.C, MR_ANIM.C).
const FROG_DEPTH_BIAS: float = 48.0
## Frog generator kinds by Frog_particle_effects slot.
const FROG_PARTICLE_KINDS: Array[ParticleField.Kind] = [ParticleField.Kind.FROG_SLIDE, ParticleField.Kind.FROG_BUBBLE, ParticleField.Kind.FROG_FIRE]
## The frog's croak sack part, THROAT of GEN_FROG_PARTS (gen_frog.h:35).
const THROAT_PART: int = 15
## Des_rock_shadow_offsets (ent_des.c:33-39), the falling rock and tumbleweed shadow corners.
const DESERT_SHADOW_OFFSETS: Array[Vector3i] = [Vector3i(-0x70, 0, 0x70), Vector3i(0x70, 0, 0x70), Vector3i(-0x70, 0, -0x70), Vector3i(0x70, 0, -0x70)]
## Seed of the entity particle stream.
const ENTITY_FIELD_SEED: int = 0x50a11c
## Colour scale of an entity mesh no fade has scaled.
const UNSCALED_COLOUR := Vector3i(128, 128, 128)

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
var _definitions: Array[EntityDefinition] = []
var _camera: Camera3D
var _map_instance: MapMesh.Instance
var _frog_pose_tick: int = -1
var _projection_size: Vector2i = Vector2i.ZERO
var _entity_models: Array[AnimatedModelInstance] = []
var _entity_meshes: Array[ModelMesh] = []
var _drawn_meshes: Dictionary[ModelMesh, ModelMesh] = {}
var _entity_files: Array[MofFile] = []
var _entity_generations: Array[int] = []
var _entity_pose_tick: int = -1
var _entity_lighting: MapLighting = null
var _motion := TerrainMotion.new()
## Level grid that supplies shadow heights; null leaves shadows off.
var effect_grid: GridDefinition = null
var _shadow_view: FrogShadowView
var _trail_view: HopTrailView
var _particle_view: ParticleSpriteView
var _pop_view: PopRingView
var _splash_view: SplashView
var _piece_view: PolyPiecePopView
var _glow_view: GoldGlowView
var _entity_fields: EntityParticleFields = null
var _field_generations: Dictionary[int, int] = {}
var _effects: EffectResources = null
var _trail := HopTrailState.new()
var _fields: Array[ParticleField] = []
var _frog_field: ParticleField = null
var _rings: Array[PopRingGeometry] = []
var _splashes: Array[SplashView.Splash] = []
var _effect_tick: int = -1
var _effect_drawn_tick: int = -1
var _frog_light_tick: int = -1
var _options_lighting: MapLighting = null
## Whether [method build_world] creates the sound-effect and music players.
var audio_enabled: bool = false
var _voice_view: SoundVoiceView = null
var _music_player: MusicPlayer = null
## The scene's lights and environment, created by [method build_world].
var scene_lighting: SceneLighting = null
## The shadow-effect setting, [constant ShadowEffectPolicy.RETAIL] or
## [constant ShadowEffectPolicy.OFF]; it decides through [ShadowEffectPolicy]
## whether the blob shadow effects draw.
var effect_shadows: String = ShadowEffectPolicy.DEFAULT
## Whether the scene lights cast real shadows; read when entities are built.
var real_shadows: bool = true

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
		if _frog_light_tick != _current.tick_index:
			_light_frog(_current.frog)
			_apply_throat(_current.frog)
			_frog_light_tick = _current.tick_index
		_frog_model.render(weight)
	_draw_effects(frog_transform, weight)
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
	var cave_lit: bool = _cave_lit()
	if cave_lit:
		var radii: PackedInt64Array = cave_radii(weight)
		scene_lighting.set_cave_light(frog_transform.origin, radii[0], radii[1], GraphicsMapping.cave_mode(GraphicsProfile.current().cave_light_mode))
	elif scene_lighting != null and scene_lighting.cave_light_node() != null:
		scene_lighting.clear_cave_light()
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
					var scaled: bool = entity.colour_scaled or entity.colour_scale != Vector3i.ZERO
					if scaled and cave_lit and cave_faded(entity):
						scaled = false
					model.set_source_lighting(_entity_lighting, entity.colour_scale, entity.ambient, scaled, entity.ambient != Vector3i.ZERO)
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

## Squared cave radii between the previous and current committed states at
## [param weight]; the map's initial radii when no state carries an entity environment.
func cave_radii(weight: float) -> PackedInt64Array:
	var now: EntityEnvironmentState = _current.entity_environment if _current != null else null
	if now == null:
		var scene: MapSceneData = _map_instance.source.scene if _map_instance != null else null
		return PackedInt64Array([scene.cave_min_r2, scene.cave_max_r2]) if scene != null else PackedInt64Array([0, 0])
	var before: EntityEnvironmentState = _previous.entity_environment if _previous != null and _previous.entity_environment != null else now
	return PackedInt64Array([
		roundi(lerpf(float(before.light_min_squared), float(now.light_min_squared), weight)),
		roundi(lerpf(float(before.light_max_squared), float(now.light_max_squared), weight)),
	])

## True when [param entity]'s colour scale is the cave fade alone
## (EntityScaleColours replaces the scale with the fade grey), so a lit model
## leaves it to the cave light. Entities that opt out of screen fades, are not
## displayed, or multiply script colours by the fade keep their scale.
static func cave_faded(entity: EntitySnapshot) -> bool:
	return entity.colour_scaled and not entity.live_flags & (EntityLiveFlags.NO_SCREEN_FADE | EntityLiveFlags.RESPECT_SCALE_COLOURS) and not entity.entity_flags & EntityDefinition.NO_DISPLAY

func _notification(what: int) -> void:
	if what != NOTIFICATION_ENTER_TREE and what != NOTIFICATION_EXIT_TREE:
		return
	var profile: GraphicsSettings = GraphicsProfile.current()
	var connected: bool = profile.changed.is_connected(_apply_look)
	if what == NOTIFICATION_ENTER_TREE and not connected:
		profile.changed.connect(_apply_look)
	elif what == NOTIFICATION_EXIT_TREE and connected:
		profile.changed.disconnect(_apply_look)

## Gives the glow halos their strength and the map the water look, vertex
## tint and lava emission of the live graphics profile.
func _apply_look() -> void:
	var settings: GraphicsSettings = GraphicsProfile.current()
	if _cave_sprite_view != null:
		_cave_sprite_view.set_halo_strength(settings.glow_halo_strength)
	if _glow_view != null:
		_glow_view.set_halo_strength(settings.glow_halo_strength)
	if _map_instance == null:
		return
	_map_instance.set_water_look(settings.water_reflection, settings.water_specular, settings.water_shininess)
	_map_instance.set_vertex_tint(settings.vertex_tint)
	_map_instance.set_emission_scale(settings.lava_emission)

func _cave_lit() -> bool:
	return scene_lighting != null and _map_instance != null and _map_instance.source.scene.cave_enabled

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
	_shadow_view = FrogShadowView.new()
	add_child(_shadow_view)
	_trail_view = HopTrailView.new()
	add_child(_trail_view)
	_particle_view = ParticleSpriteView.new()
	add_child(_particle_view)
	_splash_view = SplashView.new()
	add_child(_splash_view)
	_pop_view = PopRingView.new()
	add_child(_pop_view)
	_piece_view = PolyPiecePopView.new()
	add_child(_piece_view)
	_glow_view = GoldGlowView.new()
	add_child(_glow_view)
	if audio_enabled:
		_voice_view = SoundVoiceView.new()
		add_child(_voice_view)
		_music_player = MusicPlayer.new()
		add_child(_music_player)
	scene_lighting = SceneLighting.new()
	add_child(scene_lighting)
	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.position = Vector3(3.5, 4.5, 5.5)
	_camera.fov = 45.0
	add_child(_camera)
	_camera.look_at(Vector3.ZERO)
	_camera.current = true
	_apply_look()

func _clear_entity_visuals() -> void:
	if scene_lighting != null:
		scene_lighting.clear()
	if _swarm_view != null:
		_swarm_view.clear()
	if _cave_sprite_view != null:
		_cave_sprite_view.clear()
	if _overlay_view != null:
		_overlay_view.clear()
	if _placeholder_view != null:
		_placeholder_view.clear()
	_sprite_definitions = []
	_definitions = []
	if _piece_view != null:
		_piece_view.clear()
		_glow_view.collapse()
	_release_entity_fields()
	for model: AnimatedModelInstance in _entity_models:
		if model != null:
			remove_child(model)
			model.queue_free()
	_entity_models.clear()
	_entity_meshes.clear()
	_drawn_meshes.clear()
	_entity_files.clear()
	_entity_generations.clear()

## Resolves render resources for the validated authored entity definitions.
func build_entities(definitions: EntityCollisionDefinition, scene_data: MapSceneData, selected_data: AssetCatalog, use_lighting: bool = true) -> void:
	_clear_entity_visuals()
	_entity_pose_tick = -1
	_entity_lighting = null
	_frog_light_tick = -1
	if definitions == null:
		return
	_definitions = definitions.entities
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
	_light_scene(_entity_lighting)
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
			meshes[resource] = ModelMeshLibrary.mesh_for(selected_data, resource, scene_data.library, scene_data.preferred)
		if not meshes.has(resource):
			continue
		_entity_meshes[slot] = _drawn_mesh(meshes[resource])
		_entity_files[slot] = files[resource]
		if _piece_view != null:
			_piece_view.set_model(slot, files[resource], scene_data.library, scene_data.preferred)
	_configure_hilite_particles(scene_data)
	_sync_entity_models()
	if _current != null:
		_projection_size = Vector2i.ZERO
		draw_state(1.0)

## Resolves entity models from per-slot origins without a map, marking unresolved slots; returns diagnostics.
func build_mapless_entities(definitions: EntityCollisionDefinition, origins: EntityModelOrigins) -> PackedStringArray:
	_clear_entity_visuals()
	_entity_pose_tick = -1
	_entity_lighting = null
	_frog_light_tick = -1
	if definitions == null:
		return PackedStringArray()
	_definitions = definitions.entities
	var resources: MaplessEntityResources = MaplessEntityResources.resolve(definitions.entities, origins)
	var diagnostics: PackedStringArray = resources.diagnostics
	var sprite_slots: Dictionary[int, bool] = {}
	var swarm_ready: bool = false
	var sprites_ready: bool = false
	var overlay_tried: bool = false
	_light_scene(null)
	for slot: int in definitions.entities.size():
		var entity: EntityDefinition = definitions.entities[slot]
		_entity_models.append(null)
		_entity_meshes.append(_drawn_mesh(resources.meshes[slot]))
		_entity_files.append(resources.files[slot])
		_entity_generations.append(-1)
		if origins == null or not origins.resolvable(slot) or origins.data == null or not origins.data.is_valid():
			continue
		var scene: MapSceneData = resources.scene_for(origins.data, origins.themes[slot])
		if resources.files[slot] != null and _piece_view != null:
			_piece_view.set_model(slot, resources.files[slot], scene.library, scene.preferred)
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

## Lights the scene from [param lighting], or from the options screen's
## lights when there are no map lights.
func _light_scene(lighting: MapLighting) -> void:
	if scene_lighting == null:
		return
	scene_lighting.apply(SceneLightingBuilder.from_lighting(_lighting_or_options(lighting), real_shadows))

func _lighting_or_options(lighting: MapLighting) -> MapLighting:
	if lighting != null and not (lighting.directions.is_empty() and lighting.ambient.is_zero_approx()):
		return lighting
	if _options_lighting == null:
		_options_lighting = OptionsModels.options_lighting()
	return _options_lighting

func _configure_overlay(data: AssetCatalog, scene: MapSceneData, level: int, lighting: MapLighting, diagnostics: PackedStringArray) -> String:
	if _overlay_view == null:
		return ""
	var resource: int = EntityModelSelection.explosion_resource_for(data, level)
	if resource < 0:
		return "Desert rock explosion model is not in level %d's model WAD" % level
	var file: MofFile = data.read_model(resource, diagnostics)
	var model_mesh: ModelMesh = null
	if file != null and file.error.is_empty() and not file.static_models.is_empty():
		model_mesh = ModelMeshLibrary.mesh_for(data, resource, scene.library, scene.preferred)
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
	if _shadow_view != null:
		_set_effect_projection(scale)
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

func _drawn_mesh(shared: ModelMesh) -> ModelMesh:
	if shared == null:
		return null
	if not _drawn_meshes.has(shared):
		_drawn_meshes[shared] = ModelMeshCopy.of(shared)
	return _drawn_meshes[shared]

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

## Attaches the high-detail frog rendering assets, drawn with this view's own copy of their materials.
func build_frog(assets: TerrainFrogAssets) -> void:
	frog_assets = assets.with_mesh(ModelMeshCopy.of(assets.mesh))
	_apply_frog_depth_bias()
	_frog_light_tick = -1
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
	_show_frog_parts()
	_frog.visible = false

func _show_frog_parts() -> void:
	for index: int in _frog_model.part_nodes.size():
		_frog_model.part_nodes[index].visible = not frog_assets.hidden_parts.has(index)

## Applies the frog's committed colour scale and custom ambient as entities'
## are (MR_LIGHT.C MRCalculateCustomInstanceLights), under the map's lights or
## the options screen's lights without them.
func _light_frog(frog: FrogState) -> void:
	_frog_model.set_source_lighting(_lighting_or_options(_entity_lighting), frog.colour_scale, frog.custom_ambient, (frog.tint_flags & FrogTint.SCALED_COLOURS) != 0, (frog.tint_flags & FrogTint.CUSTOM_AMBIENT) != 0)

## Captures a committed state and reconciles authored entity lifetimes; the
## tick's [param events] start and stop presentation effects.
func accept_state(state: GameplayState, events: Array[TickEvent] = []) -> void:
	var fresh: bool = _current == null
	_previous = _current if _current != null else state
	_current = state
	var created: PackedInt32Array = _sync_entity_models()
	for slot: int in _entity_models.size():
		if _entity_models[slot] != null and not created.has(slot):
			_entity_models[slot].player.advance_tick()
	_motion.capture(_previous, _current)
	if fresh:
		collapse_effects()
		if _music_player != null:
			_music_player.restart()
	if state != null and state.tick_index != _effect_tick:
		_step_effects(_previous, state, events)
		_effect_tick = state.tick_index
	if _voice_view != null:
		_voice_view.accept_state(_previous, state)

## Supplies the sound-effect streams, building those of [param sound_ids] now; null silences effects.
func configure_audio(resources: AudioResources, sound_ids: PackedInt32Array = PackedInt32Array()) -> void:
	if _voice_view == null:
		return
	_voice_view.configure(resources)
	_voice_view.preload_sounds(sound_ids)

## Selects the level music played from each run start: imported CD track [param track]; -1 plays none.
func configure_music(track: int) -> void:
	if _music_player != null:
		_music_player.select(track)

## Holds or resumes every sound effect and the music where they are.
func pause_audio(paused: bool) -> void:
	if _voice_view == null:
		return
	_voice_view.pause(paused)
	_music_player.pause(paused)

## The sound-effect player pool, or null when audio is disabled.
func voice_view() -> SoundVoiceView:
	return _voice_view

## The level music player, or null when audio is disabled.
func music_player() -> MusicPlayer:
	return _music_player

## Supplies the level grid that shadows read heights from.
func set_effect_grid(grid: GridDefinition) -> void:
	effect_grid = grid
	if _shadow_view != null:
		_shadow_view.set_grid(grid)

## Forgets every running effect: trail, particles, pop rings, splashes, pops, glows, sounds and music.
func collapse_effects() -> void:
	if _voice_view != null:
		_voice_view.collapse()
		_music_player.collapse()
	_trail.collapse()
	_fields.clear()
	_frog_field = null
	_rings.clear()
	_splashes.clear()
	_effect_tick = -1
	_effect_drawn_tick = -1
	_frog_light_tick = -1
	_field_generations.clear()
	if _entity_fields != null:
		_entity_fields.collapse()
	if _shadow_view != null:
		_shadow_view.draw_shadows([])
		_trail_view.clear()
		_particle_view.draw_fields([], null, 1.0)
		_pop_view.clear()
		_splash_view.draw_splashes([])
		_piece_view.collapse()
		_glow_view.collapse()
		_glow_view.draw_glows(null, 1.0)

## Live particle fields, the frog's first.
func effect_fields() -> Array[ParticleField]:
	return _fields

## Live pop rings.
func effect_rings() -> Array[PopRingGeometry]:
	return _rings

## Live splashes.
func effect_splashes() -> Array[SplashView.Splash]:
	return _splashes

## The frog's trail.
func effect_trail() -> HopTrailState:
	return _trail

## Canvas point of game point [param at] on the 640x480 game view of [param camera].
static func canvas_point(camera: GameplayCameraSnapshot, at: Vector3i) -> Vector2i:
	var relative := Vector3(at - camera.source_world)
	var depth: float = relative.dot(Vector3(camera.axis_z_12)) / 4096.0
	if depth <= 0.0:
		return Vector2i(-0x8000, -0x8000)
	var right: float = relative.dot(Vector3(camera.axis_x_12)) / 4096.0
	var down: float = relative.dot(Vector3(camera.axis_y_12)) / 4096.0
	return Vector2i(floori(320.0 + EffectSpriteMaterial.FOCAL_X * right / depth), floori(240.0 + EffectSpriteMaterial.FOCAL_Y * down / depth))

## True when game point [param at] lies in front of [param camera].
static func in_front_of(camera: GameplayCameraSnapshot, at: Vector3i) -> bool:
	return Vector3(at - camera.source_world).dot(Vector3(camera.axis_z_12)) > 0.0

func _configure_effects(scene_data: MapSceneData) -> void:
	collapse_effects()
	_effects = scene_data.effects if scene_data != null else null
	if _shadow_view == null:
		return
	var issues := PackedStringArray()
	var shadow_symbols := PackedStringArray(["im_frog_shadow0", "im_frog_shadow1", "im_frog_shadow2", FrogShadowGeometry.NO_ROTATION_TEXTURE])
	issues.append(_shadow_view.configure(scene_data, effect_grid, shadow_symbols))
	issues.append(_particle_view.configure(scene_data, _frog_generators()))
	issues.append(_splash_view.configure(scene_data))
	issues.append(_glow_view.configure(scene_data))
	_entity_fields = null
	if _effects != null:
		_entity_fields = EntityParticleFields.new()
		_entity_fields.configure(_effects, ENTITY_FIELD_SEED)
	_set_effect_projection(GameplayProjection.clip_scale(Vector2i(get_viewport().get_visible_rect().size)))
	if scene_data != null:
		for issue: String in issues:
			if not issue.is_empty():
				scene_data.diagnostics.append(issue)

func _frog_generators() -> PackedStringArray:
	var names := PackedStringArray()
	if _effects != null and _effects.generators != null:
		for generator_name: String in _effects.generators.frog_particle_single:
			if not generator_name.is_empty():
				names.append(generator_name)
	return names

func _configure_hilite_particles(scene_data: MapSceneData) -> void:
	var used: Dictionary[int, bool] = {}
	for definition: EntityDefinition in _definitions:
		for hilite: ParticleHilite in definition.particle_hilites:
			used[hilite.kind] = true
	if used.is_empty() or _particle_view == null or scene_data == null or scene_data.effects == null:
		return
	var names: PackedStringArray = _frog_generators()
	for kind: int in EntityParticleFields.GENERATOR_NAMES.size():
		if used.has(kind):
			var generator_name: String = EntityParticleFields.GENERATOR_NAMES[kind]
			names.append(generator_name)
			if ParticleSpriteView.generator_images(scene_data.effects, generator_name).is_empty():
				scene_data.diagnostics.append("Particle image for %s is unavailable" % generator_name)
	_particle_view.configure(scene_data, names)
	_particle_view.set_projection_scale(GameplayProjection.clip_scale(Vector2i(get_viewport().get_visible_rect().size)))

func _set_effect_projection(scale: Vector2) -> void:
	_shadow_view.set_projection_scale(scale)
	_trail_view.set_projection_scale(scale)
	_particle_view.set_projection_scale(scale)
	_pop_view.set_projection_scale(scale)
	_splash_view.set_projection_scale(scale)
	_piece_view.set_projection_scale(scale)
	_glow_view.set_projection_scale(scale)

func _step_effects(before: GameplayState, after: GameplayState, events: Array[TickEvent]) -> void:
	var collected_before: int = before.entity_environment.collected if before.entity_environment != null else 0
	var collected_after: int = after.entity_environment.collected if after.entity_environment != null else 0
	if collected_after & ~collected_before:
		_kill_frog_field(-1)
	for event: TickEvent in events:
		match event.kind:
			TickEvent.Kind.SUPER_HOP:
				_trail.start(true)
			TickEvent.Kind.HOP, TickEvent.Kind.QUICK_HOP, TickEvent.Kind.AUTO_HOP, TickEvent.Kind.ROLL:
				_trail.start(false)
			TickEvent.Kind.SLIDE_PARTICLES_REQUEST:
				_start_frog_field(0, after.tick_index)
			TickEvent.Kind.SLIDE_PARTICLES_STOP:
				if _frog_field != null and _frog_field.kind == ParticleField.Kind.FROG_SLIDE:
					_kill_frog_field(-1)
			TickEvent.Kind.DEATH_FIRE_PARTICLE_REQUEST:
				_kill_frog_field(ParticleField.KILL_WHEN_FROG_DEAD)
				_start_frog_field(2, after.tick_index)
			TickEvent.Kind.DEATH_ANIMATION:
				_kill_frog_field(ParticleField.KILL_WHEN_FROG_DEAD)
				_rings.append(PopRingGeometry.new(_pop_colour()))
			TickEvent.Kind.SPRITE:
				var splash: SplashView.Splash = entity_splash(after, event)
				if splash != null:
					_splashes.append(splash)
			TickEvent.Kind.SPLASH:
				_splashes.append(SplashView.Splash.new(event.position))
				if event.entity_index < 0 and after.frog.death_equate == FrogAnimationCatalog.DROWN:
					_start_frog_field(1, after.tick_index)
			TickEvent.Kind.LEVEL_TRANSITION:
				if event.flow_phase == LevelFlowState.Phase.PLAY:
					_kill_frog_field(ParticleField.KILL_WHEN_FROG_RESET)
					_trail.collapse()
	var frog: FrogState = after.frog
	_trail.step(frog.matrix12)
	var fields: Array[ParticleField] = []
	for field: ParticleField in _fields:
		field.step(frog.matrix12, frog.velocity_16 != Vector3i.ZERO)
		if not field.finished:
			fields.append(field)
	_fields = fields
	if _frog_field != null and _frog_field.finished:
		_frog_field = null
	var rings: Array[PopRingGeometry] = []
	for ring: PopRingGeometry in _rings:
		ring.step()
		if ring.drawn():
			rings.append(ring)
	_rings = rings
	var splashes: Array[SplashView.Splash] = []
	for splash: SplashView.Splash in _splashes:
		splash.timeline.update()
		if not splash.timeline.killed:
			_follow_owner(splash, after)
			splashes.append(splash)
	_splashes = splashes
	_step_entity_effects(before, after)

func _start_frog_field(slot: int, tick: int) -> void:
	if (_frog_field != null and not _frog_field.finished) or _effects == null or _effects.generators == null:
		return
	var generators: ExeParticleGenerators = _effects.generators
	if slot >= generators.frog_particle_single.size() or generators.frog_particle_single[slot].is_empty():
		return
	var record: ParticleGeneratorRecord = generators.find(generators.frog_particle_single[slot])
	if record == null:
		return
	var flags: int = generators.frog_particle_flags[slot] if slot < generators.frog_particle_flags.size() else 0
	_frog_field = ParticleField.new(FROG_PARTICLE_KINDS[slot], record, flags, hash([tick, slot]))
	_fields.push_front(_frog_field)

func _kill_frog_field(flags: int) -> void:
	if _frog_field == null:
		return
	if flags >= 0 and not _frog_field.kill_flags & flags:
		return
	_frog_field.kill()
	_fields.erase(_frog_field)
	_frog_field = null

func _pop_colour() -> int:
	if _effects != null and _effects.generators != null and not _effects.generators.pop_colours.is_empty():
		return _effects.generators.pop_colours[0]
	return ExeParticleGenerators.C_POP_COLOURS[0]

## Sets [member effect_shadows] and [member real_shadows] from launch
## [param arguments], falling back to the project settings.
func apply_shadow_arguments(arguments: PackedStringArray) -> void:
	effect_shadows = ViewerArguments.effect_shadows(arguments)
	real_shadows = ViewerArguments.shadows(arguments)

## Whether the frog and Desert blob shadow effects draw under [member effect_shadows].
func draws_effect_shadows() -> bool:
	return ShadowEffectPolicy.draws_blob_shadows(effect_shadows)

## The blob shadows of the current state at render [param weight] with the
## frog drawn at [param frog_transform]: the frog's, then each Desert rock's
## and tumbleweed's; empty when [method draws_effect_shadows] is false.
func shadow_requests(frog_transform: Transform3D, weight: float) -> Array[FrogShadowView.Request]:
	var requests: Array[FrogShadowView.Request] = []
	if _current == null or not draws_effect_shadows():
		return requests
	if effect_grid != null and not FrogShadowGeometry.hidden(_current):
		var request := FrogShadowView.Request.new()
		var frog: FrogState = _current.frog
		var jump_phase: int = FrogShadowGeometry.phase(frog.mode, frog.flags, frog.remaining_ticks)
		request.matrix12 = frog.matrix12
		request.translation = GameSpace.to_game(frog_transform.origin)
		request.offsets = FrogShadowGeometry.phase_offsets(jump_phase)
		request.symbol = FrogShadowGeometry.PHASE_TEXTURES[jump_phase]
		requests.append(request)
	if effect_grid != null and _current.entities != null:
		for slot: int in mini(_definitions.size(), _current.entities.entities.size()):
			var shadow: FrogShadowView.Request = entity_shadow(_definitions[slot], _current.entities.entities[slot], GameSpace.to_game(_motion.entity(slot, weight).origin))
			if shadow != null:
				requests.append(shadow)
	return requests

func _draw_effects(frog_transform: Transform3D, weight: float) -> void:
	if _shadow_view == null:
		return
	_shadow_view.draw_shadows(shadow_requests(frog_transform, weight))
	var fields: Array[ParticleField] = _fields.duplicate()
	if _entity_fields != null:
		fields.append_array(_entity_fields.fields())
	_particle_view.draw_fields(fields, _current.camera, weight)
	_glow_view.draw_glows(_current.camera, weight)
	if scene_lighting != null:
		var points: Array[GlowLightSpec.Point] = []
		points.append_array(_cave_sprite_view.glow_points())
		points.append_array(_glow_view.glow_points())
		scene_lighting.place_glow_lights(points, _camera.position)
	var origin: Vector3 = Vector3(frog_transform.origin.x, -frog_transform.origin.y, -frog_transform.origin.z) * GameSpace.UNITS_PER_SQUARE
	_pop_view.draw_rings(_rings, origin, _current.camera, _current.game_timer)
	if _effect_drawn_tick != _current.tick_index:
		_trail_view.draw_trail(_trail)
		_splash_view.draw_splashes(_splashes)
		_effect_drawn_tick = _current.tick_index

## The shadow request of a Desert falling rock or tumbleweed whose committed
## shadow is on, drawn at game [param translation]; null for any other entity.
## The rock keeps EFFECT_NO_ROTATION; the shown tumbleweed clears it and turns
## by its matrix's quadrant (ent_des.c:255-256, 1714-1729).
static func entity_shadow(definition: EntityDefinition, entity: EntitySnapshot, translation: Vector3i) -> FrogShadowView.Request:
	if definition == null or definition.behavior == null or not entity.live or entity.custom_state == null or not entity.custom_state.shadow_visible:
		return null
	var kind: EntityBehavior.Kind = definition.behavior.kind
	if kind != EntityBehavior.Kind.DES_FALLING_ROCK and kind != EntityBehavior.Kind.DES_TUMBLE_WEED:
		return null
	var request := FrogShadowView.Request.new()
	request.matrix12 = entity.matrix12.duplicate()
	request.translation = translation
	request.offsets = DESERT_SHADOW_OFFSETS.duplicate()
	request.symbol = FrogShadowGeometry.NO_ROTATION_TEXTURE
	request.no_rotation = kind == EntityBehavior.Kind.DES_FALLING_ROCK
	return request

## The splash of an entity's SPRITE [param event] in [param state]: its
## offset is in the entity's frame, which carries the splash; null when the
## entity is not in the snapshot.
static func entity_splash(state: GameplayState, event: TickEvent) -> SplashView.Splash:
	var slot: int = _slot_of(state, event.entity_index)
	if slot < 0:
		return null
	var splash := SplashView.Splash.new()
	splash.owner = slot
	splash.offset = event.position
	_follow_owner(splash, state)
	return splash

## Game-space 12-bit matrix of a hilite vertex: the entity rotation times the
## part's animation rotation, translated to the turned partcel-0 vertex
## (UpdateLiveEntitySpecials, ENTITY.C:1904-1953). The source drops the
## part's own translation; an empty [param part_matrix] is a static part.
static func hilite_matrix(entity_matrix: PackedInt32Array, part_matrix: PackedInt32Array, vertex: Vector3i) -> PackedInt32Array:
	var rotation: PackedInt32Array = PlatformMath.multiply(entity_matrix, part_matrix) if part_matrix.size() == 12 else PlatformMath.multiply(entity_matrix, EntityTransform.IDENTITY)
	var turned: Vector3i = PlatformMath.apply(rotation, vertex)
	rotation[9] = PlatformMath.s32(entity_matrix[9] + turned.x)
	rotation[10] = PlatformMath.s32(entity_matrix[10] + turned.y)
	rotation[11] = PlatformMath.s32(entity_matrix[11] + turned.z)
	return rotation

static func _slot_of(state: GameplayState, entity_index: int) -> int:
	if state == null or state.entities == null or entity_index < 0:
		return -1
	for slot: int in state.entities.entities.size():
		if state.entities.entities[slot].entity_index == entity_index:
			return slot
	return -1

static func _follow_owner(splash: SplashView.Splash, state: GameplayState) -> void:
	if splash.owner < 0 or state.entities == null or splash.owner >= state.entities.entities.size():
		return
	var entity: EntitySnapshot = state.entities.entities[splash.owner]
	if not entity.live:
		return
	splash.origin = PlatformMath.apply(entity.matrix12, splash.offset) + Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11])

func _apply_throat(frog: FrogState) -> void:
	if THROAT_PART >= _frog_model.part_nodes.size():
		return
	_frog_model.set_part_scale(THROAT_PART, frog.croak_scale / 4096.0)
	_frog_model.part_nodes[THROAT_PART].visible = frog.croak_mode != FrogCroak.Mode.NONE

func _step_entity_effects(before: GameplayState, after: GameplayState) -> void:
	if after.entities == null:
		return
	if _piece_view != null:
		_piece_view.accept(after.entities.entities)
		_glow_view.accept(_definitions, after.entities.entities)
	_step_entity_fields(before, after)

func _step_entity_fields(before: GameplayState, after: GameplayState) -> void:
	if _entity_fields == null:
		return
	var entities: Array[EntitySnapshot] = after.entities.entities
	for slot: int in mini(_definitions.size(), entities.size()):
		var hilites: Array[ParticleHilite] = _definitions[slot].particle_hilites
		if hilites.is_empty():
			continue
		var entity: EntitySnapshot = entities[slot]
		if after.entities.lifecycle_enabled and not entity.live:
			if _field_generations.has(slot):
				_entity_fields.release(slot)
				_field_generations.erase(slot)
			continue
		if _field_generations.get(slot, -1) != entity.generation:
			_entity_fields.ensure(slot, entity.generation, hilites)
			_field_generations[slot] = entity.generation
		var previous: EntitySnapshot = before.entities.entities[slot] if before != null and before.entities != null and slot < before.entities.entities.size() else null
		var moving: bool = previous != null and previous.generation == entity.generation and previous.live and (previous.matrix12[9] != entity.matrix12[9] or previous.matrix12[10] != entity.matrix12[10] or previous.matrix12[11] != entity.matrix12[11])
		var colour: Vector3i = entity.colour_scale if entity.colour_scaled else UNSCALED_COLOUR
		for index: int in hilites.size():
			var hilite: ParticleHilite = hilites[index]
			_entity_fields.step(slot, index, hilite_matrix(entity.matrix12, _part_matrix(slot, entity, hilite.part), _hilite_vertex(slot, hilite)), moving, colour)

func _part_matrix(slot: int, entity: EntitySnapshot, part: int) -> PackedInt32Array:
	var file: MofFile = _entity_files[slot] if slot < _entity_files.size() else null
	if file == null or file.animated == null or entity.animation == null or entity.animation.action < 0:
		return PackedInt32Array()
	return file.animated.sample_matrix(0, entity.animation.action, maxi(entity.animation.cel, 0), part)

func _hilite_vertex(slot: int, hilite: ParticleHilite) -> Vector3i:
	var file: MofFile = _entity_files[slot] if slot < _entity_files.size() else null
	if file == null or file.static_models.is_empty() or hilite.part >= file.static_models[0].parts.size():
		return Vector3i.ZERO
	var part: MofPart = file.static_models[0].parts[hilite.part]
	if part.partcels.is_empty():
		return Vector3i.ZERO
	var vertices: PackedInt32Array = part.partcels[0].vertices
	var at: int = hilite.vertex * 3
	return Vector3i(vertices[at], vertices[at + 1], vertices[at + 2]) if at + 2 < vertices.size() else Vector3i.ZERO

func _release_entity_fields() -> void:
	if _entity_fields != null:
		for slot: int in _field_generations:
			_entity_fields.release(slot)
	_field_generations.clear()

## Instantiates a decoded map without advancing simulation.
func build_map(scene_data: MapSceneData) -> void:
	_projection_size = Vector2i.ZERO
	for child: Node in _ground.get_children():
		_ground.remove_child(child)
		child.queue_free()
	_map_instance = MapMeshBuilder.new().build(scene_data).create_instance()
	_ground.add_child(_map_instance)
	_map_instance.set_projection_scale(GameplayProjection.clip_scale(Vector2i(get_viewport().get_visible_rect().size)))
	_apply_look()
	_configure_effects(scene_data)

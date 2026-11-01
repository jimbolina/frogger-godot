extends GutTest
## The gameplay frog takes its committed colour scale and custom ambient as its tint under the map's
## lights or the options lights; the scene is lit from the map's lights, casts real shadows unless
## switched off and draws the blob shadow effects only when the shadow-effect setting keeps them; the map's
## water look, vertex tint and cave light mode follow the live graphics profile, and the built map's lava
## lights its surroundings.

const SCALE := Vector3i(0, 64, 192)
const AMBIENT := Vector3i(32, 64, 64)

var _view: GameplayWorldView
var _lighting: MapLighting
var _tick: int = 0

func before_each() -> void:
	_view = GameplayWorldView.new()
	add_child_autofree(_view)
	_view.build_world()
	var assets := TerrainFrogAssets.new()
	assets.model = SyntheticMof.static_file([SyntheticMof.square(MofPolygonType.F4)])
	assets.mesh = ModelMeshBuilder.new(TextureLibrary.new()).build_animated(assets.model)
	assets.player = ModelAnimationPlayer.new(assets.model)
	_view.build_frog(assets)
	_lighting = OptionsModels.options_lighting()
	_tick = 0

func after_each() -> void:
	GraphicsProfile.reset()

func _draw(flags: int) -> void:
	_tick += 1
	var state := GameplayState.new()
	state.tick_index = _tick
	state.frog.colour_scale = SCALE
	state.frog.custom_ambient = AMBIENT
	state.frog.tint_flags = flags
	_view.accept_state(state)
	_view.draw_state(1.0)

func _depth_bias() -> float:
	var material: ShaderMaterial = _view._frog_model.part_nodes[0].get_active_material(0) as ShaderMaterial
	var value: float = material.get_shader_parameter("depth_bias") if material != null else -1.0
	return value

func _assert_tint(expected: SceneTint) -> void:
	assert_eq(_view._frog_model.scene_tint.scale, expected.scale)
	assert_eq(_view._frog_model.scene_tint.ambient, expected.ambient)
	assert_eq(_depth_bias(), GameplayWorldView.FROG_DEPTH_BIAS)

func test_map_lights_leave_the_frog_untinted_without_flags() -> void:
	_view._entity_lighting = _lighting
	_draw(0)
	_assert_tint(SceneTint.new())

func test_custom_ambient_and_colour_scale_tint_the_frog() -> void:
	_view._entity_lighting = _lighting
	_draw(FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS)
	_assert_tint(SceneTint.of(SCALE, AMBIENT, true, true))

func test_without_map_lights_the_frog_takes_the_options_lights() -> void:
	_draw(FrogTint.SCALED_COLOURS)
	_assert_tint(SceneTint.of(SCALE, AMBIENT, true, false))
	assert_eq(_view._lighting_or_options(null).ambient, OptionsModels.options_lighting().ambient)

func test_rebuilding_entities_without_lights_keeps_the_tint_on_the_same_tick() -> void:
	var flags: int = FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS
	_view._entity_lighting = _lighting
	_draw(flags)
	_view.build_entities(null, null, null)
	assert_null(_view._entity_lighting)
	_view.draw_state(1.0)
	_assert_tint(SceneTint.of(SCALE, AMBIENT, true, true))

func _lit_map() -> MapSceneData:
	var ambient := MapLight.new()
	ambient.light_type = 1
	ambient.enabled = true
	ambient.color = Color8(0x30, 0x40, 0x50)
	var parallel := MapLight.new()
	parallel.light_type = 2
	parallel.enabled = true
	parallel.color = Color8(0xc0, 0xa0, 0x80)
	parallel.direction = Vector3i(0x400, -0x1000, 0x200)
	var scene := MapSceneData.new()
	scene.map = MapFile.new()
	scene.map.lights = [ambient, parallel]
	return scene

func _map_lighting(scene: MapSceneData) -> MapLighting:
	var lighting := MapLighting.new()
	lighting.configure(scene.map.lights)
	return lighting

func test_the_scene_is_lit_from_the_map() -> void:
	var scene: MapSceneData = _lit_map()
	_view.build_entities(EntityCollisionDefinition.new(), scene, AssetCatalog.new())
	var expected: SceneLightingSpec = SceneLightingBuilder.from_lighting(_map_lighting(scene))
	assert_eq(_view.scene_lighting.light_nodes().size(), expected.lights.size())
	assert_gt(_view.scene_lighting.light_nodes().size(), 0)
	assert_almost_eq(_view.scene_lighting.applied_ambient, expected.ambient, Vector3.ONE * 1e-6)
	assert_not_null(_view.scene_lighting.environment)
	assert_not_null(_view._entity_lighting, "the source lighting stays for the frog and entities")

func test_the_scene_falls_back_to_the_options_lights_without_map_lighting() -> void:
	_view.build_entities(EntityCollisionDefinition.new(), _lit_map(), AssetCatalog.new(), false)
	var expected: SceneLightingSpec = SceneLightingBuilder.from_lighting(OptionsModels.options_lighting())
	assert_eq(_view.scene_lighting.light_nodes().size(), expected.lights.size())
	assert_almost_eq(_view.scene_lighting.applied_ambient, expected.ambient, Vector3.ONE * 1e-6)
	var unlit := MapSceneData.new()
	unlit.map = MapFile.new()
	_view.build_entities(EntityCollisionDefinition.new(), unlit, AssetCatalog.new())
	assert_almost_eq(_view.scene_lighting.applied_ambient, expected.ambient, Vector3.ONE * 1e-6, "a map without lights also falls back")

func test_clearing_entities_clears_the_scene_lights() -> void:
	_view.build_entities(EntityCollisionDefinition.new(), _lit_map(), AssetCatalog.new())
	_view._clear_entity_visuals()
	assert_eq(_view.scene_lighting.light_nodes().size(), 0)
	assert_eq(_view.scene_lighting.applied_ambient, Vector3.ONE)

func _cave_map() -> MapSceneData:
	var scene: MapSceneData = _lit_map()
	scene.remap = TextureRemap.new()
	scene.cave_enabled = true
	var radii: PackedInt64Array = MapLighting.initial_cave_radii(5)
	scene.cave_min_r2 = radii[0]
	scene.cave_max_r2 = radii[1]
	return scene

func _cave_state(tick: int, position_16: Vector3i, radius: int, entities: Array[EntitySnapshot] = []) -> GameplayState:
	var state := GameplayState.new()
	state.tick_index = tick
	state.frog.position_16 = position_16
	state.entity_environment = EntityEnvironmentState.new()
	var radii: PackedInt64Array = MapLighting.initial_cave_radii(radius)
	state.entity_environment.light_min_squared = radii[0]
	state.entity_environment.light_max_squared = radii[1]
	state.entities = EntityRunSnapshot.new()
	state.entities.entities.assign(entities)
	return state

func _build_cave(scene: MapSceneData = _cave_map()) -> void:
	_view.build_map(scene)
	_view.build_entities(EntityCollisionDefinition.new(), scene, AssetCatalog.new())

func test_a_cave_is_lit_from_above_the_drawn_frog() -> void:
	_build_cave()
	_view.smoothing = true
	_view.accept_state(_cave_state(1, Vector3i.ZERO, 4))
	_view.accept_state(_cave_state(2, Vector3i(512 << 16, 0, -(256 << 16)), 8))
	_view.draw_state(0.25)
	var light: OmniLight3D = _view.scene_lighting.cave_light_node()
	assert_not_null(light)
	if light == null:
		return
	var frog: Vector3 = GameSpace.fixed_position(Vector3i(512 << 16, 0, -(256 << 16))) * 0.25
	assert_almost_eq(light.position, frog + Vector3.UP * CaveLightShape.HEIGHT, Vector3.ONE * 1e-5)
	var before: PackedInt64Array = MapLighting.initial_cave_radii(4)
	var after: PackedInt64Array = MapLighting.initial_cave_radii(8)
	var min_r2: int = roundi(lerpf(float(before[0]), float(after[0]), 0.25))
	var max_r2: int = roundi(lerpf(float(before[1]), float(after[1]), 0.25))
	assert_eq(_view.cave_radii(0.25), PackedInt64Array([min_r2, max_r2]))
	assert_almost_eq(light.omni_range, CaveLightShape.range_of(max_r2, CaveLightShape.DEFAULT_MODE), 1e-5)
	assert_almost_eq(light.light_energy, CaveLightShape.energy_of(min_r2, max_r2, CaveLightShape.DEFAULT_MODE), 1e-5)
	assert_eq(_view.scene_lighting.light_nodes().size(), 0, "cave mode drops the directional lights")
	_view.draw_state(1.0)
	assert_almost_eq(light.omni_range, 8.0, 1e-5)

func test_a_map_without_caves_has_no_cave_light() -> void:
	var scene: MapSceneData = _cave_map()
	scene.cave_enabled = false
	_build_cave(scene)
	_view.accept_state(_cave_state(1, Vector3i.ZERO, 4))
	_view.draw_state(1.0)
	assert_null(_view.scene_lighting.cave_light_node())
	assert_gt(_view.scene_lighting.light_nodes().size(), 0)

func _faded_entity() -> EntitySnapshot:
	var entity := EntitySnapshot.new()
	entity.live = true
	entity.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0])
	entity.colour_scale = Vector3i(40, 40, 40)
	entity.colour_scaled = true
	return entity

func _lit_model() -> AnimatedModelInstance:
	var file: MofFile = SyntheticMof.static_file([SyntheticMof.square(MofPolygonType.F4)])
	var builder := ModelMeshBuilder.new(TextureLibrary.new())
	var model := AnimatedModelInstance.new()
	add_child_autofree(model)
	model.setup(builder.build_animated(file), ModelAnimationPlayer.new(file))
	return model

func _with_entities(models: Array[AnimatedModelInstance], definitions: Array[EntityDefinition]) -> void:
	for model: AnimatedModelInstance in models:
		_view._entity_models.append(model)
		_view._entity_meshes.append(null)
		_view._entity_files.append(null)
		_view._entity_generations.append(-1)
	_view._sprite_definitions = definitions

func _firefly_view() -> void:
	var sprites: Array[CaveSpriteView.Sprite] = []
	for _image: int in 2:
		sprites.append(CaveSpriteView.Sprite.new(ModelShaders.material(null, ModelShaders.Blend.OPAQUE, false, true), 16, 10))
	_view._cave_sprite_view._firefly = sprites

func test_cave_models_leave_the_fade_to_the_light_and_sprites_keep_it() -> void:
	_build_cave()
	var model: AnimatedModelInstance = _lit_model()
	var firefly := EntityDefinition.new()
	firefly.behavior.kind = EntityBehavior.Kind.FIREFLY
	_with_entities([model, null], [EntityDefinition.new(), firefly])
	_firefly_view()
	_view.accept_state(_cave_state(1, Vector3i.ZERO, 4, [_faded_entity(), _faded_entity()]))
	_view.draw_state(1.0)
	assert_eq(model.scene_tint.scale, Vector3.ONE, "the omni light fades lit models")
	var colours: PackedColorArray = _view._cave_sprite_view.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_eq(colours[0], Color(40 / 255.0, 40 / 255.0, 40 / 255.0), "sprites keep the committed fade")

func test_cave_models_keep_scales_that_are_not_the_fade_alone() -> void:
	_build_cave()
	var model: AnimatedModelInstance = _lit_model()
	_with_entities([model], [])
	var entity: EntitySnapshot = _faded_entity()
	entity.live_flags = EntityLiveFlags.NO_SCREEN_FADE
	_view.accept_state(_cave_state(1, Vector3i.ZERO, 4, [entity]))
	_view.draw_state(1.0)
	assert_eq(model.scene_tint.scale, SceneTint.of(Vector3i(40, 40, 40), Vector3i.ZERO, true, false).scale)
	assert_false(GameplayWorldView.cave_faded(entity))
	entity.live_flags = EntityLiveFlags.RESPECT_SCALE_COLOURS
	assert_false(GameplayWorldView.cave_faded(entity), "script colours times the fade cannot be told apart")
	entity.live_flags = 0
	assert_true(GameplayWorldView.cave_faded(entity))

func test_models_outside_caves_keep_the_scale() -> void:
	var scene: MapSceneData = _cave_map()
	scene.cave_enabled = false
	_build_cave(scene)
	var model: AnimatedModelInstance = _lit_model()
	_with_entities([model], [])
	_view.accept_state(_cave_state(1, Vector3i.ZERO, 4, [_faded_entity()]))
	_view.draw_state(1.0)
	assert_eq(model.scene_tint.scale, SceneTint.of(Vector3i(40, 40, 40), Vector3i.ZERO, true, false).scale)

func _shadow_state() -> GameplayState:
	var state := GameplayState.new()
	state.tick_index = 1
	state.frog.flags = FrogFlags.ACTIVE
	state.entities = EntityRunSnapshot.new()
	var rock := EntitySnapshot.new()
	rock.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0])
	rock.custom_state = EntityCustomState.new()
	rock.custom_state.shadow_visible = true
	state.entities.entities.append(rock)
	return state

func _shadow_requests(setting: String) -> Array[FrogShadowView.Request]:
	_view.effect_shadows = setting
	var definition := EntityDefinition.new()
	definition.behavior.kind = EntityBehavior.Kind.DES_FALLING_ROCK
	_view._definitions = [definition]
	_view.effect_grid = GridDefinition.new()
	_view.accept_state(_shadow_state())
	return _view.shadow_requests(Transform3D.IDENTITY, 1.0)

func test_no_blob_shadows_draw_when_the_setting_is_off() -> void:
	assert_eq(_view.effect_shadows, ShadowEffectPolicy.DEFAULT)
	assert_eq(_shadow_requests(ShadowEffectPolicy.OFF).size(), 0, "neither the frog's nor the rock's shadow")
	assert_false(_view.draws_effect_shadows())

func test_blob_shadows_draw_with_the_retail_setting() -> void:
	var requests: Array[FrogShadowView.Request] = _shadow_requests(ShadowEffectPolicy.RETAIL)
	assert_eq(requests.size(), 2, "the frog's and the rock's shadow")
	assert_eq(requests[1].symbol, FrogShadowGeometry.NO_ROTATION_TEXTURE)

func test_launch_arguments_choose_the_shadow_effects_and_real_shadows() -> void:
	_view.apply_shadow_arguments(PackedStringArray(["--effect-shadows=retail", "--shadows=off"]))
	assert_eq(_view.effect_shadows, ShadowEffectPolicy.RETAIL)
	assert_false(_view.real_shadows)
	_view.apply_shadow_arguments(PackedStringArray())
	assert_eq(_view.effect_shadows, ShadowEffectPolicy.OFF, "the project setting")
	assert_true(_view.real_shadows)

func _casters() -> int:
	var casters: int = 0
	for light: DirectionalLight3D in _view.scene_lighting.light_nodes():
		if light.shadow_enabled:
			casters += 1
	return casters

func test_real_shadows_off_leaves_the_lights_without_a_caster() -> void:
	_view.build_entities(EntityCollisionDefinition.new(), _lit_map(), AssetCatalog.new())
	assert_eq(_casters(), 1, "the brightest light casts by default")
	assert_true(_view.scene_lighting.applied_spec.shadows)
	_view.real_shadows = false
	_view.build_entities(EntityCollisionDefinition.new(), _lit_map(), AssetCatalog.new())
	assert_gt(_view.scene_lighting.light_nodes().size(), 0)
	assert_eq(_casters(), 0, "no light casts")
	assert_false(_view.scene_lighting.applied_spec.shadows)

func _look(reflection: float, specular: float, shininess: float, tint: float) -> GraphicsSettings:
	var values: GraphicsSettings = GraphicsProfile.current().copy()
	values.water_reflection = reflection
	values.water_specular = specular
	values.water_shininess = shininess
	values.vertex_tint = tint
	values.lava_emission = tint * 2.0
	return values

func test_the_map_takes_the_profile_look_when_built_and_when_it_changes() -> void:
	GraphicsProfile.replace(_look(0.5, 0.3, 256.0, 0.6))
	_view.build_map(_cave_map())
	assert_eq(_view._map_instance.water_look(), PackedFloat32Array([0.5, 0.3, 256.0]))
	assert_almost_eq(_view._map_instance._vertex_tint, 0.6, 1e-6)
	assert_almost_eq(_view._map_instance.emission_scale(), 1.2, 1e-6)
	GraphicsProfile.replace(_look(0.1, 0.0, 128.0, 0.0))
	assert_eq(_view._map_instance.water_look(), PackedFloat32Array([0.1, 0.0, 128.0]))
	assert_eq(_view._map_instance._vertex_tint, 0.0)
	assert_eq(_view._map_instance.emission_scale(), 0.0)

func test_a_view_outside_the_tree_ignores_profile_changes() -> void:
	_view.build_map(_cave_map())
	remove_child(_view)
	GraphicsProfile.replace(_look(0.5, 0.3, 256.0, 0.6))
	assert_eq(_view._map_instance.water_look(), PackedFloat32Array([MapMesh.Instance.WATER_REFLECTION, MapMesh.Instance.WATER_SPECULAR, MapMesh.Instance.WATER_SHININESS]))
	add_child(_view)
	GraphicsProfile.replace(_look(0.5, 0.3, 256.0, 0.6))
	assert_eq(_view._map_instance.water_look(), PackedFloat32Array([0.5, 0.3, 256.0]))

func test_the_cave_light_follows_the_profile_mode() -> void:
	_build_cave()
	_view.accept_state(_cave_state(1, Vector3i.ZERO, 8))
	_view.draw_state(1.0)
	var light: OmniLight3D = _view.scene_lighting.cave_light_node()
	var radii: PackedInt64Array = MapLighting.initial_cave_radii(8)
	assert_almost_eq(light.omni_range, CaveLightShape.range_of(radii[1], CaveLightShape.Mode.EXACT_EDGE), 1e-5)
	var values: GraphicsSettings = GraphicsProfile.current().copy()
	values.cave_light_mode = GraphicsSettings.CaveMode.FITTED_RANGE
	GraphicsProfile.replace(values)
	_view.draw_state(1.0)
	assert_eq(_view.scene_lighting.cave_light_node(), light, "the same cave light")
	assert_almost_eq(light.omni_range, CaveLightShape.range_of(radii[1], CaveLightShape.Mode.FITTED_RANGE), 1e-5)
	assert_almost_eq(light.light_energy, CaveLightShape.energy_of(radii[0], radii[1], CaveLightShape.Mode.FITTED_RANGE), 1e-5)
	assert_eq(_view.scene_lighting.light_nodes().size(), 0, "cave mode survives the change")

func _lava_map() -> MapSceneData:
	var scene: MapSceneData = _lit_map()
	scene.remap = TextureRemap.new()
	scene.remap.texture_ids = PackedInt32Array([301])
	var entry := EmissiveImage.new()
	entry.colour = Color(1.0, 0.6, 0.4)
	entry.light = true
	entry.light_energy = 1.0
	scene.emissive = {301: entry}
	scene.map.vertices = [Vector3i(0, 0, 0), Vector3i(512, 0, 0), Vector3i(0, 0, 512), Vector3i(512, 0, 512)]
	var polygon := MapPolygon.new()
	polygon.type_index = 3
	polygon.vertex_indices = PackedInt32Array([0, 1, 2, 3])
	polygon.colors = PackedColorArray([Color8(128, 128, 128)])
	polygon.uvs = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE])
	polygon.texture_id = 0
	scene.map.polygons.append(polygon)
	var group := MapGroup.new()
	group.polygon_indices = PackedInt32Array([0])
	scene.map.groups.append(group)
	return scene

func test_the_lava_lights_of_the_built_map_survive_the_entity_rebuild() -> void:
	var scene: MapSceneData = _lava_map()
	_view.build_map(scene)
	_view.build_entities(EntityCollisionDefinition.new(), scene, AssetCatalog.new())
	var lava: EmissiveLightSet = _view.scene_lighting.emissive_light_set()
	assert_not_null(lava, "lit after the entity rebuild cleared the scene lighting")
	assert_eq(lava.shown_count(), 1)
	var expected: EmissiveClusters.Cluster = EmissiveClusters.build(scene)[0]
	assert_eq(lava.lights()[0].position, expected.centre)
	assert_almost_eq(lava.lights()[0].light_energy, expected.energy, 1e-6)
	_view.build_entities(EntityCollisionDefinition.new(), scene, AssetCatalog.new())
	assert_eq(_view.scene_lighting.emissive_light_set().shown_count(), 1, "relit after a second rebuild")
	var values: GraphicsSettings = GraphicsProfile.current().copy()
	values.lava_emission = 0.5
	GraphicsProfile.replace(values)
	assert_almost_eq(_view.scene_lighting.emissive_light_set().lights()[0].light_energy, expected.energy * 0.5, 1e-6)

func test_a_map_without_lava_has_no_lava_lights() -> void:
	_build_cave()
	assert_null(_view.scene_lighting.emissive_light_set())

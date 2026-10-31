extends GutTest
## The gameplay frog is lit per part from the map's lights with its committed colour scale and custom ambient, and tinted only without map lights;
## the modern profile also lights the scene from the map's lights.

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

func _draw(flags: int) -> void:
	_tick += 1
	var state := GameplayState.new()
	state.tick_index = _tick
	state.frog.colour_scale = SCALE
	state.frog.custom_ambient = AMBIENT
	state.frog.tint_flags = flags
	_view.accept_state(state)
	_view.draw_state(1.0)

func _shown() -> ShaderMaterial:
	return _view._frog_model.part_nodes[0].get_surface_override_material(0) as ShaderMaterial

func _vector(name: StringName) -> Vector3:
	var material: ShaderMaterial = _shown()
	assert_not_null(material, "the frog draws an instance-local material")
	var value: Vector3 = material.get_shader_parameter(name) if material != null else Vector3(-1, -1, -1)
	return value

func _lit() -> bool:
	var material: ShaderMaterial = _shown()
	return material != null and material.get_shader_parameter("source_lighting") == true

func _depth_bias() -> float:
	var material: ShaderMaterial = _shown()
	var value: float = material.get_shader_parameter("depth_bias") if material != null else -1.0
	return value

func _assert_map_lit(ambient: Vector3, colour0: Vector3) -> void:
	assert_true(_lit())
	assert_eq(_vector("source_direction0"), _lighting.directions[0])
	assert_eq(_vector("source_colour0"), colour0)
	assert_eq(_vector("source_ambient"), ambient)
	assert_eq(_depth_bias(), GameplayWorldView.FROG_DEPTH_BIAS)

func test_map_lights_reach_the_frog_without_flags() -> void:
	_view._entity_lighting = _lighting
	_draw(0)
	_assert_map_lit(_lighting.ambient, _lighting.colours[0])

func test_custom_ambient_and_colour_scale_follow_the_source_matrix() -> void:
	_view._entity_lighting = _lighting
	_draw(FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS)
	var ambient: Vector3 = Vector3(floorf(32.0 * 0.0 / 128.0), floorf(64.0 * 64.0 / 128.0), floorf(64.0 * 192.0 / 128.0)) * 16.0
	_assert_map_lit(ambient, (_lighting.colours[0] * Vector3(SCALE) / 128.0).floor())

func test_without_map_lights_the_tint_fallback_applies() -> void:
	var flags: int = FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS
	_draw(flags)
	assert_true(_lit())
	assert_eq(_vector("source_colour0"), Vector3.ZERO)
	assert_eq(_vector("source_ambient"), AnimatedModelInstance.tint_light(SCALE, AMBIENT, flags))
	assert_eq(_depth_bias(), GameplayWorldView.FROG_DEPTH_BIAS)

func test_tinted_then_lit_then_unlit_keeps_no_stale_uniforms() -> void:
	var flags: int = FrogTint.CUSTOM_AMBIENT | FrogTint.SCALED_COLOURS
	_draw(flags)
	_view._entity_lighting = _lighting
	_view._frog_light_tick = -1
	_view.draw_state(1.0)
	_assert_map_lit(Vector3(0, 32, 96) * 16.0, (_lighting.colours[0] * Vector3(SCALE) / 128.0).floor())
	_view.build_entities(null, null, null)
	assert_null(_view._entity_lighting)
	_view.draw_state(1.0)
	assert_eq(_vector("source_colour0"), Vector3.ZERO, "rebuilding entities without lights re-tints the frog on the same tick")
	assert_eq(_vector("source_ambient"), AnimatedModelInstance.tint_light(SCALE, AMBIENT, flags))
	assert_eq(_depth_bias(), GameplayWorldView.FROG_DEPTH_BIAS)

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

func test_the_modern_profile_lights_the_scene_from_the_map() -> void:
	var scene: MapSceneData = _lit_map()
	_view.rendering_profile = RenderingProfile.modern()
	_view.build_entities(EntityCollisionDefinition.new(), scene, AssetCatalog.new())
	var expected: SceneLightingSpec = SceneLightingBuilder.from_lighting(_map_lighting(scene))
	assert_eq(_view.scene_lighting.light_nodes().size(), expected.lights.size())
	assert_gt(_view.scene_lighting.light_nodes().size(), 0)
	assert_almost_eq(_view.scene_lighting.applied_ambient, expected.ambient, Vector3.ONE * 1e-6)
	assert_not_null(_view.scene_lighting.environment)
	assert_not_null(_view._entity_lighting, "the source lighting stays for the frog and entities")

func test_the_modern_profile_falls_back_to_the_options_lights_without_map_lighting() -> void:
	_view.rendering_profile = RenderingProfile.modern()
	_view.build_entities(EntityCollisionDefinition.new(), _lit_map(), AssetCatalog.new(), false)
	var expected: SceneLightingSpec = SceneLightingBuilder.from_lighting(OptionsModels.options_lighting())
	assert_eq(_view.scene_lighting.light_nodes().size(), expected.lights.size())
	assert_almost_eq(_view.scene_lighting.applied_ambient, expected.ambient, Vector3.ONE * 1e-6)
	var unlit := MapSceneData.new()
	unlit.map = MapFile.new()
	_view.build_entities(EntityCollisionDefinition.new(), unlit, AssetCatalog.new())
	assert_almost_eq(_view.scene_lighting.applied_ambient, expected.ambient, Vector3.ONE * 1e-6, "a map without lights also falls back")

func test_clearing_entities_clears_the_scene_lights() -> void:
	_view.rendering_profile = RenderingProfile.modern()
	_view.build_entities(EntityCollisionDefinition.new(), _lit_map(), AssetCatalog.new())
	_view._clear_entity_visuals()
	assert_eq(_view.scene_lighting.light_nodes().size(), 0)
	assert_eq(_view.scene_lighting.applied_ambient, Vector3.ONE)

func test_the_retail_profile_applies_no_scene_lighting() -> void:
	_view.build_entities(EntityCollisionDefinition.new(), _lit_map(), AssetCatalog.new())
	assert_false(_view.rendering_profile.is_modern())
	assert_not_null(_view._entity_lighting)
	assert_eq(_view.scene_lighting.light_nodes().size(), 0)
	assert_null(_view.scene_lighting.environment)
	assert_null(_view.scene_lighting.world_environment())
	assert_null(_view.scene_lighting.applied_spec)
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

func _build_cave(profile: RenderingProfile, scene: MapSceneData = _cave_map()) -> void:
	_view.rendering_profile = profile
	_view.build_map(scene)
	_view.build_entities(EntityCollisionDefinition.new(), scene, AssetCatalog.new())

func test_the_modern_profile_lights_a_cave_from_above_the_drawn_frog() -> void:
	_build_cave(RenderingProfile.modern())
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

func test_the_retail_profile_adds_no_cave_light() -> void:
	_build_cave(RenderingProfile.retail())
	_view.accept_state(_cave_state(1, Vector3i.ZERO, 4))
	_view.draw_state(1.0)
	assert_null(_view.scene_lighting.cave_light_node())
	assert_eq(_view.scene_lighting.get_child_count(), 0)

func test_a_modern_map_without_caves_has_no_cave_light() -> void:
	var scene: MapSceneData = _cave_map()
	scene.cave_enabled = false
	_build_cave(RenderingProfile.modern(), scene)
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
	builder.lit_materials = true
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

func test_modern_cave_models_leave_the_fade_to_the_light_and_sprites_keep_it() -> void:
	_build_cave(RenderingProfile.modern())
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
	_build_cave(RenderingProfile.modern())
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

func test_lit_models_outside_caves_and_under_retail_keep_the_scale() -> void:
	var scene: MapSceneData = _cave_map()
	scene.cave_enabled = false
	_build_cave(RenderingProfile.modern(), scene)
	var model: AnimatedModelInstance = _lit_model()
	_with_entities([model], [])
	_view.accept_state(_cave_state(1, Vector3i.ZERO, 4, [_faded_entity()]))
	_view.draw_state(1.0)
	assert_eq(model.scene_tint.scale, SceneTint.of(Vector3i(40, 40, 40), Vector3i.ZERO, true, false).scale)

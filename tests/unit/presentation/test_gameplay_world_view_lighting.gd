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

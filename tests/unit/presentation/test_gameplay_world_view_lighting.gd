extends GutTest
## The gameplay frog is lit per part from the map's lights with its committed colour scale and custom ambient, and tinted only without map lights.

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
	assets.model = MofFile.parse(SyntheticMof.build_static([SyntheticMof.square(MofPolygonType.F4)]))
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

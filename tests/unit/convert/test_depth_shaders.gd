extends GutTest
## Depth-only ordering biases in map and model shader sources.

func test_only_ordinary_terrain_source_pushes_depth() -> void:
	var push: String = MapShaders.terrain_depth_code()
	for blend: ModelShaders.Blend in [ModelShaders.Blend.OPAQUE, ModelShaders.Blend.AVERAGE, ModelShaders.Blend.ADD]:
		assert_string_contains(MapShaders.shader(true, blend, false, false).code, push)
		assert_string_contains(MapShaders.shader(false, blend, true, false).code, push)
		assert_false(MapShaders.shader(true, blend, false, true).code.contains(push), "far layers keep their fixed depth")
	assert_false(MapShaders.sky_shader(false).code.contains(push), "sky keeps its fixed depth")
	assert_true(push.begins_with("\tif (!reference_projection) {"), "the reference projection keeps its own depth")
	var code: String = MapShaders.shader(true, ModelShaders.Blend.OPAQUE, false, false).code
	assert_lt(code.find(push), code.find("POSITION.xy *= projection_scale;"), "screen XY scaling follows the depth push")
	assert_false(code.contains("depth_bias"), "terrain uses its fixed push, not the model uniform")

func test_terrain_push_changes_depth_only() -> void:
	var push: String = MapShaders.terrain_depth_code()
	assert_string_contains(push, "eye.z - %.1f / 256.0" % MapShaders.TERRAIN_DEPTH_BIAS)
	assert_string_contains(push, "POSITION.z = behind.z / behind.w * POSITION.w;")
	assert_false(push.contains("POSITION.xy"))
	assert_false(push.contains("POSITION.w ="))

func test_model_depth_bias_defaults_to_zero_and_moves_depth_only() -> void:
	var material: ShaderMaterial = ModelShaders.material(null, ModelShaders.Blend.OPAQUE, false, false)
	var code: String = material.shader.code
	assert_string_contains(code, "uniform float depth_bias = 0.0;")
	assert_string_contains(code, "if (depth_bias != 0.0) {")
	assert_string_contains(code, "eye.z + depth_bias / 256.0")
	assert_lt(code.find("depth_bias / 256.0"), code.find("POSITION.xy *= projection_scale;"))
	var bias: Variant = material.get_shader_parameter("depth_bias")
	var unset: bool = typeof(bias) == TYPE_NIL
	assert_true(unset, "materials leave the zero default")

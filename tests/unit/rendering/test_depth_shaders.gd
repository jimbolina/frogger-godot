extends GutTest
## Depth-only ordering biases in model shader sources.

func test_model_depth_bias_defaults_to_zero_and_moves_depth_only() -> void:
	for lit: bool in [true, false]:
		var material: ShaderMaterial = ModelShaders.material(null, ModelShaders.Blend.OPAQUE, false, true, lit)
		var include: String = "model.gdshaderinc" if lit else "model_unlit.gdshaderinc"
		assert_string_contains(material.shader.code, "#include \"%s\"" % include)
		var code: String = FileAccess.get_file_as_string(ModelShaders.SHADER_DIR.path_join(include))
		assert_string_contains(code, "uniform float depth_bias = 0.0;", include)
		assert_string_contains(code, "if (depth_bias != 0.0) {", include)
		assert_string_contains(code, "eye.z + depth_bias / 256.0", include)
		assert_lt(code.find("depth_bias / 256.0"), code.find("POSITION.xy *= projection_scale;"), include)
		var bias: Variant = material.get_shader_parameter("depth_bias")
		var unset: bool = typeof(bias) == TYPE_NIL
		assert_true(unset, "materials leave the zero default")

func test_lit_models_skip_the_bias_and_projection_in_shadow_passes() -> void:
	var code: String = FileAccess.get_file_as_string(ModelShaders.SHADER_DIR.path_join("model.gdshaderinc"))
	var guard: int = code.find("if (!IN_SHADOW_PASS) {")
	assert_gt(guard, -1)
	assert_lt(guard, code.find("depth_bias / 256.0"))
	assert_lt(guard, code.find("POSITION.xy *= projection_scale;"))

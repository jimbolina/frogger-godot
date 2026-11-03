extends GutTest
## Each model shader finds its linear-filtered variant from its file; the imported suite's test_model_mesh_copy_imported.gd checks the material copies views draw meshes from.

func test_the_linear_variant_is_found_from_the_shader_file() -> void:
	var opaque: Shader = ModelShaders.shader(true, ModelShaders.Blend.OPAQUE, false, false)
	assert_same(ModelShaders.linear_variant(opaque), ModelShaders.shader(true, ModelShaders.Blend.OPAQUE, true, false))
	var two_sided: Shader = ModelShaders.shader(true, ModelShaders.Blend.ADD_QUARTER, false, true)
	assert_same(ModelShaders.linear_variant(two_sided), ModelShaders.shader(true, ModelShaders.Blend.ADD_QUARTER, true, true))
	var linear: Shader = ModelShaders.shader(true, ModelShaders.Blend.AVERAGE, true, false)
	assert_same(ModelShaders.linear_variant(linear), linear)
	var flat: Shader = ModelShaders.shader(false, ModelShaders.Blend.OPAQUE, false, false)
	assert_same(ModelShaders.linear_variant(flat), flat)
	var unlit: Shader = ModelShaders.shader(true, ModelShaders.Blend.SUBTRACT, false, true, false)
	assert_same(ModelShaders.linear_variant(unlit), ModelShaders.shader(true, ModelShaders.Blend.SUBTRACT, true, true, false))
	var unlit_flat: Shader = ModelShaders.shader(false, ModelShaders.Blend.ADD, false, true, false)
	assert_same(ModelShaders.linear_variant(unlit_flat), unlit_flat)
	assert_null(ModelShaders.linear_variant(null))

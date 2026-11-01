extends GutTest
## The glow halo is an unlit additive radial falloff with the unlit sprites' depth bias and projection scale.

const UNLIT_INCLUDE: String = "res://src/rendering/shaders/model_unlit.gdshaderinc"


func _vertex_lines(code: String) -> PackedStringArray:
	var lines := PackedStringArray()
	var inside: bool = false
	for line: String in code.split("\n"):
		var text: String = line.strip_edges()
		if text.begins_with("POSITION = PROJECTION_MATRIX"):
			inside = true
		if inside:
			lines.append(text)
		if text == "POSITION.xy *= projection_scale;":
			break
	return lines


func test_render_modes_draw_an_additive_unlit_halo_without_depth_writes() -> void:
	var code: String = GlowHaloMaterial.create(0.0, Vector2.ONE).shader.code
	for mode: String in ["unshaded", "blend_add", "depth_draw_never", "cull_disabled", "fog_disabled"]:
		assert_string_contains(code, mode)
	assert_string_contains(code, "pow(clamp(1.0 - length(UV * 2.0 - 1.0), 0.0, 1.0), falloff)")
	assert_string_contains(code, "halo_strength")


func test_vertex_stage_repeats_the_unlit_depth_bias_and_projection_lines() -> void:
	var halo: PackedStringArray = _vertex_lines(GlowHaloMaterial.create(0.0, Vector2.ONE).shader.code)
	var unlit: PackedStringArray = _vertex_lines(FileAccess.get_file_as_string(UNLIT_INCLUDE))
	assert_gt(unlit.size(), 5)
	assert_eq(halo, unlit)


func test_parameters_are_set_and_the_shader_is_shared() -> void:
	var material: ShaderMaterial = GlowHaloMaterial.create(32.0, Vector2(0.75, 1.0), 4.0)
	var bias: float = material.get_shader_parameter("depth_bias")
	var scale: Vector2 = material.get_shader_parameter("projection_scale")
	var strength: float = material.get_shader_parameter("halo_strength")
	var falloff: float = material.get_shader_parameter("falloff")
	assert_eq([bias, scale, strength, falloff], [32.0, Vector2(0.75, 1.0), 4.0, GlowHaloMaterial.DEFAULT_FALLOFF])
	var default_strength: float = GlowHaloMaterial.create(0.0, Vector2.ONE).get_shader_parameter("halo_strength")
	assert_eq(default_strength, GlowHaloMaterial.DEFAULT_STRENGTH)
	assert_same(GlowHaloMaterial.create(0.0, Vector2.ONE).shader, material.shader)
	assert_eq(material.shader.resource_path, GlowHaloMaterial.SHADER_PATH)

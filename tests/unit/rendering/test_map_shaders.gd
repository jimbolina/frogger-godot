extends GutTest
## The lit map shader files and their shared include.

const VARIANTS: Dictionary[String, String] = {
	"opaque": "render_mode blend_mix, depth_draw_opaque, cull_back;",
	"average": "render_mode blend_mix, depth_draw_never, cull_back;",
	"add": "render_mode blend_add, depth_draw_never, cull_back;",
	"subtract": "render_mode blend_sub, depth_draw_never, cull_back;",
	"add_quarter": "render_mode blend_add, depth_draw_never, cull_back;",
}


func test_ten_variants_sky_and_include_exist() -> void:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(MapShaders.SHADER_DIR):
		if file.begins_with("map") and (file.ends_with(".gdshader") or file.ends_with(".gdshaderinc")):
			found.append(file)
	found.sort()
	assert_eq(found.size(), 12, ", ".join(found))
	for blend: ModelShaders.Blend in ModelShaders.Blend.values():
		for far: bool in [false, true]:
			assert_true(FileAccess.file_exists(MapShaders.shader_path(blend, far)), MapShaders.shader_path(blend, far))
			assert_not_null(MapShaders.shader(blend, far))
	assert_true(FileAccess.file_exists(MapShaders.sky_shader_path()))
	assert_true(FileAccess.file_exists(MapShaders.INCLUDE_PATH))


func test_render_modes_per_variant() -> void:
	for blend: ModelShaders.Blend in ModelShaders.Blend.values():
		var mode: String = VARIANTS[ModelShaders.BLEND_NAMES[blend]]
		var near: String = _code(MapShaders.shader_path(blend, false))
		var far: String = _code(MapShaders.shader_path(blend, true))
		assert_string_contains(near, mode)
		assert_string_contains(far, mode.replace("depth_draw_opaque", "depth_draw_never"))
		assert_string_contains(far, "#define MAP_FAR")
		assert_false(near.contains("MAP_FAR"))
		assert_eq(near.contains("#define MAP_TRANSLUCENT"), blend != ModelShaders.Blend.OPAQUE)
		assert_eq(near.contains("#define MAP_AVERAGE"), blend == ModelShaders.Blend.AVERAGE)
		assert_eq(near.contains("#define MAP_QUARTER"), blend == ModelShaders.Blend.ADD_QUARTER)
		for code: String in [near, far]:
			assert_string_contains(code, "#include \"map.gdshaderinc\"")
			assert_false(code.contains("unshaded"))
			assert_false(code.contains("diffuse_"), "the include's light() shades")
	assert_string_contains(_code(MapShaders.sky_shader_path()), "render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;")


func test_samplers_repeat_in_colour_space_without_retail_uniforms() -> void:
	var include: String = _code(MapShaders.INCLUDE_PATH)
	assert_string_contains(include, "uniform sampler2D image_nearest : source_color, filter_nearest, repeat_enable;")
	assert_string_contains(include, "uniform sampler2D image_linear : source_color, filter_linear_mipmap_anisotropic, repeat_enable;")
	assert_false(include.contains("unshaded"))
	var sky: String = _code(MapShaders.sky_shader_path())
	assert_string_contains(sky, "uniform sampler2DArray tiles : source_color, filter_nearest, repeat_disable;")
	assert_string_contains(sky, "uniform sampler2DArray tiles_linear : source_color, filter_linear_mipmap")
	for path: String in [MapShaders.INCLUDE_PATH, MapShaders.sky_shader_path()]:
		var code: String = _code(path)
		assert_false(code.contains("through_renderer"), path)
		assert_false(code.contains("reference_projection"), path)
		assert_false(code.contains("cave_"), path)
		assert_false(code.contains("affine"), path)


func test_include_holds_the_uv_and_shadow_gate_code() -> void:
	var include: String = _code(MapShaders.INCLUDE_PATH)
	assert_string_contains(include, MapShaders.uv_code())
	assert_string_contains(include, MapShaders.shadow_gate_code())
	assert_string_contains(include, "IN_SHADOW_PASS")
	assert_lt(include.find("if (!IN_SHADOW_PASS)"), include.find("eye.z - "), "the depth push is gated")
	assert_string_contains(include, MapShaders.terrain_depth_code())
	assert_lt(include.find(MapShaders.terrain_depth_code()), include.find("POSITION.xy *= projection_scale;"),
		"screen XY scaling follows the depth push")
	assert_false(include.contains("depth_bias"), "terrain uses its fixed push, not the model uniform")
	assert_string_contains(include, "void light()")
	assert_string_contains(include, "LIGHT_IS_DIRECTIONAL")
	assert_string_contains(include, "ALPHA_SCISSOR_THRESHOLD = 0.5;")
	assert_string_contains(include, "EMISSION = vec3(1.0, 0.0, 1.0);")
	for parameter: String in ["image_origin", "image_padding", "image_padded_size", "vertex_tint", "omni_wrap",
			"specular_strength", "shininess", "animated", "animation_offset", "environment_uv", "camera_game",
			"water_enabled", "water_offsets", "projection_scale", "far_layer", "missing_image", "textured", "linear_filter"]:
		assert_string_contains(include, " %s" % parameter, parameter)


func test_terrain_push_changes_depth_only_outside_far_layers_and_the_sky() -> void:
	var push: String = MapShaders.terrain_depth_code()
	assert_string_contains(push, "eye.z - %.1f / 256.0" % MapShaders.TERRAIN_DEPTH_BIAS)
	assert_string_contains(push, "POSITION.z = behind.z / behind.w * POSITION.w;")
	assert_false(push.contains("POSITION.xy"))
	assert_false(push.contains("POSITION.w ="))
	var include: String = _code(MapShaders.INCLUDE_PATH)
	assert_lt(include.find("#ifdef MAP_FAR"), include.find(push), "far layers keep their fixed depth")
	assert_lt(include.find("#else"), include.find(push))
	assert_false(_code(MapShaders.sky_shader_path()).contains("eye.z - "), "the sky keeps its fixed depth")


func test_normalised_uv_mirrors_the_include() -> void:
	var image := VloImage.new()
	image.u = 1
	image.v = 1
	image.width = 253
	image.height = 253
	image.padded_width = 255
	image.padded_height = 255
	assert_eq(MapShaders.normalised_uv(Vector2(0, 0), image), Vector2(1, 1) / 255.0)
	assert_eq(MapShaders.normalised_uv(Vector2(253, 0), image), Vector2(254, 1) / 255.0, "u == width reaches the padding")
	assert_eq(MapShaders.normalised_uv(Vector2(0, 0), image, Vector2(0, 254)), Vector2(1, 255) / 255.0)
	assert_eq(MapShaders.normalised_uv(Vector2(0, 0), image, Vector2(0, 255)), Vector2(1, 0) / 255.0,
		"the page byte wraps before normalising")


func test_sky_samples_the_tile_array_at_the_uv2_layer() -> void:
	var sky: String = _code(MapShaders.sky_shader_path())
	assert_string_contains(sky, MapShaders.sky_layer_code())
	assert_string_contains(sky, "varying flat float tile_layer;")
	assert_string_contains(sky, "vec3(UV, tile_layer)")
	assert_false(sky.contains("sampler2D "), "no page atlas")
	assert_false(sky.contains("CUSTOM0"))
	assert_false(sky.contains("258"))
	var image := VloImage.new()
	image.width = 32
	image.height = 32
	image.padded_width = 40
	image.padded_height = 40
	assert_eq(MapSkyTiles.layer_uv(Vector2(31, 32), image), Vector2(35, 36) / 40.0)
	var material: ShaderMaterial = MapShaders.sky_material(null, true, Vector2(4, 4), Vector2(40, 40))
	var padding: Vector2 = material.get_shader_parameter("tile_padding")
	var padded_size: Vector2 = material.get_shader_parameter("tile_padded_size")
	var linear_filter: bool = material.get_shader_parameter("linear_filter")
	assert_eq(padding, Vector2(4, 4))
	assert_eq(padded_size, Vector2(40, 40))
	assert_true(linear_filter)
	assert_eq(material.render_priority, -127)

func _code(path: String) -> String:
	return FileAccess.get_file_as_string(path)

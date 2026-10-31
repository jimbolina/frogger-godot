extends GutTest
## The lit model shaders of the modern rendering profile: one thin file per
## retail model shader, drawn the same way but shaded by the scene's lights.

const RETAIL_DIR: String = "res://src/convert/shaders"
const LIT_DIR: String = "res://src/convert/shaders/modern"
const INCLUDE: String = "model_lit.gdshaderinc"


func _retail_files() -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(RETAIL_DIR):
		if file.begins_with("model_") and file.ends_with(".gdshader"):
			found.append(file)
	return found


func _lit_files() -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(LIT_DIR):
		if file.begins_with("model_lit_") and file.ends_with(".gdshader"):
			found.append(file)
	return found


func _code(folder: String, file: String) -> String:
	return FileAccess.get_file_as_string(folder.path_join(file))


func _render_modes(code: String) -> PackedStringArray:
	for line: String in code.split("\n"):
		if line.begins_with("render_mode "):
			var modes := PackedStringArray()
			for mode: String in line.trim_prefix("render_mode ").trim_suffix(";").split(","):
				modes.append(mode.strip_edges())
			return modes
	return PackedStringArray()


func _drawing_modes(modes: PackedStringArray) -> PackedStringArray:
	var kept := PackedStringArray()
	for mode: String in modes:
		if mode.begins_with("blend_") or mode.begins_with("depth_") or mode.begins_with("cull_"):
			kept.append(mode)
	return kept


func test_one_lit_file_per_retail_model_shader_and_the_include() -> void:
	var retail: PackedStringArray = _retail_files()
	assert_eq(retail.size(), 30)
	var lit: PackedStringArray = _lit_files()
	assert_eq(lit.size(), 30)
	for file: String in retail:
		assert_true(lit.has("model_lit_" + file.trim_prefix("model_")), file)
	assert_true(FileAccess.file_exists(LIT_DIR.path_join(INCLUDE)))


func test_lit_files_are_lit_and_draw_like_their_retail_counterpart() -> void:
	for file: String in _lit_files():
		var code: String = _code(LIT_DIR, file)
		var modes: PackedStringArray = _render_modes(code)
		assert_false(modes.has("unshaded"), file)
		for wanted: String in ["diffuse_lambert", "specular_disabled", "ambient_light_disabled"]:
			assert_true(modes.has(wanted), "%s has %s" % [file, wanted])
		var retail: String = "model_" + file.trim_prefix("model_lit_")
		assert_eq(_drawing_modes(modes), _drawing_modes(_render_modes(_code(RETAIL_DIR, retail))), file)
		assert_string_contains(code, "#include \"%s\"" % INCLUDE, file)
		assert_false(code.contains("through_renderer"), file)
		var textured: bool = file.begins_with("model_lit_textured_")
		assert_eq(code.contains("#define TEXTURED"), textured, file)
		if textured:
			var filter: String = "filter_linear_mipmap" if file.contains("_linear") else "filter_nearest"
			assert_string_contains(code, "uniform sampler2D image : source_color, %s, repeat_disable;" % filter, file)
		else:
			assert_false(code.contains("sampler2D image"), file)
		for blend: String in ModelShaders.BLEND_NAMES:
			var named: bool = file.trim_suffix(".gdshader").trim_suffix("_two_sided").trim_suffix("_linear").ends_with("_" + blend)
			assert_eq(code.contains("#define BLEND_%s\n" % blend.to_upper()), named, "%s %s" % [file, blend])


func test_the_include_lights_with_the_scene_and_keeps_casters_undistorted() -> void:
	var code: String = _code(LIT_DIR, INCLUDE)
	assert_string_contains(code, "IN_SHADOW_PASS")
	assert_string_contains(code, "instance uniform vec3 tint_scale")
	assert_string_contains(code, "instance uniform vec4 tint_ambient")
	assert_string_contains(code, "global uniform vec3 frogger_model_ambient;")
	assert_string_contains(code, "NORMAL = -NORMAL;")
	assert_false(code.contains("through_renderer"))
	assert_false(code.contains("source_lighting"))
	assert_false(code.contains("unshaded"))


func test_lit_shaders_are_found_from_the_retail_ones() -> void:
	for textured: bool in [false, true]:
		for blend: int in ModelShaders.BLEND_NAMES.size():
			for linear: bool in [false, true]:
				for two_sided: bool in [false, true]:
					var retail: Shader = ModelShaders.shader(textured, blend as ModelShaders.Blend, linear, two_sided)
					var lit: Shader = ModelShaders.lit_variant(retail)
					assert_true(ModelShaders.is_lit(lit), retail.resource_path)
					assert_false(ModelShaders.is_lit(retail), retail.resource_path)
					assert_eq(lit.resource_path, "%s/model_lit_%s" % [LIT_DIR, retail.resource_path.get_file().trim_prefix("model_")])
					assert_same(ModelShaders.lit_variant(lit), lit, "a lit shader is its own lit variant")
					var made: ShaderMaterial = ModelShaders.material(null, blend as ModelShaders.Blend, linear, two_sided, true)
					assert_true(ModelShaders.is_lit(made.shader))
	assert_null(ModelShaders.lit_variant(null))
	assert_false(ModelShaders.is_lit(null))
	var map: Shader = load("res://src/convert/shaders/map_textured_opaque.gdshader") as Shader
	assert_same(ModelShaders.lit_variant(map), map, "map shaders have no lit model variant")

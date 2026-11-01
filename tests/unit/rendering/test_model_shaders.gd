extends GutTest
## The model shader families: thirty lit files sharing [code]model.gdshaderinc[/code],
## shaded by the scene's lights, and the two-sided unlit files sharing
## [code]model_unlit.gdshaderinc[/code] for sprites and effects.

const SHADER_DIR: String = "res://src/rendering/shaders"
const LIT_INCLUDE: String = "model.gdshaderinc"
const UNLIT_INCLUDE: String = "model_unlit.gdshaderinc"
const LIT_MODES: PackedStringArray = ["diffuse_lambert", "specular_disabled", "ambient_light_disabled"]


func _model_files(unlit: bool) -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(SHADER_DIR):
		if file.begins_with("model_") and file.ends_with(".gdshader") and file.begins_with(ModelShaders.UNLIT_PREFIX) == unlit:
			found.append(file)
	return found


func _code(file: String) -> String:
	return FileAccess.get_file_as_string(SHADER_DIR.path_join(file))


func _render_modes(code: String) -> PackedStringArray:
	for line: String in code.split("\n"):
		if line.begins_with("render_mode "):
			var modes := PackedStringArray()
			for mode: String in line.trim_prefix("render_mode ").trim_suffix(";").split(","):
				modes.append(mode.strip_edges())
			return modes
	return PackedStringArray()


func _drawing_modes(blend: String, two_sided: bool) -> PackedStringArray:
	var modes := PackedStringArray()
	match blend:
		"opaque":
			modes.append_array(["blend_mix", "depth_draw_opaque"])
		"average":
			modes.append_array(["blend_mix", "depth_draw_never"])
		"subtract":
			modes.append_array(["blend_sub", "depth_draw_never"])
		_:
			modes.append_array(["blend_add", "depth_draw_never"])
	modes.append("cull_disabled" if two_sided else "cull_back")
	return modes


func _blend_of(file: String, prefix: String) -> String:
	return file.trim_prefix(prefix).trim_prefix("textured_").trim_prefix("flat_").trim_suffix(".gdshader") \
		.trim_suffix("_two_sided").trim_suffix("_linear")


func _assert_thin_file(file: String, prefix: String, include: String, extra_modes: PackedStringArray) -> void:
	var code: String = _code(file)
	var blend: String = _blend_of(file, prefix)
	assert_true(ModelShaders.BLEND_NAMES.has(blend), file)
	var modes: PackedStringArray = _render_modes(code)
	var wanted: PackedStringArray = extra_modes.duplicate()
	wanted.append_array(_drawing_modes(blend, file.ends_with("_two_sided.gdshader")))
	modes.sort()
	wanted.sort()
	assert_eq(modes, wanted, file)
	assert_string_contains(code, "#include \"%s\"" % include, file)
	var textured: bool = file.begins_with(prefix + "textured_")
	assert_eq(code.contains("#define TEXTURED"), textured, file)
	for blend_name: String in ModelShaders.BLEND_NAMES:
		assert_eq(code.contains("#define BLEND_%s\n" % blend_name.to_upper()), blend_name == blend, "%s %s" % [file, blend_name])


func test_thirty_lit_files_keep_the_committed_material_names() -> void:
	var lit: PackedStringArray = _model_files(false)
	assert_eq(lit.size(), 30)
	for textured: bool in [false, true]:
		for blend: int in ModelShaders.BLEND_NAMES.size():
			for linear: bool in [false, true]:
				for two_sided: bool in [false, true]:
					var path: String = ModelShaders.shader_path(textured, blend as ModelShaders.Blend, linear, two_sided)
					assert_true(lit.has(path.get_file()), path)
					assert_eq(ModelShaders.material(null, blend as ModelShaders.Blend, linear, two_sided).shader.resource_path,
						ModelShaders.shader_path(false, blend as ModelShaders.Blend, false, two_sided))
	assert_true(FileAccess.file_exists(SHADER_DIR.path_join(LIT_INCLUDE)))
	assert_false(DirAccess.dir_exists_absolute(SHADER_DIR.path_join("modern")) and _has_model_files(SHADER_DIR.path_join("modern")),
		"no lit model file is left under modern/")


func _has_model_files(folder: String) -> bool:
	for file: String in DirAccess.get_files_at(folder):
		if file.begins_with("model_"):
			return true
	return false


func test_lit_files_are_lit_and_keep_their_drawing_modes() -> void:
	for file: String in _model_files(false):
		_assert_thin_file(file, "model_", LIT_INCLUDE, LIT_MODES)
		var code: String = _code(file)
		if file.begins_with("model_textured_"):
			var filter: String = "filter_linear_mipmap" if file.contains("_linear") else "filter_nearest"
			assert_string_contains(code, "uniform sampler2D image : source_color, %s, repeat_disable;" % filter, file)
		else:
			assert_false(code.contains("sampler2D image"), file)


func test_the_lit_include_lights_with_the_scene_and_keeps_casters_undistorted() -> void:
	var code: String = _code(LIT_INCLUDE)
	assert_string_contains(code, "IN_SHADOW_PASS")
	assert_string_contains(code, "instance uniform vec3 %s" % ModelShaders.TINT_SCALE)
	assert_string_contains(code, "instance uniform vec4 %s" % ModelShaders.TINT_AMBIENT)
	assert_string_contains(code, "global uniform vec3 %s;" % ModelShaders.AMBIENT_GLOBAL)
	assert_string_contains(code, "NORMAL = -NORMAL;")
	assert_false(code.contains("source_"))
	assert_false(code.contains("unshaded"))


func test_unlit_files_cover_every_two_sided_sprite_combination() -> void:
	var unlit: PackedStringArray = _model_files(true)
	assert_eq(unlit.size(), 15, "textured nearest, textured linear and flat for each blend")
	for textured: bool in [false, true]:
		for blend: int in ModelShaders.BLEND_NAMES.size():
			for linear: bool in [false, true]:
				var path: String = ModelShaders.shader_path(textured, blend as ModelShaders.Blend, linear, true, false)
				assert_true(unlit.has(path.get_file()), path)
				assert_eq(path, ModelShaders.shader_path(textured, blend as ModelShaders.Blend, linear, false, false), "unlit files are two-sided")
				var made: ShaderMaterial = ModelShaders.material(null, blend as ModelShaders.Blend, linear, true, false)
				assert_true(made.shader.resource_path.get_file().begins_with(ModelShaders.UNLIT_PREFIX))
	for file: String in unlit:
		assert_true(file.ends_with("_two_sided.gdshader"), file)
		_assert_thin_file(file, ModelShaders.UNLIT_PREFIX, UNLIT_INCLUDE, ["unshaded"])
		var code: String = _code(file)
		assert_true(code.split("\n")[1].begins_with("render_mode unshaded, "), "%s keeps the anchor the patchers extend" % file)
		if file.begins_with(ModelShaders.UNLIT_PREFIX + "textured_"):
			var filter: String = "filter_linear_mipmap" if file.contains("_linear") else "filter_nearest"
			assert_string_contains(code, "uniform sampler2D image : %s, repeat_disable;" % filter, file)
		else:
			assert_false(code.contains("sampler2D image"), file)


func test_the_unlit_include_shows_the_stored_colour_in_linear_light() -> void:
	var code: String = _code(UNLIT_INCLUDE)
	assert_string_contains(code, "vec3 shown = texel.rgb * min(COLOR.rgb * 2.0, vec3(1.0));")
	assert_string_contains(code, "vec3 shown = COLOR.rgb;")
	assert_string_contains(code, "ALBEDO = to_linear(clamp(shown, vec3(0.0), vec3(1.0)));")
	assert_string_contains(code, "if (texel.a < 0.5) {")
	assert_false(code.contains("source_"))
	assert_false(code.contains("IN_SHADOW_PASS"))
	assert_false(code.contains("tint_"))


func test_shader_code_writes_out_the_unlit_include() -> void:
	var code: String = ModelShaders.shader_code(true, ModelShaders.Blend.ADD, true)
	assert_true(code.begins_with(_code(ModelShaders.shader_path(true, ModelShaders.Blend.ADD, true, true, false).get_file()).get_slice("#include", 0)))
	assert_false(code.contains("#include"))
	assert_string_contains(code, "uniform sampler2D image : filter_linear_mipmap, repeat_disable;")
	assert_string_contains(code, _code(UNLIT_INCLUDE).strip_edges())


func test_no_shader_under_the_folder_uses_the_retail_colour_correction() -> void:
	var checked: int = 0
	var folders: Array[String] = [SHADER_DIR]
	while not folders.is_empty():
		var folder: String = folders.pop_back()
		for child: String in DirAccess.get_directories_at(folder):
			folders.append(folder.path_join(child))
		for file: String in DirAccess.get_files_at(folder):
			if file.ends_with(".gdshader") or file.ends_with(".gdshaderinc"):
				assert_false(FileAccess.get_file_as_string(folder.path_join(file)).contains("through_renderer"), folder.path_join(file))
				checked += 1
	assert_gt(checked, 45)

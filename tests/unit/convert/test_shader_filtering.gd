extends GutTest
## Image sampling in the shader files: linear variants mipmap, nearest variants do not.

const SHADER_DIR: String = "res://src/convert/shaders"
const LINEAR_IMAGE: String = "uniform sampler2D image : filter_linear_mipmap, repeat_disable;"
const NEAREST_IMAGE: String = "uniform sampler2D image : filter_nearest, repeat_disable;"
const NEAREST_CELS: String = "uniform sampler2D cel_texture : filter_nearest, repeat_disable;"


func test_linear_variants_sample_the_image_with_mipmaps() -> void:
	var linear := PackedStringArray()
	for file: String in _shader_files():
		if file.contains("_linear"):
			linear.append(file)
	assert_eq(linear.size(), 21, "ten map, one sky and ten model linear variants")
	for file: String in linear:
		var code: String = _code(file)
		assert_string_contains(code, LINEAR_IMAGE, file)
		if code.contains("cel_texture"):
			assert_string_contains(code, NEAREST_CELS, "%s keeps its cel data nearest" % file)


func test_nearest_variants_never_mipmap() -> void:
	for file: String in _shader_files():
		if file.contains("_linear"):
			continue
		var code: String = _code(file)
		assert_false(code.contains("mipmap"), file)
		if code.contains("sampler2D image"):
			assert_string_contains(code, NEAREST_IMAGE, file)


func test_linear_map_variants_inset_by_the_bound_texel() -> void:
	for file: String in _shader_files():
		if not file.begins_with("map_") or not file.contains("_linear"):
			continue
		var code: String = _code(file)
		assert_string_contains(code, "uniform vec2 texel_inset = vec2(0.0);", file)
		assert_string_contains(code, "texture(image, affine_uv / affine_weight - texel_inset)", file)
		assert_false(code.contains("pixel_scale * 0.5"), file)


func _shader_files() -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(SHADER_DIR):
		if file.ends_with(".gdshader"):
			found.append(file)
	assert_false(found.is_empty(), "shader folder is readable")
	return found


func _code(file: String) -> String:
	return FileAccess.get_file_as_string("%s/%s" % [SHADER_DIR, file])

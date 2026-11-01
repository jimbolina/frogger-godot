extends GutTest
## Image sampling in the model shader files: linear variants mipmap, nearest variants do not.

const SHADER_DIR: String = "res://src/rendering/shaders"
const LINEAR_SAMPLING: String = "filter_linear_mipmap, repeat_disable;"
const NEAREST_SAMPLING: String = "filter_nearest, repeat_disable;"
const NEAREST_CELS: String = "uniform sampler2D cel_texture : filter_nearest, repeat_disable;"


func test_linear_variants_sample_the_image_with_mipmaps() -> void:
	var linear := PackedStringArray()
	for file: String in _shader_files():
		if file.contains("_linear"):
			linear.append(file)
	assert_eq(linear.size(), 15, "ten lit and five unlit model linear variants")
	for file: String in linear:
		assert_string_contains(_image_line(file), LINEAR_SAMPLING, file)


func test_nearest_variants_never_mipmap() -> void:
	for file: String in _shader_files():
		if file.contains("_linear"):
			continue
		var code: String = _code(file)
		assert_false(code.contains("mipmap"), file)
		if code.contains("sampler2D image"):
			assert_string_contains(_image_line(file), NEAREST_SAMPLING, file)


func test_cel_data_stays_nearest() -> void:
	for include: String in ["model.gdshaderinc", "model_unlit.gdshaderinc"]:
		var code: String = _code(include)
		assert_string_contains(code, NEAREST_CELS, include)
		assert_false(code.contains("mipmap"), include)


func _image_line(file: String) -> String:
	for line: String in _code(file).split("\n"):
		if line.begins_with("uniform sampler2D image : "):
			return line
	return ""


func _shader_files() -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(SHADER_DIR):
		if file.begins_with("model_") and file.ends_with(".gdshader"):
			found.append(file)
	assert_false(found.is_empty(), "shader folder is readable")
	return found


func _code(file: String) -> String:
	return FileAccess.get_file_as_string("%s/%s" % [SHADER_DIR, file])

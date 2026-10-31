extends GutTest
## The retail shaders apply their Compatibility colour correction only on that
## renderer, so unshaded retail surfaces show the same bytes elsewhere.

const SHADER_DIR: String = "res://src/convert/shaders"
const GUARD: String = "#if CURRENT_RENDERER == RENDERER_COMPATIBILITY"


func _files(prefix: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file: String in DirAccess.get_files_at(SHADER_DIR):
		if file.begins_with(prefix) and file.ends_with(".gdshader"):
			found.append(SHADER_DIR.path_join(file))
	return found


func _assert_guarded(paths: PackedStringArray) -> void:
	assert_false(paths.is_empty())
	for path: String in paths:
		var code: String = FileAccess.get_file_as_string(path)
		var start: int = code.find("vec3 through_renderer(vec3 wanted) {")
		assert_gt(start, -1, path)
		var end: int = code.find("\n}\n", start)
		assert_gt(end, start, path)
		var body: String = code.substr(start, end - start)
		assert_true(body.begins_with("vec3 through_renderer(vec3 wanted) {\n%s\n" % GUARD), path)
		assert_string_contains(body, "\n#else\n\treturn mix(wanted / 12.92, pow((wanted + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), wanted));\n#endif", path)


func test_model_shaders_correct_only_on_compatibility() -> void:
	var paths: PackedStringArray = _files("model_")
	assert_eq(paths.size(), 30)
	_assert_guarded(paths)


func test_map_shaders_correct_only_on_compatibility() -> void:
	var paths: PackedStringArray = _files("map_")
	assert_eq(paths.size(), 32)
	_assert_guarded(paths)

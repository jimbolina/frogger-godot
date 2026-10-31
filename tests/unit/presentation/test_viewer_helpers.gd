extends GutTest
## Shared argument and capture helpers use explicit inputs and report filesystem failures.

var _folder: String


func before_each() -> void:
	_folder = ProjectSettings.globalize_path("user://viewer_capture_helpers")
	assert_eq(DirAccess.make_dir_recursive_absolute(_folder), OK)


func after_each() -> void:
	DirAccess.remove_absolute(_folder.path_join("capture.png"))
	DirAccess.remove_absolute(_folder.path_join("blocked"))
	DirAccess.remove_absolute(_folder.path_join("created"))
	DirAccess.remove_absolute(_folder)


func test_arguments_preserve_first_prefix_match_and_exact_flags() -> void:
	var arguments := PackedStringArray(["--level=first", "--level=second", "--tick=", "--tick=9", "--benchmark=true", "--probe-model", "--model=A=B"])
	assert_eq(ViewerArguments.value(arguments, "--level="), "first")
	assert_eq(ViewerArguments.value(arguments, "--tick="), "")
	assert_true(ViewerArguments.has_prefix(arguments, "--tick="))
	assert_eq(ViewerArguments.value(arguments, "--model="), "A=B")
	assert_eq(ViewerArguments.value(arguments, "--missing="), "")
	assert_false(ViewerArguments.has_prefix(arguments, "--missing="))
	assert_true(ViewerArguments.has_flag(arguments, "--probe-model"))
	assert_false(ViewerArguments.has_flag(arguments, "--benchmark"))
	assert_true(ViewerArguments.has_flag(PackedStringArray(["--benchmark"]), "--benchmark"))



func test_the_rendering_argument_wins_over_the_project_setting() -> void:
	var saved: String = str(ProjectSettings.get_setting(ViewerArguments.RENDERING_SETTING))
	assert_eq(saved, RenderingProfile.RETAIL)
	assert_eq(ViewerArguments.rendering_profile(PackedStringArray()), RenderingProfile.RETAIL)
	assert_eq(ViewerArguments.rendering_profile(PackedStringArray(["--rendering="])), RenderingProfile.RETAIL)
	assert_eq(ViewerArguments.rendering_profile(PackedStringArray(["--rendering= Modern "])), RenderingProfile.MODERN)
	ProjectSettings.set_setting(ViewerArguments.RENDERING_SETTING, RenderingProfile.MODERN)
	var from_setting: String = ViewerArguments.rendering_profile(PackedStringArray())
	var from_argument: String = ViewerArguments.rendering_profile(PackedStringArray(["--rendering=retail"]))
	ProjectSettings.set_setting(ViewerArguments.RENDERING_SETTING, saved)
	assert_eq(from_setting, RenderingProfile.MODERN)
	assert_eq(from_argument, RenderingProfile.RETAIL)


func test_assets_are_used_for_a_level_or_the_frog_only() -> void:
	assert_false(ViewerArguments.uses_assets(PackedStringArray()))
	assert_false(ViewerArguments.uses_assets(PackedStringArray(["--level=", "--scenario=normal"])))
	assert_true(ViewerArguments.uses_assets(PackedStringArray(["--level=ORG1"])))
	assert_true(ViewerArguments.uses_assets(PackedStringArray(["--frog-assets"])))
	assert_false(ViewerArguments.uses_assets(PackedStringArray(["--frog-assets=false"])))


func test_capture_validation_normalizes_paths_and_preserves_sibling_boundaries() -> void:
	var project: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	assert_false(ViewerCapture.external_folder(project))
	assert_false(ViewerCapture.external_folder(project.path_join("captures/../captures")))
	assert_false(ViewerCapture.external_folder(project.to_upper().replace("/", "\\") + "\\capture"))
	assert_false(ViewerCapture.external_folder("capture"))
	assert_false(ViewerCapture.external_folder("res://capture"))
	assert_false(ViewerCapture.external_folder("user://capture"))
	assert_true(ViewerCapture.external_folder(project + "-captures"))
	assert_true(ViewerCapture.external_folder(_folder))


func test_capture_directory_creation_reports_existing_file_failure() -> void:
	assert_eq(ViewerCapture.prepare_folder(_folder.path_join("created")), "")
	assert_true(DirAccess.dir_exists_absolute(_folder.path_join("created")))
	var blocked: String = _folder.path_join("blocked")
	var file: FileAccess = FileAccess.open(blocked, FileAccess.WRITE)
	file.store_string("synthetic blocker")
	file.close()
	var problem: String = ViewerCapture.prepare_folder(blocked.path_join("nested"))
	assert_engine_error("Method/function failed. Returning: err", "Godot reports the attempted directory creation failure")
	assert_string_contains(problem, blocked)
	assert_string_contains(problem, "Cannot create capture folder")
	assert_string_contains(ViewerCapture.prepare_folder("relative"), "outside the repository")


func test_image_capture_reports_write_failure_and_saves_valid_image() -> void:
	var image: Image = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var valid: String = _folder.path_join("capture.png")
	assert_eq(ViewerCapture.save_image(image, valid), "")
	assert_true(FileAccess.file_exists(valid))
	var invalid: String = _folder.path_join("missing/capture.png")
	var problem: String = ViewerCapture.save_image(image, invalid)
	assert_engine_error("Condition \"err\" is true. Returning: err", "Godot reports the attempted PNG write failure")
	assert_string_contains(problem, invalid)
	assert_string_contains(problem, "Cannot write capture")
	assert_string_contains(ViewerCapture.save_image(null, valid), "no image")

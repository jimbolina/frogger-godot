extends GutTest
## GraphicsStore round trips, defaults and recovery from damaged files.

const ROOT: String = "user://test_graphics_store"

var _path: String = ROOT.path_join("graphics.cfg")


func before_each() -> void:
	_remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)


func after_all() -> void:
	_remove_tree(ROOT)


func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _write_text(text: String) -> void:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _sample() -> GraphicsSettings:
	var settings := GraphicsSettings.new()
	settings.window_mode = GraphicsSettings.WindowMode.BORDERLESS_FULLSCREEN
	settings.window_size = Vector2i(1600, 900)
	settings.vsync = GraphicsSettings.Vsync.MAILBOX
	settings.max_fps = 144
	settings.render_scale = 0.75
	settings.scaler = GraphicsSettings.Scaler.FSR2
	settings.fsr_sharpness = 0.5
	settings.msaa = GraphicsSettings.Msaa.X4
	settings.screen_aa = GraphicsSettings.ScreenAa.SMAA
	settings.taa = true
	settings.real_shadows = false
	settings.shadow_atlas_size = 8192
	settings.soft_shadow_quality = GraphicsSettings.SoftShadow.ULTRA
	settings.shadow_splits = 4
	settings.shadow_split_1 = 0.1
	settings.shadow_max_distance = 48.5
	settings.shadow_bias = 0.02
	settings.shadow_normal_bias = 2.5
	settings.bloom = false
	settings.bloom_intensity = 1.25
	settings.bloom_threshold = 0.9
	settings.tonemapper = GraphicsSettings.Tonemapper.AGX
	settings.exposure = 1.5
	settings.ssao = true
	settings.glow_halo_strength = 4.5
	settings.glow_lights = false
	settings.glow_lights_in_caves = true
	settings.glow_light_energy = 2.0
	settings.lava_emission = 0.5
	settings.lava_lights = false
	settings.water_reflection = 0.6
	settings.water_specular = 0.4
	settings.water_shininess = 128.0
	settings.vertex_tint = 0.75
	settings.cave_light_mode = GraphicsSettings.CaveMode.FITTED_RANGE
	return settings


func _assert_defaults(store: GraphicsStore) -> void:
	var defaults := GraphicsSettings.new()
	for field: String in GraphicsSettings.field_names():
		var actual: Variant = store.settings.get(field)
		var expected: Variant = defaults.get(field)
		assert_eq(var_to_str(actual), var_to_str(expected), field)


func test_path_and_version() -> void:
	assert_eq(GraphicsStore.DEFAULT_PATH, "user://graphics.cfg")
	assert_eq(GraphicsStore.FORMAT_VERSION, 1)


func test_layout_holds_every_field_once() -> void:
	var stored: PackedStringArray = []
	for section: String in GraphicsStore.LAYOUT:
		for field: String in GraphicsStore.LAYOUT[section]:
			stored.append(field)
	var fields: PackedStringArray = GraphicsSettings.field_names()
	assert_eq(stored.size(), fields.size())
	for field: String in fields:
		assert_eq(stored.count(field), 1, field)
	assert_eq(GraphicsStore.LAYOUT.keys(), ["display", "quality", "shadows", "post", "effects", "look"])


func test_sample_differs_from_the_defaults_in_every_field() -> void:
	var sample: GraphicsSettings = _sample()
	var defaults := GraphicsSettings.new()
	assert_eq(sample.validate(), "")
	for field: String in GraphicsSettings.field_names():
		var changed: Variant = sample.get(field)
		var original: Variant = defaults.get(field)
		assert_ne(var_to_str(changed), var_to_str(original), field)


func test_round_trip_keeps_every_field() -> void:
	var saved: GraphicsSettings = _sample()
	assert_eq(GraphicsStore.save(saved, _path), "")
	var loaded: GraphicsStore = GraphicsStore.load_from(_path)
	assert_eq(loaded.error, "")
	for field: String in GraphicsSettings.field_names():
		var actual: Variant = loaded.settings.get(field)
		var expected: Variant = saved.get(field)
		assert_eq(var_to_str(actual), var_to_str(expected), field)
		assert_eq(typeof(actual), typeof(expected), field)


func test_save_writes_the_sections_and_version() -> void:
	assert_eq(GraphicsStore.save(GraphicsSettings.new(), _path), "")
	var file := ConfigFile.new()
	assert_eq(file.load(_path), OK)
	var version: Variant = file.get_value("meta", "format_version")
	var vsync: Variant = file.get_value("display", "vsync")
	var shininess: Variant = file.get_value("look", "water_shininess")
	assert_eq(var_to_str(version), "1")
	assert_eq(var_to_str(vsync), str(GraphicsSettings.Vsync.ENABLED))
	assert_eq(var_to_str(shininess), "512.0")


func test_save_creates_missing_folders() -> void:
	var nested: String = ROOT.path_join("a/b/graphics.cfg")
	assert_eq(GraphicsStore.save(_sample(), nested), "")
	assert_eq(GraphicsStore.load_from(nested).settings.max_fps, 144)


func test_missing_file_gives_defaults_without_error() -> void:
	var store: GraphicsStore = GraphicsStore.load_from(ROOT.path_join("absent.cfg"))
	assert_eq(store.error, "")
	_assert_defaults(store)


func test_missing_keys_take_their_defaults() -> void:
	_write_text("[meta]\nformat_version=1\n[display]\nmax_fps=60\n[post]\nbloom=false\n")
	var store: GraphicsStore = GraphicsStore.load_from(_path)
	assert_eq(store.error, "")
	assert_eq(store.settings.max_fps, 60)
	assert_false(store.settings.bloom)
	assert_eq(store.settings.vsync, GraphicsSettings.Vsync.ENABLED)
	assert_eq(store.settings.water_shininess, 512.0)


func test_integer_is_accepted_for_a_decimal() -> void:
	_write_text("[meta]\nformat_version=1\n[shadows]\nshadow_max_distance=40\n")
	var store: GraphicsStore = GraphicsStore.load_from(_path)
	assert_eq(store.error, "")
	assert_eq(store.settings.shadow_max_distance, 40.0)
	assert_eq(typeof(store.settings.shadow_max_distance), TYPE_FLOAT)


func test_corrupt_file_gives_defaults_and_names_the_file() -> void:
	_write_text("[meta\nformat_version=((((\n")
	var store: GraphicsStore = GraphicsStore.load_from(_path)
	assert_engine_error("ConfigFile parse error", "Godot reports the malformed file")
	assert_string_contains(store.error, _path)
	assert_string_contains(store.error, "using defaults")
	_assert_defaults(store)


func test_other_version_gives_defaults_and_names_both_versions() -> void:
	_write_text("[meta]\nformat_version=2\n[display]\nmax_fps=60\n")
	var store: GraphicsStore = GraphicsStore.load_from(_path)
	assert_string_contains(store.error, "format version 2, expected 1")
	_assert_defaults(store)


func test_missing_or_non_integer_version_is_rejected() -> void:
	_write_text("[display]\nmax_fps=60\n")
	assert_string_contains(GraphicsStore.load_from(_path).error, "no format version")
	_write_text("[meta]\nformat_version=\"1\"\n[display]\nmax_fps=60\n")
	var store: GraphicsStore = GraphicsStore.load_from(_path)
	assert_string_contains(store.error, "non-integer format version")
	_assert_defaults(store)


func test_wrong_types_are_rejected_whole() -> void:
	var cases: PackedStringArray = [
		"[display]\nvsync=\"on\"\n",
		"[display]\nwindow_size=Vector2(800, 600)\n",
		"[display]\nmax_fps=60.0\n",
		"[quality]\ntaa=1\n",
		"[shadows]\nshadow_bias=\"0.1\"\n",
		"[post]\nbloom=\"yes\"\n",
		"[look]\ncave_light_mode=0.0\n",
	]
	for body: String in cases:
		_write_text("[meta]\nformat_version=1\n[effects]\nlava_emission=0.5\n" + body)
		var store: GraphicsStore = GraphicsStore.load_from(_path)
		assert_string_contains(store.error, "type", body)
		_assert_defaults(store)


func test_out_of_range_values_are_rejected_whole() -> void:
	var cases: PackedStringArray = [
		"[display]\nwindow_mode=3\n",
		"[display]\nmax_fps=-5\n",
		"[quality]\nrender_scale=4.0\n",
		"[shadows]\nshadow_atlas_size=3000\n",
		"[shadows]\nshadow_splits=3\n",
		"[post]\nexposure=0\n",
		"[look]\nwater_specular=-1.0\n",
	]
	for body: String in cases:
		_write_text("[meta]\nformat_version=1\n[effects]\nlava_emission=0.5\n" + body)
		var store: GraphicsStore = GraphicsStore.load_from(_path)
		assert_string_contains(store.error, "using defaults", body)
		_assert_defaults(store)


func test_overwrite_replaces_the_file_and_leaves_no_temporary() -> void:
	assert_eq(GraphicsStore.save(_sample(), _path), "")
	var second := GraphicsSettings.new()
	second.max_fps = 30
	assert_eq(GraphicsStore.save(second, _path), "")
	var loaded: GraphicsStore = GraphicsStore.load_from(_path)
	assert_eq(loaded.error, "")
	assert_eq(loaded.settings.max_fps, 30)
	assert_true(loaded.settings.bloom)
	assert_false(FileAccess.file_exists(_path + ".tmp"))


func test_stale_temporary_does_not_block_saving() -> void:
	var stale: FileAccess = FileAccess.open(_path + ".tmp", FileAccess.WRITE)
	stale.store_string("garbage")
	stale.close()
	assert_eq(GraphicsStore.save(_sample(), _path), "")
	assert_eq(GraphicsStore.load_from(_path).error, "")
	assert_false(FileAccess.file_exists(_path + ".tmp"))


func test_invalid_values_are_not_saved_and_keep_the_previous_file() -> void:
	assert_eq(GraphicsStore.save(_sample(), _path), "")
	var bad := GraphicsSettings.new()
	bad.shadow_splits = 3
	assert_string_contains(GraphicsStore.save(bad, _path), "shadow_splits 3")
	assert_eq(GraphicsStore.load_from(_path).settings.max_fps, 144)
	assert_false(FileAccess.file_exists(_path + ".tmp"))

extends GutTest
## GraphicsSettings defaults, validation rules and copy isolation.


func _problem(field: String, value: Variant) -> String:
	var settings := GraphicsSettings.new()
	settings.set(field, value)
	return settings.validate()


func test_defaults() -> void:
	var settings := GraphicsSettings.new()
	assert_eq(settings.window_mode, GraphicsSettings.WindowMode.WINDOWED)
	assert_eq(settings.window_size, Vector2i.ZERO)
	assert_eq(settings.vsync, GraphicsSettings.Vsync.ENABLED)
	assert_eq(settings.max_fps, 0)
	assert_eq(settings.render_scale, 1.0)
	assert_eq(settings.scaler, GraphicsSettings.Scaler.BILINEAR)
	assert_eq(settings.fsr_sharpness, 0.2)
	assert_eq(settings.msaa, GraphicsSettings.Msaa.OFF)
	assert_eq(settings.screen_aa, GraphicsSettings.ScreenAa.OFF)
	assert_false(settings.taa)
	assert_true(settings.real_shadows)
	assert_eq(settings.shadow_atlas_size, 4096)
	assert_eq(settings.soft_shadow_quality, GraphicsSettings.SoftShadow.LOW)
	assert_eq(settings.shadow_splits, 2)
	assert_eq(settings.shadow_split_1, 0.25)
	assert_eq(settings.shadow_max_distance, 32.0)
	assert_eq(settings.shadow_bias, 0.05)
	assert_eq(settings.shadow_normal_bias, 1.0)
	assert_true(settings.bloom)
	assert_eq(settings.bloom_intensity, 0.8)
	assert_eq(settings.bloom_threshold, 1.0)
	assert_eq(settings.tonemapper, GraphicsSettings.Tonemapper.LINEAR)
	assert_eq(settings.exposure, 1.0)
	assert_false(settings.ssao)
	assert_eq(settings.glow_halo_strength, 3.0)
	assert_true(settings.glow_lights)
	assert_false(settings.glow_lights_in_caves)
	assert_eq(settings.glow_light_energy, 1.0)
	assert_eq(settings.lava_emission, 1.0)
	assert_true(settings.lava_lights)
	assert_eq(settings.water_reflection, 0.35)
	assert_eq(settings.water_specular, 0.2)
	assert_eq(settings.water_shininess, 512.0)
	assert_eq(settings.vertex_tint, 1.0)
	assert_eq(settings.cave_light_mode, GraphicsSettings.CaveMode.EXACT_EDGE)
	assert_eq(settings.validate(), "")


func test_field_names_cover_every_field_once() -> void:
	var names: PackedStringArray = GraphicsSettings.field_names()
	assert_eq(names.size(), 35)
	assert_eq(names[0], "window_mode")
	assert_eq(names[names.size() - 1], "cave_light_mode")
	for name: String in names:
		assert_eq(names.count(name), 1, name)


func test_enum_fields_reject_values_outside_their_enum() -> void:
	var counts: Dictionary[String, int] = {
		"window_mode": GraphicsSettings.WindowMode.size(),
		"vsync": GraphicsSettings.Vsync.size(),
		"scaler": GraphicsSettings.Scaler.size(),
		"msaa": GraphicsSettings.Msaa.size(),
		"screen_aa": GraphicsSettings.ScreenAa.size(),
		"soft_shadow_quality": GraphicsSettings.SoftShadow.size(),
		"tonemapper": GraphicsSettings.Tonemapper.size(),
		"cave_light_mode": GraphicsSettings.CaveMode.size(),
	}
	for field: String in counts:
		assert_eq(_problem(field, counts[field] - 1), "", field)
		assert_string_contains(_problem(field, counts[field]), field)
		assert_string_contains(_problem(field, -1), field)


func test_window_size_is_zero_or_positive() -> void:
	assert_eq(_problem("window_size", Vector2i(1280, 720)), "")
	assert_string_contains(_problem("window_size", Vector2i(0, 720)), "window_size")
	assert_string_contains(_problem("window_size", Vector2i(-1, -1)), "window_size")


func test_max_fps_is_uncapped_or_one_to_a_thousand() -> void:
	for good: int in [0, 1, 60, 1000]:
		assert_eq(_problem("max_fps", good), "", str(good))
	for bad: int in [-1, 1001]:
		assert_string_contains(_problem("max_fps", bad), "max_fps", str(bad))


func test_render_scale_range() -> void:
	for good: float in [0.25, 1.0, 2.0]:
		assert_eq(_problem("render_scale", good), "", str(good))
	for bad: float in [0.24, 2.01, NAN, INF]:
		assert_string_contains(_problem("render_scale", bad), "render_scale", str(bad))


func test_fsr_sharpness_range() -> void:
	assert_eq(_problem("fsr_sharpness", 0.0), "")
	assert_eq(_problem("fsr_sharpness", 2.0), "")
	assert_string_contains(_problem("fsr_sharpness", -0.1), "fsr_sharpness")
	assert_string_contains(_problem("fsr_sharpness", 2.1), "fsr_sharpness")


func test_shadow_atlas_is_a_power_of_two_in_range() -> void:
	for good: int in [512, 1024, 4096, 16384]:
		assert_eq(_problem("shadow_atlas_size", good), "", str(good))
	for bad: int in [256, 3000, 32768, 0, -4096]:
		assert_string_contains(_problem("shadow_atlas_size", bad), "shadow_atlas_size", str(bad))


func test_shadow_splits_are_one_two_or_four() -> void:
	for good: int in [1, 2, 4]:
		assert_eq(_problem("shadow_splits", good), "", str(good))
	for bad: int in [0, 3, 5]:
		assert_string_contains(_problem("shadow_splits", bad), "shadow_splits", str(bad))


func test_shadow_split_is_a_fraction() -> void:
	assert_eq(_problem("shadow_split_1", 0.0), "")
	assert_eq(_problem("shadow_split_1", 1.0), "")
	assert_string_contains(_problem("shadow_split_1", -0.01), "shadow_split_1")
	assert_string_contains(_problem("shadow_split_1", 1.01), "shadow_split_1")


func test_distance_and_exposure_must_be_positive() -> void:
	for field: String in ["shadow_max_distance", "exposure"]:
		assert_eq(_problem(field, 0.5), "", field)
		assert_string_contains(_problem(field, 0.0), field)
		assert_string_contains(_problem(field, -1.0), field)
		assert_string_contains(_problem(field, INF), field)


func test_scalars_must_be_finite_and_non_negative() -> void:
	var fields: PackedStringArray = [
		"shadow_bias", "shadow_normal_bias", "bloom_intensity", "bloom_threshold",
		"glow_halo_strength", "glow_light_energy", "lava_emission", "water_reflection",
		"water_specular", "water_shininess", "vertex_tint",
	]
	for field: String in fields:
		assert_eq(_problem(field, 0.0), "", field)
		assert_eq(_problem(field, 100.0), "", field)
		assert_string_contains(_problem(field, -0.01), field)
		assert_string_contains(_problem(field, NAN), field)
		assert_string_contains(_problem(field, INF), field)


func test_copy_is_independent() -> void:
	var source := GraphicsSettings.new()
	source.window_size = Vector2i(800, 600)
	source.bloom = false
	source.tonemapper = GraphicsSettings.Tonemapper.AGX
	var duplicate: GraphicsSettings = source.copy()
	assert_ne(duplicate, source)
	assert_eq(duplicate.window_size, Vector2i(800, 600))
	assert_false(duplicate.bloom)
	assert_eq(duplicate.tonemapper, GraphicsSettings.Tonemapper.AGX)
	source.window_size = Vector2i(1, 1)
	source.bloom = true
	assert_eq(duplicate.window_size, Vector2i(800, 600))
	assert_false(duplicate.bloom)


func test_assign_copies_every_field_without_linking() -> void:
	var source := GraphicsSettings.new()
	source.max_fps = 144
	source.render_scale = 0.5
	source.cave_light_mode = GraphicsSettings.CaveMode.FITTED_RANGE
	var target := GraphicsSettings.new()
	target.assign(source)
	for field: String in GraphicsSettings.field_names():
		var copied: Variant = target.get(field)
		var original: Variant = source.get(field)
		assert_eq(var_to_str(copied), var_to_str(original), field)
	source.max_fps = 30
	assert_eq(target.max_fps, 144)


func test_assign_does_not_emit_changed() -> void:
	var target := GraphicsSettings.new()
	watch_signals(target)
	target.assign(GraphicsSettings.new())
	assert_signal_not_emitted(target, "changed")

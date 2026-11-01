extends GutTest
## The graphics defaults reproduce the accepted modern look and launch settings.

var _defaults := GraphicsSettings.new()


func test_shadow_defaults_match_the_scene_lighting_spec() -> void:
	var spec := SceneLightingSpec.new()
	assert_eq(_defaults.shadow_splits, spec.shadow_splits)
	assert_eq(_defaults.shadow_split_1, spec.split_1)
	assert_eq(_defaults.shadow_max_distance, spec.max_distance)
	assert_eq(_defaults.shadow_bias, spec.bias)
	assert_eq(_defaults.shadow_normal_bias, spec.normal_bias)


func test_water_and_tint_defaults_match_the_map_mesh() -> void:
	assert_eq(_defaults.water_reflection, MapMesh.Instance.WATER_REFLECTION)
	assert_eq(_defaults.water_specular, MapMesh.Instance.WATER_SPECULAR)
	assert_eq(_defaults.water_shininess, MapMesh.Instance.WATER_SHININESS)
	assert_eq(_defaults.vertex_tint, 1.0)


func test_halo_strength_matches_the_halo_material() -> void:
	assert_eq(_defaults.glow_halo_strength, GlowHaloMaterial.DEFAULT_STRENGTH)


func test_cave_mode_matches_the_cave_light_shape() -> void:
	assert_eq(int(_defaults.cave_light_mode), int(CaveLightShape.DEFAULT_MODE))
	assert_eq(GraphicsSettings.CaveMode.size(), CaveLightShape.Mode.size())
	assert_eq(int(GraphicsSettings.CaveMode.EXACT_EDGE), int(CaveLightShape.Mode.EXACT_EDGE))
	assert_eq(int(GraphicsSettings.CaveMode.FITTED_RANGE), int(CaveLightShape.Mode.FITTED_RANGE))


func _setting(name: String) -> int:
	var value: Variant = ProjectSettings.get_setting(name)
	assert_eq(typeof(value), TYPE_INT, name)
	if typeof(value) != TYPE_INT:
		return -1
	var setting: int = value
	return setting


func test_quality_defaults_match_the_project_settings() -> void:
	assert_eq(_defaults.shadow_atlas_size, _setting("rendering/lights_and_shadows/directional_shadow/size"))
	assert_eq(int(_defaults.soft_shadow_quality),
		_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))
	assert_eq(int(_defaults.msaa), _setting("rendering/anti_aliasing/quality/msaa_3d"))
	assert_eq(int(_defaults.vsync), _setting("display/window/vsync/vsync_mode"))
	assert_eq(_defaults.max_fps, _setting("application/run/max_fps"))

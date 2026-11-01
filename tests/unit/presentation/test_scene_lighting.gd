extends GutTest
## The scene lighting node builds one environment and a directional light per spec slot, and leaves nothing behind;
## bloom, tone mapping and the shadow constants follow the live graphics profile in place.

var _lighting: SceneLighting


func before_each() -> void:
	_lighting = SceneLighting.new()
	add_child_autofree(_lighting)


func after_each() -> void:
	GraphicsProfile.reset()


func _change(field: String, value: Variant) -> void:
	var values: GraphicsSettings = GraphicsProfile.current().copy()
	values.set(field, value)
	GraphicsProfile.replace(values)


func _spec() -> SceneLightingSpec:
	var spec := SceneLightingSpec.new()
	spec.ambient = Vector3(0.1, 0.2, 0.05)
	spec.shadows = true
	spec.split_1 = 0.3
	spec.max_distance = 40.0
	spec.fade_start = 0.7
	spec.bias = 0.04
	spec.normal_bias = 0.9
	spec.blur = 1.5
	var first := SceneLightingSpec.Light.new()
	first.basis = Basis.looking_at(Vector3(1, -1, 0).normalized(), Vector3.UP)
	first.colour = Color(1.0, 0.8, 0.6)
	first.energy = 0.7
	first.casts_shadow = true
	var second := SceneLightingSpec.Light.new()
	second.basis = Basis.looking_at(Vector3(0, -1, 1).normalized(), Vector3.UP)
	second.colour = Color(0.5, 0.6, 1.0)
	second.energy = 0.2
	spec.lights = [first, second]
	return spec


func _children_of(type: String) -> int:
	var count: int = 0
	for child: Node in _lighting.get_children():
		if child.is_class(type):
			count += 1
	return count


func test_a_two_light_spec_builds_two_lights_and_one_environment() -> void:
	var spec: SceneLightingSpec = _spec()
	_lighting.apply(spec)
	assert_eq(_children_of("DirectionalLight3D"), 2)
	assert_eq(_children_of("WorldEnvironment"), 1)
	var lights: Array[DirectionalLight3D] = _lighting.light_nodes()
	assert_eq(lights.size(), 2)
	var casters: int = 0
	for index: int in lights.size():
		var light: DirectionalLight3D = lights[index]
		var source: SceneLightingSpec.Light = spec.lights[index]
		assert_true(light.transform.basis.is_equal_approx(source.basis))
		assert_eq(light.light_color, source.colour)
		assert_almost_eq(light.light_energy, source.energy, 1e-6)
		assert_eq(light.light_angular_distance, 0.0)
		assert_eq(light.shadow_caster_mask, SceneLightingSpec.SHADOW_CASTER_LAYER)
		assert_eq(light.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
		assert_almost_eq(light.directional_shadow_split_1, 0.25, 1e-6, "the settings' split")
		assert_almost_eq(light.directional_shadow_max_distance, 32.0, 1e-6, "the settings' distance")
		assert_almost_eq(light.directional_shadow_fade_start, 0.7, 1e-6)
		assert_almost_eq(light.shadow_bias, 0.05, 1e-6, "the settings' bias")
		assert_almost_eq(light.shadow_normal_bias, 1.0, 1e-6, "the settings' normal bias")
		assert_almost_eq(light.shadow_blur, 1.5, 1e-6)
		if light.shadow_enabled:
			casters += 1
	assert_eq(casters, 1, "only the spec's caster casts shadows")
	assert_true(lights[0].shadow_enabled)
	assert_eq(_lighting.applied_ambient, spec.ambient)
	assert_eq(_lighting.applied_spec, spec)


func test_split_counts_follow_the_settings_not_the_spec() -> void:
	var spec: SceneLightingSpec = _spec()
	spec.shadow_splits = 1
	_change("shadow_splits", 4)
	_lighting.apply(spec)
	for light: DirectionalLight3D in _lighting.light_nodes():
		assert_eq(light.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	_change("shadow_splits", 1)
	assert_eq(_lighting.light_nodes()[0].directional_shadow_mode, DirectionalLight3D.SHADOW_ORTHOGONAL)


func test_the_spec_is_the_shadow_ceiling() -> void:
	var spec: SceneLightingSpec = _spec()
	spec.shadows = false
	_lighting.apply(spec)
	for light: DirectionalLight3D in _lighting.light_nodes():
		assert_false(light.shadow_enabled, "the spec turns shadows off even when the settings allow them")
	_change("bloom", false)
	assert_false(_lighting.light_nodes()[0].shadow_enabled, "a profile change does not lift the ceiling")


func test_real_shadows_off_in_the_settings_turns_the_caster_off_in_place() -> void:
	_lighting.apply(_spec())
	var caster: DirectionalLight3D = _lighting.light_nodes()[0]
	assert_true(caster.shadow_enabled)
	_change("real_shadows", false)
	assert_false(caster.shadow_enabled)
	_change("real_shadows", true)
	assert_true(caster.shadow_enabled)
	assert_false(_lighting.light_nodes()[1].shadow_enabled, "a light that is not the caster stays off")
	_change("real_shadows", false)
	_lighting.apply(_spec())
	assert_false(_lighting.light_nodes()[0].shadow_enabled, "applying reads the settings")


func test_shadow_constants_follow_a_profile_change_on_the_same_lights() -> void:
	_lighting.apply(_spec())
	var before: Array[DirectionalLight3D] = _lighting.light_nodes()
	var values: GraphicsSettings = GraphicsProfile.current().copy()
	values.shadow_split_1 = 0.4
	values.shadow_max_distance = 48.0
	values.shadow_bias = 0.08
	values.shadow_normal_bias = 1.5
	GraphicsProfile.replace(values)
	var after: Array[DirectionalLight3D] = _lighting.light_nodes()
	assert_eq(after, before, "the lights are not rebuilt")
	assert_eq(_children_of("DirectionalLight3D"), 2)
	for light: DirectionalLight3D in after:
		assert_almost_eq(light.directional_shadow_split_1, 0.4, 1e-6)
		assert_almost_eq(light.directional_shadow_max_distance, 48.0, 1e-6)
		assert_almost_eq(light.shadow_bias, 0.08, 1e-6)
		assert_almost_eq(light.shadow_normal_bias, 1.5, 1e-6)
		assert_almost_eq(light.directional_shadow_fade_start, 0.7, 1e-6, "fade stays on the spec")
		assert_almost_eq(light.shadow_blur, 1.5, 1e-6, "blur stays on the spec")


func test_the_environment_carries_the_linear_ambient_and_the_default_post() -> void:
	var spec: SceneLightingSpec = _spec()
	_lighting.apply(spec)
	var environment: Environment = _lighting.environment
	assert_not_null(environment)
	assert_eq(_lighting.world_environment().environment, environment)
	assert_eq(environment.background_mode, Environment.BG_COLOR)
	assert_eq(environment.background_color, Color.BLACK)
	assert_eq(environment.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)
	var ambient: Color = environment.ambient_light_color.srgb_to_linear()
	assert_almost_eq(Vector3(ambient.r, ambient.g, ambient.b), spec.ambient, Vector3.ONE * 1e-4)
	assert_eq(environment.ambient_light_energy, 1.0)
	assert_eq(environment.tonemap_mode, Environment.TONE_MAPPER_LINEAR)
	assert_eq(environment.tonemap_exposure, 1.0)
	assert_true(environment.glow_enabled, "bloom is on by default")
	assert_almost_eq(environment.glow_intensity, 0.8, 1e-6)
	assert_eq(environment.glow_hdr_threshold, 1.0, "stored colours of one or less do not bloom")
	assert_eq(environment.glow_hdr_scale, 2.0)
	assert_eq(environment.glow_bloom, 0.0)
	assert_eq(environment.glow_blend_mode, Environment.GLOW_BLEND_MODE_ADDITIVE)
	assert_false(environment.fog_enabled)
	assert_false(environment.volumetric_fog_enabled)
	assert_false(environment.ssao_enabled)
	assert_false(environment.ssil_enabled)
	assert_false(environment.ssr_enabled)
	assert_false(environment.sdfgi_enabled)


func test_reapplying_leaves_no_leftover_nodes() -> void:
	_lighting.apply(_spec())
	var single: SceneLightingSpec = _spec()
	single.lights = [single.lights[1]]
	_lighting.apply(single)
	assert_eq(_lighting.get_child_count(), 2)
	assert_eq(_children_of("DirectionalLight3D"), 1)
	assert_eq(_children_of("WorldEnvironment"), 1)
	assert_eq(_lighting.light_nodes().size(), 1)


func test_clear_removes_the_lights_and_resets_the_ambient() -> void:
	_lighting.apply(_spec())
	var environment: Environment = _lighting.environment
	_lighting.clear()
	assert_eq(_children_of("DirectionalLight3D"), 0)
	assert_eq(_lighting.light_nodes().size(), 0)
	assert_eq(_children_of("WorldEnvironment"), 1, "the environment stays")
	assert_eq(_lighting.environment, environment)
	assert_eq(_lighting.applied_ambient, Vector3.ONE)
	assert_null(_lighting.applied_spec)


func test_nothing_is_built_before_a_spec_is_applied() -> void:
	assert_eq(_lighting.get_child_count(), 0)
	assert_null(_lighting.environment)
	assert_null(_lighting.world_environment())


func test_the_cave_light_is_created_once_and_follows_its_radii() -> void:
	_lighting.apply(_spec())
	var radii: PackedInt64Array = MapLighting.initial_cave_radii(5)
	_lighting.set_cave_light(Vector3(1, 2, 3), radii[0], radii[1])
	var light: OmniLight3D = _lighting.cave_light_node()
	assert_not_null(light)
	assert_eq(_children_of("OmniLight3D"), 1)
	assert_eq(light.omni_attenuation, 0.0)
	assert_false(light.shadow_enabled)
	assert_eq(light.light_specular, 0.0)
	assert_almost_eq(light.position, Vector3(1, 2 + CaveLightShape.HEIGHT, 3), Vector3.ONE * 1e-6)
	assert_almost_eq(light.omni_range, CaveLightShape.range_of(radii[1], CaveLightShape.DEFAULT_MODE), 1e-5)
	assert_almost_eq(light.light_energy, CaveLightShape.energy_of(radii[0], radii[1], CaveLightShape.DEFAULT_MODE), 1e-5)
	var wider: PackedInt64Array = MapLighting.initial_cave_radii(8)
	_lighting.set_cave_light(Vector3(-4, 0, 2), wider[0], wider[1], CaveLightShape.Mode.FITTED_RANGE)
	assert_eq(_lighting.cave_light_node(), light, "the same light is updated")
	assert_eq(_children_of("OmniLight3D"), 1)
	assert_almost_eq(light.position, Vector3(-4, CaveLightShape.HEIGHT, 2), Vector3.ONE * 1e-6)
	assert_almost_eq(light.omni_range, CaveLightShape.range_of(wider[1], CaveLightShape.Mode.FITTED_RANGE), 1e-5)
	assert_almost_eq(light.light_energy, CaveLightShape.energy_of(wider[0], wider[1], CaveLightShape.Mode.FITTED_RANGE), 1e-5)


func test_cave_mode_removes_the_directional_lights_and_dims_the_ambient() -> void:
	var spec: SceneLightingSpec = _spec()
	_lighting.apply(spec)
	_lighting.set_cave_light(Vector3.ZERO, 1, 65536)
	assert_eq(_children_of("DirectionalLight3D"), 0)
	assert_eq(_lighting.light_nodes().size(), 0)
	assert_eq(_lighting.applied_spec, spec, "the spec is kept for restoring")
	assert_almost_eq(_lighting.environment.ambient_light_energy, CaveLightShape.CAVE_AMBIENT, 1e-6)
	assert_eq(_lighting.environment.background_color, Color.BLACK)
	assert_almost_eq(_lighting.applied_ambient, spec.ambient * CaveLightShape.CAVE_AMBIENT, Vector3.ONE * 1e-7)
	_lighting.apply(spec)
	assert_eq(_children_of("DirectionalLight3D"), 0, "reapplying keeps cave mode")
	assert_almost_eq(_lighting.environment.ambient_light_energy, CaveLightShape.CAVE_AMBIENT, 1e-6)


func test_clearing_the_cave_light_restores_the_spec() -> void:
	var spec: SceneLightingSpec = _spec()
	_lighting.apply(spec)
	_lighting.set_cave_light(Vector3.ZERO, 1, 65536)
	_lighting.clear_cave_light()
	assert_null(_lighting.cave_light_node())
	assert_eq(_children_of("OmniLight3D"), 0)
	assert_eq(_children_of("DirectionalLight3D"), 2)
	assert_eq(_lighting.environment.ambient_light_energy, 1.0)
	assert_eq(_lighting.applied_ambient, spec.ambient)


func test_clear_also_removes_the_cave_light() -> void:
	_lighting.apply(_spec())
	_lighting.set_cave_light(Vector3.ZERO, 1, 65536)
	_lighting.clear()
	assert_null(_lighting.cave_light_node())
	assert_eq(_children_of("OmniLight3D"), 0)
	assert_eq(_lighting.applied_ambient, Vector3.ONE)
	assert_eq(_lighting.environment.ambient_light_energy, 1.0)


func test_a_profile_change_updates_the_environment_in_place() -> void:
	_lighting.apply(_spec())
	var environment: Environment = _lighting.environment
	var values: GraphicsSettings = GraphicsProfile.current().copy()
	values.bloom = false
	values.bloom_intensity = 1.4
	values.bloom_threshold = 1.5
	values.tonemapper = GraphicsSettings.Tonemapper.AGX
	values.exposure = 1.2
	values.ssao = true
	GraphicsProfile.replace(values)
	assert_eq(_lighting.environment, environment, "the same environment")
	assert_eq(_lighting.world_environment().environment, environment)
	assert_false(environment.glow_enabled)
	assert_almost_eq(environment.glow_intensity, 1.4, 1e-6)
	assert_almost_eq(environment.glow_hdr_threshold, 1.5, 1e-6)
	assert_eq(environment.tonemap_mode, Environment.TONE_MAPPER_AGX)
	assert_almost_eq(environment.tonemap_exposure, 1.2, 1e-6)
	assert_true(environment.ssao_enabled)
	assert_false(environment.ssr_enabled, "effects the settings do not own stay off")


func test_a_profile_change_keeps_a_background_set_after_apply() -> void:
	_lighting.apply(_spec())
	_lighting.environment.background_mode = Environment.BG_CANVAS
	_lighting.environment.background_color = Color(0.3, 0.3, 0.3)
	_change("bloom", false)
	assert_eq(_lighting.environment.background_mode, Environment.BG_CANVAS)
	assert_eq(_lighting.environment.background_color, Color(0.3, 0.3, 0.3))
	assert_eq(_lighting.applied_ambient, _spec().ambient, "the ambient is untouched")


func test_cave_mode_survives_a_profile_change() -> void:
	var spec: SceneLightingSpec = _spec()
	_lighting.apply(spec)
	_lighting.set_cave_light(Vector3.ZERO, 1, 65536)
	var light: OmniLight3D = _lighting.cave_light_node()
	_change("real_shadows", false)
	_change("tonemapper", GraphicsSettings.Tonemapper.FILMIC)
	assert_eq(_lighting.cave_light_node(), light)
	assert_eq(_children_of("DirectionalLight3D"), 0, "no directional light returns")
	assert_almost_eq(_lighting.environment.ambient_light_energy, CaveLightShape.CAVE_AMBIENT, 1e-6)
	assert_almost_eq(_lighting.applied_ambient, spec.ambient * CaveLightShape.CAVE_AMBIENT, Vector3.ONE * 1e-7)
	assert_eq(_lighting.environment.tonemap_mode, Environment.TONE_MAPPER_FILMIC)
	_lighting.clear_cave_light()
	assert_false(_lighting.light_nodes()[0].shadow_enabled, "restored lights read the settings")


func test_a_light_outside_the_tree_reads_the_profile_on_apply_and_ignores_changes() -> void:
	var detached := SceneLighting.new()
	_change("bloom", false)
	detached.apply(_spec())
	assert_false(detached.environment.glow_enabled)
	_change("bloom", true)
	assert_false(detached.environment.glow_enabled, "not subscribed outside the tree")
	detached.free()


func test_leaving_the_tree_stops_following_the_profile() -> void:
	_lighting.apply(_spec())
	remove_child(_lighting)
	_change("bloom", false)
	assert_true(_lighting.environment.glow_enabled)
	add_child(_lighting)
	_change("bloom", false)
	assert_false(_lighting.environment.glow_enabled, "re-entering subscribes again")

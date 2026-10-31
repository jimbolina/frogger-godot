extends GutTest
## The scene lighting node builds one environment and a directional light per spec slot, and leaves nothing behind.

var _lighting: SceneLighting


func before_each() -> void:
	_lighting = SceneLighting.new()
	add_child_autofree(_lighting)


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
		assert_almost_eq(light.directional_shadow_split_1, 0.3, 1e-6)
		assert_almost_eq(light.directional_shadow_max_distance, 40.0, 1e-6)
		assert_almost_eq(light.directional_shadow_fade_start, 0.7, 1e-6)
		assert_almost_eq(light.shadow_bias, 0.04, 1e-6)
		assert_almost_eq(light.shadow_normal_bias, 0.9, 1e-6)
		assert_almost_eq(light.shadow_blur, 1.5, 1e-6)
		if light.shadow_enabled:
			casters += 1
	assert_eq(casters, 1, "only the spec's caster casts shadows")
	assert_true(lights[0].shadow_enabled)
	assert_eq(_lighting.applied_ambient, spec.ambient)
	assert_eq(_lighting.applied_spec, spec)


func test_shadows_off_and_split_counts_follow_the_spec() -> void:
	var spec: SceneLightingSpec = _spec()
	spec.shadows = false
	spec.shadow_splits = 4
	_lighting.apply(spec)
	for light: DirectionalLight3D in _lighting.light_nodes():
		assert_false(light.shadow_enabled)
		assert_eq(light.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	spec.shadow_splits = 1
	_lighting.apply(spec)
	assert_eq(_lighting.light_nodes()[0].directional_shadow_mode, DirectionalLight3D.SHADOW_ORTHOGONAL)


func test_the_environment_carries_the_linear_ambient_and_no_effects() -> void:
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
	assert_false(environment.glow_enabled)
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

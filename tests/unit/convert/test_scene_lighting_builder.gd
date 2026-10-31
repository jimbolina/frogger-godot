extends GutTest
## SceneLightingBuilder maps C ambient and parallel slots to linear scene light, light bases and one shadow caster.

const EPSILON: float = 1e-6
const COLOUR_EPSILON: float = 1e-5


func _lighting(ambient: Vector3, directions: Array[Vector3], colours: Array[Vector3]) -> MapLighting:
	var lighting := MapLighting.new()
	lighting.ambient = ambient
	lighting.directions = directions
	lighting.colours = colours
	return lighting


func test_basis_minus_z_is_the_travel_direction() -> void:
	var directions: Array[Vector3] = [Vector3(-0.5483, -0.8142, -0.1907).normalized(), Vector3(1, 0, 0),
		Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(0.3, -0.2, 0.9).normalized()]
	for direction: Vector3 in directions:
		var forward: Vector3 = SceneLightingBuilder.forward_basis(direction) * Vector3.FORWARD
		assert_true(forward.is_equal_approx(direction) and forward.distance_to(direction) <= EPSILON, "%s gives %s" % [direction, forward])


func test_vertical_directions_fall_back_to_forward_up() -> void:
	for direction: Vector3 in [Vector3.DOWN, Vector3.UP, Vector3(0.0001, -1.0, 0.0).normalized()]:
		var basis: Basis = SceneLightingBuilder.forward_basis(direction)
		assert_true((basis * Vector3.FORWARD).distance_to(direction) <= EPSILON, "%s" % direction)
		assert_true(basis.is_conformal() and absf(basis.determinant() - 1.0) <= EPSILON, "%s orthonormal" % direction)
	assert_eq(SceneLightingBuilder.forward_basis(Vector3.ZERO), Basis.IDENTITY)


func test_gamma_clamps_stored_fractions() -> void:
	assert_eq(SceneLightingBuilder.gamma(-0.5), 0.0)
	assert_eq(SceneLightingBuilder.gamma(1.5), 1.0)
	assert_almost_eq(SceneLightingBuilder.gamma(0.5), pow(0.5, 2.2), EPSILON)


func test_brightest_slot_casts_with_lowest_index_on_ties() -> void:
	var down: Array[Vector3] = [Vector3.DOWN, Vector3.LEFT, Vector3.BACK]
	var colours: Array[Vector3] = [Vector3(1024, 1024, 1024), Vector3(0, 2048, 0), Vector3(0, 2048, 0)]
	var spec: SceneLightingSpec = SceneLightingBuilder.from_lighting(_lighting(Vector3.ZERO, down, colours))
	assert_eq(_casters(spec), [1])
	var blue_first: Array[Vector3] = [Vector3(0, 0, 4080), Vector3(4080, 0, 0)]
	var two: Array[Vector3] = [Vector3.DOWN, Vector3.LEFT]
	assert_eq(_casters(SceneLightingBuilder.from_lighting(_lighting(Vector3.ZERO, two, blue_first))), [1], "red outweighs blue")
	var unshadowed: SceneLightingSpec = SceneLightingBuilder.from_lighting(_lighting(Vector3.ZERO, down, colours), false)
	assert_eq(_casters(unshadowed), [])
	assert_false(unshadowed.shadows)


func test_saturated_slots_keep_only_the_remaining_light() -> void:
	var directions: Array[Vector3] = [Vector3.DOWN, Vector3.LEFT]
	var colours: Array[Vector3] = [Vector3(4080, 4080, 4080), Vector3(4080, 4080, 4080)]
	var spec: SceneLightingSpec = SceneLightingBuilder.from_lighting(_lighting(Vector3(3072, 3072, 3072), directions, colours))
	var remaining: float = 1.0 - pow(0.75, 2.2)
	assert_almost_eq(spec.ambient.x, pow(0.75, 2.2), COLOUR_EPSILON)
	for light: SceneLightingSpec.Light in spec.lights:
		assert_almost_eq(light.energy, remaining * SceneLightingBuilder.LAMBERT_SCALE, COLOUR_EPSILON)
		assert_eq(light.colour, Color.WHITE)
	var full: SceneLightingSpec = SceneLightingBuilder.from_lighting(_lighting(Vector3(4096, 4096, 4096), directions, colours))
	assert_eq(full.lights[0].energy, 0.0)
	assert_eq(full.lights[0].colour, Color.WHITE)
	assert_eq(_casters(full), [0])


func test_lambert_scale_multiplies_energy() -> void:
	var directions: Array[Vector3] = [Vector3.DOWN]
	var colours: Array[Vector3] = [Vector3(2048, 1024, 0)]
	var spec: SceneLightingSpec = SceneLightingBuilder.from_lighting(_lighting(Vector3.ZERO, directions, colours))
	assert_almost_eq(spec.lights[0].energy, pow(0.5, 2.2) * SceneLightingBuilder.LAMBERT_SCALE, COLOUR_EPSILON)
	assert_almost_eq(SceneLightingBuilder.light_energy(Vector3(0.2, 0.4, 0.1)), 0.4 * SceneLightingBuilder.LAMBERT_SCALE, EPSILON)
	var colour: Color = spec.lights[0].colour
	assert_almost_eq(colour.r, 1.0, COLOUR_EPSILON)
	assert_almost_eq(colour.g, Color(pow(0.25, 2.2) / pow(0.5, 2.2), 0, 0).linear_to_srgb().r, COLOUR_EPSILON)
	assert_eq(colour.b, 0.0)


func test_no_lights_give_an_empty_spec() -> void:
	var lighting := MapLighting.new()
	var empty: Array[MapLight] = []
	lighting.configure(empty)
	var spec: SceneLightingSpec = SceneLightingBuilder.from_lighting(lighting)
	assert_eq(spec.ambient, Vector3.ZERO)
	assert_true(spec.lights.is_empty())
	assert_true(spec.shadows)


func test_zero_direction_slot_lights_nothing() -> void:
	var directions: Array[Vector3] = [Vector3.ZERO]
	var colours: Array[Vector3] = [Vector3(4080, 4080, 4080)]
	var spec: SceneLightingSpec = SceneLightingBuilder.from_lighting(_lighting(Vector3.ZERO, directions, colours))
	assert_eq(spec.lights[0].energy, 0.0)
	assert_eq(spec.lights[0].basis, Basis.IDENTITY)


func test_shadow_defaults() -> void:
	var spec := SceneLightingSpec.new()
	assert_eq(SceneLightingSpec.SHADOW_CASTER_LAYER, 1 << 19)
	assert_eq(spec.shadow_splits, 2)
	assert_eq(spec.split_1, 0.25)
	assert_eq(spec.max_distance, 32.0)
	assert_eq(spec.fade_start, 0.8)
	assert_eq(spec.bias, 0.05)
	assert_eq(spec.normal_bias, 1.0)
	assert_eq(spec.blur, 1.0)


func _casters(spec: SceneLightingSpec) -> Array:
	var result: Array = []
	for index: int in spec.lights.size():
		if spec.lights[index].casts_shadow:
			result.append(index)
	return result

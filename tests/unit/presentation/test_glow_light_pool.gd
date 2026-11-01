extends GutTest
## The glow light pool reuses its shadowless lights across frames and hides those it does not need.

var _pool: GlowLightPool


func before_each() -> void:
	_pool = GlowLightPool.new()
	add_child_autofree(_pool)


func _points(count: int) -> Array[GlowLightSpec.Point]:
	var points: Array[GlowLightSpec.Point] = []
	for index: int in count:
		points.append(GlowLightSpec.Point.new(Vector3(index, 0.5, 0), Color(1.0, 0.5, 0.25), 0.5 + index, 1.5))
	return points


func test_points_place_lights_with_their_colour_energy_and_range() -> void:
	assert_eq(_pool.place(_points(2), 2.0), 2)
	var lights: Array[OmniLight3D] = _pool.lights()
	assert_eq(lights.size(), 2)
	assert_eq(lights[1].position, Vector3(1, 0.5, 0))
	assert_eq(lights[1].light_color, Color(1.0, 0.5, 0.25))
	assert_eq(lights[1].light_energy, 3.0, "point energy times the scale")
	assert_eq(lights[1].omni_range, 1.5)
	for light: OmniLight3D in lights:
		assert_false(light.shadow_enabled)
		assert_eq(light.light_specular, 0.0)
		assert_eq(light.omni_attenuation, GlowLightPool.ATTENUATION)
		assert_true(light.visible)


func test_lights_are_reused_and_unused_ones_hidden() -> void:
	_pool.place(_points(3))
	var first: Array[OmniLight3D] = _pool.lights()
	_pool.place(_points(1))
	var second: Array[OmniLight3D] = _pool.lights()
	assert_eq(second, first, "the same nodes")
	assert_eq(_pool.get_child_count(), 3)
	assert_true(second[0].visible)
	assert_false(second[1].visible)
	assert_false(second[2].visible)
	assert_eq(_pool.shown_count(), 1)
	_pool.place(_points(3))
	assert_eq(_pool.lights(), first)
	assert_eq(_pool.shown_count(), 3)
	_pool.hide_all()
	assert_eq(_pool.shown_count(), 0)
	assert_eq(_pool.get_child_count(), 3)


func test_the_pool_is_capped() -> void:
	assert_eq(_pool.place(_points(GlowLightPool.MAX_LIGHTS + 4)), GlowLightPool.MAX_LIGHTS)
	assert_eq(_pool.get_child_count(), GlowLightPool.MAX_LIGHTS)
	assert_eq(_pool.shown_count(), GlowLightPool.MAX_LIGHTS)

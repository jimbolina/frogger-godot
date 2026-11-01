extends GutTest
## Glow lights take the halo's colour, pulse with it and are chosen nearest the camera in a stable order.


func _point(at: Vector3) -> GlowLightSpec.Point:
	return GlowLightSpec.Point.new(at, Color.WHITE, 1.0, 1.0)


func test_bgr_glow_colours_convert_to_sprite_and_light_colours() -> void:
	var colour: Color = GlowLightSpec.colour_of(0x508410)
	assert_eq(colour, Color(0x10 / 255.0, 0x84 / 255.0, 0x50 / 255.0))
	assert_eq(GlowLightSpec.light_colour(colour), Color(0x20 / 255.0, 1.0, 0xa0 / 255.0), "doubled and clamped like the halo")


func test_energy_follows_the_pulse_between_its_extremes() -> void:
	var largest: int = GlowPulse.magnitude(GlowLightSpec.PEAK_ANGLE)
	var smallest: int = GlowPulse.magnitude(0xc00)
	for age: int in 16:
		var magnitude: int = GlowPulse.magnitude(GlowPulse.angle_after(age))
		assert_between(magnitude, smallest, largest)
	assert_eq(GlowLightSpec.energy_ratio(largest), 1.0)
	assert_almost_eq(GlowLightSpec.energy_ratio(smallest), float(GlowPulse.BASE - 4096) / float(GlowPulse.BASE + 4096), 0.000001)
	var point: GlowLightSpec.Point = GlowLightSpec.point(Vector3(1, 2, 3), Color(0.25, 0.5, 0.75), largest)
	assert_eq(point.position, Vector3(1, 2, 3) + Vector3.UP * GlowLightSpec.LIFT)
	assert_eq(point.colour, Color(0.5, 1.0, 1.0))
	assert_eq(point.energy, GlowLightSpec.ENERGY)
	assert_eq(point.radius, GlowLightSpec.RANGE_SQUARES)
	assert_lt(GlowLightSpec.point(Vector3.ZERO, Color.WHITE, smallest).energy, point.energy)


func test_nearest_caps_and_orders_by_distance_with_a_stable_tie_break() -> void:
	var far: GlowLightSpec.Point = _point(Vector3(10, 0, 0))
	var left: GlowLightSpec.Point = _point(Vector3(-2, 0, 0))
	var right: GlowLightSpec.Point = _point(Vector3(2, 0, 0))
	var near: GlowLightSpec.Point = _point(Vector3(0, 1, 0))
	var points: Array[GlowLightSpec.Point] = [far, left, right, near]
	var chosen: Array[GlowLightSpec.Point] = GlowLightSpec.nearest(points, Vector3.ZERO, 3)
	assert_eq(chosen.size(), 3)
	assert_same(chosen[0], near)
	assert_same(chosen[1], left, "equal distances keep their supplied order")
	assert_same(chosen[2], right)
	var swapped: Array[GlowLightSpec.Point] = [far, right, left, near]
	assert_same(GlowLightSpec.nearest(swapped, Vector3.ZERO, 3)[1], right)
	assert_eq(GlowLightSpec.nearest(points, Vector3.ZERO, 10).size(), 4)
	assert_eq(GlowLightSpec.nearest(points, Vector3.ZERO, 0).size(), 0)
	var unchanged: Array[GlowLightSpec.Point] = [far, left, right, near]
	assert_eq(points, unchanged, "the input is untouched")

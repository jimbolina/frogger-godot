extends GutTest
## The cave omni light's window, ramp, radii and both modes' ranges and energies.

func _initial(radius: int) -> PackedInt64Array:
	return MapLighting.initial_cave_radii(radius)

func test_window_is_one_at_the_light_and_zero_at_the_range() -> void:
	assert_eq(CaveLightShape.window(0.0, 3.0), 1.0)
	assert_eq(CaveLightShape.window(3.0, 3.0), 0.0)
	assert_eq(CaveLightShape.window(4.0, 3.0), 0.0)
	assert_eq(CaveLightShape.window(1.0, 0.0), 0.0, "no range lights nothing")
	assert_almost_eq(CaveLightShape.window(1.5, 3.0), pow(1.0 - pow(0.5, 4.0), 2.0), 1e-9)

func test_window_falls_monotonically() -> void:
	var previous: float = 2.0
	for step: int in 101:
		var value: float = CaveLightShape.window(step * 0.05, 5.0)
		assert_true(value <= previous, "window at %s" % [step * 0.05])
		previous = value

func test_ramp_follows_the_doubled_cave_grey() -> void:
	assert_eq(CaveLightShape.ramp(0, 100, 1000), 1.0, "grey 128 doubles past one and clamps")
	assert_eq(CaveLightShape.ramp(1001, 100, 1000), 0.0)
	var grey: int = MapLighting.cave_intensity(550, 100, 1000)
	assert_almost_eq(CaveLightShape.ramp(550, 100, 1000), 2.0 * grey / 255.0, 1e-9)

func test_inner_and_edge_are_the_square_roots_in_squares() -> void:
	var radii: PackedInt64Array = _initial(5)
	assert_almost_eq(CaveLightShape.inner_of(radii[0]), 3.0, 1e-9, "five squares less the band leaves three")
	assert_almost_eq(CaveLightShape.edge_of(radii[1]), 5.0, 1e-9)
	assert_eq(CaveLightShape.inner_of(0), 0.0)

func test_band_minimum_matches_the_initial_radii() -> void:
	for radius: int in [1, 3, 4, 5, 8, 255]:
		var radii: PackedInt64Array = _initial(radius)
		assert_eq(CaveLightShape.band_minimum(radii[1]), radii[0], "radius %d" % radius)

func test_exact_edge_ends_the_light_where_the_ramp_ends() -> void:
	for radius: int in [1, 4, 8, 12]:
		var radii: PackedInt64Array = _initial(radius)
		assert_almost_eq(CaveLightShape.range_of(radii[1], CaveLightShape.Mode.EXACT_EDGE), float(radius), 1e-9)

func test_exact_edge_energies_lie_in_the_planned_bands() -> void:
	for radius: int in [1, 3, 4]:
		var small: PackedInt64Array = _initial(radius)
		var energy: float = CaveLightShape.energy_of(small[0], small[1], CaveLightShape.Mode.EXACT_EDGE)
		assert_between(energy, 0.85, 0.95, "radius %d" % radius)
	for radius: int in [8, 12, 255]:
		var large: PackedInt64Array = _initial(radius)
		var energy: float = CaveLightShape.energy_of(large[0], large[1], CaveLightShape.Mode.EXACT_EDGE)
		assert_between(energy, 1.25, 1.35, "radius %d" % radius)

func test_fitted_range_reaches_past_the_edge_with_a_flatter_energy() -> void:
	for radius: int in [8, 12, 255]:
		var radii: PackedInt64Array = _initial(radius)
		var scale: float = CaveLightShape.range_of(radii[1], CaveLightShape.Mode.FITTED_RANGE) / float(radius)
		assert_between(scale, 1.18, 1.3, "radius %d scale" % radius)
		var energy: float = CaveLightShape.energy_of(radii[0], radii[1], CaveLightShape.Mode.FITTED_RANGE)
		assert_between(energy, 1.12, 1.2, "radius %d energy" % radius)
	var small: PackedInt64Array = _initial(1)
	assert_gt(CaveLightShape.range_of(small[1], CaveLightShape.Mode.FITTED_RANGE), 1.0)

func test_fit_energy_is_zero_without_light() -> void:
	assert_eq(CaveLightShape.fit_energy(1, 65536, 0.0), 0.0)
	assert_eq(CaveLightShape.energy_of(0, 0, CaveLightShape.Mode.EXACT_EDGE), 0.0)
	assert_eq(CaveLightShape.range_of(0, CaveLightShape.Mode.FITTED_RANGE), 0.0)

func test_default_mode_is_the_exact_edge() -> void:
	assert_eq(CaveLightShape.DEFAULT_MODE, CaveLightShape.Mode.EXACT_EDGE)

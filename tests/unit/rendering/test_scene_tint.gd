extends GutTest
## SceneTint linearises committed colour scales and custom ambients.

const EPSILON: float = 1e-6


func _scale(byte: int) -> float:
	return pow(byte / 128.0, 2.2)


func _ambient(byte: int) -> float:
	return pow(byte / 256.0, 2.2)


func _assert_scale(tint: SceneTint, bytes: Vector3i, label: String) -> void:
	var expected := Vector3(_scale(bytes.x), _scale(bytes.y), _scale(bytes.z))
	assert_true(tint.scale.distance_to(expected) <= EPSILON, "%s scale %s against %s" % [label, tint.scale, expected])


func _assert_ambient(tint: SceneTint, bytes: Vector3i, label: String) -> void:
	assert_almost_eq(tint.ambient.r, _ambient(bytes.x), EPSILON, label + " red")
	assert_almost_eq(tint.ambient.g, _ambient(bytes.y), EPSILON, label + " green")
	assert_almost_eq(tint.ambient.b, _ambient(bytes.z), EPSILON, label + " blue")
	assert_eq(tint.ambient.a, 1.0, label + " alpha")


func test_unmodulated_tint_is_neutral() -> void:
	var tint: SceneTint = SceneTint.of(Vector3i(24, 0, 0), Vector3i(64, 64, 64), false, false)
	assert_eq(tint.scale, Vector3.ONE)
	assert_eq(tint.ambient, Color(0, 0, 0, 0))
	var neutral: SceneTint = SceneTint.of(Vector3i(128, 128, 128), Vector3i.ZERO, true, false)
	assert_true(neutral.scale.is_equal_approx(Vector3.ONE))
	assert_eq(neutral.ambient.a, 0.0)


func test_frog_edge_fade_scales_grey() -> void:
	for grey: int in [128, 96, 40, 0]:
		var tint: SceneTint = SceneTint.of(Vector3i(grey, grey, grey), Vector3i.ZERO, true, false)
		_assert_scale(tint, Vector3i(grey, grey, grey), "edge fade %d" % grey)
		assert_eq(tint.ambient.a, 0.0)


func test_frog_drowning_uses_water_ambient() -> void:
	var scale: Vector3i = FrogTint.drowning_scale(-64, 0)
	var tint: SceneTint = SceneTint.of(scale, FrogTint.DROWN_AMBIENT, true, true)
	_assert_scale(tint, scale, "drowning")
	_assert_ambient(tint, Vector3i(32, 64, 64), "drowning")


func test_volcano_char_scales_and_replaces_ambient() -> void:
	var tint: SceneTint = SceneTint.of(Vector3i(24, 0, 0), Vector3i(24, 0, 0), true, true)
	_assert_scale(tint, Vector3i(24, 0, 0), "char")
	_assert_ambient(tint, Vector3i(24, 0, 0), "char")


func test_reset_header_ambient_is_unscaled() -> void:
	var tint: SceneTint = SceneTint.of(Vector3i(128, 128, 128), Vector3i(160, 144, 128), false, true)
	assert_eq(tint.scale, Vector3.ONE)
	_assert_ambient(tint, Vector3i(160, 144, 128), "reset")


func test_cave_fade_scales_grey() -> void:
	var tint: SceneTint = SceneTint.of(Vector3i(72, 72, 72), Vector3i.ZERO, true, false)
	_assert_scale(tint, Vector3i(72, 72, 72), "cave")


func test_turtle_and_beaver_dives_use_blue_ambient() -> void:
	for scale: Vector3i in [Vector3i(110, 136, 146), Vector3i(176, 104, 32)]:
		var tint: SceneTint = SceneTint.of(scale, Vector3i(64, 64, 192), true, true)
		_assert_scale(tint, scale, "dive %s" % scale)
		_assert_ambient(tint, Vector3i(64, 64, 192), "dive")


func test_swamp_rat_ambients() -> void:
	for ambient: Vector3i in [Vector3i(255, 255, 255), Vector3i(255, 0, 255)]:
		var tint: SceneTint = SceneTint.of(Vector3i.ZERO, ambient, false, true)
		assert_eq(tint.scale, Vector3.ONE)
		_assert_ambient(tint, ambient, "rat %s" % ambient)


func test_checkpoint_ambient() -> void:
	_assert_ambient(SceneTint.of(Vector3i.ZERO, Vector3i(160, 160, 160), false, true), Vector3i(160, 160, 160), "checkpoint")


func test_desert_crack_scale_exceeds_one_unclamped() -> void:
	var tint: SceneTint = SceneTint.of(Vector3i(176, 176, 176), Vector3i.ZERO, true, false)
	_assert_scale(tint, Vector3i(176, 176, 176), "crack")
	assert_gt(tint.scale.x, 1.0)

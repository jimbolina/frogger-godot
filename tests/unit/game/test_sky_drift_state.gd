extends GutTest
## Frozen UpdateSkyLand drift arithmetic and its shared MRrand draws.

func test_selection_tick_draws_x_then_z_and_normalises_without_moving() -> void:
	var drift := SkyDriftState.new()
	var random: SourceRandom = SourceRandom.create(12345)
	random.begin_tick()
	drift.step(256, random)
	var expected: Array[String] = ["sky:drift_x", "sky:drift_z"]
	assert_eq(random.consumers, expected)
	assert_eq(random.state, 2802067423)
	assert_eq(drift.acceleration, Vector3i(25824, 0, 20176), "normalise(988, 0, 772) << 3")
	assert_eq(drift.velocity, Vector3i.ZERO)
	assert_eq(drift.position, Vector3i.ZERO)

func test_three_ticks_from_a_known_seed_follow_mrrand() -> void:
	var drift := SkyDriftState.new()
	var random: SourceRandom = SourceRandom.create(12345)
	for timer: int in 3:
		drift.step(timer, random)
	assert_eq(random.draw_count, 2)
	assert_eq(drift.velocity, Vector3i(51648, 0, 40352))
	assert_eq(drift.position, Vector3i(77472, 0, 60528))
	assert_eq(drift.translation(), Vector3i(1, 0, 0))

func test_low_phase_accelerates_and_high_phase_decays() -> void:
	var drift := SkyDriftState.new()
	var random: SourceRandom = SourceRandom.create(1)
	drift.acceleration = Vector3i(8, 0, -16)
	drift.velocity = Vector3i(100, 0, -1000)
	drift.step(0x15f, random)
	assert_eq(drift.velocity, Vector3i(108, 0, -1016))
	assert_eq(drift.position, Vector3i(108, 0, -1016))
	drift.velocity = Vector3i(100, 0, -1000)
	drift.step(0x160, random)
	assert_eq(drift.velocity, Vector3i(93, 0, -992), "(v >> 5) * 31 with an arithmetic shift")
	assert_eq(drift.position, Vector3i(201, 0, -2008))
	assert_eq(random.draw_count, 0)

func test_position_clamps_x_and_z_only() -> void:
	var drift := SkyDriftState.new()
	drift.position = Vector3i(SkyDriftState.MAX_POSITION - 4, SkyDriftState.MAX_POSITION - 4, -SkyDriftState.MAX_POSITION + 4)
	drift.velocity = Vector3i(64, 64, -64)
	drift.step(0x160, SourceRandom.create(1))
	assert_eq(drift.velocity, Vector3i(62, 62, -62))
	assert_eq(drift.position, Vector3i(SkyDriftState.MAX_POSITION, SkyDriftState.MAX_POSITION + 58, -SkyDriftState.MAX_POSITION))

func test_far_drift_pulls_back_without_drawing() -> void:
	var drift := SkyDriftState.new()
	var random: SourceRandom = SourceRandom.create(7)
	drift.position = Vector3i((SkyDriftState.MAX_DRIFT + 1) << 16, 0, 0)
	drift.step(0x80, random)
	assert_eq(random.draw_count, 0)
	assert_eq(drift.acceleration, Vector3i(-4096 * 8, 0, 0))
	drift.position = Vector3i(3 << 16, 0, -((SkyDriftState.MAX_DRIFT + 1) << 16))
	drift.step(0x80, random)
	assert_eq(random.draw_count, 0)
	assert_eq(drift.acceleration, EntityTransform._normalise(Vector3i(-3, 0, SkyDriftState.MAX_DRIFT + 1)) * 8)
	drift.position = Vector3i(SkyDriftState.MAX_DRIFT << 16, 0, 0)
	drift.step(0x80, random)
	assert_eq(random.draw_count, 2, "the bound itself still draws")

func test_clear_translation_and_copy() -> void:
	var drift := SkyDriftState.new()
	drift.position = Vector3i(-1, 0x1ffff, -0x10000)
	drift.velocity = Vector3i(1, 2, 3)
	drift.acceleration = Vector3i(4, 5, 6)
	assert_eq(drift.translation(), Vector3i(-1, 1, -1))
	var duplicate: SkyDriftState = drift.copy()
	drift.clear()
	assert_eq(drift.position, Vector3i.ZERO)
	assert_eq(drift.velocity, Vector3i.ZERO)
	assert_eq(drift.acceleration, Vector3i.ZERO)
	assert_eq(duplicate.velocity, Vector3i(1, 2, 3))

extends GutTest
## Presentation particle buffers step headless, repeat for one seed and follow the frog generator rules.

var _at := PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 256, -64, 512])

func _record(generator_name: String) -> ParticleGeneratorRecord:
	return ExeParticleGenerators.c_constants().find(generator_name)

func _field(kind: ParticleField.Kind, generator_name: String, seed: int = 7) -> ParticleField:
	return ParticleField.new(kind, _record(generator_name), ParticleField.KILL_WHEN_FROG_RESET, seed)

func _positions(field: ParticleField) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for index: int in field.live_indices():
		result.append(field.particles[index].position_16)
	return result

func test_slide_adds_only_while_the_owner_moves_and_lives_twelve_ticks() -> void:
	var field: ParticleField = _field(ParticleField.Kind.FROG_SLIDE, "PGIN_frog_slip_effect")
	assert_eq(field.max_particles, 50)
	for _tick: int in 20:
		field.step(_at, false)
	assert_eq(field.live_indices().size(), 0, "a still frog adds nothing")
	for _tick: int in 40:
		field.step(_at, true)
	var live: PackedInt32Array = field.live_indices()
	assert_gt(live.size(), 0)
	assert_lte(live.size(), 12, "at most one particle per tick for its twelve-tick life")
	for index: int in live:
		var particle: ParticleField.Particle = field.particles[index]
		assert_between(particle.lifetime, 0, 11)
		assert_eq(field.colour(index), Vector3i.ONE * mini(particle.lifetime << 2, 255))
		assert_eq(field.extent(index, 16), 16 * (96 << 10))
	for _tick: int in 12:
		field.step(_at, false)
	assert_eq(field.live_indices().size(), 0, "particles expire")
	assert_false(field.finished, "the slip generator is infinite")

func test_same_seed_repeats_and_another_seed_differs() -> void:
	var first: ParticleField = _field(ParticleField.Kind.FROG_SLIDE, "PGIN_frog_slip_effect", 11)
	var second: ParticleField = _field(ParticleField.Kind.FROG_SLIDE, "PGIN_frog_slip_effect", 11)
	var other: ParticleField = _field(ParticleField.Kind.FROG_SLIDE, "PGIN_frog_slip_effect", 12)
	for _tick: int in 30:
		first.step(_at, true)
		second.step(_at, true)
		other.step(_at, true)
	assert_eq(_positions(first), _positions(second))
	assert_ne(_positions(first), _positions(other))

func test_slide_particles_rise_under_negative_gravity_and_interpolate() -> void:
	var field: ParticleField = _field(ParticleField.Kind.FROG_SLIDE, "PGIN_frog_slip_effect")
	while field.live_indices().is_empty():
		field.step(_at, true)
	var index: int = field.live_indices()[0]
	var particle: ParticleField.Particle = field.particles[index]
	var velocity: int = particle.velocity_16.y
	field.step(_at, false)
	assert_eq(particle.velocity_16.y, velocity - 65536, "gravity -1 in 16.16 after moving")
	assert_eq(field.position(index, 0.0), Vector3(particle.previous_16) / 65536.0)
	assert_eq(field.position(index, 1.0), Vector3(particle.position_16) / 65536.0)

func test_bubbles_shrink_every_ten_ticks_close_at_ninety_and_finish() -> void:
	var field: ParticleField = _field(ParticleField.Kind.FROG_BUBBLE, "PGIN_frog_water_bubble")
	field.step(_at, false)
	assert_eq(field.max_particles, 19, "the first update lowers the ring at life 90")
	assert_eq(field.live_indices().size(), 1)
	assert_eq(field.particles[field.live_indices()[0]].previous_16, Vector3i(256 << 16, -(64 << 16), 512 << 16), "bubbles start at the owner origin")
	var closed_at: int = -1
	var finished_at: int = -1
	for tick: int in range(2, 200):
		field.step(_at, false)
		if field.closing and closed_at < 0:
			closed_at = tick
		if field.finished:
			finished_at = tick
			break
	assert_eq(closed_at, 90)
	assert_gt(finished_at, 90)
	assert_lt(finished_at, 120)
	assert_eq(field.max_particles, 0)
	assert_eq(field.live_indices().size(), 0)

func test_fire_colour_and_size_follow_the_user_value() -> void:
	var field: ParticleField = _field(ParticleField.Kind.FROG_FIRE, "PGIN_frog_on_fire")
	while field.live_indices().is_empty():
		field.step(_at, false)
	var index: int = field.live_indices()[0]
	var particle: ParticleField.Particle = field.particles[index]
	assert_true(particle.user in [50 - 4, 82 - 4], "max life plus rand & 32, less one frame")
	var user: int = particle.user
	assert_eq(field.colour(index), Vector3i(255, mini(255, user), 0))
	assert_eq(field.extent(index, 16), (16 * (120 << 9) * user) >> 4)
	assert_eq(particle.velocity_16.x, 0)
	assert_eq(particle.velocity_16.z, 0)
	field.step(_at, false)
	assert_eq(particle.user, user - 4)

func test_killed_or_missing_generators_draw_nothing() -> void:
	var field: ParticleField = _field(ParticleField.Kind.FROG_SLIDE, "PGIN_frog_slip_effect")
	for _tick: int in 10:
		field.step(_at, true)
	field.kill()
	assert_true(field.finished)
	assert_eq(field.live_indices().size(), 0)
	var missing := ParticleField.new(ParticleField.Kind.FROG_FIRE, null)
	assert_true(missing.finished)
	missing.step(_at, true)
	assert_eq(missing.ticks, 0)

func _hilite(kind: ParticleField.Kind, generator_name: String, seed: int = 7) -> ParticleField:
	return ParticleField.new(kind, _record(generator_name), 0, seed)

func test_exhaust_gates_adds_rises_and_clamps_to_the_owner_colour_scale() -> void:
	var field: ParticleField = _hilite(ParticleField.Kind.HILITE_EXHAUST, "PGIN_hilite_exhaust")
	assert_eq(field.max_particles, 25)
	assert_eq(field.ot_offset(), 0x10, "HILITE_EXHAUST_OT_OFFSET sorts further")
	assert_false(field.clamps_near())
	var adds: int = 0
	for _tick: int in 64:
		var before: int = field.next_particle
		field.step(_at, false)
		adds += 1 if field.next_particle != before else 0
		assert_lte(field.live_indices().size(), 8, "eight-tick lives, at most one add per tick")
	assert_between(adds, 1, 63, "the add is gated by the seeded random draw")
	var added: bool = false
	while not added:
		var previous: int = field.next_particle
		field.step(_at, false, Vector3i(40, 255, 0))
		added = field.next_particle != previous
	var index: int = (field.next_particle + field.max_particles - 1) % field.max_particles
	var particle: ParticleField.Particle = field.particles[index]
	assert_eq(particle.lifetime, 7)
	assert_eq(particle.user, 0)
	assert_eq(particle.previous_16, Vector3i(256 << 16, -(64 << 16), 512 << 16), "exhaust starts at the owner translation")
	assert_eq(particle.velocity_16.z, -(0x10 << 16))
	assert_between(particle.velocity_16.x >> 16, -8, 7)
	assert_eq(field.colour(index), Vector3i(40, 112, 0), "min(life << 4, 255) clamped per channel")
	assert_eq(field.extent(index, 16), 16 * (64 << 9))
	var velocity: int = particle.velocity_16.y
	field.step(_at, false)
	assert_eq(particle.velocity_16.y, velocity - 65536, "gravity after moving")
	assert_eq(field.colour_scale, ParticleField.DEFAULT_COLOUR_SCALE)
	assert_eq(field.colour(index), Vector3i(96, 96, 96))

func test_exhaust_velocity_follows_the_owner_rotation() -> void:
	var turned := PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 0, 0, 0])
	var field: ParticleField = _hilite(ParticleField.Kind.HILITE_EXHAUST, "PGIN_hilite_exhaust", 3)
	while field.live_indices().is_empty():
		field.step(turned, false)
	var particle: ParticleField.Particle = field.particles[field.live_indices()[0]]
	assert_eq(particle.velocity_16.x, -(0x10 << 16), "the -0x10 Z push turns with the owner")

func test_dust_steps_through_its_texture_list_and_dies_at_the_end() -> void:
	var field: ParticleField = _hilite(ParticleField.Kind.HILITE_DUST, "PGIN_hilite_dust")
	assert_eq(field.max_particles, 14)
	assert_eq(field.image_count, 6)
	assert_eq(field.ot_offset(), ParticleField.OT_OFFSET, "Hilite_dust_disp uses FROG_EFFECT_SLIP_OT_OFFSET")
	while field.next_particle == 0:
		field.step(_at, false)
	var particle: ParticleField.Particle = field.particles[0]
	assert_eq(particle.lifetime, 11)
	assert_eq(field.image_index(0), 0)
	assert_eq(field.colour(0), Vector3i(176, 176, 176))
	assert_eq(field.extent(0, 16), 16 * (64 << 11))
	for image: int in range(1, 6):
		field.step(_at, false)
		assert_eq(field.image_index(0), image)
		assert_eq(particle.lifetime, 11 - image)
	field.step(_at, false)
	assert_eq(particle.lifetime, 0, "the list's NULL terminator ends the particle")
	assert_false(field.live_indices().has(0))

func test_hilite_fire_adds_every_tick_without_gravity_and_colours_by_user() -> void:
	var turned := PackedInt32Array([0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 256, -64, 512])
	var field: ParticleField = _hilite(ParticleField.Kind.HILITE_FIRE, "PGIN_hilite_fire")
	assert_eq(field.max_particles, 40)
	assert_eq(field.ot_offset(), ParticleField.OT_OFFSET)
	assert_true(field.clamps_near())
	for tick: int in 5:
		field.step(turned, false)
		assert_eq(field.live_indices().size(), tick + 1, "one particle every move")
	var particle: ParticleField.Particle = field.particles[4]
	assert_eq(particle.lifetime, 19)
	assert_between(particle.user, 20 - 1, 20 + 0x1f - 1, "max life plus rand & 0x1f, less one move")
	assert_eq(particle.previous_16, Vector3i(156 << 16, -(64 << 16), 512 << 16), "the owner translation plus the turned (0, 0, -100)")
	for axis: int in 3:
		assert_between(particle.velocity_16[axis] >> 16, -8, 7)
	assert_eq(field.colour(4), Vector3i(255, mini(255, particle.user << 1), 0))
	assert_eq(field.extent(4, 16), (16 * (70 << 10) * particle.user) >> 4)
	var user: int = particle.user
	var velocity: Vector3i = particle.velocity_16
	field.step(turned, false)
	assert_eq(particle.user, user - 1)
	assert_eq(particle.velocity_16, velocity, "no gravity")
	for _tick: int in 18:
		field.step(turned, false)
	assert_eq(particle.lifetime, 0, "twenty-tick life")

func test_hilite_kinds_repeat_for_one_seed() -> void:
	for kind: ParticleField.Kind in [ParticleField.Kind.HILITE_EXHAUST, ParticleField.Kind.HILITE_DUST, ParticleField.Kind.HILITE_FIRE]:
		var generator_name: String = ["PGIN_hilite_exhaust", "PGIN_hilite_dust", "PGIN_hilite_fire"][kind - ParticleField.Kind.HILITE_EXHAUST]
		var first: ParticleField = _hilite(kind, generator_name, 21)
		var second: ParticleField = _hilite(kind, generator_name, 21)
		var other: ParticleField = _hilite(kind, generator_name, 22)
		for _tick: int in 20:
			first.step(_at, true)
			second.step(_at, true)
			other.step(_at, true)
		assert_eq(_positions(first), _positions(second), generator_name)
		assert_ne(_positions(first), _positions(other), generator_name)

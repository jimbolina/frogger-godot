class_name ParticleField
extends RefCounted
## A presentation particle buffer for one generator record, stepped once per committed tick.
##
## The add and move rules follow the frog generators of PARTICLE.C: the slip
## (FrogEffectSlippingAdd/Move, 1594-1686), the water bubble
## (FrogEffectBubbleAdd/Move, 1706-1866) and the on-fire generator
## (FrogEffectFireAdd/Move, 1752-1949). A seeded [RandomNumberGenerator]
## stands in for the source's shared rand() draws, so the particle stream is
## repeatable for one seed but never the original's. Particles live in a ring
## of [member max_particles] entries; positions and velocities are 16.16 and
## gravity is added to Y velocity after moving where the generator applies it.
## Display rules come from FrogEffectSlippingDisp (grey min(life << 2, 255),
## size from user data 1) and FrogEffectFireDisp (colour (255, user, 0),
## size from user data 1 times the particle's user value >> 4, the user value
## falling by 4 per drawn frame, applied here once per tick). A field never
## reads or changes gameplay state.

## Particle kinds by the generator behaviour they follow; the frog kinds use
## the Frog_particle_effects order.
enum Kind { FROG_SLIDE, FROG_BUBBLE, FROG_FIRE }

## Source EFFECT_KILL_WHEN_FROG_DEAD and EFFECT_KILL_WHEN_FROG_RESET.
const KILL_WHEN_FROG_DEAD: int = 1 << 8
const KILL_WHEN_FROG_RESET: int = 1 << 9
## Source FROG_EFFECT_SLIP_OT_OFFSET and FROG_EFFECT_PARTICLE_DISPLAY_MAX_HALFWIDTH.
const OT_OFFSET: int = -0x10
const MAX_HALF_WIDTH: int = 0x60
## Per-frame fall of a fire particle's user value.
const FIRE_USER_STEP: int = 4
## Bubble generator ticks between max_particles reductions.
const BUBBLE_SHRINK_PERIOD: int = 10
## Source rand() range.
const RAND_MASK: int = 0x7fff

## One particle in 16.16 world units.
class Particle extends RefCounted:
	var lifetime: int = 0
	var position_16 := Vector3i.ZERO
	var previous_16 := Vector3i.ZERO
	var velocity_16 := Vector3i.ZERO
	var user: int = 0

var kind: Kind = Kind.FROG_SLIDE
var generator_name: String = ""
## Particles the move and display loops visit; the bubble generator lowers it.
var max_particles: int = 0
## Remaining generator life; -1 is infinite.
var generator_life: int = -1
var particle_max_life: int = 0
var gravity_16: int = 0
## Source pg_user_data_1 size scale.
var scale: int = 0
## Frog_particle_effects kill flags.
var kill_flags: int = 0
var next_particle: int = 0
var particles: Array[Particle] = []
## Source MR_PF_CLOSING_DOWN: the generator life ran out.
var closing: bool = false
## The generator is destroyed: by its own life, or killed by its owner.
var finished: bool = false
## Committed ticks stepped so far.
var ticks: int = 0
var _random := RandomNumberGenerator.new()


func _init(field_kind: Kind = Kind.FROG_SLIDE, record: ParticleGeneratorRecord = null, flags: int = 0, seed: int = 0) -> void:
	kind = field_kind
	kill_flags = flags
	_random.seed = seed
	if record == null:
		finished = true
		return
	generator_name = record.name
	max_particles = record.max_particles
	generator_life = record.generator_life
	particle_max_life = record.particle_max_life
	gravity_16 = record.gravity_16
	scale = record.user_data_1
	for _index: int in record.max_particles:
		particles.append(Particle.new())


## Runs the generator's move callback once with the owner frame
## [param owner_matrix12]; [param owner_moving] is the slip's non-zero frog
## velocity test.
func step(owner_matrix12: PackedInt32Array, owner_moving: bool) -> void:
	if finished:
		return
	ticks += 1
	match kind:
		Kind.FROG_SLIDE:
			if _rand() & 1 and owner_moving:
				_add_slide(owner_matrix12)
			_move(true)
		Kind.FROG_BUBBLE:
			if generator_life % BUBBLE_SHRINK_PERIOD == 0:
				max_particles = maxi(0, max_particles - 1)
			_add_bubble(owner_matrix12)
			var active: bool = _move(false)
			if generator_life > 0:
				generator_life -= 1
				closing = closing or generator_life == 0
			elif generator_life == 0 and not active:
				finished = true
		Kind.FROG_FIRE:
			if _rand() & 1:
				_add_fire(owner_matrix12)
			_move(false)
			for index: int in max_particles:
				var particle: Particle = particles[index]
				if particle.lifetime != 0:
					particle.user = particle.user - FIRE_USER_STEP if particle.user > 2 else 0


## Destroys the generator at once, as FROG_KILL_PARTICLE_EFFECT does.
func kill() -> void:
	finished = true


## Indices of the particles the display loop draws.
func live_indices() -> PackedInt32Array:
	var result := PackedInt32Array()
	if finished:
		return result
	for index: int in mini(max_particles, particles.size()):
		if particles[index].lifetime != 0:
			result.append(index)
	return result


## Interpolated world position of particle [param index] in game units.
func position(index: int, fraction: float) -> Vector3:
	var particle: Particle = particles[index]
	var before := Vector3(particle.previous_16) / 65536.0
	var now := Vector3(particle.position_16) / 65536.0
	return before.lerp(now, clampf(fraction, 0.0, 1.0))


## The display numerator for an image extent of [param size] texels: the
## source xcalc/ycalc before the division by view depth.
func extent(index: int, size: int) -> int:
	if kind == Kind.FROG_FIRE:
		return (size * scale * particles[index].user) >> 4
	return size * scale


## Polygon colour bytes of particle [param index].
func colour(index: int) -> Vector3i:
	var particle: Particle = particles[index]
	if kind == Kind.FROG_FIRE:
		return Vector3i(255, mini(255, particle.user), 0)
	var grey: int = mini(particle.lifetime << 2, 255)
	return Vector3i(grey, grey, grey)


func _move(gravity: bool) -> bool:
	var active: bool = false
	for index: int in max_particles:
		var particle: Particle = particles[index]
		if particle.lifetime == 0:
			continue
		active = true
		particle.lifetime -= 1
		particle.previous_16 = particle.position_16
		particle.position_16 = _s32(particle.position_16 + particle.velocity_16)
		if gravity:
			particle.velocity_16.y = PlatformMath.s32(particle.velocity_16.y + gravity_16)
	return active


func _next(wrap_at_or_above: bool) -> Particle:
	var particle: Particle = particles[next_particle]
	next_particle += 1
	if next_particle == max_particles or (wrap_at_or_above and next_particle >= max_particles):
		next_particle = 0
	particle.lifetime = particle_max_life
	return particle


func _add_slide(matrix12: PackedInt32Array) -> void:
	var particle: Particle = _next(false)
	var vx: int = (_rand() & 0x7) - 4
	var vz: int = -(_rand() & 0x7) - 4
	var velocity: Vector3i = PlatformMath.apply(matrix12, Vector3i(vx, -0xf, vz))
	particle.velocity_16 = _shifted(velocity)
	var offset: Vector3i = PlatformMath.apply(matrix12, Vector3i((_rand() & 0x4f) - 0x28, 0x1f, 0))
	_place(particle, _translation(matrix12) + offset)


func _add_bubble(matrix12: PackedInt32Array) -> void:
	if particles.is_empty():
		return
	var particle: Particle = _next(true)
	var vx: int = (_rand() & 0x16) - 8
	var vz: int = (_rand() & 0x16) - 8
	particle.velocity_16 = _shifted(PlatformMath.apply(matrix12, Vector3i(vx, -0x6, vz)))
	_place(particle, _translation(matrix12))


func _add_fire(matrix12: PackedInt32Array) -> void:
	var particle: Particle = _next(false)
	particle.user = particle_max_life + (_rand() & 32)
	var ox: int = (_rand() & 63) - 32
	var oz: int = (_rand() & 63) - 32
	var offset: Vector3i = PlatformMath.apply(matrix12, Vector3i(ox, -0x10, oz))
	particle.velocity_16 = Vector3i(0, PlatformMath.s32((-(_rand() & 15)) << 15), 0)
	_place(particle, _translation(matrix12) + offset)


func _place(particle: Particle, at: Vector3i) -> void:
	particle.position_16 = _shifted(at)
	particle.previous_16 = particle.position_16


func _rand() -> int:
	return _random.randi() & RAND_MASK


static func _translation(matrix12: PackedInt32Array) -> Vector3i:
	return Vector3i(matrix12[9], matrix12[10], matrix12[11])


static func _shifted(value: Vector3i) -> Vector3i:
	return Vector3i(PlatformMath.s32(value.x << 16), PlatformMath.s32(value.y << 16), PlatformMath.s32(value.z << 16))


static func _s32(value: Vector3i) -> Vector3i:
	return Vector3i(PlatformMath.s32(value.x), PlatformMath.s32(value.y), PlatformMath.s32(value.z))

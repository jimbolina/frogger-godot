class_name PopRingGeometry
extends RefCounted
## The death pop ring of PGIN_frog_pop_explosion and Frog_pop_explosion_disp (PARTICLE.C:104, 908-1060).
##
## FrogKill creates the generator with life FROG_POP_EXPLOSION_DURATION;
## Particle_no_geometry_move takes one per update and the ring is drawn while
## the life is non-zero. Each drawn frame scales the octagons by
## ((30 - life) + 10) << 1 and rotates them by Game_timer << 7. Outer
## vertices are (life * 8, 0, 0); inner vertices are life times the player's
## pop colour, red in the low byte. Offsets here are before projection, which
## multiplies them by vp_perspective over SYSTEM_PERSPECTIVE (0x100 / 192).

const DURATION: int = 30
## SYSTEM_PERSPECTIVE, the octagon's fixed view depth.
const SYSTEM_PERSPECTIVE: int = 192
const POINTS: int = 8

## Offsets and colours of one drawn frame.
class Frame extends RefCounted:
	var scale: int = 0
	var angle: int = 0
	var cosine: int = 0
	var sine: int = 0
	var outer: Array[Vector2i] = []
	var inner: Array[Vector2i] = []
	var outer_rgb := Vector3i.ZERO
	var inner_rgb := Vector3i.ZERO

## Remaining generator life; the ring is gone at zero.
var life: int = DURATION
## Player pop colour, red in the low byte.
var colour: int = 0


func _init(pop_colour: int = 0) -> void:
	colour = pop_colour


## Runs one Particle_no_geometry_move.
func step() -> void:
	if life > 0:
		life -= 1


## True while Frog_pop_explosion_disp draws.
func drawn() -> bool:
	return life > 0


## The frame drawn with this life at [param game_timer].
func frame(game_timer: int) -> Frame:
	return frame_for(life, game_timer, colour)


## The frame drawn at [param ring_life] and [param game_timer] with [param pop_colour].
static func frame_for(ring_life: int, game_timer: int, pop_colour: int) -> Frame:
	var result := Frame.new()
	result.scale = PlatformMath.s16(((DURATION - ring_life) + 10) << 1)
	result.angle = (game_timer << 7) & 0xfff
	var cos_table: int = roundi(cos(float(result.angle) * TAU / 4096.0) * 4096.0)
	var sin_table: int = roundi(sin(float(result.angle) * TAU / 4096.0) * 4096.0)
	result.cosine = PlatformMath.s16((cos_table * result.scale) >> 12)
	result.sine = PlatformMath.s16((sin_table * result.scale) >> 12)
	var octagon: PackedInt32Array = ExeParticleGenerators.EXPLOSION_OCTAGON
	for index: int in POINTS * 2:
		var ox: int = octagon[index * 2]
		var oy: int = octagon[index * 2 + 1]
		var point := Vector2i((result.cosine * ox - result.sine * oy) >> 12, (result.sine * ox + result.cosine * oy) >> 12)
		if index < POINTS:
			result.outer.append(point)
		else:
			result.inner.append(point)
	result.outer_rgb = HopTrailState.bytes((ring_life * 8) & 0xffffff)
	result.inner_rgb = HopTrailState.bytes((ring_life * pop_colour) & 0xffffff)
	return result

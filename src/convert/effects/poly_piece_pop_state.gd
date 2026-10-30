class_name PolyPiecePopState
extends RefCounted
## The motion of a poly-piece pop: frozen [code]LiveEntityStartPolyPiecePop[/code]
## (ENTITY.C 3406–3465), [code]UpdatePolyPiecePop[/code] (EFFECTS.C 2015) and
## the transform of [code]RenderPolyPiecePop[/code] (EFFECTS.C 2069–2100).
##
## Starting reads the entity's 12-bit matrix. Each piece starts at
## [code]t + R·origin[/code] in 16.16 units and flies along that rotated
## origin, raised by 0x80 units, normalised and shifted left by 10. Every
## update while the timer runs lowers it by one, adds the angular velocity
## to the shared rotation and the angular acceleration to the angular
## velocity, adds twice [code]WORLD_GRAVITY[/code] to each piece's vertical
## velocity and then the velocity to its position.
##
## Drawing turns a piece's origin-relative corners by
## [code]RotMatrix(rotation) · lwtrans[/code] ([code]MRMulMatrixABA[/code]), scales them by
## [code]min(0x1200, timer << 8)[/code] and moves them to the whole-unit
## position ([code]position >> 16[/code]). [code]RotMatrix[/code] is
## [code]Rx · Ry · Rz[/code]: Z is applied to a vector first, then Y, then X.

## FROG_POLY_PIECE_POP_DURATION.
const DURATION: int = 32
## WORLD_GRAVITY in 16.16 units per tick per tick; the pop adds twice this.
const WORLD_GRAVITY: int = 0x2d800
## POLY_PIECE_POP_ANG_ACC_X, _Y and _Z.
const ANGULAR_ACCELERATION := Vector3i(0x8, 0xC, 0x10)
## Largest drawing scale, 4096 being one.
const MAX_SCALE: int = 0x1200
## Units the start direction is raised by.
const UPWARD_BIAS: int = 0x80
## The source's left shift by 10 from a unit direction to a 16.16 start velocity.
const VELOCITY_SCALE: int = 1 << 10
## One whole unit in 16.16.
const FIXED_ONE: int = 1 << 16

## Updates left; 0 when finished or not started.
var timer: int = 0
## The duration it started with.
var duration: int = 0
## Shared 12-bit rotation angles, signed shorts.
var rotation: Vector3i = Vector3i.ZERO
## Shared angular velocity, signed shorts.
var angular_velocity: Vector3i = Vector3i.ZERO
## Each piece's 16.16 position.
var positions: Array[Vector3i] = []
## Each piece's 16.16 velocity.
var velocities: Array[Vector3i] = []
## The entity matrix: nine 12-bit rotations, then the translation. The source
## keeps a pointer to the entity's matrix, so starting reads it once and
## drawing reads its current value; assign the live matrix before drawing.
var lwtrans: PackedInt32Array = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0])


## Starts the pop from entity matrix [param matrix12] for pieces with model-space [param origins].
func start(matrix12: PackedInt32Array, origins: Array[Vector3i]) -> void:
	lwtrans = matrix12.duplicate()
	timer = DURATION
	duration = DURATION
	rotation = Vector3i.ZERO
	angular_velocity = Vector3i.ZERO
	positions.clear()
	velocities.clear()
	for origin: Vector3i in origins:
		var turned: Vector3i = PlatformMath.apply_fixed(lwtrans, origin)
		positions.append(Vector3i(PlatformMath.s32((lwtrans[9] + turned.x) * FIXED_ONE), PlatformMath.s32((lwtrans[10] + turned.y) * FIXED_ONE),
			PlatformMath.s32((lwtrans[11] + turned.z) * FIXED_ONE)))
		var direction: Vector3i = _normalise(Vector3i(turned.x, PlatformMath.s32(turned.y - UPWARD_BIAS), turned.z))
		velocities.append(Vector3i(PlatformMath.s32(direction.x * VELOCITY_SCALE), PlatformMath.s32(direction.y * VELOCITY_SCALE),
			PlatformMath.s32(direction.z * VELOCITY_SCALE)))


## One source update; does nothing once the timer is 0.
func step() -> void:
	if timer == 0:
		return
	timer -= 1
	rotation = Vector3i(PlatformMath.s16(rotation.x + angular_velocity.x), PlatformMath.s16(rotation.y + angular_velocity.y),
		PlatformMath.s16(rotation.z + angular_velocity.z))
	angular_velocity = Vector3i(PlatformMath.s16(angular_velocity.x + ANGULAR_ACCELERATION.x),
		PlatformMath.s16(angular_velocity.y + ANGULAR_ACCELERATION.y), PlatformMath.s16(angular_velocity.z + ANGULAR_ACCELERATION.z))
	for index: int in positions.size():
		var velocity: Vector3i = velocities[index]
		velocity.y = PlatformMath.s32(velocity.y + WORLD_GRAVITY * 2)
		velocities[index] = velocity
		var position: Vector3i = positions[index]
		positions[index] = Vector3i(PlatformMath.s32(position.x + velocity.x), PlatformMath.s32(position.y + velocity.y),
			PlatformMath.s32(position.z + velocity.z))


## Steps until the timer is no more than [param remaining], such as a snapshot's pop countdown.
func advance_to(remaining: int) -> void:
	while timer > maxi(remaining, 0):
		step()


## Number of pieces in motion.
func piece_count() -> int:
	return positions.size()


## The drawing scale, 4096 being one.
func scale() -> int:
	return mini(MAX_SCALE, timer * 256)


## [code]RotMatrix(rotation) · lwtrans[/code] as a 12-bit game matrix with no translation.
func rotation_matrix() -> PackedInt32Array:
	var turn: PackedInt32Array = PlatformMath.multiply(PlatformMath.multiply(PlatformMath.x_rotation(rotation.x), PlatformMath.yaw(rotation.y)),
		PlatformMath.z_rotation(rotation.z))
	return PlatformMath.multiply(turn, lwtrans)


## The scaled rotation shared by every piece, in Godot space.
func basis() -> Basis:
	return GameSpace.transform(rotation_matrix()).basis * (float(scale()) / GameSpace.NORMAL_ONE)


## Where piece [param piece]'s origin-relative mesh is drawn, in Godot space.
func transform_for(piece: int) -> Transform3D:
	var at: Vector3i = positions[piece]
	return Transform3D(basis(), GameSpace.position(at.x >> 16, at.y >> 16, at.z >> 16))


static func _normalise(value: Vector3i) -> Vector3i:
	var magnitude: float = sqrt(float(value.x) * value.x + float(value.y) * value.y + float(value.z) * value.z)
	if magnitude < 0.000001:
		return Vector3i.ZERO
	return Vector3i(roundi(value.x * 4096.0 / magnitude), roundi(value.y * 4096.0 / magnitude), roundi(value.z * 4096.0 / magnitude))

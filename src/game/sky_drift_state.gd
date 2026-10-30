class_name SkyDriftState
extends RefCounted
## Frozen UpdateSkyLand backdrop drift: signed32 16.16 position, velocity and acceleration.
## Only the Sky theme steps it; InitialiseMap and LevelStart clear it.

const THEME: int = 8
const MAX_DRIFT: int = 0xb00
const MAX_POSITION: int = 0x10000000

var position: Vector3i = Vector3i.ZERO
var velocity: Vector3i = Vector3i.ZERO
var acceleration: Vector3i = Vector3i.ZERO

## Zeroes every vector, as InitialiseMap and LevelStart do.
func clear() -> void:
	position = Vector3i.ZERO
	velocity = Vector3i.ZERO
	acceleration = Vector3i.ZERO

## Runs one UpdateSkyLand with the pre-increment Game_timer. A new acceleration draws
## X then Z from the shared MRrand stream unless the drift is pulled back toward zero.
func step(game_timer: int, random: SourceRandom) -> void:
	var timer: int = game_timer & 0xffffffff
	if not (timer & 0x7f):
		var direction := Vector3i.ZERO
		if absi(position.x >> 16) > MAX_DRIFT or absi(position.z >> 16) > MAX_DRIFT:
			direction = Vector3i(-position.x >> 16, -position.y >> 16, -position.z >> 16)
		else:
			var x: int = random.next_value("sky:drift_x") & 0x3ff
			var z: int = random.next_value("sky:drift_z") & 0x3ff
			direction = Vector3i(x, 0, z)
		acceleration = EntityTransform._normalise(direction) * 8
	elif (timer & 0xff) < 0x60:
		velocity = Vector3i(PlatformMath.s32(velocity.x + acceleration.x), PlatformMath.s32(velocity.y + acceleration.y), PlatformMath.s32(velocity.z + acceleration.z))
	else:
		velocity = Vector3i(PlatformMath.s32((velocity.x >> 5) * 31), PlatformMath.s32((velocity.y >> 5) * 31), PlatformMath.s32((velocity.z >> 5) * 31))
	position = Vector3i(PlatformMath.s32(position.x + velocity.x), PlatformMath.s32(position.y + velocity.y), PlatformMath.s32(position.z + velocity.z))
	position.x = clampi(position.x, -MAX_POSITION, MAX_POSITION)
	position.z = clampi(position.z, -MAX_POSITION, MAX_POSITION)

## Drawn backdrop translation in whole game units, an arithmetic shift of the 16.16 position.
func translation() -> Vector3i:
	return Vector3i(position.x >> 16, position.y >> 16, position.z >> 16)

## Copies the drift vectors.
func copy() -> SkyDriftState:
	var result := SkyDriftState.new()
	result.position = position
	result.velocity = velocity
	result.acceleration = acceleration
	return result

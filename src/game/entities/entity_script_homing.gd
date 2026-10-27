class_name EntityScriptHoming
extends RefCounted
## Frozen HOME_IN_ON_FROG movement and YX orientation from the target column.

## Updates the private live matrix before script deviation and callbacks.
static func apply(matrix: PackedInt32Array, frog_position: Vector3i, frog_mode: int, speed: int, distance_limit: int, literal_limit: int) -> void:
	if frog_mode in [FrogMode.DYING, FrogMode.HIT_CHECKPOINT, FrogMode.CHECKPOINT_COLLECTED]:
		return
	var direction := Vector3i(PlatformMath.s32(frog_position.x - matrix[9]), PlatformMath.s32(frog_position.y - matrix[10]), PlatformMath.s32(frog_position.z - matrix[11]))
	var squared: int = PlatformMath.s32(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
	var distance: int = int(sqrt(float(maxi(squared, 0))))
	if distance >= distance_limit and distance >= literal_limit:
		return
	if distance <= 4:
		matrix[9] = frog_position.x
		matrix[10] = PlatformMath.s32(frog_position.y + 10)
		matrix[11] = frog_position.z
		return
	var z: Vector3i = EntityTransform._normalise(direction)
	for axis: int in 3:
		matrix[axis * 3 + 2] = PlatformMath.s16(z[axis])
	var denominator: int = int(sqrt(float(z.x * z.x + z.z * z.z)))
	if denominator != 0:
		matrix[0] = PlatformMath.s16(PlatformMath.divide(PlatformMath.s32(z.z << 18), denominator) >> 6)
		matrix[1] = PlatformMath.s16(PlatformMath.divide(PlatformMath.s32(-z.x * z.y << 6), denominator) >> 6)
		matrix[3] = 0
		matrix[4] = PlatformMath.s16(denominator)
		matrix[6] = PlatformMath.s16(PlatformMath.divide(PlatformMath.s32(-z.x << 18), denominator) >> 6)
		matrix[7] = PlatformMath.s16(PlatformMath.divide(PlatformMath.s32(-z.y * z.z << 6), denominator) >> 6)
	else:
		matrix[0] = 0
		matrix[1] = -4096 if z.y > 0 else 4096
		matrix[3] = 0
		matrix[4] = 0
		matrix[6] = 4096 if z.y > 0 else -4096
		matrix[7] = 0
	for axis: int in 3:
		matrix[9 + axis] = PlatformMath.s32(matrix[9 + axis] + (PlatformMath.s32(matrix[axis * 3 + 2] * (speed >> 8)) >> 12))

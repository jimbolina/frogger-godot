class_name EntityDistanceSound
extends RefCounted
## Frozen PlaySoundDistance admission shared by scripts and custom behaviors.

## Source closest-distance seed used when no frog is active.
const NO_FROG_MODULUS: int = 9999999

## Whether a sound at the entity position is within the source distance gate for the frog.
static func within(entity_position: Vector3i, frog: GameplayState, distance: int) -> bool:
	var modulus: int = NO_FROG_MODULUS
	if frog != null:
		if frog.frog.mode == FrogMode.HIT_CHECKPOINT or frog.frog.mode == FrogMode.CHECKPOINT_COLLECTED:
			return false
		if frog.flow.phase == LevelFlowState.Phase.GAME_OVER:
			return false
		if frog.frog.flags & FrogFlags.ACTIVE:
			modulus = isqrt(squared(entity_position, Vector3i(frog.frog.matrix12[9], frog.frog.matrix12[10], frog.frog.matrix12[11])))
	return distance > isqrt(modulus)

## Source MR_SQRT(MR_SVEC_MOD(frog - point)) with signed 16-bit point and difference narrowing.
static func root_distance(point: Vector3i, frog_position: Vector3i) -> int:
	return isqrt(isqrt(squared(point, frog_position)))

## Sum of squared signed 16-bit differences between the frog and the narrowed point.
static func squared(point: Vector3i, frog_position: Vector3i) -> int:
	var total: int = 0
	for axis: int in 3:
		var difference: int = _short(frog_position[axis] - _short(point[axis]))
		total += difference * difference
	return total

## Exact integer square root of a non-negative value.
static func isqrt(value: int) -> int:
	var root: int = int(sqrt(float(value)))
	while (root + 1) * (root + 1) <= value:
		root += 1
	while root * root > value:
		root -= 1
	return root

static func _short(value: int) -> int:
	var low: int = value & 65535
	return low - 65536 if low >= 32768 else low

class_name EntityFrogDistance
extends RefCounted
## Frozen DistanceToFrogger from an entity-local point to the single-player frog.

## Source closest-distance seed returned when no frog is active.
const NO_FROG: int = 9999999

## Transforms offset_local by the entity rotation into signed shorts, adds the translation with
## signed-short narrowing, then returns MR_SVEC_MOD of the signed-short frog difference.
## Only FROG_ACTIVE gates the frog, as in the source; a null or inactive frog returns NO_FROG.
static func distance(entity_matrix: PackedInt32Array, offset_local: Vector3i, frog: GameplayState) -> int:
	if frog == null or not frog.frog.flags & FrogFlags.ACTIVE:
		return NO_FROG
	var rotated: Vector3i = PlatformMath.apply(entity_matrix, Vector3i(PlatformMath.s16(offset_local.x), PlatformMath.s16(offset_local.y), PlatformMath.s16(offset_local.z)))
	var point := Vector3i.ZERO
	for axis: int in 3:
		point[axis] = PlatformMath.s16(PlatformMath.s16(rotated[axis]) + entity_matrix[9 + axis])
	var frog_position := Vector3i(frog.frog.matrix12[9], frog.frog.matrix12[10], frog.frog.matrix12[11])
	return mini(NO_FROG, EntityDistanceSound.isqrt(EntityDistanceSound.squared(point, frog_position)))

class_name ForestVisibilityQuery
extends RefCounted
## Frozen VisibilityCollisionCheck's first consumed hit for a single-player hive.

enum Hit { NONE, FROG, ENTITY }

## Samples sixteen-unit ray steps, testing frog before live stump FORM bounds.
static func first_hit(matrix: PackedInt32Array, direction: Vector3i, frog: GameplayState, neighbors: Array[EntitySnapshot], definitions: Array[EntityDefinition], contacts: Array[FormContactDefinition], collision: EntityCollisionDefinition) -> Hit:
	if collision == null or collision.group_size.x <= 0 or collision.group_size.y <= 0:
		return Hit.NONE
	var position := Vector3i(matrix[9], matrix[10], matrix[11])
	var normal: Vector3i = EntityTransform._normalise(direction)
	var increment := Vector3i((normal.x << 4) >> 12, (normal.y << 4) >> 12, (normal.z << 4) >> 12)
	var steps: int = maxi(maxi(absi(direction.x) >> 4, absi(direction.y) >> 4), absi(direction.z) >> 4)
	for _step: int in steps:
		position += increment
		var x: int = PlatformMath.divide(PlatformMath.s32(position.x - collision.group_base.x), collision.group_size.x)
		var z: int = PlatformMath.divide(PlatformMath.s32(position.z - collision.group_base.z), collision.group_size.y)
		if x < 0 or z < 0 or x >= collision.group_dimensions.x or z >= collision.group_dimensions.y:
			return Hit.NONE
		if frog != null and frog.frog.flags & FrogFlags.ACTIVE:
			var delta := Vector3i(frog.frog.matrix12[9], frog.frog.matrix12[10], frog.frog.matrix12[11]) - position
			if PlatformMath.s32(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z) <= 10000:
				return Hit.FROG
		for moving: bool in [true, false]:
			for slot: int in range(neighbors.size() - 1, -1, -1):
				var entity: EntitySnapshot = neighbors[slot]
				var definition: EntityDefinition = definitions[slot]
				if not entity.live or definition.is_group_moving() != moving or definition.form_id not in [9, 13, 14, 35]:
					continue
				var flags: int = entity.effective_flags(definition.flags)
				if flags & EntityDefinition.NO_COLLISION or (moving and flags & EntityDefinition.HIDDEN):
					continue
				var group_matrix: PackedInt32Array = entity.matrix12 if moving else definition.matrix12
				if EntityContactOrder._group_x(collision, group_matrix[9]) != x or EntityContactOrder._group_z(collision, group_matrix[11]) != z:
					continue
				var contact: FormContactDefinition = contacts[slot]
				if not contact.has_form_data:
					continue
				var delta := Vector3i(PlatformMath.s16(position.x - entity.matrix12[9]), PlatformMath.s16(position.y - entity.matrix12[10]), PlatformMath.s16(position.z - entity.matrix12[11]))
				if PlatformMath.s32(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z) >= contact.radius_squared:
					continue
				var local: Vector3i = PlatformMath.apply(PlatformMath.transpose(entity.matrix12), delta)
				if local.x >= contact.offsets.x and local.x <= contact.offsets.x + contact.dimensions.x * 256 and local.z >= contact.offsets.y and local.z <= contact.offsets.y + contact.dimensions.y * 256:
					return Hit.ENTITY
	return Hit.NONE

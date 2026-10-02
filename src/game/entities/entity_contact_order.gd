class_name EntityContactOrder
extends RefCounted
## Source map-group traversal for all attached entity transforms.

## Returns authored entity IDs in the frozen 3x3 group and linked-list order.
static func indices(definition: EntityCollisionDefinition, snapshot: EntityRunSnapshot, point: Vector3i) -> PackedInt32Array:
	var result := PackedInt32Array()
	if definition == null or snapshot == null or not definition.validate().is_empty() or snapshot.entities.size() != definition.entities.size():
		return result
	var frog_x: int = _source_div(_signed32(point.x - definition.group_base.x), definition.group_size.x)
	var frog_z: int = _source_div(_signed32(point.z - definition.group_base.z), definition.group_size.y)
	var xmin: int = maxi(0, frog_x - 1)
	var xmax: int = mini(definition.group_dimensions.x - 1, frog_x + 1)
	var zmin: int = maxi(0, frog_z - 1)
	var zmax: int = mini(definition.group_dimensions.y - 1, frog_z + 1)
	for z: int in range(zmin, zmax + 1):
		for x: int in range(xmin, xmax + 1):
			for index: int in range(definition.entities.size() - 1, -1, -1):
				var entity: EntityDefinition = definition.entities[index]
				var pose: EntitySnapshot = snapshot.entities[index]
				if pose == null or pose.entity_index != entity.entity_index or pose.unique_id != entity.unique_id or pose.matrix12.size() != 12:
					return PackedInt32Array()
				if entity.entity_name != "MOVING" or entity.flags & EntityDefinition.HIDDEN:
					continue
				if _group_x(definition, pose.matrix12[9]) == x and _group_z(definition, pose.matrix12[11]) == z:
					result.append(entity.entity_index)
			for index: int in range(definition.entities.size() - 1, -1, -1):
				var entity: EntityDefinition = definition.entities[index]
				if entity.entity_name != "STATIC" or entity.matrix12.size() != 12:
					continue
				if _group_x(definition, entity.matrix12[9]) == x and _group_z(definition, entity.matrix12[11]) == z:
					result.append(entity.entity_index)
	return result

static func _group_x(definition: EntityCollisionDefinition, coordinate: int) -> int:
	return clampi(_source_div(_signed32(coordinate - definition.group_base.x), definition.group_size.x), 0, definition.group_dimensions.x - 1)

static func _group_z(definition: EntityCollisionDefinition, coordinate: int) -> int:
	return clampi(_source_div(_signed32(coordinate - definition.group_base.z), definition.group_size.y), 0, definition.group_dimensions.y - 1)

static func _source_div(numerator: int, denominator: int) -> int:
	@warning_ignore("integer_division")
	return numerator / denominator

static func _signed32(value: int) -> int:
	var low: int = value & 0xffffffff
	return low - 0x100000000 if low >= 0x80000000 else low

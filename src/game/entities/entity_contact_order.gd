class_name EntityContactOrder
extends RefCounted
## Source map-group traversal for all attached entity transforms.

## Returns authored entity IDs in the frozen 3x3 group and linked-list order.
static func indices(definition: EntityCollisionDefinition, snapshot: EntityRunSnapshot, point: Vector3i) -> PackedInt32Array:
	if definition == null or snapshot == null or not definition.validate().is_empty():
		return PackedInt32Array()
	return _indices_validated(definition, snapshot, point)

# The aggregate owns a validated immutable definition. Classify each pose once,
# then visit buckets in source Z/X, moving-before-static and reverse entity order.
static func _indices_validated(definition: EntityCollisionDefinition, snapshot: EntityRunSnapshot, point: Vector3i) -> PackedInt32Array:
	var result := PackedInt32Array()
	if snapshot.entities.size() != definition.entities.size():
		return result
	var moving: Dictionary[int, PackedInt32Array] = {}
	var fixed: Dictionary[int, PackedInt32Array] = {}
	for index: int in range(definition.entities.size() - 1, -1, -1):
		var entity: EntityDefinition = definition.entities[index]
		var pose: EntitySnapshot = snapshot.entities[index]
		if pose == null or pose.entity_index != entity.entity_index or pose.unique_id != entity.unique_id or pose.matrix12.size() != 12:
			return PackedInt32Array()
		if snapshot.lifecycle_enabled and not pose.live:
			continue
		if _moving(entity):
			if (entity.flags | pose.entity_flags) & EntityDefinition.HIDDEN:
				continue
			var key: int = _group_z(definition, pose.matrix12[11]) * definition.group_dimensions.x + _group_x(definition, pose.matrix12[9])
			if not moving.has(key):
				moving[key] = PackedInt32Array()
			moving[key].append(entity.entity_index)
		elif entity.matrix12.size() == 12:
			var key: int = _group_z(definition, entity.matrix12[11]) * definition.group_dimensions.x + _group_x(definition, entity.matrix12[9])
			if not fixed.has(key):
				fixed[key] = PackedInt32Array()
			fixed[key].append(entity.entity_index)
	var frog_x: int = _source_div(_signed32(point.x - definition.group_base.x), definition.group_size.x)
	var frog_z: int = _source_div(_signed32(point.z - definition.group_base.z), definition.group_size.y)
	for z: int in range(maxi(0, frog_z - 1), mini(definition.group_dimensions.y - 1, frog_z + 1) + 1):
		for x: int in range(maxi(0, frog_x - 1), mini(definition.group_dimensions.x - 1, frog_x + 1) + 1):
			var key: int = z * definition.group_dimensions.x + x
			if moving.has(key):
				result.append_array(moving[key])
			if fixed.has(key):
				result.append_array(fixed[key])
	return result


static func _moving(entity: EntityDefinition) -> bool:
	return entity.entity_name in ["MOVING", "SUB_TURTLE", "ORG_FLY", "ORG_BABY_FROG"]

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

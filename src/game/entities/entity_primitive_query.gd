class_name EntityPrimitiveQuery
extends RefCounted
## Frozen static cuboid narrow phase; sphere admission remains the caller's job.

const CONTACT: String = "contact"
const MISS: String = "miss"
const DISABLED: String = "disabled"
const UNSUPPORTED: String = "unsupported"
const INVALID: String = "invalid"

## First source-ordered frog hilite accepted by the admitted primitive.
class Result:
	extends RefCounted
	var status: String = "invalid"
	var reason: String = ""
	var part_index: int = -1
	var hilite_index: int = -1
	var primitive_part_index: int = -1
	var primitive_index: int = -1
	var reaction: int = -1
	var flags: int = 0
	var world_point: Vector3i = Vector3i.ZERO
	var local_position: Vector3i = Vector3i.ZERO

## Checks all frog parts/hilites in source order, using strict cuboid boundaries.
static func query(primitives: Array[EntityPrimitiveDefinition], matrix12: PackedInt32Array, probes: FrogCollisionQuery.Sample) -> Result:
	var result := Result.new()
	result.reason = FrogCollisionQuery.validate_matrix(matrix12)
	if not result.reason.is_empty():
		return result
	if probes == null or not probes.error.is_empty():
		result.reason = "Frog collision sample is absent or invalid"
		return result
	if probes.points.size() != probes.part_indices.size() or probes.points.size() != probes.hilite_indices.size():
		result.reason = "Frog collision sample identities do not match its points"
		return result
	if primitives.size() != 1 or primitives[0] == null:
		result.reason = "Vehicle collision requires exactly one cuboid"
		return result
	var primitive: EntityPrimitiveDefinition = primitives[0]
	result.flags = primitive.flags
	result.reason = primitive.validate()
	if not result.reason.is_empty():
		result.status = "unsupported"
		return result
	if primitive.flags & 256:
		result.status = "disabled"
		result.reason = "MR_COLL_DISABLED"
		return result
	# MRApplyMatrix rotates cp_offset before the signed-short displacement store.
	var centre := Vector3i.ZERO
	for axis: int in 3:
		centre[axis] = FrogCollisionQuery.signed32(matrix12[axis * 3] * primitive.offset.x + matrix12[axis * 3 + 1] * primitive.offset.y + matrix12[axis * 3 + 2] * primitive.offset.z) >> 12
	for point_index: int in probes.points.size():
		var point: Vector3i = probes.points[point_index]
		for axis: int in 3:
			if point[axis] < -32768 or point[axis] > 32767:
				result.reason = "Frog world collision point is outside signed16"
				return result
		var delta := Vector3i.ZERO
		for axis: int in 3:
			delta[axis] = FrogCollisionQuery.signed16(point[axis] - matrix12[9 + axis] - centre[axis])
		var local := Vector3i.ZERO
		for axis: int in 3:
			local[axis] = FrogCollisionQuery.signed32(matrix12[axis] * delta.x + matrix12[3 + axis] * delta.y + matrix12[6 + axis] * delta.z) >> 12
		if absi(local.x) < primitive.half_size.x and absi(local.y) < primitive.half_size.y and absi(local.z) < primitive.half_size.z:
			result.status = "contact"
			result.part_index = probes.part_indices[point_index]
			result.hilite_index = probes.hilite_indices[point_index]
			result.primitive_part_index = primitive.part_index
			result.primitive_index = primitive.primitive_index
			result.reaction = primitive.reaction
			result.world_point = point
			result.local_position = local
			return result
	result.status = "miss"
	result.reason = "Outside strict cuboid bounds"
	return result

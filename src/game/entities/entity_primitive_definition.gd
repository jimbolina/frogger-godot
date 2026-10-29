class_name EntityPrimitiveDefinition
extends RefCounted
## Detached entity model cuboid; lengths are source half extents.
## A static model frames it with the entity matrix, an animated model with the
## stored LW transform of [member part_index].

const STATIC: int = 1 << 0
const LAST_IN_LIST: int = 1 << 1
const DISABLED: int = 1 << 8

var part_index: int = 0
var primitive_index: int = 0
var shape: int = 0
var flags: int = LAST_IN_LIST
var offset: Vector3i = Vector3i.ZERO
var half_size: Vector3i = Vector3i.ONE
var reaction: int = 1
var matrix_index: int = -1
## Row-major rotation of the part matrix named by [member matrix_index]; empty without one.
## The stored matrix translation is not used by the source.
var rotation: PackedInt32Array = PackedInt32Array()
## Source model identity of the shared primitive matrix, or -1 when unknown.
var model_resource_id: int = -1

## Rejects shapes, matrices and reactions outside the supported cuboid contract.
func validate() -> String:
	if part_index < 0 or primitive_index != 0:
		return "Entity collision requires one primitive"
	if shape != 0:
		return "Entity collision requires a cuboid primitive"
	if matrix_index < -1 or (matrix_index >= 0) != (rotation.size() == 9) or (matrix_index == -1 and not rotation.is_empty()):
		return "Primitive matrix index is outside the part's matrices"
	for value: int in rotation:
		if value < -32768 or value > 32767:
			return "Primitive matrix rotation is outside signed16"
	if flags & ~(STATIC | LAST_IN_LIST | DISABLED) != 0 or flags & LAST_IN_LIST == 0:
		return "Vehicle cuboid flags are unsupported or lack the list terminator"
	if reaction not in [0, 1, 3]:
		return "Vehicle cuboid reaction is unsupported"
	for axis: int in 3:
		if offset[axis] < -32768 or offset[axis] > 32767:
			return "Vehicle cuboid offset is outside signed16"
		if half_size[axis] < 0 or half_size[axis] > 65535:
			return "Vehicle cuboid half extent is outside unsigned16"
	return ""

## Returns independently owned source facts.
func copy() -> EntityPrimitiveDefinition:
	var result := EntityPrimitiveDefinition.new()
	result.part_index = part_index
	result.primitive_index = primitive_index
	result.shape = shape
	result.flags = flags
	result.offset = offset
	result.half_size = half_size
	result.reaction = reaction
	result.matrix_index = matrix_index
	result.rotation = rotation.duplicate()
	result.model_resource_id = model_resource_id
	return result

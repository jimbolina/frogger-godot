class_name EntityPrimitiveDefinition
extends RefCounted
## Detached static vehicle cuboid; lengths are source half extents.

var part_index: int = 0
var primitive_index: int = 0
var shape: int = 0
var flags: int = 2
var offset: Vector3i = Vector3i.ZERO
var half_size: Vector3i = Vector3i.ONE
var reaction: int = 1
var matrix_index: int = -1

## Rejects shapes, axes and reactions outside the static vehicle contract.
func validate() -> String:
	if part_index != 0 or primitive_index != 0:
		return "Vehicle collision requires the first part and one primitive"
	if shape != 0 or matrix_index != -1:
		return "Vehicle collision requires a cuboid without a primitive matrix"
	if flags & ~0x103 != 0 or flags & 2 == 0:
		return "Vehicle cuboid flags are unsupported or lack the list terminator"
	if reaction not in [0, 1]:
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
	return result

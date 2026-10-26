class_name EntityPrimitiveContact
extends RefCounted
## Detached diagnostic of one supported primitive scan, including its source identities.

var entity_index: int = -1
var unique_id: int = 0
var status: String = "miss"
var reason: String = ""
var frog_part_index: int = -1
var hilite_index: int = -1
var primitive_part_index: int = -1
var primitive_index: int = -1
var reaction: int = -1
var world_point: Vector3i = Vector3i.ZERO
var local_position: Vector3i = Vector3i.ZERO

## Returns an independent diagnostic for presentation consumers.
func copy() -> EntityPrimitiveContact:
	var result := EntityPrimitiveContact.new()
	result.entity_index = entity_index
	result.unique_id = unique_id
	result.status = status
	result.reason = reason
	result.frog_part_index = frog_part_index
	result.hilite_index = hilite_index
	result.primitive_part_index = primitive_part_index
	result.primitive_index = primitive_index
	result.reaction = reaction
	result.world_point = world_point
	result.local_position = local_position
	return result

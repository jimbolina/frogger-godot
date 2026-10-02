class_name FormContactDefinition
extends RefCounted
## Detached collision facts for one authored entity and its first FORM grid.

var source_id: String = ""
var build_id: String = ""
var resource_id: int = -1
var entity_index: int = -1
var unique_id: int = 0
var form_grid_id: int = -1
var form_id: int = -1
var form_name: String = ""
var source_offset: int = 0
var entity_flags: int = 0
var dimensions: Vector2i = Vector2i.ZERO
var offsets: Vector2i = Vector2i.ZERO
var height: int = 0
var max_y: int = 0
var radius_squared: int = 0
var grid_flags: PackedInt32Array = PackedInt32Array()
var unsupported_reason: String = ""
var death_type: int = 0
var reaction_unsupported_reason: String = ""

## Returns an independently owned definition, including grid square flags.
func copy() -> FormContactDefinition:
	var result := FormContactDefinition.new()
	result.source_id = source_id
	result.build_id = build_id
	result.resource_id = resource_id
	result.entity_index = entity_index
	result.unique_id = unique_id
	result.form_grid_id = form_grid_id
	result.form_id = form_id
	result.form_name = form_name
	result.source_offset = source_offset
	result.entity_flags = entity_flags
	result.dimensions = dimensions
	result.offsets = offsets
	result.height = height
	result.max_y = max_y
	result.radius_squared = radius_squared
	result.grid_flags = grid_flags.duplicate()
	result.unsupported_reason = unsupported_reason
	result.death_type = death_type
	result.reaction_unsupported_reason = reaction_unsupported_reason
	return result

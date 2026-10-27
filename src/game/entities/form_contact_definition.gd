class_name FormContactDefinition
extends RefCounted
## Detached collision facts for one authored entity and its first FORM grid.

const NO_ROTATION_SNAPPING: int = 2
const NO_ENTITY_ANGLE: int = 4
const DONT_CENTER_X: int = 64
const DONT_CENTER_Z: int = 128

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
## False only when the source FORM contains no FORM_DATA fallback.
var has_form_data: bool = true
var unsupported_reason: String = ""
var sphere_callback: bool = false
var callback_kind: FormCallback.Kind = FormCallback.Kind.NONE
var death_type: int = 0
var form_book_flags: int = 0
var reaction_unsupported_reason: String = ""
## Optional explicit contact disabling reason; logical entity updates remain active.
var disabled_reason: String = ""
## Optional supported primitives checked before this FORM's fallback grid.
var primitives: Array[EntityPrimitiveDefinition] = []

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
	result.has_form_data = has_form_data
	result.unsupported_reason = unsupported_reason
	result.sphere_callback = sphere_callback
	result.callback_kind = callback_kind
	result.death_type = death_type
	result.form_book_flags = form_book_flags
	result.reaction_unsupported_reason = reaction_unsupported_reason
	result.disabled_reason = disabled_reason
	for primitive: EntityPrimitiveDefinition in primitives:
		result.primitives.append(primitive.copy() if primitive != null else null)
	return result

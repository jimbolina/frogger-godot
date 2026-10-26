class_name EntityUpdateContext
extends RefCounted
## Read-only inputs for one source-ordered candidate entity update.

var entity_index: int = -1
var form_id: int = 0
var base_matrix: PackedInt32Array = EntityTransform.IDENTITY.duplicate()
var frog_position: Vector3i = Vector3i.ZERO
var previous_hit: bool = false
var previous_carry: bool = false
var path_flags: int = 0
var has_path: bool = false
var no_display: bool = false
## Inclusive source fade X min/max then Z min/max; empty means unbounded.
var fade_bounds: PackedInt32Array = PackedInt32Array()
var sound_allocation_enabled: bool = true

## Detaches call inputs before adapting them to a run-owned entity.
func copy() -> EntityUpdateContext:
	var result := EntityUpdateContext.new()
	result.entity_index = entity_index
	result.form_id = form_id
	result.base_matrix = base_matrix.duplicate()
	result.frog_position = frog_position
	result.previous_hit = previous_hit
	result.previous_carry = previous_carry
	result.path_flags = path_flags
	result.has_path = has_path
	result.no_display = no_display
	result.fade_bounds = fade_bounds.duplicate()
	result.sound_allocation_enabled = sound_allocation_enabled
	return result

class_name EntityUpdateContext
extends RefCounted
## Read-only inputs for one source-ordered candidate entity update.

var entity_index: int = -1
var form_id: int = 0
var base_matrix: PackedInt32Array = EntityTransform.IDENTITY.duplicate()
var frog_position: Vector3i = Vector3i.ZERO
var previous_hit: bool = false
var previous_carry: bool = false
var has_path: bool = false
var no_display: bool = false
## Inclusive source fade X min/max then Z min/max; empty means unbounded.
var fade_bounds: PackedInt32Array = PackedInt32Array()
var sound_allocation_enabled: bool = true

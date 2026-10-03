class_name EntitySnapshot
extends RefCounted
## One entity's source identity, transform and optional path cursor.

var entity_index: int = -1
var unique_id: int = 0
var matrix12: PackedInt32Array = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0])
var path: PathSnapshot = null
var lifecycle_supported: bool = true
var live: bool = true
var destroy_pending: bool = false
var generation: int = 0

## Returns an independent transform and nested path snapshot.
func copy() -> EntitySnapshot:
	var result := EntitySnapshot.new()
	result.entity_index = entity_index
	result.unique_id = unique_id
	result.matrix12 = matrix12.duplicate()
	result.path = path.copy() if path != null else null
	result.lifecycle_supported = lifecycle_supported
	result.live = live
	result.destroy_pending = destroy_pending
	result.generation = generation
	return result

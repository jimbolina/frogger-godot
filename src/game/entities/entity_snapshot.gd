class_name EntitySnapshot
extends RefCounted
## One entity's source identity, transform and optional path cursor.

var pop_allocated: bool = false
var pop_remaining: int = 0
var entity_index: int = -1
var unique_id: int = 0
var matrix12: PackedInt32Array = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0])
var path: PathSnapshot = null
var lifecycle_supported: bool = true
var live: bool = true
## Whether source creation allocated a model; live FORM fallback does not require one.
var model_present: bool = true
var destroy_pending: bool = false
var generation: int = 0
var script_state: EntityScriptState = null
var animation: EntityAnimationState = null
var requests: Array[TickEvent] = []
var entity_flags: int = 0
var flags_authoritative: bool = false
var custom_state: EntityCustomState = null
var live_flags: int = 0
var colour_scale: Vector3i = Vector3i.ZERO
## Whether source colour scaling was applied; an applied zero scale draws black.
var colour_scaled: bool = false
var ambient: Vector3i = Vector3i.ZERO

## Returns an independent transform and nested path snapshot.
func copy() -> EntitySnapshot:
	var result := EntitySnapshot.new()
	result.pop_allocated = pop_allocated
	result.pop_remaining = pop_remaining
	result.entity_index = entity_index
	result.unique_id = unique_id
	result.matrix12 = matrix12.duplicate()
	result.path = path.copy() if path != null else null
	result.lifecycle_supported = lifecycle_supported
	result.live = live
	result.model_present = model_present
	result.destroy_pending = destroy_pending
	result.generation = generation
	result.script_state = script_state.copy() if script_state != null else null
	result.animation = animation.copy() if animation != null else null
	result.requests = TickEvent.copy_all(requests)
	result.entity_flags = entity_flags
	result.flags_authoritative = flags_authoritative
	result.custom_state = custom_state.copy() if custom_state != null else null
	result.live_flags = live_flags
	result.colour_scale = colour_scale
	result.colour_scaled = colour_scaled
	result.ambient = ambient
	return result

## Uses live flags when initialized, retaining authored flags for standalone probes.
func effective_flags(authored: int) -> int:
	return entity_flags if flags_authoritative else authored | entity_flags

class_name EntityRunSnapshot
extends RefCounted
## Source-ordered snapshot of a bounded set of attached entities.

var tick_index: int = 0
var entities: Array[EntitySnapshot] = []
var lifecycle_enabled: bool = false
var live_order: PackedInt32Array = PackedInt32Array()
var selected_groups: PackedInt32Array = PackedInt32Array()
var lifecycle_events: Array[TickEvent] = []
var updates: Array[EntityUpdateObservation] = []

## Returns independent entity, transform and path snapshots.
func copy() -> EntityRunSnapshot:
	var result := EntityRunSnapshot.new()
	result.tick_index = tick_index
	result.lifecycle_enabled = lifecycle_enabled
	result.live_order = live_order.duplicate()
	result.selected_groups = selected_groups.duplicate()
	result.lifecycle_events = TickEvent.copy_all(lifecycle_events)
	for update: EntityUpdateObservation in updates:
		result.updates.append(update.copy())
	for entity: EntitySnapshot in entities:
		result.entities.append(entity.copy() if entity != null else null)
	return result

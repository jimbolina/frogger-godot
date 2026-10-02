class_name EntityRunSnapshot
extends RefCounted
## Source-ordered snapshot of a bounded set of attached entities.

var tick_index: int = 0
var entities: Array[EntitySnapshot] = []

## Returns independent entity, transform and path snapshots.
func copy() -> EntityRunSnapshot:
	var result := EntityRunSnapshot.new()
	result.tick_index = tick_index
	for entity: EntitySnapshot in entities:
		result.entities.append(entity.copy() if entity != null else null)
	return result

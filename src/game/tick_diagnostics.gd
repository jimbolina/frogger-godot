class_name TickDiagnostics
extends RefCounted
## Source provenance and observations that do not drive movement.

var source_id: String = ""
var resource_id: int = -1
var map_index: int = -1
var square_source_offset: int = -1
var polygon_index: int = -1
var polygon_source_offset: int = -1
var rng_draw_count: int = 0

## Returns an independently mutable copy of every value.
func copy() -> TickDiagnostics:
	var result := TickDiagnostics.new()
	result.source_id = source_id
	result.resource_id = resource_id
	result.map_index = map_index
	result.square_source_offset = square_source_offset
	result.polygon_index = polygon_index
	result.polygon_source_offset = polygon_source_offset
	result.rng_draw_count = rng_draw_count
	return result

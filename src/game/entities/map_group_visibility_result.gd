class_name MapGroupVisibilityResult
extends RefCounted
## Ordered map-view groups and the conservative polygon-budget sum.

var groups: PackedInt32Array = PackedInt32Array()
var polygon_total: int = 0
var group_timers: PackedInt32Array = PackedInt32Array()
var error: String = ""

## Returns independent visibility facts.
func copy() -> MapGroupVisibilityResult:
	var result := MapGroupVisibilityResult.new()
	result.groups = groups.duplicate()
	result.polygon_total = polygon_total
	result.group_timers = group_timers.duplicate()
	result.error = error
	return result

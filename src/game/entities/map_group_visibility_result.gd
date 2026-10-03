class_name MapGroupVisibilityResult
extends RefCounted
## Ordered map-view groups and the conservative polygon-budget sum.

var groups: PackedInt32Array = PackedInt32Array()
var polygon_total: int = 0
var error: String = ""

## Returns independent visibility facts.
func copy() -> MapGroupVisibilityResult:
	var result := MapGroupVisibilityResult.new()
	result.groups = groups.duplicate()
	result.polygon_total = polygon_total
	result.error = error
	return result

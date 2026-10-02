class_name PathDefinition
extends RefCounted
## Detached source path and its ordered segments.

var source_id: String = ""
var resource_id: int = -1
var path_index: int = -1
var source_offset: int = -1
var segments: Array[PathSegmentDefinition] = []

## Returns an independent copy of the path and every segment.
func copy() -> PathDefinition:
	var result := PathDefinition.new()
	result.source_id = source_id
	result.resource_id = resource_id
	result.path_index = path_index
	result.source_offset = source_offset
	for segment: PathSegmentDefinition in segments:
		result.segments.append(segment.copy() if segment != null else null)
	return result

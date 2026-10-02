class_name GameplayCameraDefinition
extends RefCounted
## Setup-supplied default map offsets in original whole world units.

var source_offset: Vector3i = Vector3i(0, -500, -500)
var target_offset: Vector3i = Vector3i.ZERO

## Returns a detached definition; live cameras never borrow caller configuration.
func copy() -> GameplayCameraDefinition:
	var value := GameplayCameraDefinition.new()
	value.source_offset = source_offset
	value.target_offset = target_offset
	return value

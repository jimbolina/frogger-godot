class_name PathSnapshot
extends RefCounted
## Detached integer state and evaluated source-space path position.

var tick_index: int = 0
var segment_index: int = 0
var segment_type: int = 0
var segment_distance: int = 0
var segment_length: int = 0
var segment_param: int = 0
var total_distance: int = 0
var speed: int = 0
var flags: int = 0
var position: Vector3i = Vector3i.ZERO
var tangent: Vector3i = Vector3i.ZERO

## Returns an independent copy of the runner state.
func copy() -> PathSnapshot:
	var result := PathSnapshot.new()
	result.tick_index = tick_index
	result.segment_index = segment_index
	result.segment_type = segment_type
	result.segment_distance = segment_distance
	result.segment_length = segment_length
	result.segment_param = segment_param
	result.total_distance = total_distance
	result.speed = speed
	result.flags = flags
	result.position = position
	result.tangent = tangent
	return result

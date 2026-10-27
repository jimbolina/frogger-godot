class_name ZoneDefinition
extends RefCounted
## Detached authored camera-zone bounds. Stored coordinates retain signed16 bits.

const CHECKPOINT: int = 1 << 4
const SEMIFORCED: int = 1 << 2
const ABSOLUTE_Y: int = 1 << 3

var source_id: String = ""
var build_id: String = ""
var resource_id: int = -1
var zone_index: int = 0
var source_offset: int = -1
var zone_type: int = 0
var bounds: PackedInt32Array = PackedInt32Array()
var regions: Array[PackedInt32Array] = []
var camera_flags: int = 0
var camera_direction: int = -1
var camera_offsets: Array[Vector3i] = []

## Validates the payload required for execution, beyond bounds-only inspection.
func validate_camera() -> String:
	var issue: String = validate()
	if not issue.is_empty():
		return issue
	if camera_flags < 0 or camera_flags & ~0x1f or camera_direction < -1 or camera_direction > 3:
		return "Camera zone requires known flags and direction -1..3"
	if camera_offsets.size() != 8:
		return "Camera zone requires eight offset vectors"
	for offset: Vector3i in camera_offsets:
		for component: int in [offset.x, offset.y, offset.z]:
			if component < -32768 or component > 32767:
				return "Camera zone offsets must fit signed16"
	return ""

## Checks storage and supported semantics without normalizing inverted bounds.
func validate() -> String:
	if zone_index < 0 or source_offset < -1 or zone_type != 0:
		return "Zone requires an authored identity and known CAMERA type 0"
	if not _valid_bounds(bounds):
		return "Zone outer bounds require four signed16 stored coordinates"
	for region: PackedInt32Array in regions:
		if not _valid_bounds(region):
			return "Zone child bounds require four signed16 coordinates"
	return ""

## Copies nested bounds so caller mutation cannot change an owned run.
func copy() -> ZoneDefinition:
	var result := ZoneDefinition.new()
	result.source_id = source_id
	result.build_id = build_id
	result.resource_id = resource_id
	result.zone_index = zone_index
	result.source_offset = source_offset
	result.zone_type = zone_type
	result.camera_flags = camera_flags
	result.camera_direction = camera_direction
	result.camera_offsets.assign(camera_offsets)
	result.bounds = bounds.duplicate()
	for region: PackedInt32Array in regions:
		result.regions.append(region.duplicate())
	return result

static func _valid_bounds(value: PackedInt32Array) -> bool:
	if value.size() != 4:
		return false
	for coordinate: int in value:
		if coordinate < -32768 or coordinate > 32767:
			return false
	return true

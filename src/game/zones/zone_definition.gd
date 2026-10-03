class_name ZoneDefinition
extends RefCounted
## Detached authored camera-zone bounds. Stored coordinates retain signed16 bits.

var source_id: String = ""
var build_id: String = ""
var resource_id: int = -1
var zone_index: int = 0
var source_offset: int = -1
var zone_type: int = 0
var bounds: PackedInt32Array = PackedInt32Array()
var regions: Array[PackedInt32Array] = []

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

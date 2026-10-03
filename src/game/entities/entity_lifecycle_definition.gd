class_name EntityLifecycleDefinition
extends RefCounted
## Detached source map-group geometry and polygon counts for live-entity visibility.

var group_base: Vector3i = Vector3i.ZERO
var group_dimensions: Vector2i = Vector2i.ZERO
var group_size: Vector2i = Vector2i.ZERO
var polygon_counts: PackedInt32Array = PackedInt32Array()

## Returns independent map-group facts.
func copy() -> EntityLifecycleDefinition:
	var result := EntityLifecycleDefinition.new()
	result.group_base = group_base
	result.group_dimensions = group_dimensions
	result.group_size = group_size
	result.polygon_counts = polygon_counts.duplicate()
	return result

## Rejects geometry that cannot describe the frozen map-view grid.
func validate() -> String:
	if group_dimensions.x <= 0 or group_dimensions.y <= 0 or group_dimensions.x > 65535 or group_dimensions.y > 65535:
		return "Lifecycle group dimensions must fit positive unsigned16 values"
	if group_dimensions.y > 64:
		return "Lifecycle map groups exceed the source 64-row visibility buffer"
	if group_size.x <= 0 or group_size.y <= 0 or group_size.x > 65535 or group_size.y > 65535:
		return "Lifecycle group size must fit positive unsigned16 values"
	for coordinate: int in [group_base.x, group_base.y, group_base.z]:
		if coordinate < -32768 or coordinate > 32767:
			return "Lifecycle group base must fit signed16"
	if int(group_dimensions.x) * group_dimensions.y != polygon_counts.size():
		return "Lifecycle requires one polygon count per map group"
	if int(group_dimensions.x) * group_dimensions.y > 32768:
		return "Lifecycle map group indices must fit source signed16"
	for count: int in polygon_counts:
		if count < 0 or count > 65535:
			return "Lifecycle polygon counts must fit unsigned16"
	return ""

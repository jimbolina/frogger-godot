class_name EntityLifecycleSetup
extends RefCounted
## Copies map-group facts shared by gameplay admission and prescribed camera probes.

var error: String = ""
var definition: EntityLifecycleDefinition = null

## Detaches every visible group's eight source polygon counts without admitting gameplay.
static func from_map(map: MapFile) -> EntityLifecycleSetup:
	var result := EntityLifecycleSetup.new()
	if map == null or not map.error.is_empty():
		result.error = "Visibility lifecycle requires a valid map"
		return result
	var count: int = map.group_dimensions.x * map.group_dimensions.y
	if map.groups.size() < count:
		result.error = "Visibility lifecycle requires every authored map group"
		return result
	var lifecycle := EntityLifecycleDefinition.new()
	lifecycle.group_base = map.group_base
	lifecycle.group_dimensions = map.group_dimensions
	lifecycle.group_size = map.group_size
	for index: int in count:
		if map.groups[index].counts.size() < 8:
			result.error = "Visibility lifecycle requires eight polygon counts per group"
			return result
		var polygons: int = 0
		for kind: int in 8:
			polygons += map.groups[index].counts[kind]
		lifecycle.polygon_counts.append(polygons)
	result.error = lifecycle.validate()
	if result.error.is_empty():
		result.definition = lifecycle
	return result

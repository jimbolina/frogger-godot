class_name MapGroupAllocation
extends RefCounted
## Frozen mapdisp.c group expansion and RenderMap lifetime, once per logic tick.

## Returns visited entity groups and detached post-render allocation timers.
static func expand(definition: EntityLifecycleDefinition, selected: PackedInt32Array, previous: PackedInt32Array) -> MapGroupVisibilityResult:
	var result := MapGroupVisibilityResult.new()
	result.group_timers = previous.duplicate()
	if previous.is_empty():
		result.group_timers.resize(definition.polygon_counts.size())
	if result.group_timers.size() != definition.polygon_counts.size():
		result.error = "Map allocation requires one timer per authored group"
		return result
	var allocated: int = 0
	for timer: int in result.group_timers:
		if timer < 0 or timer > 3:
			result.error = "Map allocation timer must be in 0..3"
			return result
		if timer > 0:
			allocated += 1
	if allocated > MapGroupVisibility.GROUP_CAP:
		result.error = "Map allocation exceeds the source group pool"
		return result
	var remaining: int = MapGroupVisibility.POLYGON_BUDGET
	for group: int in selected:
		if remaining <= 0:
			break
		if group < 0 or group >= result.group_timers.size():
			result.error = "Map allocation selected group is outside authored geometry"
			return result
		result.groups.append(group)
		var count: int = definition.polygon_counts[group]
		result.polygon_total += count
		var timer: int = result.group_timers[group]
		if timer > 0:
			if timer >= 2:
				result.group_timers[group] = 3
			remaining -= count
		elif count > 0 and allocated < MapGroupVisibility.GROUP_CAP and count <= remaining:
			result.group_timers[group] = 3
			allocated += 1
			remaining -= count
	for group: int in result.group_timers.size():
		result.group_timers[group] = maxi(0, result.group_timers[group] - 1)
	return result

class_name ZoneQueries
extends RefCounted
## Pure frozen CheckCoordsInZones ordering, with unsigned outer/signed child bounds.

## Returns the first matching authored camera-zone index, or -1.
static func first_camera_match(definitions: Array[ZoneDefinition], cell: Vector2i) -> int:
	for definition: ZoneDefinition in definitions:
		if definition == null or definition.zone_type != 0 or definition.bounds.size() != 4:
			continue
		var bounds: PackedInt32Array = definition.bounds
		if cell.x < (bounds[0] & 65535) or cell.y < (bounds[1] & 65535) or cell.x > (bounds[2] & 65535) or cell.y > (bounds[3] & 65535):
			continue
		if definition.regions.is_empty():
			return definition.zone_index
		for region: PackedInt32Array in definition.regions:
			if region.size() == 4 and cell.x >= region[0] and cell.y >= region[1] and cell.x <= region[2] and cell.y <= region[3]:
				return definition.zone_index
	return -1

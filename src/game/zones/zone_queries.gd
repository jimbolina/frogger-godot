class_name ZoneQueries
extends RefCounted
## Pure frozen CheckCoordsInZones ordering, with unsigned outer/signed child bounds.

const NO_UPDATE: int = 1 << 20

## Finds an authored identity, never treating it as an array offset.
static func definition_for(definitions: Array[ZoneDefinition], identity: int) -> ZoneDefinition:
	for definition: ZoneDefinition in definitions:
		if definition.zone_index == identity:
			return definition
	return null

## Returns (zone, region); region -1 means the outer rectangle, zone -1 no match.
## Retains the current region/zone before searching authored order, as MoveFrog does.
static func update_camera_match(definitions: Array[ZoneDefinition], cell: Vector2i, current: Vector2i = Vector2i(-1, -1), flags: int = 0) -> Vector2i:
	if flags & NO_UPDATE:
		return current
	var zone: ZoneDefinition = definition_for(definitions, current.x)
	if zone != null:
		var region: PackedInt32Array = zone.bounds if current.y == -1 and zone.regions.is_empty() else PackedInt32Array()
		if current.y >= 0 and current.y < zone.regions.size():
			region = zone.regions[current.y]
		if _contains(region, cell, false):
			return current
		var retained: int = _region_in_zone(zone, cell)
		if retained != -2:
			return Vector2i(zone.zone_index, retained)
	for candidate: ZoneDefinition in definitions:
		var region_index: int = _region_in_zone(candidate, cell)
		if region_index != -2:
			return Vector2i(candidate.zone_index, region_index)
	return Vector2i(-1, -1)

static func _region_in_zone(zone: ZoneDefinition, cell: Vector2i) -> int:
	if zone.zone_type != 0 or not _contains(zone.bounds, cell, true):
		return -2
	if zone.regions.is_empty():
		return -1
	for index: int in zone.regions.size():
		if _contains(zone.regions[index], cell, false):
			return index
	return -2

static func _contains(bounds: PackedInt32Array, cell: Vector2i, unsigned: bool) -> bool:
	if bounds.size() != 4:
		return false
	var mask: int = 65535 if unsigned else -1
	return cell.x >= (bounds[0] & mask) and cell.y >= (bounds[1] & mask) and cell.x <= (bounds[2] & mask) and cell.y <= (bounds[3] & mask)

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

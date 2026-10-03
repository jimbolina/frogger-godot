class_name ExplorationGuard
extends RefCounted
## Immutable inspection admission bounds; rejecting a candidate never creates a wall.

var world_bounds: Rect2i = Rect2i()
var zones: Array[ZoneDefinition] = []

## Validates a half-open world rectangle and every supported zone definition.
func validate() -> String:
	if world_bounds.size.x <= 0 or world_bounds.size.y <= 0:
		return "Exploration boundary requires positive width and depth"
	for coordinate: int in [int(world_bounds.position.x) + world_bounds.size.x, int(world_bounds.position.y) + world_bounds.size.y]:
		if coordinate > 2147483647 or coordinate < -2147483648:
			return "Exploration boundary must fit signed32 world coordinates"
	var identities: Dictionary[int, bool] = {}
	for zone: ZoneDefinition in zones:
		if zone == null:
			return "Exploration guard contains a null zone"
		var issue: String = zone.validate()
		if not issue.is_empty():
			return "%s: %s" % [_location(zone), issue]
		if identities.has(zone.zone_index):
			return "Exploration guard contains duplicate authored zone %d" % zone.zone_index
		identities[zone.zone_index] = true
	return ""

## Returns a fully detached copy of the inspection restrictions.
func copy() -> ExplorationGuard:
	var result := ExplorationGuard.new()
	result.world_bounds = world_bounds
	for zone: ZoneDefinition in zones:
		result.zones.append(zone.copy())
	return result

## Checks actual source world X/Z using inclusive starts and exclusive ends.
func check_world(world: Vector3i) -> String:
	if world_bounds.has_point(Vector2i(world.x, world.z)):
		return ""
	return "Exploration boundary rejected (%d,%d): X[%d,%d), Z[%d,%d); tick rolled back" % [world.x, world.z, world_bounds.position.x, world_bounds.end.x, world_bounds.position.y, world_bounds.end.y]

## Rejects entry into an active camera zone at the source zone-update position.
func check_cell(cell: Vector2i) -> String:
	var match_index: int = ZoneQueries.first_camera_match(zones, cell)
	if match_index < 0:
		return ""
	for zone: ZoneDefinition in zones:
		if zone.zone_index == match_index:
			return "%s: active camera zone at cell %s is unsupported; tick rolled back" % [_location(zone), cell]
	return "Exploration zone identity is invalid"

static func _location(zone: ZoneDefinition) -> String:
	return "%s build %s resource %d ZONE[%d] offset %d" % [zone.source_id, zone.build_id, zone.resource_id, zone.zone_index, zone.source_offset]

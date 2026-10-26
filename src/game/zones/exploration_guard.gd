class_name ExplorationGuard
extends RefCounted
## Immutable inspection admission bounds; rejecting a candidate never creates a wall.

var world_bounds: Rect2i = Rect2i()
var zones: Array[ZoneDefinition] = []
## Optional complete stored-root and live-action closure for primitive exclusion.
var frog_roots: Array[PackedInt32Array] = []
var frog_actions: PackedInt32Array = PackedInt32Array()
## Authored moving collectables whose excluded sphere must stay beyond the corridor.
var collectable_indices: PackedInt32Array = PackedInt32Array()
## Explicit source-proved scripted lifetime admission, independent of exclusions.
var scripted_visibility_admitted: bool = false

## Validates a half-open world rectangle and every supported zone definition.
func validate() -> String:
	if scripted_visibility_admitted and frog_roots.is_empty():
		return "Scripted visibility requires the complete animated admission"
	if frog_roots.is_empty() != frog_actions.is_empty():
		return "Animated admission requires both root and action closure"
	for root: PackedInt32Array in frog_roots:
		if root.size() != 9:
			return "Animated admission root must contain nine values"
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
	result.collectable_indices = collectable_indices.duplicate()
	result.scripted_visibility_admitted = scripted_visibility_admitted
	for root: PackedInt32Array in frog_roots:
		result.frog_roots.append(root.duplicate())
	result.frog_actions = frog_actions.duplicate()
	for zone: ZoneDefinition in zones:
		result.zones.append(zone.copy())
	return result

## Rejects an unproved animated collision point before any neighbor scan.
func check_frog(state: RunSnapshot) -> String:
	if frog_roots.is_empty():
		return ""
	if state.powerup_flags != 0:
		return "Animated admission requires an unpowered frog; tick rolled back"
	if state.mode == 2 or state.flags & 8:
		return ""
	if not frog_roots.has(state.matrix12.slice(0, 9)):
		return "Animated admission rejected an unproved frog root; tick rolled back"
	if state.animation == null or (not frog_actions.has(state.animation.action) and not (state.animation.action == 0 and state.animation.cel == 0)):
		return "Animated admission rejected an unproved frog action; tick rolled back"
	return check_world(Vector3i(state.matrix12[9], state.matrix12[10], state.matrix12[11]))

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

## Rejects loss of a dynamic collection/contact exclusion before frog control.
func check_entities(entities: EntityRunSnapshot) -> String:
	if collectable_indices.is_empty():
		return ""
	if entities == null:
		return "Dynamic collectable admission requires entity state"
	for identity: int in collectable_indices:
		var found: bool = false
		for entity: EntitySnapshot in entities.entities:
			if entity.entity_index != identity:
				continue
			found = true
			if not entity.live:
				break
			var x: int = entity.matrix12[9]
			var z: int = entity.matrix12[11]
			var dx: int = maxi(maxi(world_bounds.position.x - x, 0), x - world_bounds.end.x + 1)
			var dz: int = maxi(maxi(world_bounds.position.y - z, 0), z - world_bounds.end.y + 1)
			if dx * dx + dz * dz <= 640 * 640:
				return "Dynamic collectable %d entered the guarded corridor's collection radius; tick rolled back" % identity
			break
		if not found:
			return "Dynamic collectable admission identity is missing"
	return ""

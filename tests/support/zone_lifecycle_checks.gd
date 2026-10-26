class_name ZoneLifecycleChecks
extends RefCounted
## Compares independent text facts with detached combined-system observations.

static func compare(raw_expected: Variant, camera: GameplayCameraSnapshot, zone: int, region: int, angle: int, world: Vector3i, entities: EntityRunSnapshot) -> String:
	var expected: Dictionary = raw_expected
	var expected_entities: Array = expected.entities
	var actual: Dictionary = TerrainTrace.facts(camera)
	actual["frog_zone"] = zone
	actual["frog_region"] = region
	actual["entity_angle"] = angle
	actual["mod_rotation"] = Array(camera.mod_matrix12.slice(0, 9))
	for key: String in expected.camera:
		if canonical(actual[key]) != canonical(expected.camera[key]):
			return "camera.%s: %s != %s" % [key, actual[key], expected.camera[key]]
	for pair: Array in [[Array(entities.selected_groups), expected.selected_groups], [Array(entities.live_order), expected.live_order],
		[TickEvent.trace_lines(entities.lifecycle_events), expected.events], [[world.x, world.y, world.z], expected.world]]:
		if canonical(pair[0]) != canonical(pair[1]):
			return "Combined observation differs: %s != %s" % pair
	if entities.entities.size() != expected_entities.size():
		return "Entity inventory differs"
	for slot: int in entities.entities.size():
		var entity: EntitySnapshot = entities.entities[slot]
		var facts: Dictionary = expected.entities[slot]
		var pose: Array = Array(entity.matrix12.slice(9, 12))
		var values: Array = [entity.entity_index, entity.live, entity.destroy_pending, entity.generation, pose]
		var wanted: Array = [facts.entity_index, facts.live, facts.destroy_pending, facts.generation, facts.position]
		if canonical(values) != canonical(wanted):
			return "Entity %d: %s != %s" % [entity.entity_index, values, wanted]
		if facts.path != null:
			var path: PathSnapshot = entity.path
			if path == null:
				return "Missing entity path"
			var fields: Array = [path.tick_index, path.segment_index, path.segment_type, path.segment_distance, path.segment_length,
				path.segment_param, path.total_distance, path.speed, path.flags, path.position.x, path.position.y, path.position.z,
				path.tangent.x, path.tangent.y, path.tangent.z]
			if canonical(fields) != canonical(facts.path):
				return "Entity %d path differs" % entity.entity_index
	return ""

static func canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

## Constructs a retail component stimulus entirely from text facts, without retail bytes.
static func inspection(raw_workload: Variant) -> CameraZoneInspection:
	var workload: Dictionary = raw_workload
	var result := CameraZoneInspection.new()
	var authored: Dictionary = workload["case"]
	result.definition = GameplayCameraDefinition.new()
	result.definition.source_offset = _vec(authored.source)
	result.definition.target_offset = _vec(authored.target)
	result.grid_base = Vector2i(-3584, -7680)
	var scenario: TerrainScenario = TerrainScenario.builtin("normal")
	var zones: Array = []
	var authored_zones: Array = authored.zones
	for index: int in authored_zones.size():
		var zone: Dictionary = authored.zones[index]
		zones.append({"zone_index": index, "bounds": zone.bounds, "regions": zone.regions,
			"camera_flags": zone.flags, "camera_direction": zone.direction, "camera_offsets": zone.offsets})
	result.error = TerrainScenarioJson.apply(scenario, {"level": {"camera_zones": zones}})
	result.zones = scenario.level.camera_zones
	var groups: Dictionary = workload.groups
	result.lifecycle = EntityLifecycleDefinition.new()
	result.lifecycle.group_base = _vec(groups.base)
	result.lifecycle.group_dimensions = Vector2i(_integer(groups.dimensions[0]), _integer(groups.dimensions[1]))
	result.lifecycle.group_size = Vector2i(_integer(groups.size[0]), _integer(groups.size[1]))
	result.lifecycle.polygon_counts = _packed(groups.counts)
	for raw: Variant in workload.entities:
		var record: Dictionary = raw
		var entity := EntityDefinition.new()
		entity.entity_index = _integer(record.index)
		entity.entity_name = record.kind
		entity.flags = _integer(record.flags)
		entity.path_definition = PathDefinition.new()
		entity.path_definition.path_index = entity.entity_index
		for item: Variant in record.segments:
			var row: Dictionary = item
			var segment := PathSegmentDefinition.new()
			segment.segment_type = _integer(row.segment_type)
			segment.length = _integer(row.length)
			if segment.segment_type == 2:
				segment.start = _vec(row.start)
				segment.end = _vec(row.end)
			else:
				segment.matrix = _packed(row.matrix)
				segment.smooth_t = _packed(row.smooth_t)
				segment.smooth_c = _packed(row.smooth_c)
			entity.path_definition.segments.append(segment)
		entity.path_start = PathStart.new()
		entity.path_start.segment_index = _integer(record.start.segment_index)
		entity.path_start.distance = _integer(record.start.distance)
		entity.path_start.speed = _integer(record.start.speed)
		entity.path_start.flags = _integer(record.start.flags)
		result.entity_definitions.append(entity)
	if result.error.is_empty():
		result.error = result.reset()
	return result

static func _vec(raw: Variant) -> Vector3i:
	var value: Array = raw
	return Vector3i(_integer(value[0]), _integer(value[1]), _integer(value[2]))

static func _integer(value: Variant) -> int:
	var number: float = value
	return int(number)

static func _packed(value: Variant) -> PackedInt32Array:
	var values: Array = value
	return PackedInt32Array(values)

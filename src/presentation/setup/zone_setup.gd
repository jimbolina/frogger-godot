class_name ZoneSetup
extends RefCounted
## Admits only completely decoded, known camera zones as detached definitions.

var definitions: Array[ZoneDefinition] = []
var error: String = ""
var diagnostics: PackedStringArray = PackedStringArray()

## Checks every source identity and camera field before exposing any zone.
static func from_map(map: MapFile, source_id: String = "", resource_id: int = -1, build_id: String = "") -> ZoneSetup:
	var result := ZoneSetup.new()
	if map == null:
		result.error = "Zone setup requires a map"
		return result
	if not map.error.is_empty():
		result.error = "Cannot set up zones from invalid map: %s" % map.error
		return result
	var packet: MapPacket = map.packets.get("ZONE")
	if packet == null or packet.count != map.zones.size() or packet.offsets.size() != packet.count:
		result.error = "ZONE record count does not match its pointer table"
		return result
	var pending: Array[ZoneDefinition] = []
	for index: int in map.zones.size():
		var zone: MapZone = map.zones[index]
		var location: String = "%s/%s resource %d ZONE[%d] at %d" % [build_id, source_id, resource_id, index, -1 if zone == null else zone.source_offset]
		if zone == null or zone.zone_index != index or zone.source_offset != packet.offsets[index]:
			result._reject("%s source identity does not match the pointer table" % location)
			break
		for issue: String in zone.diagnostics:
			result._reject("%s: %s" % [location, issue])
		if not result.error.is_empty():
			break
		if zone.zone_type != 0:
			result._reject("%s has unknown zone type %d" % [location, zone.zone_type])
		# FrogLord stores ENABLE_PER_DIRECTION_OFFSETS in bit 0; frozen C
		# names bits 1..4 and ignores bit 0 while reading the eight offsets.
		elif zone.camera_flags & ~0x1f:
			result._reject("%s has unknown camera flags 0x%X" % [location, zone.camera_flags])
		elif zone.camera_direction < -1 or zone.camera_direction > 3:
			result._reject("%s has invalid camera direction %d" % [location, zone.camera_direction])
		elif zone.bounds.size() != 4 or zone.camera_offsets.size() != 8:
			result._reject("%s has incomplete camera geometry" % location)
		if not result.error.is_empty():
			break
		var definition := ZoneDefinition.new()
		definition.source_id = source_id
		definition.build_id = build_id
		definition.resource_id = resource_id
		definition.zone_index = index
		definition.source_offset = zone.source_offset
		definition.zone_type = zone.zone_type
		definition.bounds = zone.bounds.duplicate()
		for region_index: int in zone.regions.size():
			var region: MapZoneRegion = zone.regions[region_index]
			if region == null or region.region_index != region_index or region.bounds.size() != 4:
				result._reject("%s has invalid region %d" % [location, region_index])
				break
			definition.regions.append(region.bounds.duplicate())
		if not result.error.is_empty():
			break
		var validation: String = definition.validate()
		if not validation.is_empty():
			result._reject("%s: %s" % [location, validation])
			break
		pending.append(definition)
	if result.error.is_empty():
		result.definitions = pending
	return result

func _reject(message: String) -> void:
	if error.is_empty():
		error = message
	diagnostics.append(message)

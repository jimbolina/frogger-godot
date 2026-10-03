extends GutTest
## Admission is atomic and copies source rectangles before gameplay owns them.

func _map() -> MapFile:
	var map := MapFile.new()
	var packet := MapPacket.new()
	packet.identifier = "ZONE"
	packet.count = 2
	packet.offsets = PackedInt32Array([100, 200])
	map.packets["ZONE"] = packet
	for i: int in 2:
		var zone := MapZone.new()
		zone.zone_index = i
		zone.source_offset = packet.offsets[i]
		zone.end_offset = zone.source_offset + 84
		zone.zone_type = 0
		if i == 1:
			zone.bounds = PackedInt32Array([12, 40, 15, 39])
		else:
			zone.bounds = PackedInt32Array([13, 22, 18, 32])
		zone.camera_direction = -1
		for j: int in 8:
			zone.camera_offsets.append(Vector3i(j, -j, 0))
		if i == 0:
			var child := MapZoneRegion.new()
			child.region_index = 0
			child.source_offset = 184
			child.bounds = PackedInt32Array([15, 22, 18, 32])
			zone.regions.append(child)
		map.zones.append(zone)
	return map

func test_setup_keeps_inverted_bounds_and_detaches_nested_regions() -> void:
	var map: MapFile = _map()
	var setup: ZoneSetup = ZoneSetup.from_map(map, "JUN1.MAP", 656, "pc-retail-v3.0e")
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 2)
	assert_eq(setup.definitions[0].zone_index, 0)
	assert_eq(setup.definitions[0].resource_id, 656)
	assert_eq(setup.definitions[1].bounds, PackedInt32Array([12, 40, 15, 39]))
	map.zones[0].bounds[0] = 99
	map.zones[0].regions[0].bounds[0] = 99
	assert_eq(setup.definitions[0].bounds[0], 13)
	assert_eq(setup.definitions[0].regions[0][0], 15)

func test_unknown_or_malformed_record_rejects_all_definitions() -> void:
	var map: MapFile = _map()
	map.zones[1].zone_type = 7
	var setup: ZoneSetup = ZoneSetup.from_map(map, "JUN1.MAP", 656, "pc-retail-v3.0e")
	assert_eq(setup.definitions.size(), 0)
	assert_string_contains(setup.error, "ZONE[1]")
	map = _map()
	map.zones[1].camera_flags = 1
	setup = ZoneSetup.from_map(map)
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 2)
	map = _map()
	map.zones[1].camera_flags = 32
	setup = ZoneSetup.from_map(map)
	assert_string_contains(setup.error, "camera flags")
	map = _map()
	map.zones[1].camera_direction = 4
	setup = ZoneSetup.from_map(map)
	assert_string_contains(setup.error, "direction")
	map = _map()
	map.zones[1].diagnostics.append("out-of-bounds region pointer")
	setup = ZoneSetup.from_map(map)
	assert_string_contains(setup.error, "out-of-bounds")
	map = _map()
	map.zones[1].zone_index = 0
	setup = ZoneSetup.from_map(map)
	assert_string_contains(setup.error, "identity")
	map = _map()
	map.packets["ZONE"].count = 3
	setup = ZoneSetup.from_map(map)
	assert_string_contains(setup.error, "count")

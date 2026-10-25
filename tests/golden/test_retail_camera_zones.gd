extends RetailTest
## Supplied JUN1 camera records and deterministic inspection match independent facts.

func test_jun1_zone_inspection_matches_independent_reference() -> void:
	var data: GameData = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))
	var inspection: CameraZoneInspection = CameraZoneInspection.from_data(data)
	assert_eq(inspection.error, "")
	if not inspection.error.is_empty():
		data.close()
		return
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/pc-retail-v3.0e/camera_zones.json"))
	var cases: Array = golden.cases
	var first: Dictionary = cases[0]
	var records: Array = first.zones
	assert_eq(inspection.zones.size(), records.size())
	for index: int in records.size():
		var record: Dictionary = records[index]
		var zone: ZoneDefinition = inspection.zones[index]
		assert_eq(_canonical(Array(zone.bounds)), _canonical(record.bounds))
		assert_eq(_canonical(zone.camera_flags), _canonical(record.flags))
		assert_eq(_canonical(zone.camera_direction), _canonical(record.direction))
		var offsets: Array = []
		for offset: Vector3i in zone.camera_offsets:
			offsets.append([offset.x, offset.y, offset.z])
		assert_eq(_canonical(offsets), _canonical(record.offsets))
		var regions: Array = []
		for region: PackedInt32Array in zone.regions:
			regions.append(Array(region))
		assert_eq(_canonical(regions), _canonical(record.regions))
	var defaults: Dictionary = TerrainTrace.facts(inspection.definition)
	assert_eq(_canonical(defaults.source_offset), _canonical(first.source))
	assert_eq(_canonical(defaults.target_offset), _canonical(first.target))
	for tick: int in CameraZoneInspection.TICK_LIMIT:
		assert_eq(inspection.step(), "")
		var fixture: Dictionary = cases[0 if tick < 160 else 1]
		var expected: Dictionary = fixture.expected[tick % 160]
		var actual: Dictionary = inspection.row.camera
		actual["frog_zone"] = inspection.selected.x
		actual["frog_region"] = inspection.selected.y
		actual["mod_rotation"] = Array(inspection.camera.snapshot().mod_matrix12.slice(0, 9))
		for key: String in expected:
			if key != "entity_angle":
				assert_eq(_canonical(actual[key]), _canonical(expected[key]), "tick %d %s" % [tick, key])
	assert_eq(inspection.reset(), "")
	assert_eq(inspection.tick, 0)
	assert_eq(inspection.selected, Vector2i(-1, -1))
	assert_eq(inspection.camera.snapshot().zone_index, -1)
	assert_eq(inspection.camera.snapshot().twist_counter, 0)
	data.close()

func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

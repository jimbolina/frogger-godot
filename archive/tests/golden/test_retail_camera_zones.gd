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

func test_jun1_zone_lifecycle_matches_independent_reference() -> void:
	var data: GameData = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))
	var inspection: CameraZoneInspection = CameraZoneInspection.from_data(data, true)
	assert_eq(inspection.error, "")
	if not inspection.error.is_empty():
		data.close()
		return
	assert_eq(inspection.entity_definitions.size(), 11)
	assert_eq(inspection.diagnostics.size(), inspection.map_scene.map.entities.size() - 11)
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/pc-retail-v3.0e/zone_lifecycle.json"))
	var angle: int = 0
	for tick: int in 320:
		if tick == 160:
			angle = 0
		assert_eq(inspection.step(), "", "tick %d" % tick)
		var row: Dictionary = golden.cases[0 if tick < 160 else 1].expected[tick % 160]
		angle = (angle + inspection.camera.snapshot().entity_angle_delta) & 3
		assert_eq(ZoneLifecycleChecks.compare(row, inspection.camera.snapshot(), inspection.selected.x, inspection.selected.y,
			angle, inspection.world, inspection.entities.snapshot()), "", "tick %d" % tick)
		assert_eq(ZoneLifecycleChecks._integer(inspection.row.polygon_total), ZoneLifecycleChecks._integer(row.polygon_total))
	assert_eq(inspection.reset(), "")
	assert_true(inspection.entities.snapshot().live_order.is_empty())
	var form: FormBookEntry = data.tables.theme_book().get_form(inspection.map_scene.map.general.theme, inspection.entity_definitions[0].form_id)
	var saved_script: int = form.script_id
	form.script_id = 1
	assert_string_contains(Jun1ZoneLifecycleSetup.from_data(data, inspection.map_scene).error, "changed")
	form.script_id = saved_script
	assert_eq(Jun1ZoneLifecycleSetup.from_data(data, inspection.map_scene).error, "")
	var collision: EntityCollisionSetup = EntityCollisionSetup.from_map(inspection.map_scene.map, data.tables.theme_book(), {}, "JUN1", 656, data.version_name, false, true)
	assert_string_contains(collision.error, "without authored zones")
	data.close()

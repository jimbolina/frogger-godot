extends GutTest
## Shared comparison against independently generated frozen-C/Python camera facts.

func _integer(value: Variant) -> int:
	var number: float = value
	return int(number)

func _vector(value: Variant) -> Vector3i:
	var array: Array = value
	return Vector3i(_integer(array[0]), _integer(array[1]), _integer(array[2]))

func _zone_from_record(record: Dictionary, index: int) -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_index = index
	var bounds: Array = record.bounds
	zone.bounds = PackedInt32Array(bounds)
	zone.camera_flags = _integer(record.flags)
	zone.camera_direction = _integer(record.direction)
	for region: Array in record.regions:
		zone.regions.append(PackedInt32Array(region))
	for offset: Array in record.offsets:
		zone.camera_offsets.append(_vector(offset))
	return zone

func _check_corpus(path: String) -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var schema: String = parsed.schema
	assert_eq(schema, "camera-zones-v1")
	for fixture: Dictionary in parsed.cases:
		var definition := GameplayCameraDefinition.new()
		definition.source_offset = _vector(fixture.source)
		definition.target_offset = _vector(fixture.target)
		var startup: bool = fixture.startup
		var name_text: String = fixture.name
		var camera: GameplayCamera = GameplayCamera.create(definition, Vector3i.ZERO, startup)
		assert_eq(camera.error, "", name_text)
		assert_eq(camera.transition_attachment(PlatformMath.yaw(_integer(fixture.yaw)), PackedInt32Array(), false), "")
		var zones: Array[ZoneDefinition] = []
		var records: Array = fixture.zones
		for index: int in records.size():
			var record: Dictionary = records[index]
			zones.append(_zone_from_record(record, index))
		var selected := Vector2i(-1, -1)
		var entity_angle: int = 0
		var frames: Array = fixture.frames
		for tick: int in frames.size():
			var frame: Dictionary = fixture.frames[tick]
			selected = ZoneQueries.update_camera_match(zones, Vector2i(_integer(frame.cell[0]), _integer(frame.cell[1])), selected, ZoneQueries.NO_UPDATE if frame.freeze else 0)
			if frame.turn and camera.allows_manual_turn():
				assert_eq(camera.request_turn(_integer(frame.turn), selected.x >= 0), "", "%s/%d turn" % [fixture.name, tick])
			if frame.fixed:
				camera.request_fixed()
			var input := GameplayCameraTick.new()
			input.frog_world = _vector(frame.world)
			input.start_timer = _integer(frame.start_timer)
			input.camera_zone = ZoneQueries.definition_for(zones, selected.x)
			assert_eq(camera.step(input), "", "%s/%d step" % [fixture.name, tick])
			var snapshot: GameplayCameraSnapshot = camera.snapshot()
			entity_angle = (entity_angle + snapshot.entity_angle_delta) & 3
			var actual: Dictionary = TerrainTrace.facts(snapshot)
			actual["frog_zone"] = selected.x
			actual["frog_region"] = selected.y
			actual["entity_angle"] = entity_angle
			actual["mod_rotation"] = Array(snapshot.mod_matrix12.slice(0, 9))
			var expected: Dictionary = fixture.expected[tick]
			for key: String in expected:
				assert_eq(_canonical(actual[key]), _canonical(expected[key]), "%s/%d %s" % [fixture.name, tick, key])

func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

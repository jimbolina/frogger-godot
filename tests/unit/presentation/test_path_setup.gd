extends GutTest
## Detached setup and per-path rejection contracts.

func _map_with_paths() -> MapFile:
	var map := MapFile.new()
	var packet := MapPacket.new()
	packet.identifier = "PATH"
	packet.count = 2
	packet.offsets = PackedInt32Array([100, 200])
	map.packets["PATH"] = packet
	for i: int in 2:
		var path := MapPath.new()
		path.path_index = i
		path.source_offset = 100 + i * 100
		var segment := MapPathSegment.new()
		segment.segment_type = 2
		segment.length = 160
		segment.source_offset = path.source_offset + 12
		segment.start = Vector3i(0, 0, 0)
		segment.end = Vector3i(10, 0, 0)
		path.segments.append(segment)
		map.paths.append(path)
	return map

func test_setup_copies_source_identity_and_geometry() -> void:
	var map: MapFile = _map_with_paths()
	var setup: PathSetup = PathSetup.from_map(map, "SUB1", 123)
	assert_eq(setup.error, "")
	assert_eq(setup.diagnostics.size(), 0)
	assert_eq(setup.definitions.size(), 2)
	assert_eq(setup.definitions[0].source_id, "SUB1")
	assert_eq(setup.definitions[0].resource_id, 123)
	assert_eq(setup.definitions[1].path_index, 1)
	assert_eq(setup.definitions[1].source_offset, 200)
	map.paths[0].segments[0].length = 900
	map.paths[0].segments[0].end = Vector3i(900, 0, 0)
	assert_eq(setup.definitions[0].segments[0].length, 160)
	assert_eq(setup.definitions[0].segments[0].end, Vector3i(10, 0, 0))

func test_unknown_and_zero_length_reject_only_affected_paths() -> void:
	var map: MapFile = _map_with_paths()
	map.paths[0].segments[0].segment_type = 88
	var setup: PathSetup = PathSetup.from_map(map, "CAV2", 77, "pc-retail-v3.0e")
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 1)
	assert_eq(setup.definitions[0].path_index, 1)
	assert_eq(setup.diagnostics[0].code, "unknown_segment_type")
	assert_eq(setup.diagnostics[0].source_id, "CAV2")
	assert_eq(setup.diagnostics[0].resource_id, 77)
	assert_eq(setup.diagnostics[0].build_id, "pc-retail-v3.0e")
	assert_eq(setup.diagnostics[0].source_offset, 112)
	assert_string_contains(setup.diagnostics[0].to_text(), "segment 0")
	map.paths[0].segments[0].segment_type = 2
	map.paths[0].segments[0].length = 0
	setup = PathSetup.from_map(map)
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 1)
	assert_eq(setup.diagnostics[0].code, "invalid_geometry")

func test_structural_map_error_is_setup_error() -> void:
	var map: MapFile = _map_with_paths()
	map.error = "Broken packet"
	assert_string_contains(PathSetup.from_map(map).error, "Broken packet")
	map.error = ""
	map.packets["PATH"].count = 3
	assert_string_contains(PathSetup.from_map(map).error, "count")

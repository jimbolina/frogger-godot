extends RetailTest
## Guarded JUN1 bank/log route against independently generated frozen-C facts.

const ROUTE: String = "res://tests/golden/pc-retail-v3.0e/platform_jun1_route.tsv"
const FIXTURE: String = "res://tests/golden/fixtures/jun1_log_bank.json"

var _data: GameData

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func _fields(state: GameplayState) -> Dictionary[String, String]:
	if state.entities == null:
		return {}
	var pose: EntitySnapshot = null
	for entity: EntitySnapshot in state.entities.entities:
		if entity.entity_index == 24:
			pose = entity
			break
	if pose == null or pose.path == null:
		return {}
	var hits := PackedStringArray()
	for index: int in state.attachment.entity_hit_indices:
		hits.append(str(index))
	var camera_directions: PackedInt32Array = state.camera.controller_directions
	return {
		"x16": str(state.frog.position_16.x), "y16": str(state.frog.position_16.y), "z16": str(state.frog.position_16.z),
		"vx16": str(state.frog.velocity_16.x), "vy16": str(state.frog.velocity_16.y), "vz16": str(state.frog.velocity_16.z),
		"grid_x": str(state.frog.cell.x), "grid_z": str(state.frog.cell.y), "flags": str(state.frog.flags),
		"mode": str(state.frog.mode), "attached": str(state.attachment.current_entity_index),
		"count": str(state.frog.remaining_ticks), "direction": str(state.frog.direction),
		"input": str(state.frog.current_input), "entity_x": str(pose.matrix12[9]),
		"entity_y": str(pose.matrix12[10]), "entity_z": str(pose.matrix12[11]),
		"segment": str(pose.path.segment_index), "distance": str(pose.path.segment_distance),
		"camera_x": str(state.camera.tracked_world.x), "camera_y": str(state.camera.tracked_world.y),
		"camera_z": str(state.camera.tracked_world.z),
		"controller_n": str(camera_directions[0]), "controller_e": str(camera_directions[1]),
		"controller_s": str(camera_directions[2]), "controller_w": str(camera_directions[3]),
		"old_y": str(state.frog.old_y), "entity_cell_x": str(state.attachment.entity_cell.x),
		"entity_cell_z": str(state.attachment.entity_cell.y), "forbidden": str(state.attachment.forbidden_entity_index),
		"hit_indices": ";".join(hits) if not hits.is_empty() else "-",
	}

func test_guarded_jun1_bank_log_bank_phases_match_frozen_c() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(parsed is Dictionary)
	if not parsed is Dictionary:
		return
	var fixture: Dictionary = parsed
	var scenario: TerrainScenario = TerrainScenario.from_object(fixture)
	assert_eq(scenario.error, "")
	if not scenario.error.is_empty():
		return
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--exploration=jun1-log-bank",
		"--level=JUN1", "--data-dir=retail-fixture"])), "")
	assert_eq(scenario.attach_data(_data, "JUN1"), "")
	if scenario.level == null:
		return
	var run: GameplayRun = GameplayRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var lines: PackedStringArray = FileAccess.get_file_as_string(ROUTE).strip_edges().split("\n")
	assert_eq(lines.size(), 361)
	if lines.size() != 361:
		return
	var header: PackedStringArray = lines[0].trim_suffix("\r").split("\t")
	var columns: PackedStringArray = PackedStringArray(["x16", "y16", "z16", "vx16", "vy16", "vz16",
		"grid_x", "grid_z", "flags", "mode", "attached", "count", "direction", "input",
		"entity_x", "entity_y", "entity_z", "segment", "distance", "camera_x", "camera_y",
		"camera_z", "controller_n", "controller_e", "controller_s", "controller_w", "old_y",
		"entity_cell_x", "entity_cell_z", "forbidden", "hit_indices"])
	var phase_names: PackedStringArray = PackedStringArray(["control", "move", "collision", "camera", "scripts", "pose"])
	var row_index: int = 1
	for tick: int in 60:
		var result: TickResult = run.step(scenario.command_at(tick))
		assert_eq(result.error, "", "JUN1 command %d" % tick)
		if not result.error.is_empty():
			return
		var stages: Array[GameplayState] = [result.control_snapshot, result.move_snapshot,
			result.collision_snapshot, result.camera_snapshot, result.scripts_snapshot, result.final_snapshot]
		for phase: int in 6:
			var expected: PackedStringArray = lines[row_index].trim_suffix("\r").split("\t")
			assert_eq(expected.size(), header.size())
			assert_eq(int(expected[0]), tick)
			assert_eq(expected[1], phase_names[phase])
			var fields: Dictionary[String, String] = _fields(stages[phase])
			assert_false(fields.is_empty(), "JUN1 log24 pose at %d/%s" % [tick, phase_names[phase]])
			if fields.is_empty():
				return
			for name: String in columns:
				var column: int = header.find(name)
				assert_ne(column, -1, "Missing source column " + name)
				if column >= 0:
					assert_eq(fields[name], expected[column], "JUN1 %d/%s %s" % [tick, phase_names[phase], name])
			if phase == 5:
				var order := PackedStringArray()
				for reaction: FormReactionResult in result.entity_contacts:
					order.append(str(reaction.contact.entity_index))
				var order_column: int = header.find("supported_order")
				assert_ne(order_column, -1)
				if order_column >= 0:
					assert_eq(";".join(order) if not order.is_empty() else "-", expected[order_column],
						"JUN1 %d ordered eligible contact scan" % tick)
			row_index += 1
	assert_eq(row_index, lines.size(), "No unused frozen-C route rows")

func test_all_jun1_zone_records_and_source_queries_match() -> void:
	var problems := PackedStringArray()
	var map: MapFile = _data.read_map(656, problems)
	assert_not_null(map)
	if map == null:
		return
	var records: Array[PackedStringArray] = GoldenFiles.rows("jun1_zone_records.tsv")
	assert_eq(records.size(), 19)
	assert_eq(map.zones.size(), 18)
	if records.size() != 19 or map.zones.size() != 18:
		return
	var header: PackedStringArray = records[0]
	for column: int in header.size():
		header[column] = header[column].trim_suffix("\r")
	for index: int in 18:
		var zone: MapZone = map.zones[index]
		var expected: PackedStringArray = records[index + 1]
		assert_eq(expected.size(), header.size())
		var fields: Dictionary[String, String] = {
			"zone_index": str(zone.zone_index), "source_offset": str(zone.source_offset),
			"zone_type": str(zone.zone_type), "region_count": str(zone.regions.size()),
			"xmin": str(zone.bounds[0]), "zmin": str(zone.bounds[1]),
			"xmax": str(zone.bounds[2]), "zmax": str(zone.bounds[3]),
			"region_pointer": str(zone.region_pointer), "camera_flags": str(zone.camera_flags),
			"camera_direction": str(zone.camera_direction),
		}
		for vector_index: int in 8:
			var vector: Vector3i = zone.camera_offsets[vector_index]
			fields["camera_%d_x" % vector_index] = str(vector.x)
			fields["camera_%d_y" % vector_index] = str(vector.y)
			fields["camera_%d_z" % vector_index] = str(vector.z)
		var region_offsets := PackedStringArray()
		var region_bounds := PackedStringArray()
		for region: MapZoneRegion in zone.regions:
			region_offsets.append(str(region.source_offset))
			var numbers := PackedStringArray()
			for value: int in region.bounds:
				numbers.append(str(value))
			region_bounds.append(",".join(numbers))
		fields["region_offsets"] = ";".join(region_offsets) if not region_offsets.is_empty() else "-"
		fields["region_bounds"] = ";".join(region_bounds) if not region_bounds.is_empty() else "-"
		for column: int in header.size():
			assert_true(fields.has(header[column]), "Unmapped ZONE record field " + header[column])
			if fields.has(header[column]):
				assert_eq(fields[header[column]], expected[column].trim_suffix("\r"), "ZONE[%d] %s" % [index, header[column]])
	var setup: ZoneSetup = ZoneSetup.from_map(map, "pc-retail-v3.0e:JUN1", 656, "pc-retail-v3.0e")
	assert_eq(setup.error, "")
	if not setup.error.is_empty():
		return
	var queries: Array[PackedStringArray] = GoldenFiles.rows("jun1_zones.tsv")
	assert_eq(queries.size(), 3361)
	if queries.size() != 3361:
		return
	for query_index: int in range(1, queries.size()):
		var row: PackedStringArray = queries[query_index]
		var cell := Vector2i(int(row[1]), int(row[2]))
		var actual: int = ZoneQueries.first_camera_match(setup.definitions, cell) if int(row[3]) == 0 else -1
		assert_eq(actual, int(row[5]), "ZONE query %d at %s" % [query_index - 1, cell])
	assert_eq(problems.size(), 0, "\n".join(problems))

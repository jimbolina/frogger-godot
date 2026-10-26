extends GutTest
## Independent Python/frozen-C selector and lifecycle facts for invented entities.

const FIXTURE: String = "res://tests/golden/fixtures/lifecycle_visibility.json"
const TRACE: String = "res://tests/golden/synthetic/lifecycle_visibility.tsv"
const LINE_TRACE: String = "res://tests/golden/synthetic/lifecycle_mapview_lines.tsv"
const INTEGRATED_TRACE: String = "res://tests/golden/synthetic/lifecycle_integrated.tsv"

func _integer(value: Variant) -> int:
	var number: float = value
	return int(number)

func _vec(value: Variant) -> Vector3i:
	var values: Array = value
	return Vector3i(_integer(values[0]), _integer(values[1]), _integer(values[2]))

func _camera(raw: Dictionary) -> GameplayCameraSnapshot:
	var camera := GameplayCameraSnapshot.new()
	var source: Array = raw["source"]
	var axes: Array = raw["axes"]
	camera.source_world = _vec(source)
	camera.axis_x_12 = _vec(axes[0])
	camera.axis_y_12 = _vec(axes[1])
	camera.axis_z_12 = _vec(axes[2])
	return camera

func _joined(numbers: PackedInt32Array) -> String:
	if numbers.is_empty():
		return "-"
	var parts := PackedStringArray()
	for number: int in numbers:
		parts.append(str(number))
	return ",".join(parts)

func _events(events: Array[String]) -> String:
	return ",".join(events) if not events.is_empty() else "-"

func _definition(raw: Dictionary) -> EntityDefinition:
	var entity := EntityDefinition.new()
	entity.source_id = "synthetic"
	entity.entity_index = _integer(raw["entity_index"])
	entity.unique_id = _integer(raw["unique_id"])
	entity.entity_name = str(raw["entity_name"])
	entity.behavior = EntityBehaviorCatalog.resolve(entity.entity_name)
	entity.matrix12 = PackedInt32Array([4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0])
	if entity.behavior.kind == EntityBehavior.Kind.STATIC:
		var position: Array = raw["position"]
		entity.matrix12[9] = _integer(position[0])
		entity.matrix12[10] = _integer(position[1])
		entity.matrix12[11] = _integer(position[2])
	else:
		var path_raw: Dictionary = raw["path"]
		var path := PathDefinition.new()
		path.source_id = "synthetic"
		path.path_index = 0
		var segment := PathSegmentDefinition.new()
		segment.segment_type = 2
		segment.length = _integer(path_raw["length"])
		segment.start = _vec(path_raw["start"])
		segment.end = _vec(path_raw["end"])
		path.segments.append(segment)
		entity.path_definition = path
		var start := PathStart.new()
		start.segment_index = 0
		start.distance = _integer(path_raw["initial_distance"])
		start.speed = _integer(path_raw["speed"])
		start.flags = _integer(path_raw["flags"])
		entity.path_start = start
	return entity

func test_frozen_selector_and_component_lifecycle() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(parsed is Dictionary)
	if not parsed is Dictionary:
		return
	var fixture: Dictionary = parsed
	var group_raw: Dictionary = fixture["groups"]
	var lifecycle := EntityLifecycleDefinition.new()
	lifecycle.group_base = _vec(group_raw["base"])
	var dimensions: Array = group_raw["dimensions"]
	lifecycle.group_dimensions = Vector2i(_integer(dimensions[0]), _integer(dimensions[1]))
	var sizes: Array = group_raw["size"]
	lifecycle.group_size = Vector2i(_integer(sizes[0]), _integer(sizes[1]))
	for _index: int in lifecycle.group_dimensions.x * lifecycle.group_dimensions.y:
		lifecycle.polygon_counts.append(1)
	var definitions: Array[EntityDefinition] = []
	var authored_entities: Array = fixture["entities"]
	for item: Variant in authored_entities:
		var raw: Dictionary = item
		definitions.append(_definition(raw))
	var run: EntityRun = EntityRun.create(definitions, lifecycle)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var lines: PackedStringArray = FileAccess.get_file_as_string(TRACE).strip_edges().split("\n")
	assert_eq(lines.size(), 11)
	for row_index: int in range(1, lines.size()):
		var fields: PackedStringArray = lines[row_index].strip_edges().split("\t")
		var camera_name: String = fields[2]
		var camera_raw: Dictionary
		if fields[0] == "component":
			camera_raw = fixture["cameras"][camera_name]
		else:
			camera_raw = fixture["selector_cases"][camera_name]
		var camera: GameplayCameraSnapshot = _camera(camera_raw)
		var selection: MapGroupVisibilityResult = MapGroupVisibility.query(lifecycle, camera)
		assert_eq(selection.error, "", camera_name)
		assert_eq(_joined(selection.groups), fields[3], camera_name)
		assert_eq(selection.polygon_total, fields[4].to_int(), camera_name)
		if fields[0] != "component":
			continue
		var tick: int = fields[1].to_int()
		if tick > 0:
			var schedule: Array = fixture["component_schedule"][tick]
			assert_eq(run.step(tick - 1, _integer(schedule[2])), "", "step %d" % tick)
			assert_eq(run.apply_visibility(camera), "", "visibility %d" % tick)
		var state: EntityRunSnapshot = run.snapshot()
		assert_eq(_joined(state.selected_groups), fields[3] if tick > 0 else "-", "tick %d selected" % tick)
		assert_eq(_joined(state.live_order), fields[11], "tick %d live order" % tick)
		assert_eq(_events(TickEvent.trace_lines(state.lifecycle_events)), fields[12], "tick %d events" % tick)
		for slot: int in state.entities.size():
			var entity: EntitySnapshot = state.entities[slot]
			var offset: int = 5 if entity.entity_index == 2 else 8
			assert_eq(int(entity.live), fields[offset].to_int(), "tick %d live %d" % [tick, entity.entity_index])
			assert_eq(int(entity.destroy_pending), fields[offset + 1].to_int(), "tick %d pending %d" % [tick, entity.entity_index])
			assert_eq(entity.generation, fields[offset + 2].to_int(), "tick %d generation %d" % [tick, entity.entity_index])
			if entity.entity_index == 9:
				assert_eq(entity.path.segment_distance, fields[13].to_int(), "tick %d path" % tick)

func test_signed_and_short_delta_source_raster_lines() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(parsed is Dictionary)
	if not parsed is Dictionary:
		return
	var fixture: Dictionary = parsed
	var cases: Dictionary = fixture["line_cases"]
	var rows: PackedStringArray = FileAccess.get_file_as_string(LINE_TRACE).strip_edges().split("\n")
	assert_eq(rows.size(), cases.size() + 1)
	for index: int in range(1, rows.size()):
		var fields: PackedStringArray = rows[index].split("\t")
		var values: Array = cases[fields[0]]
		var lifecycle := EntityLifecycleDefinition.new()
		lifecycle.group_dimensions = Vector2i(_integer(values[0]), _integer(values[1]))
		lifecycle.group_size = Vector2i(_integer(values[2]), _integer(values[3]))
		var row_min := PackedInt32Array()
		var row_max := PackedInt32Array()
		for _row: int in lifecycle.group_dimensions.y:
			row_min.append(2147483647)
			row_max.append(-2147483647)
		MapGroupVisibility._draw_line(Vector2i(_integer(values[4]), _integer(values[5])),
			Vector2i(_integer(values[6]), _integer(values[7])), lifecycle, row_min, row_max)
		var represented := PackedStringArray()
		for z: int in lifecycle.group_dimensions.y:
			if row_min[z] != 2147483647:
				represented.append("%d:%d:%d" % [z, row_min[z], row_max[z]])
		assert_eq(";".join(represented) if not represented.is_empty() else "-", fields[1], fields[0])

func test_integrated_visibility_transitions_follow_independent_oracle() -> void:
	var scenario: TerrainScenario = TerrainScenario.from_file("res://tests/golden/fixtures/lifecycle_integrated.json")
	assert_eq(scenario.error, "")
	assert_eq(TerrainScenarioArguments.apply(scenario, PackedStringArray(["--entity-reactions=platforms", "--entity-lifecycle=visibility"])), "")
	if not scenario.error.is_empty():
		return
	var run: TerrainRun = TerrainRun.create(scenario.level, scenario.initial)
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var rows: PackedStringArray = FileAccess.get_file_as_string(INTEGRATED_TRACE).strip_edges().split("\n")
	assert_eq(rows.size(), 337)
	for tick: int in 336:
		var result: TickResult = run.step(scenario.command_at(tick))
		assert_eq(result.error, "", "tick %d" % tick)
		if not result.error.is_empty():
			return
		var fields: PackedStringArray = rows[tick + 1].split("\t")
		var state: RunSnapshot = result.final_snapshot
		assert_eq(state.frog.world_position.x, fields[1].to_int(), "tick %d frog x" % tick)
		assert_eq(state.frog.world_position.y, fields[2].to_int(), "tick %d frog y" % tick)
		assert_eq(state.camera.source_world.x, fields[3].to_int(), "tick %d camera x" % tick)
		assert_eq(state.camera.source_world.y, fields[4].to_int(), "tick %d camera y" % tick)
		assert_eq(state.camera.source_world.z, fields[5].to_int(), "tick %d camera z" % tick)
		var entities: EntityRunSnapshot = state.entities
		assert_eq(_joined(entities.selected_groups), fields[6], "tick %d selected" % tick)
		assert_eq(_joined(entities.live_order), fields[14], "tick %d live order" % tick)
		assert_eq(_events(TickEvent.trace_lines(entities.lifecycle_events)), fields[15], "tick %d events" % tick)
		for entity: EntitySnapshot in entities.entities:
			var offset: int = 8 if entity.entity_index == 2 else 11
			assert_eq(int(entity.live), fields[offset].to_int(), "tick %d live %d" % [tick, entity.entity_index])
			assert_eq(int(entity.destroy_pending), fields[offset + 1].to_int(), "tick %d pending %d" % [tick, entity.entity_index])
			assert_eq(entity.generation, fields[offset + 2].to_int(), "tick %d gen %d" % [tick, entity.entity_index])
			if entity.entity_index == 9:
				assert_eq(entity.path.segment_distance, fields[16].to_int(), "tick %d path" % tick)

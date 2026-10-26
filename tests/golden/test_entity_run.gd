extends GutTest
## Generic entity transforms and cursors against independent Python and frozen C facts.

const ENTITY_FIXTURES: String = "res://tests/golden/fixtures/entities.json"
const PATH_FIXTURES: String = "res://tests/golden/fixtures/paths.json"
const TRACE: String = "res://tests/golden/synthetic/entities_trace.tsv"

func _integer(value: Variant) -> int:
	var number: float = value
	return int(number)

func _ints(source: Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	for value: Variant in source:
		result.append(_integer(value))
	return result

func _vec(source: Array) -> Vector3i:
	return Vector3i(_integer(source[0]), _integer(source[1]), _integer(source[2]))

func _path(raw: Dictionary) -> PathDefinition:
	var definition := PathDefinition.new()
	definition.source_id = "synthetic"
	definition.path_index = 0
	var segment_rows: Array = raw["segments"]
	for value: Variant in segment_rows:
		var segment_raw: Dictionary = value
		var segment := PathSegmentDefinition.new()
		segment.segment_type = _integer(segment_raw["segment_type"])
		segment.length = _integer(segment_raw["length"])
		if segment_raw.has("start"):
			var point: Array = segment_raw["start"]
			segment.start = _vec(point)
		if segment_raw.has("end"):
			var point: Array = segment_raw["end"]
			segment.end = _vec(point)
		if segment_raw.has("centre"):
			var point: Array = segment_raw["centre"]
			segment.centre = _vec(point)
		if segment_raw.has("normal"):
			var point: Array = segment_raw["normal"]
			segment.normal = _vec(point)
		segment.radius = _integer(segment_raw.get("radius", 0))
		segment.pitch = _integer(segment_raw.get("pitch", 0))
		if segment_raw.has("matrix"):
			var values: Array = segment_raw["matrix"]
			segment.matrix = _ints(values)
			values = segment_raw["smooth_t"]
			segment.smooth_t = _ints(values)
			values = segment_raw["smooth_c"]
			segment.smooth_c = _ints(values)
		definition.segments.append(segment)
	return definition

func _definition(raw: Dictionary, path_cases: Dictionary) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.source_id = "synthetic"
	definition.entity_index = _integer(raw["entity_index"])
	definition.unique_id = _integer(raw["unique_id"])
	definition.entity_name = str(raw["entity_name"])
	definition.behavior = EntityBehaviorCatalog.resolve(definition.entity_name)
	definition.flags = _integer(raw["flags"])
	if definition.behavior.kind == EntityBehavior.Kind.STATIC:
		var matrix: Array = raw["matrix12"]
		definition.matrix12 = _ints(matrix)
	else:
		var source: Dictionary = raw if raw.has("segments") else path_cases[str(raw["path_case"])]
		definition.path_definition = _path(source)
		var start_raw: Dictionary = raw["start"]
		var start := PathStart.new()
		start.segment_index = _integer(start_raw["segment_index"])
		start.distance = _integer(start_raw["distance"])
		start.speed = _integer(start_raw["speed"])
		start.flags = _integer(start_raw["flags"])
		definition.path_start = start
	return definition

func _fields(name: String, tick: int, entity: EntitySnapshot) -> PackedStringArray:
	var result := PackedStringArray([name, str(tick), str(entity.entity_index), str(entity.unique_id)])
	for value: int in entity.matrix12:
		result.append(str(value))
	if entity.path == null:
		for unused: int in 14:
			result.append("-1")
	else:
		var path: PathSnapshot = entity.path
		result.append_array(PackedStringArray([str(path.segment_index), str(path.segment_type),
			str(path.segment_distance), str(path.segment_length), str(path.segment_param),
			str(path.total_distance), str(path.speed), str(path.flags),
			str(path.position.x), str(path.position.y), str(path.position.z),
			str(path.tangent.x), str(path.tangent.y), str(path.tangent.z)]))
	return result

func test_source_ordered_entity_snapshots() -> void:
	var parsed_entities: Variant = JSON.parse_string(FileAccess.get_file_as_string(ENTITY_FIXTURES))
	var parsed_paths: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH_FIXTURES))
	assert_true(parsed_entities is Array)
	assert_true(parsed_paths is Array)
	if not parsed_entities is Array or not parsed_paths is Array:
		return
	var path_cases: Dictionary = {}
	for value: Variant in parsed_paths:
		var source: Dictionary = value
		path_cases[str(source["name"])] = source
	var lines: PackedStringArray = FileAccess.get_file_as_string(TRACE).split("\n", false)
	assert_true(lines.size() > 1)
	var at: int = 1
	for raw_case: Variant in parsed_entities:
		var case_data: Dictionary = raw_case
		var name: String = str(case_data["name"])
		var definitions: Array[EntityDefinition] = []
		var entities: Array = case_data["entities"]
		for raw_entity: Variant in entities:
			var entity_data: Dictionary = raw_entity
			definitions.append(_definition(entity_data, path_cases))
		var run: EntityRun = EntityRun.create(definitions)
		assert_eq(run.error, "", name)
		if not run.error.is_empty():
			continue
		var tick_limit: int = _integer(case_data["tick_limit"])
		for tick: int in tick_limit + 1:
			if tick > 0:
				var issue: String = run.step(tick - 1)
				assert_eq(issue, "", "%s tick %d" % [name, tick])
				if not issue.is_empty():
					break
			var snapshot: EntityRunSnapshot = run.snapshot()
			assert_eq(snapshot.tick_index, tick, name)
			assert_eq(snapshot.entities.size(), entities.size(), name)
			for entity: EntitySnapshot in snapshot.entities:
				assert_true(at < lines.size(), "Trace is shorter than fixtures")
				if at < lines.size():
					assert_eq(_fields(name, tick, entity), lines[at].split("\t"),
						"%s tick %d entity %d" % [name, tick, entity.entity_index])
				at += 1
	assert_eq(at, lines.size(), "Trace has no unused rows")

extends GutTest
## Full path-runner snapshots against independent Python and frozen C facts.

const FIXTURES: String = "res://tests/golden/fixtures/paths.json"
const TRACE: String = "res://tests/golden/synthetic/paths_trace.tsv"

func _number(value: Variant) -> int:
	var number: float = value
	return int(number)

func _ints(source: Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	for value: Variant in source:
		result.append(_number(value))
	return result

func _vec(source: Array) -> Vector3i:
	return Vector3i(_number(source[0]), _number(source[1]), _number(source[2]))

func _definition(case_data: Dictionary) -> PathDefinition:
	var definition := PathDefinition.new()
	definition.source_id = "synthetic"
	definition.path_index = 0
	for raw_value: Variant in case_data["segments"]:
		var raw: Dictionary = raw_value
		var segment := PathSegmentDefinition.new()
		segment.segment_type = _number(raw["segment_type"])
		segment.length = _number(raw["length"])
		if raw.has("start"):
			var values: Array = raw["start"]
			segment.start = _vec(values)
		if raw.has("end"):
			var values: Array = raw["end"]
			segment.end = _vec(values)
		if raw.has("centre"):
			var values: Array = raw["centre"]
			segment.centre = _vec(values)
		if raw.has("normal"):
			var values: Array = raw["normal"]
			segment.normal = _vec(values)
		segment.radius = _number(raw.get("radius", 0))
		segment.pitch = _number(raw.get("pitch", 0))
		if raw.has("matrix"):
			var matrix: Array = raw["matrix"]
			var smooth_t: Array = raw["smooth_t"]
			var smooth_c: Array = raw["smooth_c"]
			segment.matrix = _ints(matrix)
			segment.smooth_t = _ints(smooth_t)
			segment.smooth_c = _ints(smooth_c)
		definition.segments.append(segment)
	return definition

func _start(case_data: Dictionary) -> PathStart:
	var raw: Dictionary = case_data["start"]
	var result := PathStart.new()
	result.segment_index = _number(raw["segment_index"])
	result.distance = _number(raw["distance"])
	result.speed = _number(raw["speed"])
	result.flags = _number(raw["flags"])
	return result

func _fields(name: String, state: PathSnapshot) -> PackedStringArray:
	return PackedStringArray([name, str(state.tick_index), str(state.segment_index),
		str(state.segment_type), str(state.segment_distance), str(state.segment_length),
		str(state.segment_param), str(state.total_distance), str(state.speed), str(state.flags),
		str(state.position.x), str(state.position.y), str(state.position.z),
		str(state.tangent.x), str(state.tangent.y), str(state.tangent.z)])

func test_frozen_path_snapshots() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES))
	assert_true(parsed is Array)
	if not parsed is Array:
		return
	var lines: PackedStringArray = FileAccess.get_file_as_string(TRACE).split("\n", false)
	assert_true(lines.size() > 1)
	var at: int = 1
	for raw_case: Variant in parsed:
		var case_data: Dictionary = raw_case
		var name: String = str(case_data["name"])
		var runner: PathRunner = PathRunner.create(_definition(case_data), _start(case_data))
		assert_eq(runner.error, "", name)
		if not runner.error.is_empty():
			continue
		var tick_limit: int = _number(case_data["tick_limit"])
		for tick: int in tick_limit + 1:
			if tick > 0:
				var issue: String = runner.step(tick - 1)
				assert_eq(issue, "", "%s tick %d" % [name, tick])
				if not issue.is_empty():
					break
			assert_true(at < lines.size(), "Trace is shorter than fixtures")
			if at < lines.size():
				assert_eq(_fields(name, runner.snapshot()), lines[at].split("\t"),
					"%s tick %d" % [name, tick])
			at += 1
	assert_eq(at, lines.size(), "Trace has no unused rows")

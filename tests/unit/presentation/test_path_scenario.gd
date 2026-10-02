extends GutTest
## Asset-free authored path setup and complete trace transport tests.

func test_builtin_and_authored_types() -> void:
	for name: String in ["line", "arc", "spline"]:
		var scenario: PathScenario = PathScenario.builtin(name)
		assert_eq(scenario.error, "")
		assert_eq(PathRunner.create(scenario.definition, scenario.start).error, "")
	var object: Dictionary = {
		"name": "authored", "tick_limit": 2,
		"segments": [{"segment_type": 2, "length": 20, "start": [0, 0, 0], "end": [20, 0, 0]}],
		"start": {"segment_index": 0, "distance": 3, "speed": 4, "flags": 9}
	}
	var scenario: PathScenario = PathScenario.from_object(object)
	assert_eq(scenario.error, "")
	assert_eq(scenario.start.distance, 3)
	assert_eq(scenario.tick_limit, 2)
	object.segments[0].start[0] = 99
	assert_eq(scenario.definition.segments[0].start, Vector3i.ZERO)

func test_invalid_authored_values_are_reported() -> void:
	var object: Dictionary = {
		"name": "invalid", "segments": [{"segment_type": 2, "length": 20, "start": [0, 0, 0], "end": [20, 0, 0]}],
		"start": {"segment_index": 0, "distance": 0, "speed": 1, "flags": 9}
	}
	object.segments[0].length = 3.5
	assert_false(PathScenario.from_object(object).error.is_empty())
	object.segments[0].length = 20
	object.segments[0].start = [40000, 0, 0]
	assert_false(PathScenario.from_object(object).error.is_empty())
	object.segments[0].start = [0, 0, 0]
	object.start.flags = 128
	assert_false(PathScenario.from_object(object).error.is_empty())

func test_zero_tick_trace_carries_all_fields_and_blocks_checkout() -> void:
	var scenario: PathScenario = PathScenario.builtin("line")
	scenario.tick_limit = 0
	var run: PathRunner = PathRunner.create(scenario.definition, scenario.start)
	assert_eq(run.error, "")
	var trace := PathTrace.new()
	trace.configure(scenario)
	trace.append_snapshot(run.snapshot())
	assert_eq(trace.rows.size(), 2)
	var header: Dictionary = JSON.parse_string(trace.rows[0])
	var row: Dictionary = JSON.parse_string(trace.rows[1])
	var schema: String = header.get("schema")
	var limit: int = header.get("tick_limit")
	var tick: int = row.get("tick_index")
	assert_eq(schema, "path-run-v1")
	assert_eq(limit, 0)
	assert_eq(tick, 0)
	for field: String in ["segment_index", "segment_type", "segment_distance", "segment_length", "segment_param", "total_distance", "speed", "flags", "position", "tangent"]:
		assert_true(row.has(field), field)
	var forbidden: String = ProjectSettings.globalize_path("res://tests/path-trace.jsonl")
	assert_false(trace.save(forbidden).is_empty())

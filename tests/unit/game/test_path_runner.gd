extends GutTest
## Asset-free source path movement and ownership boundary tests.

func _line(length_value: int, x0: int, x1: int) -> PathSegmentDefinition:
	var segment := PathSegmentDefinition.new()
	segment.segment_type = PathSegmentDefinition.LINE
	segment.length = length_value
	segment.start = Vector3i(x0, 0, 0)
	segment.end = Vector3i(x1, 0, 0)
	return segment

func _path() -> PathDefinition:
	var definition := PathDefinition.new()
	definition.segments.append(_line(100, 0, 100))
	definition.segments.append(_line(100, 100, 200))
	return definition

func test_line_sample_and_boundary_transition() -> void:
	var definition: PathDefinition = _path()
	var initial := PathStart.new()
	initial.distance = 90
	initial.speed = 10
	var run: PathRunner = PathRunner.create(definition, initial)
	assert_eq(run.error, "")
	assert_eq(run.snapshot().tick_index, 0)
	assert_eq(run.snapshot().position, Vector3i(90, 0, 0))
	assert_eq(run.step(0), "")
	var state: PathSnapshot = run.snapshot()
	assert_eq(state.tick_index, 1)
	assert_eq(state.segment_index, 1)
	assert_eq(state.segment_distance, 0)
	assert_eq(state.total_distance, 100)
	assert_eq(state.position, Vector3i(100, 0, 0))
	assert_eq(state.tangent, Vector3i(4096, 0, 0))
	assert_eq(state.segment_param, 0)
	assert_eq(run.step(1), "")
	assert_eq(run.snapshot().position, Vector3i(110, 0, 0))

func test_backward_repeat_and_event_clear() -> void:
	var initial := PathStart.new()
	initial.distance = 5
	initial.speed = 10
	initial.flags = PathStart.ACTIVE | PathStart.REPEAT | PathStart.BACKWARDS
	var run: PathRunner = PathRunner.create(_path(), initial)
	assert_eq(run.error, "")
	assert_eq(run.step(0), "")
	var state: PathSnapshot = run.snapshot()
	assert_eq(state.segment_index, 1)
	assert_eq(state.segment_distance, 95)
	assert_eq(state.total_distance, 195)
	assert_true(bool(state.flags & PathStart.JUST_REPEATED_START))
	assert_eq(state.tangent, Vector3i(-4096, 0, 0))
	assert_eq(run.step(1), "")
	assert_false(bool(run.snapshot().flags & PathStart.JUST_CLEAR_MASK))

func test_one_shot_keeps_active_and_reports_each_hit() -> void:
	var initial := PathStart.new()
	initial.segment_index = 1
	initial.distance = 95
	initial.speed = 10
	initial.flags = PathStart.ACTIVE | PathStart.ONE_SHOT
	var run: PathRunner = PathRunner.create(_path(), initial)
	assert_eq(run.error, "")
	assert_eq(run.step(0), "")
	var state: PathSnapshot = run.snapshot()
	assert_eq(state.segment_distance, 100)
	assert_eq(state.total_distance, 200)
	assert_eq(state.position, Vector3i(200, 0, 0))
	assert_true(bool(state.flags & PathStart.ACTIVE))
	assert_true(bool(state.flags & PathStart.AT_END))
	assert_true(bool(state.flags & PathStart.JUST_HIT_END))
	assert_eq(run.step(1), "")
	assert_true(bool(run.snapshot().flags & PathStart.JUST_HIT_END))

func test_bounce_and_out_of_range_rollback() -> void:
	var initial := PathStart.new()
	initial.segment_index = 1
	initial.distance = 95
	initial.speed = 10
	initial.flags = PathStart.ACTIVE
	var run: PathRunner = PathRunner.create(_path(), initial)
	assert_eq(run.error, "")
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().segment_distance, 95)
	assert_eq(run.snapshot().total_distance, 195)
	assert_true(bool(run.snapshot().flags & PathStart.BACKWARDS))
	assert_true(bool(run.snapshot().flags & PathStart.JUST_BOUNCED_END))
	var before: PathSnapshot = run.snapshot()
	assert_false(run.step(3).is_empty())
	assert_eq(run.snapshot().tick_index, before.tick_index)
	assert_eq(run.snapshot().position, before.position)
	var fast := PathStart.new()
	fast.speed = 250
	var excessive: PathRunner = PathRunner.create(_path(), fast)
	assert_eq(excessive.error, "")
	assert_eq(excessive.step(0), "")
	assert_eq(excessive.snapshot().segment_index, 1)
	assert_eq(excessive.snapshot().segment_distance, 150)
	assert_eq(excessive.snapshot().position, Vector3i(250, 0, 0))

func test_reset_and_definition_are_detached() -> void:
	var definition: PathDefinition = _path()
	var run: PathRunner = PathRunner.create(definition)
	assert_eq(run.error, "")
	var fork: PathRunner = run.copy()
	definition.segments[0].end = Vector3i(1000, 0, 0)
	var state: PathSnapshot = run.snapshot()
	state.position = Vector3i(999, 999, 999)
	assert_eq(run.snapshot().position, Vector3i.ZERO)
	var bad := PathStart.new()
	bad.distance = 101
	assert_false(run.reset(bad).is_empty())
	assert_eq(run.snapshot().tick_index, 0)
	assert_eq(run.step(0), "")
	assert_eq(run.snapshot().position, Vector3i(16, 0, 0))
	assert_eq(fork.snapshot().tick_index, 0)
	assert_eq(fork.step(0), "")
	assert_eq(fork.snapshot().position, Vector3i(16, 0, 0))
	assert_eq(fork.reset(), "")
	assert_eq(fork.snapshot().position, Vector3i.ZERO)
	assert_eq(run.snapshot().position, Vector3i(16, 0, 0))

func test_evaluator_rejects_invalid_shapes_and_distance() -> void:
	var line: PathSegmentDefinition = _line(100, 0, 100)
	assert_eq(PathEvaluator.sample(line, -1).position, Vector3i(-1, 0, 0))
	line.end = line.start
	assert_eq(PathEvaluator.validate_segment(line), "")
	assert_eq(PathEvaluator.sample(line, 50).position, Vector3i.ZERO)
	assert_eq(PathEvaluator.sample(line, 50).tangent, Vector3i.ZERO)
	var spline := PathSegmentDefinition.new()
	spline.segment_type = PathSegmentDefinition.SPLINE
	spline.length = 100
	assert_false(PathEvaluator.validate_segment(spline).is_empty())
	var arc := PathSegmentDefinition.new()
	arc.segment_type = PathSegmentDefinition.ARC
	arc.length = 100
	assert_false(PathEvaluator.validate_segment(arc).is_empty())
	arc.radius = 10
	assert_eq(PathEvaluator.validate_segment(arc), "")
	assert_eq(PathEvaluator.sample(arc, 0).tangent, Vector3i.ZERO)

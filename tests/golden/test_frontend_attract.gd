extends GutTest
## AttractCycle and AttractTimer agree with the independent frozen-C attract facts in
## tests/golden/synthetic/frontend_attract.json (tools/golden/make_golden_attract.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_attract.json"
const StackLayoutTest := preload("res://tests/unit/game/frontend/test_stack_layout.gd")

var _document: Dictionary = {}


func before_all() -> void:
	_document = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))


static func _int(value: Variant) -> int:
	var number: float = value
	return int(number)


static func _rows(value: Variant) -> Array:
	var rows: Array = value
	return rows


static func _dict(value: Variant) -> Dictionary:
	var result: Dictionary = value
	return result


static func _text(value: Variant) -> String:
	var text: String = value
	return text


static func _flag(value: Variant) -> bool:
	var flag: bool = value
	return flag


static func _code(level: int) -> String:
	return "INTRO" if level == AttractCycle.INTRO else FroggerIds.level_code(level)


static func _phase(timer: AttractTimer) -> String:
	var names: Array = AttractTimer.Phase.keys()
	var name_text: String = names[timer.phase]
	return name_text


func _cycle() -> AttractCycle:
	var levels := PackedInt32Array()
	var gates := PackedInt32Array()
	for row: Variant in _rows(_document.table):
		var pair: Array = _rows(row)
		levels.append(_int(pair[0]))
		gates.append(_int(pair[1]))
	return AttractCycle.from_rows(levels, gates)


func _progress(open: Array) -> LevelProgress:
	var progress: LevelProgress = LevelProgress.create(StackLayoutTest.retail_stack())
	progress.arcade_flags.fill(0)
	for level: Variant in open:
		assert_true(progress.set_flags(_int(level), LevelProgress.SELECTABLE | LevelProgress.ZONE_ACCESSIBLE))
	return progress


func _append_run(runs: Array, value: String) -> void:
	if not runs.is_empty() and runs[-1][0] == value:
		runs[-1][1] += 1
	else:
		runs.append([value, 1])


func _runs(value: Variant) -> Array:
	var result: Array = []
	for run: Variant in _rows(value):
		var pair: Array = _rows(run)
		result.append([_text(pair[0]), _int(pair[1])])
	return result


func test_constants() -> void:
	var constants: Dictionary = _dict(_document.constants)
	assert_eq(AttractTimer.SCORE_TIME, _int(constants.score_time))
	assert_eq(AttractTimer.FLY_TIME, _int(constants.fly_time))
	assert_eq(AttractTimer.FADE_UNITS, _int(constants.fade_units))
	assert_eq(AttractTimer.DEMO_END_TICKS, _int(constants.demo_end_ticks))
	assert_eq(AttractTimer.LOADING_BRIGHTEN, _int(constants.loading_brighten))
	assert_eq(AttractTimer.MENU_SLIDE, _int(constants.menu_slide))


func test_table_rows() -> void:
	var cycle: AttractCycle = _cycle()
	var codes: Array = _rows(_document.table_codes)
	assert_eq(cycle.row_count(), codes.size())
	for index: int in codes.size():
		assert_eq(_code(cycle.level_at(index)), _text(codes[index]), "row %d" % index)


func test_fresh_boot_set_is_the_initial_progress() -> void:
	var fresh: LevelProgress = LevelProgress.create(StackLayoutTest.retail_stack())
	var open: Array = []
	for level: int in fresh.arcade_levels:
		if fresh.is_selectable(level):
			open.append(level)
	open.sort()
	var expected: Array = []
	for level: Variant in _rows(_dict(_dict(_document.cycles).fresh_boot).selectable):
		expected.append(_int(level))
	assert_eq(open, expected)


func test_cycles() -> void:
	var cycles: Dictionary = _dict(_document.cycles)
	for name: String in cycles:
		var entry: Dictionary = _dict(cycles[name])
		var progress: LevelProgress = _progress(_rows(entry.selectable))
		var cycle: AttractCycle = _cycle()
		assert_eq(_code(cycle.current_level()), _text(entry.first), "%s first demo" % name)
		var steps: Array = _rows(entry.steps)
		for index: int in steps.size():
			var step: Array = _rows(steps[index])
			var result: int = cycle.finish(progress)
			var label: String = "%s step %d" % [name, index + 1]
			assert_eq(_code(result), _text(step[0]), label)
			assert_eq(cycle.seen, _int(step[1]), label + " seen")
			assert_eq(_code(cycle.current_level()), _text(step[2]), label + " next demo")


func test_dwell_trace() -> void:
	var trace: Dictionary = _dict(_document.dwell_trace)
	var timer := AttractTimer.new()
	timer.start_dwell()
	var start: Dictionary = _dict(trace.start)
	assert_eq(_phase(timer), _text(start.phase))
	assert_eq(timer.score_time, _int(start.score_time))
	assert_eq(timer.fly_on, _int(start.fly_on))
	assert_eq(timer.fly_off, _int(start.fly_off))
	assert_eq(timer.menu_slide(), _int(start.menu_slide))
	timer.dwell_tick(false)
	var view_init: Dictionary = _dict(trace.view_init)
	assert_eq(_phase(timer), _text(view_init.phase), "VIEW_INIT falls through")
	assert_eq(timer.fly_on, _int(view_init.fly_on))
	assert_eq(timer.score_time, _int(view_init.score_time))
	assert_eq(timer.menu_slide(), _int(view_init.menu_slide))
	var samples: Dictionary = {}
	for sample: Variant in _rows(trace.view_main_samples):
		var row: Array = _rows(sample)
		samples[_int(row[0])] = row
	var phases: Array = []
	var calls: int = _int(trace.view_main_calls)
	assert_eq(calls, _int(_dict(_document.constants).view_main_calls))
	for call: int in range(1, calls + 1):
		timer.dwell_tick(false)
		_append_run(phases, _phase(timer))
		if samples.has(call):
			var row: Array = samples[call]
			var label: String = "VIEW_MAIN call %d" % call
			assert_eq(_phase(timer), _text(row[1]), label)
			assert_eq(timer.fly_on, _int(row[2]), label + " fly_on")
			assert_eq(timer.score_time, _int(row[3]), label + " score_time")
			assert_eq(timer.menu_slide(), _int(row[4]), label + " menu_slide")
	assert_eq(phases, _runs(trace.view_main_phases))
	var loading: Array = _rows(trace.loading)
	for index: int in loading.size():
		var row: Array = _rows(loading[index])
		var label: String = "LOADING call %d" % (index + 1)
		timer.loading_tick()
		assert_eq(timer.fly_off, _int(row[0]), label + " fly_off")
		assert_eq(timer.loading_brightness, _int(row[1]), label + " brightness")
		assert_eq(timer.loading_done(), _flag(row[2]), label + " done")
		assert_eq(timer.menu_slide(), _int(row[3]), label + " menu_slide")
	timer.start_demo()
	var frames: int = _int(trace.demo_frames)
	var first: Array = _rows(trace.playing_first)
	var playing: Array = []
	var demo_time: int = frames
	var call_count: int = 0
	while timer.phase == AttractTimer.Phase.PLAYING and call_count < frames:
		demo_time -= 1
		timer.demo_tick(demo_time)
		_append_run(playing, _phase(timer))
		if call_count < first.size():
			var row: Array = _rows(first[call_count])
			var label: String = "DEMO_MAIN call %d" % (call_count + 1)
			assert_eq(demo_time, _int(row[0]), label + " demo_time")
			assert_eq(timer.fly_on, _int(row[1]), label + " fly_on")
			assert_eq(timer.menu_slide(), _int(row[2]), label + " menu_slide")
		call_count += 1
	assert_eq(playing, _runs(trace.playing_phases))
	assert_eq(demo_time, _int(trace.switch_demo_time))
	var fade: Array = _rows(trace.fade)
	for index: int in fade.size():
		var row: Array = _rows(fade[index])
		var label: String = "FADE_OUT call %d" % (index + 1)
		timer.fade_tick()
		assert_eq(_phase(timer), _text(row[0]), label)
		assert_eq(timer.fly_off, _int(row[1]), label + " fly_off")
		assert_eq(timer.loading_brightness, _int(row[2]), label + " brightness")
		assert_eq(timer.fade_grey, _int(row[3]), label + " grey")
		assert_eq(timer.menu_slide(), _int(row[4]), label + " menu_slide")


func test_fire_gate() -> void:
	for gate: Variant in _rows(_document.fire_gate):
		var row: Array = _rows(gate)
		var timer := AttractTimer.new()
		timer.fly_on = _int(row[0])
		timer.fly_off = _int(row[1])
		assert_eq(timer.fire_allowed(_flag(row[2]), _flag(row[3])), _flag(row[4]), str(row))

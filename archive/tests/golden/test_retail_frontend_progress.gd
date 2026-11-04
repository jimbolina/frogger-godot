extends RetailTest
## Needs the retail files: unlock rules over the stack read from FROGGER.EXE match the
## independent facts in tests/golden/pc-retail-v3.0e/frontend_progress.tsv
## (tools/golden/make_golden_frontend.py, see tests/golden/specs/frontend.md).

var _data: GameData
var _stack: LevelStack
var _rows: Array[PackedStringArray] = []


func before_all() -> void:
	if not retail_skip_reason().is_empty():
		return
	var version: GameVersionConfig = FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e")
	_data = GameData.open(retail_source(), version)
	_stack = LevelProgressSetup.stack_from_table(_data.tables.level_select())
	_rows = GoldenFiles.rows("frontend_progress.tsv")


func after_all() -> void:
	if _data != null:
		_data.close()


func _kind(kind: String) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	for row: PackedStringArray in _rows:
		if row[0] == kind:
			result.append(row)
	return result


func _joined(values: PackedInt32Array) -> String:
	var parts: PackedStringArray = []
	for value: int in values:
		parts.append(str(value))
	return ",".join(parts)


func test_constants_and_initial_flags_match_select_level_init() -> void:
	var constants: Dictionary[String, int] = {}
	for row: PackedStringArray in _kind("constant"):
		constants[row[1]] = int(row[2])
	assert_eq(LevelProgress.COMPLETED, constants["COMPLETED"])
	assert_eq(LevelProgress.SELECTABLE, constants["SELECTABLE"])
	assert_eq(LevelProgress.ZONE_ACCESSIBLE, constants["ZONEACCESSIBLE"])
	assert_eq(LevelProgress.ALL_GOLD_FROGS, constants["ALL_GOLD_FROGS"])
	var progress: LevelProgress = LevelProgress.create(_stack)
	var initial: Array[PackedStringArray] = _kind("initial")
	assert_eq(initial.size(), _stack.arcade_count() + _stack.race_count())
	for row: PackedStringArray in initial:
		var position: int = int(row[2])
		var level: int = int(row[3])
		var listed: int = _stack.arcade_row(position).level if row[1] == "arcade" else _stack.race_row(position).level
		assert_eq(listed, level, "%s row %d holds %s" % [row[1], position, row[4]])
		assert_eq(progress.flags_of(level), int(row[5]), "%s starts with flags %s" % [row[4], row[5]])


func test_completing_every_level_in_stack_order() -> void:
	var progress: LevelProgress = LevelProgress.create(_stack)
	var steps: Array[PackedStringArray] = _kind("complete")
	assert_eq(steps.size(), _stack.arcade_count())
	for row: PackedStringArray in steps:
		var completion: LevelProgress.Completion = progress.complete_level(int(row[2]))
		assert_true(completion.found, "%s is on the arcade stack" % row[3])
		if completion.next_level != -1:
			progress.open_level_if_closed(completion.next_level)
		assert_eq(completion.next_level, int(row[4]), "%s is followed by %s" % [row[3], row[4]])
		assert_eq(_joined(progress.arcade_levels), row[5], "levels after %s" % row[3])
		assert_eq(_joined(progress.arcade_flags), row[6], "flags after %s" % row[3])
	for row: PackedStringArray in _kind("lookup"):
		assert_eq(progress.flags_of(int(row[1])), int(row[2]), "level %s reads its jungle row" % row[1])


func test_replaying_a_level_through_both_unlock_arms() -> void:
	var replays: Array[PackedStringArray] = _kind("replay")
	assert_eq(replays.size(), 2)
	for row: PackedStringArray in replays:
		var progress: LevelProgress = LevelProgress.create(_stack)
		var world: int = _stack.arcade_row(0).world
		var levels: PackedInt32Array = []
		for index: int in _stack.arcade_count():
			if _stack.arcade_row(index).world == world:
				levels.append(_stack.arcade_row(index).level)
		levels.append(int(row[2]))
		for level: int in levels:
			var completion: LevelProgress.Completion = progress.complete_level(level)
			if completion.next_level == -1:
				continue
			if row[1] == "countdown":
				progress.open_level(completion.next_level)
			else:
				progress.open_level_if_closed(completion.next_level)
		assert_eq(_joined(progress.arcade_flags), row[4], "%s arm replay" % row[1])


func test_gold_frogs_open_closed_worlds_in_stack_order() -> void:
	var progress: LevelProgress = LevelProgress.create(_stack)
	var steps: Array[PackedStringArray] = _kind("gold_frog")
	assert_gt(steps.size(), 0)
	for row: PackedStringArray in steps:
		var opened: int = progress.collect_gold_frog(int(row[2]))
		assert_eq(opened, int(row[4]), "gold frog %s of theme %s opens %s" % [row[1], row[2], row[4]])
		assert_eq(progress.gold_frogs, int(row[3]), "gold frog bits after step %s" % row[1])
		assert_eq(_joined(progress.arcade_flags), row[5], "flags after gold frog %s" % row[1])

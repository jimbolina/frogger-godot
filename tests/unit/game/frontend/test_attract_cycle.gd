extends GutTest
## The attract demo order against DEMO_FINISH (tempopt.c:1578-1614) over small tables.

const StackLayoutTest := preload("res://tests/unit/game/frontend/test_stack_layout.gd")
const I: int = AttractCycle.INTRO
const ORG1: int = 24
const SUB1: int = 48
const FOR1: int = 12
const SKY1: int = 42
const SKY3: int = 44
const CAV1: int = 0


func _progress(open: PackedInt32Array) -> LevelProgress:
	var progress: LevelProgress = LevelProgress.create(StackLayoutTest.retail_stack())
	progress.arcade_flags.fill(0)
	for level: int in open:
		progress.set_flags(level, LevelProgress.SELECTABLE | LevelProgress.ZONE_ACCESSIBLE)
	return progress


func test_empty_table_has_nothing_to_play() -> void:
	var cycle: AttractCycle = AttractCycle.from_rows(PackedInt32Array(), PackedInt32Array())
	assert_eq(cycle.row_count(), 0)
	assert_eq(cycle.current_level(), AttractCycle.NONE)
	assert_eq(cycle.finish(_progress([SUB1])), AttractCycle.NONE)


func test_terminator_ends_the_rows() -> void:
	var cycle: AttractCycle = AttractCycle.from_rows([SUB1, FOR1, -1, ORG1], [SUB1, FOR1, -1, ORG1])
	assert_eq(cycle.row_count(), 2)
	assert_eq(cycle.level_at(2), AttractCycle.NONE)


func test_first_row_plays_without_its_gate() -> void:
	var cycle: AttractCycle = AttractCycle.from_rows([SKY3, FOR1], [SKY1, FOR1])
	assert_eq(cycle.current_level(), SKY3, "Row 0 is the session's first demo, unchecked")


func test_closed_rows_are_skipped() -> void:
	var cycle: AttractCycle = AttractCycle.from_rows([SUB1, SKY3, CAV1, FOR1], [SUB1, SKY1, CAV1, FOR1])
	assert_eq(cycle.finish(_progress([SUB1, FOR1])), FOR1)
	assert_eq(cycle.seen, 3)
	assert_eq(cycle.current_level(), FOR1)


func test_wrap_to_row_zero_requests_the_intro() -> void:
	var cycle: AttractCycle = AttractCycle.from_rows([SUB1, FOR1], [SUB1, FOR1])
	var progress: LevelProgress = _progress([SUB1, FOR1])
	assert_eq(cycle.finish(progress), FOR1)
	assert_eq(cycle.finish(progress), I)
	assert_eq(cycle.seen, 0)
	assert_eq(cycle.current_level(), SUB1)


func test_wrap_past_a_closed_row_zero_does_not_request_the_intro() -> void:
	var cycle: AttractCycle = AttractCycle.from_rows([SKY3, FOR1, CAV1], [SKY1, FOR1, CAV1])
	var progress: LevelProgress = _progress([FOR1])
	assert_eq(cycle.finish(progress), FOR1)
	assert_eq(cycle.finish(progress), FOR1, "Row 0 is checked after a wrap and is closed")
	assert_eq(cycle.seen, 1)


func test_intro_row_positions_on_the_unchecked_row_after_it() -> void:
	var cycle: AttractCycle = AttractCycle.from_rows([SUB1, I, SKY3, FOR1], [SUB1, I, SKY1, FOR1])
	var progress: LevelProgress = _progress([SUB1, FOR1])
	assert_eq(cycle.finish(progress), I)
	assert_eq(cycle.seen, 2)
	assert_eq(cycle.current_level(), SKY3, "The row after a play-intro row is taken without its gate")
	assert_eq(cycle.finish(progress), FOR1)
	assert_eq(cycle.finish(progress), I)
	assert_eq(cycle.seen, 0)


func test_final_intro_row_wraps_to_row_zero() -> void:
	var cycle: AttractCycle = AttractCycle.from_rows([SUB1, FOR1, I], [SUB1, FOR1, I])
	cycle.seen = 1
	assert_eq(cycle.finish(_progress([SUB1, FOR1])), I)
	assert_eq(cycle.seen, 0)


func test_no_qualifying_row_returns_none() -> void:
	var cycle: AttractCycle = AttractCycle.from_rows([SUB1, SKY3, CAV1], [SUB1, SKY1, CAV1])
	assert_eq(cycle.finish(_progress([ORG1])), AttractCycle.NONE)
	assert_eq(cycle.seen, 0, "The position is kept")

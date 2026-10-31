extends GutTest
## The level-select tick machine against SelectLevelUpdate's rules (SELECT.C:1255-2647).

const StackLayoutTest := preload("res://tests/unit/game/frontend/test_stack_layout.gd")
const ORG1_ROW: int = 0
const SUB1_ROW: int = 5
const FOR1_ROW: int = 10
const VOL1_ROW: int = 12
const ORG1_CAMERA: int = -4032 - 0xf00
const SUB1_CAMERA: int = -3552 - 0xf00
const SPIN_SINES: PackedInt32Array = [-4096, -3895, -3312, -2405, -1261, 0, 1261, 2405, 3312, 3895, 4096]
const PANEL_XS: PackedInt32Array = [672, 666, 646, 616, 578, 536, 495, 457, 427, 407, 400]

var _progress: LevelProgress = null


func _selector(first_time: bool = true, glow: bool = true) -> StackSelector:
	var stack: LevelStack = StackLayoutTest.retail_stack()
	_progress = LevelProgress.create(stack)
	return StackSelector.create(StackLayout.create(stack), _progress, 24, first_time, PackedInt32Array(), glow)


func _idle() -> StackSelector.Buttons:
	return StackSelector.Buttons.new()


func _kinds(events: Array[StackSelector.Event]) -> Array[int]:
	var kinds: Array[int] = []
	for event: StackSelector.Event in events:
		kinds.append(event.kind)
	return kinds


func _run(selector: StackSelector, ticks: int, buttons: StackSelector.Buttons = null) -> Array[int]:
	var kinds: Array[int] = []
	for _tick: int in ticks:
		kinds.append_array(_kinds(selector.step(buttons if buttons != null else _idle())))
	return kinds


func _extend_and_open(selector: StackSelector) -> void:
	_run(selector, 8)
	selector.step(StackSelector.Buttons.new(false, false, true))
	_run(selector, 11)


func test_starts_on_the_given_level() -> void:
	var selector: StackSelector = _selector()
	assert_eq(selector.focused_row, ORG1_ROW)
	assert_eq(selector.focused_level(), 24)
	assert_eq(selector.camera_y, ORG1_CAMERA)
	assert_eq(selector.camera_flag, StackSelector.CAMERA_STATIONARY)
	assert_eq(selector.mode, StackSelector.Mode.SELECTING)
	assert_eq(selector.glow_value, 0xa0)
	assert_eq(selector.tint(ORG1_ROW), StackSelector.DARK_COLOUR, "SelectCreateMOF's tint before the first glow update")


func test_focused_row_slides_out_in_eight_ticks() -> void:
	var selector: StackSelector = _selector()
	var trace: PackedInt32Array = PackedInt32Array()
	for _tick: int in 9:
		selector.step(_idle())
		trace.append(selector.current_z(ORG1_ROW))
	assert_eq(trace, PackedInt32Array([-64, -128, -192, -256, -320, -384, -448, -480, -480]))
	assert_eq(selector.current_z(ORG1_ROW - 1), 0)
	assert_eq(selector.current_z(ORG1_ROW + 1), 0)


func test_go_needs_a_fully_extended_box() -> void:
	var selector: StackSelector = _selector()
	_run(selector, 6)
	var early: Array[StackSelector.Event] = selector.step(StackSelector.Buttons.new(false, false, true))
	assert_true(early.is_empty(), "The slide runs first, so current_z is -448 when GO is read")
	assert_eq(selector.mode, StackSelector.Mode.SELECTING)
	var events: Array[StackSelector.Event] = selector.step(StackSelector.Buttons.new(false, false, true))
	assert_eq(_kinds(events), [StackSelector.EventKind.HOP])
	assert_eq(selector.mode, StackSelector.Mode.SHOW_LEVEL_INFO)
	assert_eq(selector.spin_mode, StackSelector.SPIN_OUT)
	assert_eq(selector.spin_row, ORG1_ROW)
	assert_true(selector.spin_visible())


func test_a_tap_down_skips_locked_rows_and_stops_on_the_next_selectable() -> void:
	var selector: StackSelector = _selector()
	var first: Array[StackSelector.Event] = selector.step(StackSelector.Buttons.new(false, true))
	assert_eq(_kinds(first), [StackSelector.EventKind.HOP])
	assert_eq(selector.focused_row, SUB1_ROW, "ORG2-ORG5 are not selectable")
	assert_eq(selector.target_y, SUB1_CAMERA)
	assert_eq(selector.camera_y, ORG1_CAMERA, "The camera starts moving on the next tick")
	var velocities: PackedInt32Array = PackedInt32Array()
	var ticks: int = 0
	while selector.camera_flag != StackSelector.CAMERA_STATIONARY and ticks < 100:
		selector.step(_idle())
		velocities.append(selector.camera_velocity)
		ticks += 1
	assert_eq(ticks, 16, "480 units: 420 accelerating, then 56 per tick until crossing")
	assert_eq(velocities[0], 4)
	assert_eq(velocities[13], 56)
	assert_eq(velocities[14], 56)
	assert_eq(velocities[15], 0, "Velocity clears on the snap")
	assert_eq(selector.camera_y, SUB1_CAMERA, "The camera snaps back onto the target")
	assert_eq(selector.glow_value, StackSelector.DARK_COLOUR, "Reaching the target resets the glow")


func test_held_down_chains_through_selectable_rows() -> void:
	var selector: StackSelector = _selector()
	var down := StackSelector.Buttons.new(false, true)
	var hops: Array[int] = _run(selector, 17, down)
	assert_eq(hops, [StackSelector.EventKind.HOP], "Only the start of a move hops")
	assert_eq(selector.focused_row, FOR1_ROW, "Crossing SUB1 while held targets FOR1")
	assert_eq(selector.camera_flag, StackSelector.CAMERA_GOING_DOWN)
	assert_eq(selector.camera_velocity, StackSelector.CAMERA_MAX_VEL)
	_run(selector, 80, down)
	assert_eq(selector.focused_row, VOL1_ROW)
	assert_eq(selector.camera_flag, StackSelector.CAMERA_STATIONARY, "No selectable row below VOL1")
	assert_eq(selector.camera_y, -2560 - 0xf00)


func test_up_at_the_top_does_nothing_and_down_wins_over_up() -> void:
	var selector: StackSelector = _selector()
	selector.step(StackSelector.Buttons.new(true, true))
	assert_eq(selector.focused_row, SUB1_ROW, "Down is read before up")
	_run(selector, 40)
	var up := StackSelector.Buttons.new(true)
	_run(selector, 60, up)
	assert_eq(selector.focused_row, ORG1_ROW, "Held up returns to ORG1")
	assert_eq(selector.camera_y, ORG1_CAMERA)
	assert_true(selector.step(up).is_empty(), "Nothing above ORG1")
	assert_eq(selector.camera_flag, StackSelector.CAMERA_STATIONARY)


func test_back_only_while_first_time_and_stationary() -> void:
	var first: StackSelector = _selector(true)
	assert_eq(_kinds(first.step(StackSelector.Buttons.new(false, false, false, true))), [StackSelector.EventKind.BACK])
	assert_true(first.finished, "The page is left")
	assert_true(first.step(_idle()).is_empty())
	var later: StackSelector = _selector(false)
	assert_true(later.step(StackSelector.Buttons.new(false, false, false, true)).is_empty())
	var both: StackSelector = _selector(true)
	assert_true(both.step(StackSelector.Buttons.new(false, false, true, true)).is_empty(), "GO is read before back")


func test_spin_out_hold_and_back_in() -> void:
	var selector: StackSelector = _selector()
	_run(selector, 8)
	selector.step(StackSelector.Buttons.new(false, false, true))
	var sines: PackedInt32Array = PackedInt32Array()
	var panel: PackedInt32Array = PackedInt32Array()
	for _tick: int in 11:
		selector.step(StackSelector.Buttons.new(false, false, true, true))
		sines.append(selector.spin_sin)
		panel.append(selector.panel_x)
	assert_eq(sines, SPIN_SINES, "Half-sine ease over times 0..10; buttons are ignored while spinning")
	assert_eq(panel, PANEL_XS)
	assert_eq(selector.spin_mode, StackSelector.SPIN_HOLD)
	assert_eq(selector.spin_time, StackSelector.SPIN_TIME)
	assert_almost_eq(selector.spin_ease(), 1.0, 0.0001)
	assert_eq(_kinds(selector.step(StackSelector.Buttons.new(false, false, true, true))), [StackSelector.EventKind.HOP],
		"Back wins over GO and spins in")
	assert_eq(selector.spin_mode, StackSelector.SPIN_IN)
	var back_sines: PackedInt32Array = PackedInt32Array()
	for _tick: int in 11:
		selector.step(_idle())
		back_sines.append(selector.spin_sin)
	var reversed: PackedInt32Array = SPIN_SINES.duplicate()
	reversed.reverse()
	assert_eq(back_sines, reversed)
	assert_eq(selector.mode, StackSelector.Mode.SELECTING)
	assert_eq(selector.spin_time, -1)
	assert_false(selector.spin_visible())
	assert_eq(selector.current_z(ORG1_ROW), StackSelector.SLIDE_DIST, "The box stayed out")


func test_second_go_croaks_fades_and_enters_the_game() -> void:
	var selector: StackSelector = _selector(true)
	_extend_and_open(selector)
	assert_eq(_kinds(selector.step(StackSelector.Buttons.new(false, false, true))), [StackSelector.EventKind.CROAK])
	assert_eq(selector.mode, StackSelector.Mode.START_FADE)
	assert_false(selector.first_time, "Choosing a level ends the first-time period")
	var counts: PackedInt32Array = PackedInt32Array()
	for _tick: int in StackSelector.FADE_TICKS:
		assert_true(selector.step(_idle()).is_empty())
		counts.append(selector.fade_count)
	assert_eq(counts[0], 1)
	assert_eq(counts[31], 32)
	assert_eq(selector.fade_shade(), 255)
	var events: Array[StackSelector.Event] = selector.step(_idle())
	assert_eq(_kinds(events), [StackSelector.EventKind.ENTER_GAME])
	assert_eq(events[0].level, 24)
	assert_true(selector.finished)
	assert_eq(selector.mode, StackSelector.Mode.UPDATE_FADE)
	assert_true(selector.step(StackSelector.Buttons.new(false, false, true)).is_empty())
	assert_true(selector.spin_visible(), "The spun box stays up through the fade")


func test_enter_game_reports_the_rows_current_level() -> void:
	var stack: LevelStack = StackLayoutTest.retail_stack()
	_progress = LevelProgress.create(stack)
	_progress.rewrite_jungle_row()
	_progress.set_flags(19, LevelProgress.SELECTABLE | LevelProgress.ZONE_ACCESSIBLE)
	var selector: StackSelector = StackSelector.create(StackLayout.create(stack), _progress, 19, false)
	assert_eq(selector.focused_row, 32)
	_extend_and_open(selector)
	selector.step(StackSelector.Buttons.new(false, false, true))
	var kinds: Array[int] = []
	var level: int = -1
	for _tick: int in 40:
		for event: StackSelector.Event in selector.step(_idle()):
			kinds.append(event.kind)
			level = event.level
	assert_eq(kinds, [StackSelector.EventKind.ENTER_GAME])
	assert_eq(level, 19)


func test_glow_pulses_while_stationary() -> void:
	var selector: StackSelector = _selector()
	var values: PackedInt32Array = PackedInt32Array()
	for _tick: int in 14:
		selector.step(_idle())
		values.append(selector.glow_value)
	assert_eq(values, PackedInt32Array([0x90, 0x80, 0x70, 0x60, 0x50, 0x60, 0x70, 0x80, 0x90, 0xa0, 0xb0, 0xa0, 0x90, 0x80]),
		"Direction turns once the value is outside 0x60..0xa0")
	assert_eq(selector.tint(ORG1_ROW), 0x80, "The open level of the glowy theme takes the glow")
	assert_eq(selector.tint(ORG1_ROW + 1), StackSelector.DARK_COLOUR, "Zone-accessible but closed")
	assert_eq(selector.tint(SUB1_ROW), StackSelector.DARK_COLOUR, "SUB1 is open but of another theme")
	assert_eq(selector.tint(15), StackSelector.LIGHT_COLOUR, "Rows outside open zones are light")


func test_glow_falls_while_moving_and_completed_rows_are_light() -> void:
	var selector: StackSelector = _selector()
	_progress.set_flags(24, LevelProgress.COMPLETED | LevelProgress.SELECTABLE | LevelProgress.ZONE_ACCESSIBLE)
	selector.step(StackSelector.Buttons.new(false, true))
	var values: PackedInt32Array = PackedInt32Array()
	for _tick: int in 9:
		selector.step(_idle())
		values.append(selector.glow_value)
	assert_eq(values, PackedInt32Array([0x80, 0x70, 0x60, 0x50, 0x40, 0x30, 0x30, 0x30, 0x30]),
		"Forced down while moving and held once below 0x40")
	assert_eq(selector.glowy_row, 2, "The last row slid out further than the new focus wins, here ORG3 under the passing camera")
	assert_eq(selector.tint(ORG1_ROW), StackSelector.LIGHT_COLOUR)


func test_glow_disabled_keeps_creation_tints() -> void:
	var selector: StackSelector = _selector(true, false)
	_run(selector, 20)
	assert_eq(selector.glow_value, 0xa0)
	assert_eq(selector.tint(ORG1_ROW), StackSelector.DARK_COLOUR)
	assert_eq(selector.tint(15), StackSelector.DARK_COLOUR, "SelectCreateMOF only lights completed rows")
	assert_eq(StackSelector.creation_tint(LevelProgress.COMPLETED), StackSelector.LIGHT_COLOUR)


func test_find_target_and_creep_camera() -> void:
	var selector: StackSelector = _selector()
	assert_true(selector.find_target(1))
	assert_eq(selector.focused_row, SUB1_ROW)
	assert_eq(selector.target_y, SUB1_CAMERA)
	assert_eq(selector.camera_y, ORG1_CAMERA, "SelectFindTarget only aims the camera")
	assert_true(selector.creep_camera(20))
	assert_eq(selector.camera_y, ORG1_CAMERA + 20)
	for _tick: int in 30:
		selector.creep_camera(20)
	assert_eq(selector.camera_y, ORG1_CAMERA + 480, "the camera stops at or past the target")
	assert_false(selector.creep_camera(20))
	assert_true(selector.find_target(-1))
	assert_false(selector.find_target(-1), "nothing above ORIGINAL1")
	assert_eq(selector.focused_row, ORG1_ROW)


func test_spin_out_with_slide_out_and_spin_in() -> void:
	var selector: StackSelector = _selector()
	selector.update_slide()
	selector.spin_out(true)
	assert_eq(selector.current_z(ORG1_ROW), StackSelector.SLIDE_DIST)
	assert_eq(selector.mode, StackSelector.Mode.SHOW_LEVEL_INFO)
	assert_true(selector.spin_visible())
	for _tick: int in 11:
		assert_true(selector.advance_spin())
	assert_eq(selector.spin_mode, StackSelector.SPIN_HOLD)
	assert_false(selector.advance_spin(), "nothing moves while held")
	selector.spin_in()
	for _tick: int in 11:
		assert_true(selector.advance_spin())
	assert_eq(selector.mode, StackSelector.Mode.SELECTING)
	assert_false(selector.spin_visible())


func test_travel_pieces_match_a_held_down_tick() -> void:
	var selector: StackSelector = _selector()
	var reached: bool = selector.advance_camera(false)
	assert_true(reached, "a stationary camera has arrived")
	assert_true(selector.start_travel(1))
	assert_eq(selector.camera_flag, StackSelector.CAMERA_GOING_DOWN)
	assert_eq(selector.camera_acceleration, StackSelector.CAMERA_ACC)
	selector.continue_travel(false, false, false)
	assert_eq(selector.camera_flag, StackSelector.CAMERA_GOING_DOWN | StackSelector.CAMERA_STOPPING,
		"releasing DOWN stops at the next target")
	var glow: int = selector.glow_value
	while selector.camera_flag != StackSelector.CAMERA_STATIONARY:
		selector.update_slide()
		selector.continue_travel(false, false, selector.advance_camera(false))
	assert_eq(selector.camera_y, SUB1_CAMERA)
	assert_eq(selector.glow_value, glow, "the high-score view's copy leaves the glow")

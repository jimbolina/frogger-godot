extends GutTest
## The high-score view page machine against HSViewStartup and HSViewUpdate (HSView.c:633-1634).

const StackLayoutTest := preload("res://tests/unit/game/frontend/test_stack_layout.gd")
const FOR1: int = 12
const FOR1_ROW: int = 10
const JUNGLE_ROW: int = 32

var _progress: LevelProgress = null
var _water: MenuWater = null


func _tour(from_options: bool, automatic: bool, new_main: bool = false, flagged: PackedInt32Array = PackedInt32Array()) -> HighScoreTour:
	var stack: LevelStack = StackLayoutTest.retail_stack()
	_progress = LevelProgress.create(stack)
	_water = MenuWater.create(0)
	var flags := PackedByteArray()
	flags.resize(60)
	for level: int in flagged:
		flags[level] = 1
	var rows: Array[HighScoreRow] = [HighScoreRow.create("TIM", 250000)]
	return HighScoreTour.create(StackLayout.create(stack), _progress, rows, from_options, automatic, new_main, flags)


func _step(tour: HighScoreTour, held: int = 0, pressed: int = 0) -> Array[int]:
	var events: Array[int] = tour.tick(OptionsMenu.Buttons.new(held, pressed), _water)
	_water.advance()
	return events


func _run(tour: HighScoreTour, ticks: int, held: int = 0) -> Array[int]:
	var events: Array[int] = []
	for _tick: int in ticks:
		events.append_array(_step(tour, held))
	return events


func test_options_entry_opens_the_stack_at_original1() -> void:
	var tour: HighScoreTour = _tour(true, false)
	assert_eq(tour.operation, HighScoreTour.Operation.LEVEL_SELECT)
	assert_eq(tour.selector.focused_level(), HighScoreTour.LEVEL_ORIGINAL1)
	assert_true(tour.left_arrow_visible)
	assert_false(tour.right_arrow_visible)
	assert_true(tour.title_visible)
	assert_eq(tour.prompt, HighScoreTour.PROMPT_SELECT1)
	assert_eq(tour.counter, HighScoreTour.AFTER_INPUT_DURATION)
	assert_eq(tour.camera_mode, HighScoreTour.CameraMode.STATIC)


func test_table_after_entry_times_out_on_the_121st_tick() -> void:
	var tour: HighScoreTour = _tour(false, false)
	assert_eq(tour.operation, HighScoreTour.Operation.SCROLLY)
	assert_eq(tour.prompt, HighScoreTour.PROMPT_SKIP)
	assert_false(tour.right_arrow_visible)
	assert_eq(_run(tour, 120), [] as Array[int])
	assert_eq(tour.counter, 0)
	assert_eq(_step(tour), [HighScoreTour.EventKind.TIMEOUT] as Array[int])
	assert_eq(tour.request, HighScoreTour.Request.MAIN_MENU)
	assert_eq(tour.counter, 0xffffffff, "HSView_counter is unsigned and post-decremented")
	assert_eq(_step(tour), [] as Array[int], "nothing runs after a request")


func test_table_flies_on_and_triangle_after_entry_leaves() -> void:
	var tour: HighScoreTour = _tour(false, false)
	_run(tour, 3)
	assert_eq(tour.fly_on, 7)
	assert_eq(_step(tour, 0, OptionsMenu.Buttons.BACK), [HighScoreTour.EventKind.BACK] as Array[int])
	assert_eq(tour.request, HighScoreTour.Request.MAIN_MENU)
	assert_eq(tour.fly_on, 0, "OptionsCameraSnapToMain stops the fly-on")


func test_left_and_right_switch_views_from_options() -> void:
	var tour: HighScoreTour = _tour(true, false)
	_run(tour, 2)
	assert_eq(_step(tour, 0, OptionsMenu.Buttons.LEFT),
		[HighScoreTour.EventKind.HOP, HighScoreTour.EventKind.SWITCHED] as Array[int])
	assert_eq(tour.operation, HighScoreTour.Operation.SCROLLY)
	assert_true(tour.prompt_is_back)
	assert_true(tour.right_arrow_visible)
	assert_false(tour.left_arrow_visible)
	assert_eq(tour.fly_on, HighScoreScene.FLY_TIME)
	assert_eq(_step(tour, 0, OptionsMenu.Buttons.LEFT), [] as Array[int], "LEFT does nothing on the table")
	assert_eq(_step(tour, 0, OptionsMenu.Buttons.RIGHT),
		[HighScoreTour.EventKind.HOP, HighScoreTour.EventKind.SWITCHED] as Array[int])
	assert_eq(tour.operation, HighScoreTour.Operation.LEVEL_SELECT)
	assert_eq(tour.selector.focused_level(), HighScoreTour.LEVEL_ORIGINAL1)
	assert_eq(tour.selector.current_z(0), 0, "the stack restarts")
	assert_eq(tour.request, HighScoreTour.Request.NONE)


func test_back_from_the_table_returns_to_options() -> void:
	var tour: HighScoreTour = _tour(true, false)
	_step(tour, 0, OptionsMenu.Buttons.LEFT)
	assert_eq(_step(tour, 0, OptionsMenu.Buttons.BACK),
		[HighScoreTour.EventKind.CROAK, HighScoreTour.EventKind.BACK_TO_OPTIONS] as Array[int])
	assert_eq(tour.request, HighScoreTour.Request.OPTIONS)
	assert_false(tour.right_arrow_visible)


func test_manual_stack_hops_croaks_and_spins() -> void:
	var tour: HighScoreTour = _tour(true, false)
	assert_eq(_step(tour, OptionsMenu.Buttons.UP),
		[HighScoreTour.EventKind.HOP, HighScoreTour.EventKind.CROAK] as Array[int], "nothing above ORIGINAL1")
	assert_eq(_step(tour, 0, OptionsMenu.Buttons.FIRE), [] as Array[int], "the box is not fully out yet")
	_run(tour, 8)
	assert_eq(_step(tour, 0, OptionsMenu.Buttons.FIRE),
		[HighScoreTour.EventKind.CROAK, HighScoreTour.EventKind.SPIN_OUT] as Array[int])
	assert_eq(tour.shown_level, HighScoreTour.LEVEL_ORIGINAL1)
	assert_true(tour.prompt_is_back)
	_run(tour, 11)
	assert_eq(tour.selector.spin_mode, StackSelector.SPIN_HOLD)
	assert_eq(_step(tour, 0, OptionsMenu.Buttons.BACK),
		[HighScoreTour.EventKind.CROAK, HighScoreTour.EventKind.SPIN_IN] as Array[int])
	_run(tour, 11)
	assert_eq(tour.selector.mode, StackSelector.Mode.SELECTING)
	assert_eq(tour.shown_level, -1)
	assert_eq(tour.prompt, HighScoreTour.PROMPT_SELECT1)
	assert_eq(_step(tour, 0, OptionsMenu.Buttons.BACK),
		[HighScoreTour.EventKind.CROAK, HighScoreTour.EventKind.BACK_TO_OPTIONS] as Array[int])
	assert_eq(tour.request, HighScoreTour.Request.OPTIONS)


func test_held_down_hops_once_then_travels() -> void:
	var tour: HighScoreTour = _tour(true, false)
	assert_eq(_step(tour, OptionsMenu.Buttons.DOWN), [HighScoreTour.EventKind.HOP] as Array[int])
	assert_eq(tour.selector.camera_flag, StackSelector.CAMERA_GOING_DOWN)
	assert_eq(tour.selector.focused_level(), 48, "SUB1 is the next selectable row")
	assert_eq(_step(tour, OptionsMenu.Buttons.DOWN), [] as Array[int])
	assert_eq(_step(tour, OptionsMenu.Buttons.DOWN, OptionsMenu.Buttons.BACK), [] as Array[int],
		"BACK is read only while stationary")


func test_tour_spins_original1_first_for_its_multiplayer_flag() -> void:
	var tour: HighScoreTour = _tour(false, true, false, PackedInt32Array([HighScoreTour.LEVEL_ORIGINAL_MULTI_PLAYER]))
	assert_false(tour.title_visible)
	assert_eq(_step(tour), [HighScoreTour.EventKind.CROAK, HighScoreTour.EventKind.SPIN_OUT] as Array[int])
	assert_eq(tour.shown_level, HighScoreTour.LEVEL_ORIGINAL1)
	assert_eq(tour.selector.current_z(0), StackSelector.SLIDE_DIST, "the row is set fully out")
	assert_eq(tour.counter, HighScoreTour.LEVEL_DURATION)
	assert_eq(tour.background_counter, HighScoreTour.BACKGROUND_PERIOD >> 1)
	assert_eq(_run(tour, 11), [] as Array[int])
	assert_eq(_run(tour, 90), [] as Array[int], "the table is held for the counter's 91 checks")
	assert_eq(_step(tour), [HighScoreTour.EventKind.CROAK, HighScoreTour.EventKind.SPIN_IN] as Array[int])
	_run(tour, 11)
	assert_eq(tour.selector.mode, StackSelector.Mode.SELECTING)
	assert_eq(_step(tour), [HighScoreTour.EventKind.TIMEOUT] as Array[int], "no other flags: main menu")
	assert_eq(tour.request, HighScoreTour.Request.MAIN_MENU)


func test_tour_creeps_to_a_flagged_level_and_waits_ten_ticks() -> void:
	var tour: HighScoreTour = _tour(false, true, true, PackedInt32Array([FOR1]))
	assert_eq(_step(tour), [] as Array[int])
	assert_true(tour.picked)
	assert_eq(tour.selector.focused_row, FOR1_ROW)
	var start: int = tour.selector.camera_y
	var distance: int = tour.selector.target_y - start
	var creep: int = (distance + HighScoreTour.CREEP_STEP - 1) / HighScoreTour.CREEP_STEP
	assert_eq(_run(tour, creep), [] as Array[int])
	assert_eq(tour.selector.camera_y, start + creep * HighScoreTour.CREEP_STEP)
	assert_eq(_run(tour, HighScoreTour.TOUR_WAIT - 1), [] as Array[int])
	assert_eq(tour.tour_wait, HighScoreTour.TOUR_WAIT - 1)
	assert_eq(_step(tour), [HighScoreTour.EventKind.CROAK, HighScoreTour.EventKind.SPIN_OUT] as Array[int])
	assert_eq(tour.shown_level, FOR1)
	assert_eq(tour.tour_wait, 0)
	_run(tour, 11 + 91 + 11)
	assert_eq(_step(tour), [HighScoreTour.EventKind.SWITCHED] as Array[int], "a new main score shows the table")
	assert_eq(tour.operation, HighScoreTour.Operation.SCROLLY)
	assert_false(tour.automatic)
	assert_eq(tour.prompt, HighScoreTour.PROMPT_SKIP)
	assert_eq(tour.counter, HighScoreTour.AFTER_INPUT_DURATION)


func test_a_switch_on_the_tick_of_back_restarts_the_page() -> void:
	var tour: HighScoreTour = _tour(false, true, true)
	assert_eq(_step(tour, 0, OptionsMenu.Buttons.BACK), [HighScoreTour.EventKind.SWITCHED] as Array[int],
		"the switch's request is written after BACK's")
	assert_eq(tour.request, HighScoreTour.Request.NONE)
	assert_eq(tour.operation, HighScoreTour.Operation.SCROLLY)
	assert_true(_step(tour, 0, OptionsMenu.Buttons.BACK).has(HighScoreTour.EventKind.BACK))
	assert_eq(tour.request, HighScoreTour.Request.MAIN_MENU)


func test_rewritten_jungle_row_uses_the_jungle1_flag() -> void:
	var tour: HighScoreTour = _tour(false, true, false, PackedInt32Array([LevelProgress.LEVEL_JUNGLE1]))
	_progress.arcade_levels[JUNGLE_ROW] = LevelProgress.LEVEL_JUNGLE2
	_progress.arcade_flags[JUNGLE_ROW] = LevelProgress.SELECTABLE
	_step(tour)
	assert_true(tour.picked)
	assert_eq(tour.selector.focused_row, JUNGLE_ROW)


func test_arrow_glow_and_prompt_position() -> void:
	assert_eq(HighScoreTour.arrow_glow(0), 0)
	assert_eq(HighScoreTour.arrow_glow(1), 0x10)
	assert_eq(HighScoreTour.arrow_glow(15), 0xf0)
	assert_eq(HighScoreTour.arrow_glow(16), 0, "the shifted count wraps in the colour byte")
	var tour: HighScoreTour = _tour(true, false)
	assert_eq(tour.prompt_x(100), 460)
	_step(tour, 0, OptionsMenu.Buttons.LEFT)
	assert_eq(tour.prompt_x(100), 444)

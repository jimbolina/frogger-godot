extends GutTest
## The main-menu dwell and demo phases against MainOptionsUpdate (tempopt.c:1333-1685).


func _dwell(immediate: bool = false) -> AttractTimer:
	var timer := AttractTimer.new()
	timer.start_dwell(immediate)
	return timer


func _ticks_until_exit(timer: AttractTimer, delayed: bool = false, limit: int = 2000) -> int:
	for call: int in limit:
		if timer.dwell_tick(delayed) != AttractTimer.Phase.DWELL:
			return call + 1
	return -1


func test_dwell_lasts_the_init_call_and_819_view_main_calls() -> void:
	var timer: AttractTimer = _dwell()
	assert_eq(timer.score_time, AttractTimer.SCORE_TIME)
	assert_eq(timer.fly_on, AttractTimer.FLY_TIME)
	assert_eq(_ticks_until_exit(timer), 820)
	assert_eq(timer.phase, AttractTimer.Phase.LOADING)
	assert_eq(timer.fly_off, AttractTimer.FLY_TIME)
	assert_eq(timer.fly_on, 0)
	assert_eq(timer.loading_brightness, 0)
	assert_eq(timer.score_time, 0, "The port does not wrap the unsigned count-down")


func test_immediate_dwell_waits_for_the_fly_on() -> void:
	assert_eq(_ticks_until_exit(_dwell(true)), 10)


func test_delayed_request_holds_the_count_down() -> void:
	var timer: AttractTimer = _dwell()
	for _call: int in 20:
		timer.dwell_tick(true)
	assert_eq(timer.score_time, AttractTimer.SCORE_TIME, "The conjunction stops before score_time--")
	assert_eq(timer.phase, AttractTimer.Phase.DWELL)
	assert_eq(_ticks_until_exit(timer), 811)


func test_dwell_fly_off_slides_down_without_counting() -> void:
	var timer: AttractTimer = _dwell()
	for _call: int in 10:
		timer.dwell_tick(false)
	timer.fly_off = 4
	assert_eq(timer.menu_slide(), 48)
	timer.dwell_tick(false)
	assert_eq(timer.fly_off, 3)
	assert_eq(timer.score_time, AttractTimer.SCORE_TIME - 1)


func test_loading_brightens_while_flying_off_and_then_waits() -> void:
	var timer: AttractTimer = _dwell(true)
	_ticks_until_exit(timer)
	for call: int in 10:
		assert_false(timer.loading_done())
		timer.loading_tick()
		assert_eq(timer.loading_brightness, 16 * (call + 1))
	assert_true(timer.loading_done())
	assert_eq(timer.menu_slide(), 80)
	timer.loading_tick()
	assert_eq(timer.fly_off, 0, "The counter does not run below zero")
	assert_eq(timer.loading_brightness, 160)


func test_brightness_clamps_at_255() -> void:
	var timer: AttractTimer = _dwell(true)
	_ticks_until_exit(timer)
	timer.loading_brightness = 250
	timer.loading_tick()
	assert_eq(timer.loading_brightness, 255)


func test_demo_flies_the_menu_on_and_latches_the_end() -> void:
	var timer := AttractTimer.new()
	timer.start_demo()
	assert_eq(timer.menu_slide(), 80)
	assert_eq(timer.demo_tick(40), AttractTimer.Phase.PLAYING)
	assert_eq(timer.fly_on, 9)
	assert_eq(timer.demo_tick(32), AttractTimer.Phase.PLAYING)
	assert_eq(timer.demo_tick(29), AttractTimer.Phase.FADE_OUT, "A skipped 30 still ends the demo")
	assert_eq(timer.count_down_units, AttractTimer.FADE_UNITS)
	assert_eq(timer.fly_off, AttractTimer.FLY_TIME)
	assert_eq(timer.fly_on, 0)
	assert_eq(timer.demo_tick(100), AttractTimer.Phase.FADE_OUT, "Once fading, demo ticks change nothing")
	assert_eq(timer.count_down_units, AttractTimer.FADE_UNITS)


func test_short_demo_ends_on_its_first_tick() -> void:
	var timer := AttractTimer.new()
	timer.start_demo()
	assert_eq(timer.demo_tick(0), AttractTimer.Phase.FADE_OUT)


func test_fade_reaches_black_after_thirty_calls() -> void:
	var timer := AttractTimer.new()
	timer.start_demo()
	timer.demo_tick(30)
	for _call: int in 29:
		assert_eq(timer.fade_tick(), AttractTimer.Phase.FADE_OUT)
	assert_eq(timer.fade_grey, 246)
	assert_eq(timer.fade_tick(), AttractTimer.Phase.FINISHED)
	assert_eq(timer.fade_grey, 255)
	assert_eq(timer.loading_brightness, 160)
	assert_eq(timer.menu_slide(), 80)
	assert_eq(timer.fade_tick(), AttractTimer.Phase.FINISHED)


func test_fire_needs_both_counters_clear() -> void:
	var timer: AttractTimer = _dwell()
	assert_false(timer.fire_allowed(false, false))
	for _call: int in 10:
		timer.dwell_tick(false)
	assert_true(timer.fire_allowed(false, false))
	assert_false(timer.fire_allowed(true, false))
	assert_false(timer.fire_allowed(false, true))

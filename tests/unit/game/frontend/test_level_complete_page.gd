extends GutTest
## The level-complete page machine against LevelCompleteStartup and LevelCompleteUpdate
## (tempopt.c:5792-6067).

const CHECKPOINT_TICKS: PackedInt32Array = [30, 31, 2971, 0, 60]


func _page(variant: LevelCompletePage.Kind) -> LevelCompletePage:
	return LevelCompletePage.create(variant, 7, CHECKPOINT_TICKS, 1850, false)


func _run(page: LevelCompletePage, updates: int) -> int:
	var event: int = -1
	for _update: int in updates:
		event = page.tick(false, false)
	return event


func test_create_rounds_checkpoint_seconds_up_and_sums_them() -> void:
	var page: LevelCompletePage = LevelCompletePage.create(LevelCompletePage.Kind.NEXT_LEVEL, 7, CHECKPOINT_TICKS, 1850, true)
	assert_eq(page.checkpoint_seconds, PackedInt32Array([1, 2, 99, 0, 2]))
	assert_eq(page.total_seconds, 104)
	assert_eq(page.level_score, 1850)
	assert_eq(page.next_level, 7)
	assert_true(page.show_gold_frog)
	assert_eq(page.units, LevelCompletePage.START_UNITS)
	assert_eq(page.ticks, LevelCompletePage.UNIT_TICKS)
	assert_eq(page.frame, 0)
	assert_false(page.press_fire_visible)
	assert_false(page.finished())


func test_missing_checkpoints_count_zero() -> void:
	var page: LevelCompletePage = LevelCompletePage.create(LevelCompletePage.Kind.STATISTICS, -1, PackedInt32Array([45]), 0, false)
	assert_eq(page.checkpoint_seconds, PackedInt32Array([2, 0, 0, 0, 0]))
	assert_eq(page.total_seconds, 2)


func test_startup_sound_and_music_pause_belong_to_next_level_only() -> void:
	var next: LevelCompletePage = _page(LevelCompletePage.Kind.NEXT_LEVEL)
	assert_eq(next.startup_sounds(), PackedInt32Array([LevelCompletePage.SOUND_LEVEL_COMPLETE]))
	assert_true(next.pauses_music())
	for variant: LevelCompletePage.Kind in [LevelCompletePage.Kind.ZONE_COMPLETE, LevelCompletePage.Kind.STATISTICS]:
		var page: LevelCompletePage = _page(variant)
		assert_eq(page.startup_sounds(), PackedInt32Array())
		assert_false(page.pauses_music())


func test_units_fall_every_31_updates_down_to_17() -> void:
	var page: LevelCompletePage = _page(LevelCompletePage.Kind.NEXT_LEVEL)
	_run(page, 30)
	assert_eq(page.units, 20)
	assert_eq(page.ticks, 1)
	_run(page, 1)
	assert_eq(page.units, 19, "update 31")
	assert_eq(page.ticks, LevelCompletePage.UNIT_TICKS)
	_run(page, 31)
	assert_eq(page.units, 18, "update 62")
	_run(page, 31)
	assert_eq(page.units, 17, "update 93")
	_run(page, 31)
	assert_eq(page.frame, 124)
	assert_eq(page.units, 17, "units stop at 17")
	assert_eq(page.ticks, 0)
	_run(page, 1)
	assert_eq(page.ticks, 4294967295, "the MR_ULONG countdown wraps")
	assert_eq(page.units, 17)


func test_idle_page_never_times_out() -> void:
	for variant: LevelCompletePage.Kind in [LevelCompletePage.Kind.NEXT_LEVEL, LevelCompletePage.Kind.ZONE_COMPLETE, LevelCompletePage.Kind.STATISTICS]:
		var page: LevelCompletePage = _page(variant)
		assert_eq(_run(page, 10000), -1)
		assert_false(page.finished())
		assert_eq(page.units, 17)


func test_fire_is_ignored_until_units_fall_below_19() -> void:
	var page: LevelCompletePage = _page(LevelCompletePage.Kind.NEXT_LEVEL)
	_run(page, 60)
	assert_false(page.accepts_fire())
	assert_eq(page.tick(true, false), -1, "update 61")
	assert_eq(page.sounds, PackedInt32Array())
	assert_eq(page.units, 19)
	assert_eq(page.tick(true, false), FrontEndFlow.Event.NEXT_LEVEL, "update 62 croaks and leaves")
	assert_eq(page.sounds, PackedInt32Array([LevelCompletePage.SOUND_CROAK]))
	assert_eq(page.units, 0)
	assert_eq(page.ticks, 0)
	assert_true(page.finished())


func test_fire_on_zone_complete_leaves_with_zone_complete() -> void:
	var page: LevelCompletePage = _page(LevelCompletePage.Kind.ZONE_COMPLETE)
	_run(page, 61)
	assert_false(page.accepts_fire(), "update 61 still gates fire")
	assert_eq(page.tick(true, false), FrontEndFlow.Event.ZONE_COMPLETE, "the 62nd update reads fire")
	assert_eq(page.units, 0)
	assert_eq(page.sounds, PackedInt32Array([LevelCompletePage.SOUND_CROAK]))


func test_back_leaves_at_once() -> void:
	for variant: LevelCompletePage.Kind in [LevelCompletePage.Kind.NEXT_LEVEL, LevelCompletePage.Kind.ZONE_COMPLETE]:
		var page: LevelCompletePage = _page(variant)
		assert_eq(page.tick(false, true), FrontEndFlow.Event.BACK, "update 1")
		assert_eq(page.sounds, PackedInt32Array())
		assert_true(page.finished())


func test_fire_and_back_together_croak_then_leave_with_back() -> void:
	var page: LevelCompletePage = _page(LevelCompletePage.Kind.NEXT_LEVEL)
	_run(page, 61)
	assert_eq(page.tick(true, true), FrontEndFlow.Event.BACK)
	assert_eq(page.sounds, PackedInt32Array([LevelCompletePage.SOUND_CROAK]))
	assert_eq(page.units, 0)


func test_press_fire_hidden_until_update_62_then_blinks_on_frame_bit_16() -> void:
	var page: LevelCompletePage = _page(LevelCompletePage.Kind.NEXT_LEVEL)
	for update: int in range(1, 62):
		page.tick(false, false)
		assert_false(page.press_fire_visible, "update %d" % update)
	for update: int in range(62, 300):
		page.tick(false, false)
		assert_eq(page.press_fire_visible, (update & 16) == 0, "update %d" % update)
	var at_62: LevelCompletePage = _page(LevelCompletePage.Kind.ZONE_COMPLETE)
	_run(at_62, 62)
	assert_false(at_62.press_fire_visible, "62 has bit 16 set")
	_run(at_62, 2)
	assert_true(at_62.press_fire_visible, "64 clears bit 16")


func test_statistics_ignores_keys_and_never_prompts() -> void:
	var page: LevelCompletePage = _page(LevelCompletePage.Kind.STATISTICS)
	assert_false(page.shows_prompt())
	for _update: int in 300:
		assert_eq(page.tick(true, true), -1)
		assert_false(page.press_fire_visible)
		assert_false(page.accepts_fire())
		assert_eq(page.sounds, PackedInt32Array())
	assert_eq(page.units, 17)
	assert_false(page.finished())


func test_ticks_after_an_exit_change_nothing() -> void:
	var page: LevelCompletePage = _page(LevelCompletePage.Kind.NEXT_LEVEL)
	_run(page, 61)
	page.tick(true, false)
	var frame: int = page.frame
	var visible: bool = page.press_fire_visible
	for _update: int in 50:
		assert_eq(page.tick(true, true), FrontEndFlow.Event.NEXT_LEVEL)
	assert_eq(page.frame, frame)
	assert_eq(page.units, 0)
	assert_eq(page.ticks, 0)
	assert_eq(page.press_fire_visible, visible)
	assert_eq(page.sounds, PackedInt32Array([LevelCompletePage.SOUND_CROAK]))
	assert_eq(page.exit_event, FrontEndFlow.Event.NEXT_LEVEL)

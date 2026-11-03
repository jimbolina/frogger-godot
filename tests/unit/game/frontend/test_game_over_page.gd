extends GutTest
## The game-over page machine against GameOverStartup and GameOverUpdate (tempopt.c:4057-4175,
## FROGGER.EXE 0x00443630 and 0x00443700).


func _run(page: GameOverPage, updates: int, fire: bool = false) -> int:
	var event: int = -1
	for _update: int in updates:
		event = page.tick(fire)
	return event


func test_create_sets_the_startup_countdown_and_shrink() -> void:
	var page: GameOverPage = GameOverPage.create(false)
	assert_eq(page.units, 165)
	assert_eq(page.shrink_steps, 41)
	assert_eq(page.width_step, 11)
	assert_eq(page.view_width, 640)
	assert_eq(page.view_height, 480)
	assert_eq(page.sprite_grey, 0)
	assert_eq(page.frame, 0)
	assert_false(page.quit)
	assert_false(page.finished())
	assert_false(page.overlay_visible())
	assert_eq(page.exit_event, -1)
	assert_true(GameOverPage.create(true).quit)


func test_startup_plays_track_22_mutes_effects_and_hides_the_hud() -> void:
	var page: GameOverPage = GameOverPage.create(false)
	assert_eq(page.startup_track(), 22)
	assert_true(page.mutes_effects())
	assert_true(page.hides_hud())
	assert_eq(GameOverPage.IMAGE, "opt_gameover")
	assert_eq(GameOverPage.FIRE_UNITS, 90)


func test_predelay_changes_nothing_but_the_countdown() -> void:
	var page: GameOverPage = GameOverPage.create(false)
	assert_eq(_run(page, 30, true), -1)
	assert_eq(page.frame, 30)
	assert_eq(page.units, 135)
	assert_eq(page.view_rect(), Rect2i(0, 0, 640, 480))
	assert_eq(page.sprite_grey, 0)
	assert_false(page.overlay_visible())
	assert_eq(page.sounds, PackedInt32Array())


func test_shrink_and_sprite_grey_follow_retail() -> void:
	var page: GameOverPage = GameOverPage.create(false)
	_run(page, 31)
	assert_eq(page.units, 134)
	assert_true(page.overlay_visible())
	assert_eq(page.view_rect(), Rect2i(5, 4, 629, 471), "tick 31")
	assert_eq(page.sprite_grey, 4)
	_run(page, 14)
	assert_eq(page.units, 120)
	assert_eq(page.view_width, 640 - 15 * 11, "tick 45")
	assert_eq(page.view_height, 480 * 475 / 640)
	assert_eq(page.sprite_grey, (15 * 255 / 30) >> 1)
	_run(page, 15)
	assert_eq(page.units, 105)
	assert_eq(page.view_rect(), Rect2i(165, 124, 310, 232), "tick 60")
	assert_eq(page.sprite_grey, 127)
	_run(page, 28)
	assert_eq(page.view_width, 2, "tick 88")
	_run(page, 1)
	assert_eq(page.units, 76)
	assert_eq(page.view_rect(), Rect2i(320, 240, 0, 0), "tick 89")
	assert_eq(page.sprite_grey, 127)
	_run(page, 10)
	assert_eq(page.view_rect(), Rect2i(320, 240, 0, 0))


func test_fire_is_ignored_until_units_fall_below_90() -> void:
	var page: GameOverPage = GameOverPage.create(false)
	assert_eq(_run(page, 74), -1)
	assert_false(page.accepts_fire())
	assert_eq(page.tick(true), -1, "tick 75, units 90")
	assert_eq(page.units, 90)
	assert_eq(page.sounds, PackedInt32Array())
	assert_false(page.finished())
	assert_eq(page.tick(true), FrontEndFlow.Event.GAME_OVER_DONE, "tick 76, units 89")
	assert_eq(page.units, 89)
	assert_eq(page.sounds, PackedInt32Array([GameOverPage.SOUND_CROAK]))
	assert_true(page.finished())
	assert_false(page.accepts_fire())


func test_fire_during_the_predelay_and_early_page_is_ignored() -> void:
	var page: GameOverPage = GameOverPage.create(true)
	assert_eq(_run(page, 75, true), -1)
	assert_eq(page.units, 90)
	assert_false(page.accepts_fire())
	assert_eq(page.tick(true), FrontEndFlow.Event.GAME_OVER_DONE, "the update reaching 89 reads fire")
	assert_true(page.quit)


func test_idle_page_leaves_when_units_reach_zero() -> void:
	var page: GameOverPage = GameOverPage.create(false)
	assert_eq(_run(page, 164), -1)
	assert_eq(page.units, 1)
	assert_eq(page.tick(false), FrontEndFlow.Event.GAME_OVER_DONE)
	assert_eq(page.frame, 165)
	assert_eq(page.units, 0)
	assert_eq(page.sounds, PackedInt32Array())


func test_ticks_after_an_exit_change_nothing() -> void:
	var page: GameOverPage = GameOverPage.create(false)
	_run(page, 75)
	page.tick(true)
	var units: int = page.units
	var frame: int = page.frame
	var rect: Rect2i = page.view_rect()
	var grey: int = page.sprite_grey
	assert_eq(_run(page, 200, true), FrontEndFlow.Event.GAME_OVER_DONE)
	assert_eq(page.units, units)
	assert_eq(page.frame, frame)
	assert_eq(page.view_rect(), rect)
	assert_eq(page.sprite_grey, grey)
	assert_eq(page.sounds, PackedInt32Array([GameOverPage.SOUND_CROAK]))

extends GutTest
## The game-over view masks the 640x480 canvas around the page's game viewport and centres the
## opt_gameover sprite, brightening it with the page's grey once the predelay is over.


func test_the_full_canvas_needs_no_mask() -> void:
	assert_eq(GameOverView.mask_rects(Rect2i(0, 0, 640, 480)), [] as Array[Rect2i])


func test_a_centred_viewport_leaves_four_bands() -> void:
	var view := Rect2i(165, 124, 310, 232)
	var expected: Array[Rect2i] = [
		Rect2i(0, 0, 640, 124),
		Rect2i(0, 356, 640, 124),
		Rect2i(0, 124, 165, 232),
		Rect2i(475, 124, 165, 232),
	]
	assert_eq(GameOverView.mask_rects(view), expected)


func test_an_empty_viewport_masks_the_whole_canvas() -> void:
	var whole: Array[Rect2i] = [Rect2i(0, 0, 640, 480)]
	assert_eq(GameOverView.mask_rects(Rect2i()), whole)
	assert_eq(GameOverView.mask_rects(Rect2i(320, 240, 0, 0)), whole)


func test_the_page_rects_tile_the_canvas() -> void:
	var page: GameOverPage = GameOverPage.create(false)
	for tick: int in GameOverPage.DURATION + GameOverPage.PREDELAY:
		page.tick(false)
		var view: Rect2i = page.view_rect()
		var area: int = view.get_area()
		for band: Rect2i in GameOverView.mask_rects(view):
			assert_true(not view.has_area() or not band.intersects(view), "tick %d" % page.frame)
			area += band.get_area()
		assert_eq(area, 640 * 480, "tick %d" % page.frame)


func test_the_sprite_is_centred_on_the_canvas() -> void:
	assert_eq(GameOverView.sprite_position(Vector2(256, 64)), Vector2(192, 208))
	assert_eq(GameOverView.sprite_position(Vector2(201, 33)), Vector2(219, 223), "odd sizes round down")


func test_the_brightest_grey_is_just_below_the_image_colours() -> void:
	var value: float = 0x7F / 128.0
	assert_eq(PauseView.glow_modulate(0x7F), Color(value, value, value))
	assert_eq(PauseView.glow_modulate(0), Color(0, 0, 0))


func test_the_view_follows_the_page_and_keeps_the_last_mask_when_finished() -> void:
	var view := GameOverView.new()
	add_child_autofree(view)
	view.size = Vector2(640, 480)
	assert_false(view.visible)
	var page: GameOverPage = GameOverPage.create(false)
	view.open(page)
	assert_true(view.visible)
	assert_eq(view.view_rect(), Rect2i(0, 0, 640, 480))
	assert_false(view.shows_sprite(), "the predelay hides the sprite")
	for tick: int in 40:
		page.tick(false)
	view.present(page)
	assert_true(view.shows_sprite())
	assert_eq(view.view_rect(), page.view_rect())
	view.queue_redraw()
	await wait_process_frames(1)
	view.finish()
	assert_true(view.visible)
	assert_false(view.shows_sprite())
	assert_eq(view.view_rect(), page.view_rect(), "the mask stays")
	view.close()
	assert_false(view.visible)
	assert_eq(view.view_rect(), Rect2i(0, 0, 640, 480))

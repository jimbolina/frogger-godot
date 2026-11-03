extends GutTest
## The level-complete view veils the map in translucent grey; without assets it draws only the
## overlay. The imported suite's test_level_complete_view_imported.gd draws the sprites.


func _view() -> LevelCompleteView:
	var view := LevelCompleteView.new()
	add_child_autofree(view)
	view.size = Vector2(1280, 960)
	return view


func test_the_overlay_is_the_psx_average_of_grey_0x60() -> void:
	assert_eq(LevelCompleteView.OVERLAY_COLOUR, Color(0x60 / 255.0, 0x60 / 255.0, 0x60 / 255.0, 0.5))


func test_without_assets_only_the_overlay_draws() -> void:
	var view: LevelCompleteView = _view()
	assert_false(view.visible, "hidden until opened")
	assert_eq(view.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	view.configure(null, null)
	var page: LevelCompletePage = LevelCompletePage.create(LevelCompletePage.Kind.NEXT_LEVEL, 3, PackedInt32Array(), 0, true)
	page.press_fire_visible = true
	view.open(page)
	assert_true(view.visible)
	assert_gt(view.drawn_sprites().size(), 0)
	for sprite: LevelCompleteLayout.Sprite in view.drawn_sprites():
		assert_null(view.texture_for(sprite.image), sprite.image)
		assert_eq(view.retail_size_of(sprite.image), Vector2.ZERO, sprite.image)
	for width: int in view.widths().values():
		assert_eq(width, 0)
	view.present(page)
	await get_tree().process_frame
	view.close()
	assert_false(view.visible)
	assert_eq(view.drawn_sprites().size(), 0)

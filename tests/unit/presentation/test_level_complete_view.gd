extends GutTest
## The level-complete view veils the map in translucent grey and draws every sprite of the page at
## its retail size from the HUD and front-end images, the next level's name from its in-game image,
## in English and localised.

const LOCALISED: Dictionary[String, String] = {
	"next": "next_g", "select4": "select4_g", "zone_complete": "zone_complete_g",
	"press_fire": "press_fire_g", "opt_sec": "optg_sec",
}

var _data: ImportedAssets


func before_all() -> void:
	_data = ImportedAssets.open()


func _view() -> LevelCompleteView:
	var view := LevelCompleteView.new()
	add_child_autofree(view)
	view.size = Vector2(1280, 960)
	return view


func _next_level() -> int:
	return _data.tables.level_select().arcade[1].level


func _page(variant: LevelCompletePage.Kind) -> LevelCompletePage:
	var next_level: int = _next_level() if variant == LevelCompletePage.Kind.NEXT_LEVEL else -1
	var page: LevelCompletePage = LevelCompletePage.create(variant, next_level, PackedInt32Array([300, 600, 900, 1200, 1500]), 12345, true)
	page.press_fire_visible = true
	return page


func _images(view: LevelCompleteView) -> PackedStringArray:
	var names := PackedStringArray()
	for sprite: LevelCompleteLayout.Sprite in view.drawn_sprites():
		names.append(sprite.image)
	return names


func _assert_every_sprite_resolves(view: LevelCompleteView, page: LevelCompletePage) -> void:
	view.open(page)
	var sprites: Array[LevelCompleteLayout.Sprite] = view.drawn_sprites()
	assert_gt(sprites.size(), 0)
	for sprite: LevelCompleteLayout.Sprite in sprites:
		var texture: Texture2D = view.texture_for(sprite.image)
		assert_not_null(texture, sprite.image)
		assert_gt(view.retail_size_of(sprite.image).x, 0.0, sprite.image)
		assert_gt(view.retail_size_of(sprite.image).y, 0.0, sprite.image)


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


func test_every_sprite_of_both_variants_resolves_at_its_retail_size_in_english() -> void:
	assert_eq(_data.error, "")
	var hud: GameplayHudAssets = GameplayHudAssets.from_data(_data)
	var text: FrontEndAssets = FrontEndAssets.from_data(_data)
	assert_eq(hud.error, "")
	assert_eq(text.error, "")
	var view: LevelCompleteView = _view()
	view.configure(hud, text)
	var next_page: LevelCompletePage = _page(LevelCompletePage.Kind.NEXT_LEVEL)
	_assert_every_sprite_resolves(view, next_page)
	var images: PackedStringArray = _images(view)
	for image_name: String in ["next", LevelCompleteLayout.LEVEL_NAME_IMAGE, "press_fire", "select4", "total_time", "total_score", "opt_sec", "med_0", "babyfrog1_0", "babyfroggold_0"]:
		assert_has(images, image_name)
	assert_eq(view.retail_size_of("opt_sec"), text.retail_size("opt_sec"), "the seconds label is the front-end image")
	assert_eq(view.retail_size_of("med_1"), hud.retail_size("med_1"))
	assert_eq(view.widths()["next"], int(text.retail_size("next").x))
	await get_tree().process_frame
	_assert_every_sprite_resolves(view, _page(LevelCompletePage.Kind.ZONE_COMPLETE))
	images = _images(view)
	assert_has(images, "zone_complete")
	assert_has(images, "press_fire")
	assert_does_not_have(images, "next")
	assert_does_not_have(images, LevelCompleteLayout.LEVEL_NAME_IMAGE)
	await get_tree().process_frame


func test_the_next_level_name_is_its_in_game_level_select_image() -> void:
	var text: FrontEndAssets = FrontEndAssets.from_data(_data)
	var view: LevelCompleteView = _view()
	view.configure(null, text)
	view.open(_page(LevelCompletePage.Kind.NEXT_LEVEL))
	var expected: Texture2D = text.level_texture(_next_level(), FrontEndAssets.LevelImage.GAME_NAME)
	assert_not_null(expected)
	assert_same(view.texture_for(LevelCompleteLayout.LEVEL_NAME_IMAGE), expected)
	var size: Vector2 = text.level_retail_size(_next_level(), FrontEndAssets.LevelImage.GAME_NAME)
	assert_eq(view.retail_size_of(LevelCompleteLayout.LEVEL_NAME_IMAGE), size)
	assert_eq(view.widths()[LevelCompleteLayout.LEVEL_NAME_IMAGE], int(size.x))
	for sprite: LevelCompleteLayout.Sprite in view.drawn_sprites():
		if sprite.image == LevelCompleteLayout.LEVEL_NAME_IMAGE:
			assert_eq(sprite.at.x, LevelCompleteLayout.centred_x(int(size.x)))


func test_german_labels_resolve_to_their_localised_images_without_diagnostics() -> void:
	var hud: GameplayHudAssets = GameplayHudAssets.from_data(_data)
	var text: FrontEndAssets = FrontEndAssets.from_data(_data, GameLanguage.Id.GERMAN)
	assert_eq(text.error, "")
	assert_eq(text.diagnostics, PackedStringArray())
	for image_name: String in LOCALISED:
		assert_eq(text.source_name(image_name), LOCALISED[image_name], image_name)
	var view: LevelCompleteView = _view()
	view.configure(hud, text)
	_assert_every_sprite_resolves(view, _page(LevelCompletePage.Kind.NEXT_LEVEL))
	_assert_every_sprite_resolves(view, _page(LevelCompletePage.Kind.ZONE_COMPLETE))
	assert_same(view.texture_for("zone_complete"), text.texture("zone_complete"))
	await get_tree().process_frame

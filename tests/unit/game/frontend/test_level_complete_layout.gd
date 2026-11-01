extends GutTest
## Level-complete sprite positions against LevelCompleteStartup (tempopt.c:5806-5960).

const WIDTHS: Dictionary[String, int] = {"next": 64, "level_name": 200, "press_fire": 128, "select4": 160, "zone_complete": 192}


func _page(variant: LevelCompletePage.Kind, frame: int, gold: bool, press_fire: bool) -> LevelCompletePage:
	var page := LevelCompletePage.new()
	page.variant = variant
	page.checkpoint_seconds = PackedInt32Array([1, 2, 3, 4, 5])
	page.total_seconds = 15
	page.level_score = 1850
	page.show_gold_frog = gold
	page.frame = frame
	page.press_fire_visible = press_fire
	return page


func _pairs(sprites: Array[LevelCompleteLayout.Sprite]) -> Array:
	var pairs: Array = []
	for sprite: LevelCompleteLayout.Sprite in sprites:
		pairs.append([sprite.image, sprite.at])
	return pairs


func _figures(cel: int) -> Array:
	return [
		["babyfrog1_%d" % cel, Vector2i(215, 170)], ["med_0", Vector2i(236, 170)], ["med_1", Vector2i(252, 170)], ["opt_sec", Vector2i(268, 170)],
		["babyfrog2_%d" % cel, Vector2i(215, 190)], ["med_0", Vector2i(236, 190)], ["med_2", Vector2i(252, 190)], ["opt_sec", Vector2i(268, 190)],
		["babyfrog3_%d" % cel, Vector2i(215, 210)], ["med_0", Vector2i(236, 210)], ["med_3", Vector2i(252, 210)], ["opt_sec", Vector2i(268, 210)],
		["babyfrog4_%d" % cel, Vector2i(215, 230)], ["med_0", Vector2i(236, 230)], ["med_4", Vector2i(252, 230)], ["opt_sec", Vector2i(268, 230)],
		["babyfrog5_%d" % cel, Vector2i(215, 250)], ["med_0", Vector2i(236, 250)], ["med_5", Vector2i(252, 250)], ["opt_sec", Vector2i(268, 250)],
		["total_time", Vector2i(304, 180)],
		["med_0", Vector2i(330, 200)], ["med_1", Vector2i(346, 200)], ["med_5", Vector2i(362, 200)], ["opt_sec", Vector2i(378, 200)],
		["total_score", Vector2i(298, 225)],
		["med_0", Vector2i(310, 245)], ["med_0", Vector2i(326, 245)], ["med_1", Vector2i(342, 245)],
		["med_8", Vector2i(358, 245)], ["med_5", Vector2i(374, 245)], ["med_0", Vector2i(390, 245)],
	]


func test_next_level_page_at_frame_0() -> void:
	var expected: Array = _figures(0)
	expected.append_array([
		["babyfroggold_0", Vector2i(215, 270)],
		["next", Vector2i(288, 390)],
		["level_name", Vector2i(220, 410)],
		["press_fire", Vector2i(256, 430)],
		["select4", Vector2i(240, 450)],
	])
	assert_eq(_pairs(LevelCompleteLayout.sprites(_page(LevelCompletePage.Kind.NEXT_LEVEL, 0, true, true), WIDTHS)), expected)


func test_next_level_page_at_frame_75() -> void:
	var expected: Array = _figures(2)
	expected.append_array([
		["babyfroggold_5", Vector2i(215, 270)],
		["next", Vector2i(288, 390)],
		["level_name", Vector2i(220, 410)],
		["press_fire", Vector2i(256, 430)],
		["select4", Vector2i(240, 450)],
	])
	assert_eq(_pairs(LevelCompleteLayout.sprites(_page(LevelCompletePage.Kind.NEXT_LEVEL, 75, true, true), WIDTHS)), expected)


func test_zone_complete_page_at_frame_70() -> void:
	var expected: Array = _figures(0)
	expected.append_array([
		["babyfroggold_0", Vector2i(215, 270)],
		["zone_complete", Vector2i(224, 430)],
		["press_fire", Vector2i(256, 448)],
	])
	assert_eq(_pairs(LevelCompleteLayout.sprites(_page(LevelCompletePage.Kind.ZONE_COMPLETE, 70, true, true), WIDTHS)), expected)


func test_press_fire_is_omitted_while_hidden() -> void:
	var next: Array = _figures(0)
	next.append_array([
		["next", Vector2i(288, 390)],
		["level_name", Vector2i(220, 410)],
		["select4", Vector2i(240, 450)],
	])
	assert_eq(_pairs(LevelCompleteLayout.sprites(_page(LevelCompletePage.Kind.NEXT_LEVEL, 0, false, false), WIDTHS)), next)
	var zone: Array = _figures(0)
	zone.append(["zone_complete", Vector2i(224, 430)])
	assert_eq(_pairs(LevelCompleteLayout.sprites(_page(LevelCompletePage.Kind.ZONE_COMPLETE, 0, false, false), WIDTHS)), zone)


func test_statistics_has_no_bottom_sprites() -> void:
	assert_eq(_pairs(LevelCompleteLayout.sprites(_page(LevelCompletePage.Kind.STATISTICS, 0, false, true), WIDTHS)), _figures(0))


func test_gold_frog_only_when_shown() -> void:
	for gold: bool in [false, true]:
		var images: Array[String] = []
		for sprite: LevelCompleteLayout.Sprite in LevelCompleteLayout.sprites(_page(LevelCompletePage.Kind.STATISTICS, 3, gold, false), WIDTHS):
			images.append(sprite.image)
		assert_eq(images.has("babyfroggold_3"), gold)


func test_missing_widths_centre_on_zero() -> void:
	var empty: Dictionary[String, int] = {}
	var sprites: Array[LevelCompleteLayout.Sprite] = LevelCompleteLayout.sprites(_page(LevelCompletePage.Kind.ZONE_COMPLETE, 0, false, true), empty)
	assert_eq(sprites[sprites.size() - 1].at, Vector2i(320, 448))


func test_centring_halves_odd_widths_downwards() -> void:
	assert_eq(LevelCompleteLayout.centred_x(65), 288)
	assert_eq(LevelCompleteLayout.centred_x(127), 257)
	assert_eq(LevelCompleteLayout.centred_x(1), 320)
	assert_eq(LevelCompleteLayout.centred_x(0), 320)


func test_digits_keep_the_last_digits_zero_padded() -> void:
	assert_eq(LevelCompleteLayout.digits(1234, 3), "234")
	assert_eq(LevelCompleteLayout.digits(5, 2), "05")
	assert_eq(LevelCompleteLayout.digits(1850, 6), "001850")
	assert_eq(LevelCompleteLayout.digits(0, 2), "00")
	assert_eq(LevelCompleteLayout.digits(1234567, 6), "234567")
	assert_eq(LevelCompleteLayout.digits(-12, 3), "000")


func test_checkpoint_cels_advance_every_second_update() -> void:
	assert_eq(LevelCompleteLayout.checkpoint_image(0, 0), "babyfrog1_0")
	assert_eq(LevelCompleteLayout.checkpoint_image(0, 1), "babyfrog1_0")
	assert_eq(LevelCompleteLayout.checkpoint_image(1, 2), "babyfrog2_1")
	assert_eq(LevelCompleteLayout.checkpoint_image(4, 13), "babyfrog5_6")
	assert_eq(LevelCompleteLayout.checkpoint_image(2, 14), "babyfrog3_0")
	assert_eq(LevelCompleteLayout.checkpoint_image(3, 75), "babyfrog4_2")


func test_gold_cels_advance_every_update() -> void:
	assert_eq(LevelCompleteLayout.gold_image(0), "babyfroggold_0")
	assert_eq(LevelCompleteLayout.gold_image(6), "babyfroggold_6")
	assert_eq(LevelCompleteLayout.gold_image(7), "babyfroggold_0")
	assert_eq(LevelCompleteLayout.gold_image(75), "babyfroggold_5")


func test_sprite_create_holds_image_and_corner() -> void:
	var sprite: LevelCompleteLayout.Sprite = LevelCompleteLayout.Sprite.create("next", Vector2i(3, 4))
	assert_eq(sprite.image, "next")
	assert_eq(sprite.at, Vector2i(3, 4))

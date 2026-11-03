extends GutTest
## PauseView places pause.c's sprites by their retail widths, glows the selected one and fades by
## subtraction, drawing nothing while no pause shows.

const WIDTHS: Dictionary[String, int] = {
	"opt_paused": 128, "opt_big_continue": 160, "quit": 64, "opt_yes": 48, "opt_no": 40,
}

var _view: PauseView


func before_each() -> void:
	_view = PauseView.new()
	add_child_autofree(_view)
	assert_eq(_view.configure(_assets()), "")


func _assets() -> FrontEndAssets:
	var assets := FrontEndAssets.new()
	var textures: Dictionary[String, Texture2D] = {}
	var sizes: Dictionary[String, Vector2] = {}
	for image_name: String in WIDTHS:
		textures[image_name] = ImageTexture.create_from_image(Image.create(WIDTHS[image_name], 16, false, Image.FORMAT_RGBA8))
		sizes[image_name] = Vector2(WIDTHS[image_name], 16)
	assets._textures = textures
	assets._sizes = sizes
	return assets


func _page(mode: PausePage.Mode, menu_mode: PausePage.MenuMode, frame: int) -> PausePage:
	var page := PausePage.new()
	page.mode = mode
	page.menu_mode = menu_mode
	page.frame = frame
	page.fade_level = PausePage.FADE_END if mode == PausePage.Mode.MENU else 0x40
	return page


func _by_image(placed: Array[PauseView.PlacedSprite]) -> Dictionary[String, PauseView.PlacedSprite]:
	var result: Dictionary[String, PauseView.PlacedSprite] = {}
	for sprite: PauseView.PlacedSprite in placed:
		result[sprite.image] = sprite
	return result


func test_the_quit_menu_places_all_five_sprites_by_their_widths() -> void:
	_view.present(_page(PausePage.Mode.MENU, PausePage.MenuMode.QUIT, 0))
	var placed: Array[PauseView.PlacedSprite] = _view.sprites()
	assert_eq(placed.size(), 5)
	var images := PackedStringArray()
	for sprite: PauseView.PlacedSprite in placed:
		images.append(sprite.image)
	assert_eq(images, PackedStringArray(["opt_paused", "opt_big_continue", "quit", "opt_yes", "opt_no"]))
	var by_image: Dictionary[String, PauseView.PlacedSprite] = _by_image(placed)
	assert_eq(Vector2i(by_image["opt_paused"].x, by_image["opt_paused"].y), Vector2i(256, 240))
	assert_eq(Vector2i(by_image["opt_big_continue"].x, by_image["opt_big_continue"].y), Vector2i(240, 272))
	assert_eq(Vector2i(by_image["quit"].x, by_image["quit"].y), Vector2i(288, 288))
	assert_eq(Vector2i(by_image["opt_yes"].x, by_image["opt_yes"].y), Vector2i(344, 304))
	assert_eq(Vector2i(by_image["opt_no"].x, by_image["opt_no"].y), Vector2i(252, 304))


func test_the_continue_menu_hides_yes_and_no() -> void:
	_view.present(_page(PausePage.Mode.MENU, PausePage.MenuMode.CONTINUE, 0))
	var by_image: Dictionary[String, PauseView.PlacedSprite] = _by_image(_view.sprites())
	assert_eq(by_image.keys(), ["opt_paused", "opt_big_continue", "quit"])


func test_the_selected_sprite_glows_and_the_others_stay_white() -> void:
	var page: PausePage = _page(PausePage.Mode.MENU, PausePage.MenuMode.CONTINUE, 2)
	page.selection = PausePage.QUIT_SELECTED
	_view.present(page)
	var by_image: Dictionary[String, PauseView.PlacedSprite] = _by_image(_view.sprites())
	assert_eq(by_image["quit"].modulate, Color(0.5, 0.5, 0.5), "(2 & 7) << 5 is 0x40 of the neutral 0x80")
	assert_eq(by_image["opt_big_continue"].modulate, Color.WHITE)
	assert_eq(by_image["opt_paused"].modulate, Color.WHITE)
	page.frame = 7
	by_image = _by_image(_view.sprites())
	assert_eq(by_image["quit"].modulate, Color.WHITE, "0xE0 is capped at the image's own colours")
	page.frame = 8
	by_image = _by_image(_view.sprites())
	assert_eq(by_image["quit"].modulate, Color.BLACK)
	page.menu_mode = PausePage.MenuMode.QUIT
	page.quit_selection = PausePage.QUIT_YES
	page.frame = 3
	by_image = _by_image(_view.sprites())
	assert_eq(by_image["opt_yes"].modulate, Color(0.75, 0.75, 0.75))
	assert_eq(by_image["opt_no"].modulate, Color.WHITE)
	assert_eq(by_image["quit"].modulate, Color.WHITE)


func test_the_fade_down_shows_unlit_sprites_over_a_subtractive_fade() -> void:
	_view.present(_page(PausePage.Mode.FADE_DOWN, PausePage.MenuMode.CONTINUE, 5))
	var placed: Array[PauseView.PlacedSprite] = _view.sprites()
	assert_eq(placed.size(), 3)
	for sprite: PauseView.PlacedSprite in placed:
		assert_eq(sprite.modulate, Color.WHITE, sprite.image)
	assert_eq(_view.fade_level(), 0x40)
	var fade: ColorRect = _view.get_node("Fade")
	assert_true(fade.visible)
	assert_true(fade.show_behind_parent, "the sprites draw over the fade")
	assert_eq((fade.material as CanvasItemMaterial).blend_mode, CanvasItemMaterial.BLEND_MODE_SUB)
	assert_eq(fade.color, PauseView.fade_colour(0x40))
	assert_almost_eq(PauseView.fade_colour(PausePage.FADE_END).r, 128.0 / 255.0, 0.0001)


func test_the_fade_up_keeps_the_fade_without_sprites() -> void:
	var page: PausePage = _page(PausePage.Mode.FADE_UP, PausePage.MenuMode.QUIT, 20)
	_view.present(page)
	assert_true(_view.sprites().is_empty())
	assert_true((_view.get_node("Fade") as ColorRect).visible)


func test_nothing_is_drawn_without_an_active_pause() -> void:
	_view.present(PausePage.new())
	assert_true(_view.sprites().is_empty())
	assert_eq(_view.fade_level(), 0)
	assert_false((_view.get_node("Fade") as ColorRect).visible)
	_view.present(_page(PausePage.Mode.MENU, PausePage.MenuMode.QUIT, 0))
	_view.clear()
	assert_true(_view.sprites().is_empty())
	assert_false((_view.get_node("Fade") as ColorRect).visible)


func test_missing_images_are_reported() -> void:
	var view := PauseView.new()
	add_child_autofree(view)
	assert_string_contains(view.configure(null), "front-end images")
	var assets: FrontEndAssets = _assets()
	assets._textures.erase("quit")
	assert_eq(view.configure(assets), "Pause page images are missing: quit")

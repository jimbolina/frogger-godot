extends GutTest
## Physical PC page upload order, shared colour keys, byte-wrap neighbours and the sky atlas.

func _image(id: int, x: int, y: int, width: int, height: int, colour: Color) -> VloImage:
	var image := VloImage.new()
	image.texture_id = id
	image.vram_x = x
	image.vram_y = y
	image.u = x
	image.v = y & 255
	image.width = width
	image.height = height
	image.padded_width = width
	image.padded_height = height
	for _pixel: int in width * height:
		image.pixels.append_array(PackedByteArray([colour.r8, colour.g8, colour.b8, colour.a8]))
	return image

func _bank(images: Array[VloImage]) -> VloFile:
	var bank := VloFile.new()
	bank.images = images
	return bank

func test_byte_wrap_samples_neighbour_image_on_the_same_page() -> void:
	var right: VloImage = _image(1, 254, 0, 2, 1, Color.RED)
	var left: VloImage = _image(2, 0, 0, 1, 1, Color.GREEN)
	var banks: Array[VloFile] = [_bank([right, left])]
	var diagnostics := PackedStringArray()
	var page: Image = VramPages.compose_page(banks, 0, diagnostics)
	assert_eq(page.get_pixel(255, 0), Color.RED)
	assert_eq(page.get_pixel((right.u + 2) & 255, 0), Color.GREEN)
	assert_eq(diagnostics, PackedStringArray())

func test_later_theme_uploads_override_and_colour_key_covers_the_page() -> void:
	var first: VloImage = _image(1, 10, 0, 2, 1, Color8(7, 6, 5))
	first.pixels[3] = 0
	var exact_black: VloImage = _image(3, 9, 0, 1, 1, Color.BLACK)
	var later: VloImage = _image(2, 11, 0, 1, 1, Color.BLUE)
	later.flags = VloImage.FLAG_BLACK_IS_TRANSPARENT
	var banks: Array[VloFile] = [_bank([first, exact_black]), _bank([later])]
	var page: Image = VramPages.compose_page(banks, 0, PackedStringArray())
	assert_eq(page.get_pixel(9, 0).a, 0.0, "page colour key also applies to unmarked earlier images")
	assert_eq(page.get_pixel(10, 0).a, 1.0, "RGB1..7 remains opaque in the frozen PC page sampler")
	assert_eq(page.get_pixel(11, 0), Color.BLUE, "later physical upload wins")
	assert_eq(page.get_pixel(0, 0).a, 0.0, "unwritten black pixels share the page key")
	assert_true(VramPages.colour_keyed(banks, 0))
	assert_false(VramPages.colour_keyed(banks, 1))

func test_physical_upload_may_cross_a_page_boundary() -> void:
	var image: VloImage = _image(1, 0, 255, 1, 2, Color.RED)
	image.pixels[4] = 0
	image.pixels[6] = 255
	image.flags = VloImage.FLAG_BLACK_IS_TRANSPARENT
	var banks: Array[VloFile] = [_bank([image])]
	var first: Image = VramPages.compose_page(banks, 0, PackedStringArray())
	var next: Image = VramPages.compose_page(banks, 1, PackedStringArray())
	assert_eq(first.get_pixel(0, 255), Color.RED)
	assert_eq(next.get_pixel(0, 0), Color.BLUE)
	assert_eq(next.get_pixel(1, 0).a, 1.0, "loader marks only the image's starting page")

func test_bad_uploads_and_pages_are_reported() -> void:
	var banks: Array[VloFile] = [_bank([_image(1, 256, 0, 1, 1, Color.RED)])]
	var diagnostics := PackedStringArray()
	var first: Image = VramPages.compose_page(banks, 0, diagnostics)
	assert_eq(first.get_pixel(0, 0), Color.BLACK)
	assert_eq(diagnostics.size(), 1)
	banks.append(_bank([_image(2, 0, 0, 1, 1, Color.GREEN)]))
	assert_eq(VramPages.compose_page(banks, 0, diagnostics).get_pixel(0, 0), Color.GREEN)
	assert_null(VramPages.compose_page(banks, 14, diagnostics))
	assert_true(diagnostics.has("Invalid PC texture page 14"))

func test_runtime_colour_key_keeps_every_low_nonzero_rgb_opaque() -> void:
	var black: VloImage = _image(0, 0, 0, 1, 1, Color.BLACK)
	black.flags = VloImage.FLAG_BLACK_IS_TRANSPARENT
	var images: Array[VloImage] = [black]
	for value: int in range(1, 8):
		var near_black: VloImage = _image(value, value, 0, 1, 1, Color8(value, value, value))
		near_black.pixels[3] = 0
		images.append(near_black)
	var banks: Array[VloFile] = [_bank(images)]
	var page: Image = VramPages.compose_page(banks, 0, PackedStringArray())
	assert_eq(page.get_pixel(0, 0).a, 0.0)
	for value: int in range(1, 8):
		assert_eq(page.get_pixel(value, 0).a, 1.0)

func test_sky_atlas_repeats_each_page_edge_row_in_its_slot() -> void:
	var first := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	first.fill(Color8(128, 128, 128))
	first.set_pixel(20, 255, Color8(10, 20, 30))
	var second := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	second.fill(Color8(240, 240, 240))
	var pages: Array[Image] = [first, second]
	var atlas: Image = VramPages.sky_atlas(pages, PackedInt32Array([0, 1, -1]))
	assert_eq(atlas.get_size(), Vector2i(256, 3 * 258))
	assert_eq(atlas.get_pixel(20, 0), atlas.get_pixel(20, 1), "top page clamp row")
	assert_eq(atlas.get_pixel(20, 257), atlas.get_pixel(20, 256), "bottom page clamp row")
	assert_eq(atlas.get_pixel(20, 258), atlas.get_pixel(20, 259), "second top clamp row")
	assert_ne(atlas.get_pixel(20, 257), atlas.get_pixel(20, 258), "neighbour pages remain distinct")
	assert_eq(atlas.get_pixel(20, 2 * 258 + 5), Color.MAGENTA, "a missing image leaves its slot magenta")

func test_sky_order_lists_tile_pages_in_first_seen_order() -> void:
	var low: VloImage = _image(7, 0, 256, 1, 1, Color.RED)
	var high: VloImage = _image(8, 0, 0, 1, 1, Color.RED)
	var general_only: VloImage = _image(9, 0, 512, 1, 1, Color.RED)
	var shadowed: VloImage = _image(7, 0, 768, 1, 1, Color.RED)
	var general: VloFile = _bank([shadowed, general_only])
	var theme: VloFile = _bank([low, high])
	var remap := TextureRemap.new()
	remap.texture_ids = PackedInt32Array([7, 8, 99, 9])
	var sky := SkyLandFile.new()
	sky.texture_ids = PackedInt32Array([0, 1, 0, 2, 1, 3])
	assert_eq(VramPages.sky_order(general, theme, sky, remap), PackedInt32Array([1, 0, -1, 2]),
		"the theme bank wins, the general bank fills in")

func test_page_set_holds_textures_keys_and_the_sky_atlas() -> void:
	var keyed: VloImage = _image(1, 0, 0, 1, 1, Color.BLACK)
	keyed.flags = VloImage.FLAG_BLACK_IS_TRANSPARENT
	var plain: VloImage = _image(2, 0, 256, 1, 1, Color.GREEN)
	var diagnostics := PackedStringArray()
	var made: TexturePageSet = VramPages.page_set(PackedStringArray(["GEN_VRAM", "SKY_VRAM"]), _bank([keyed]), _bank([plain]),
		diagnostics, true, PackedInt32Array([1]))
	assert_eq(made.set_name, "GEN_VRAM+SKY_VRAM")
	assert_eq(made.pages.size(), TexturePageSet.PAGE_COUNT)
	assert_true(made.colour_keyed[0])
	assert_false(made.colour_keyed[1])
	assert_eq(made.page(1).get_image().get_pixel(0, 0), Color.GREEN)
	assert_eq(made.sky_pages, PackedInt32Array([1]))
	assert_eq(made.sky_atlas.get_image().get_pixel(0, 1), Color.GREEN)
	assert_eq(diagnostics, PackedStringArray())
	assert_null(VramPages.page_set(PackedStringArray(["A", "B"]), _bank([]), _bank([]), diagnostics).sky_atlas)

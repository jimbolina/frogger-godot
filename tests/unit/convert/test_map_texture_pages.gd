extends GutTest
## Physical PC page upload order, shared colour keys and byte-wrap neighbours.

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
	var library := TextureLibrary.new()
	library.add_bank(_bank([right, left]))
	var pages := MapTexturePages.new()
	pages.configure(library)
	var page: Image = pages.image_for_page(0)
	assert_eq(page.get_pixel(255, 0), Color.RED)
	assert_eq(page.get_pixel((right.u + 2) & 255, 0), Color.GREEN)
	assert_same(pages.texture_for(right), pages.texture_for(left))
	assert_eq(pages.cached_texture_count(), 1)

func test_later_theme_uploads_override_and_colour_key_covers_the_page() -> void:
	var first: VloImage = _image(1, 10, 0, 2, 1, Color8(7, 6, 5))
	first.pixels[3] = 0
	var exact_black: VloImage = _image(3, 9, 0, 1, 1, Color.BLACK)
	var later: VloImage = _image(2, 11, 0, 1, 1, Color.BLUE)
	later.flags = VloImage.FLAG_BLACK_IS_TRANSPARENT
	var library := TextureLibrary.new()
	library.add_bank(_bank([first, exact_black]), "GENERAL")
	library.add_bank(_bank([later]), "THEME")
	var pages := MapTexturePages.new()
	pages.configure(library)
	var page: Image = pages.image_for_page(0)
	assert_eq(page.get_pixel(9, 0).a, 0.0, "page colour key also applies to unmarked earlier images")
	assert_eq(page.get_pixel(10, 0).a, 1.0, "RGB1..7 remains opaque in the frozen PC page sampler")
	assert_eq(page.get_pixel(11, 0), Color.BLUE, "later physical upload wins")
	assert_eq(page.get_pixel(0, 0).a, 0.0, "unwritten black pixels share the page key")

func test_physical_upload_may_cross_a_page_boundary() -> void:
	var image: VloImage = _image(1, 0, 255, 1, 2, Color.RED)
	image.pixels[4] = 0
	image.pixels[6] = 255
	image.flags = VloImage.FLAG_BLACK_IS_TRANSPARENT
	var library := TextureLibrary.new()
	library.add_bank(_bank([image]))
	var pages := MapTexturePages.new()
	pages.configure(library)
	var first: Image = pages.image_for_page(0)
	var next: Image = pages.image_for_page(1)
	assert_eq(first.get_pixel(0, 255), Color.RED)
	assert_eq(next.get_pixel(0, 0), Color.BLUE)
	assert_eq(next.get_pixel(1, 0).a, 1.0, "loader marks only the image's starting page")

func test_bad_uploads_are_bounded_and_bank_addition_invalidates_cached_pages() -> void:
	var image: VloImage = _image(1, 256, 0, 1, 1, Color.RED)
	var library := TextureLibrary.new()
	library.add_bank(_bank([image]))
	var pages := MapTexturePages.new()
	pages.configure(library)
	var first: Image = pages.image_for_page(0)
	assert_eq(first.get_pixel(0, 0), Color.BLACK)
	assert_eq(pages.diagnostics.size(), 1)
	library.add_bank(_bank([_image(2, 0, 0, 1, 1, Color.GREEN)]))
	var updated: Image = pages.image_for_page(0)
	assert_eq(updated.get_pixel(0, 0), Color.GREEN)
	assert_null(pages.image_for_page(14))
	assert_null(library.bank_at(-1))


func test_runtime_colour_key_keeps_every_low_nonzero_rgb_opaque() -> void:
	var black: VloImage = _image(0, 0, 0, 1, 1, Color.BLACK)
	black.flags = VloImage.FLAG_BLACK_IS_TRANSPARENT
	var images: Array[VloImage] = [black]
	for value: int in range(1, 8):
		var near_black: VloImage = _image(value, value, 0, 1, 1, Color8(value, value, value))
		near_black.pixels[3] = 0
		images.append(near_black)
	var library := TextureLibrary.new()
	library.add_bank(_bank(images))
	var pages := MapTexturePages.new()
	pages.configure(library)
	var page: Image = pages.image_for_page(0)
	assert_eq(page.get_pixel(0, 0).a, 0.0)
	for value: int in range(1, 8):
		assert_eq(page.get_pixel(value, 0).a, 1.0)

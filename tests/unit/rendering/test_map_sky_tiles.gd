extends GutTest
## The sky's tile array: layer order, texture-set scale, magenta fallbacks and layer coordinates.

class UpscaledCatalog extends AssetCatalog:
	var scaled: Dictionary[VloImage, Texture2D] = {}

	func texture_set() -> TextureSet:
		return TextureSet.x4()

	func texture_of(image: VloImage) -> Texture2D:
		if image == null:
			return null
		if not scaled.has(image):
			var pixels: Image = image.texture.get_image()
			pixels.resize(image.padded_width * 4, image.padded_height * 4, Image.INTERPOLATE_NEAREST)
			scaled[image] = ImageTexture.create_from_image(pixels)
		return scaled[image]


const COLOURS: Array[Color] = [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)]


func test_one_layer_per_image_in_the_given_order() -> void:
	var images: Array[VloImage] = [_tile(301, COLOURS[2]), _tile(302, COLOURS[0]), _tile(303, COLOURS[1])]
	var diagnostics := PackedStringArray()
	var tiles: Texture2DArray = MapSkyTiles.build(images, TextureLibrary.new(), false, diagnostics)
	assert_true(diagnostics.is_empty(), ", ".join(diagnostics))
	assert_eq(tiles.get_layers(), 3)
	assert_eq(Vector2(tiles.get_width(), tiles.get_height()), Vector2(40, 40))
	assert_false(tiles.has_mipmaps())
	assert_eq(tiles.get_format(), Image.FORMAT_RGBA8)
	var made: Array[Image] = MapSkyTiles.layers(images, TextureLibrary.new(), false, diagnostics)
	var expected: Array[Color] = [COLOURS[2], COLOURS[0], COLOURS[1]]
	for layer: int in 3:
		assert_eq(made[layer].get_pixel(20, 20), expected[layer], "layer %d" % layer)
	assert_true(diagnostics.is_empty())


func test_linear_layers_carry_mipmaps() -> void:
	var images: Array[VloImage] = [_tile(301, COLOURS[0]), _tile(302, COLOURS[1])]
	var tiles: Texture2DArray = MapSkyTiles.build(images, TextureLibrary.new(), true, PackedStringArray())
	assert_true(tiles.has_mipmaps())
	for made: Image in MapSkyTiles.layers(images, TextureLibrary.new(), true, PackedStringArray()):
		assert_true(made.has_mipmaps())


func test_x4_layers_come_from_the_texture_set() -> void:
	var library := TextureLibrary.new()
	library.catalog = UpscaledCatalog.new()
	var images: Array[VloImage] = [_tile(301, COLOURS[0]), _tile(302, COLOURS[1])]
	var diagnostics := PackedStringArray()
	var tiles: Texture2DArray = MapSkyTiles.build(images, library, true, diagnostics)
	assert_true(diagnostics.is_empty(), ", ".join(diagnostics))
	assert_eq(Vector2(tiles.get_width(), tiles.get_height()), Vector2(160, 160))
	var made: Array[Image] = MapSkyTiles.layers(images, library, true, diagnostics)
	assert_eq(made[1].get_size(), Vector2i(160, 160))
	assert_eq(made[1].get_pixel(80, 80), COLOURS[1])


func test_missing_and_mismatched_tiles_become_magenta_with_one_line_each() -> void:
	var wide: VloImage = _tile(304, COLOURS[1])
	wide.padded_width = 48
	wide.width = 40
	var wide_pixels := Image.create(48, 40, false, Image.FORMAT_RGBA8)
	wide_pixels.fill(COLOURS[1])
	wide.texture = ImageTexture.create_from_image(wide_pixels)
	var shifted: VloImage = _tile(305, COLOURS[2])
	shifted.width = 36
	var images: Array[VloImage] = [null, _tile(302, COLOURS[0]), wide, shifted]
	var diagnostics := PackedStringArray()
	var tiles: Texture2DArray = MapSkyTiles.build(images, TextureLibrary.new(), false, diagnostics)
	assert_eq(tiles.get_layers(), 4)
	assert_eq(diagnostics.size(), 3, "\n".join(diagnostics))
	assert_eq(Vector2(tiles.get_width(), tiles.get_height()), Vector2(40, 40), "the first tile with a texture sets the size")
	var made: Array[Image] = MapSkyTiles.layers(images, TextureLibrary.new(), false, PackedStringArray())
	assert_eq(made[0].get_pixel(5, 5), MapSkyTiles.MISSING_COLOUR)
	assert_eq(made[1].get_pixel(5, 5), COLOURS[0])
	assert_eq(made[2].get_pixel(5, 5), MapSkyTiles.MISSING_COLOUR)
	assert_eq(made[2].get_size(), Vector2i(40, 40))
	assert_eq(made[3].get_pixel(5, 5), MapSkyTiles.MISSING_COLOUR, "same size, other padding")
	assert_string_contains(diagnostics[0], "layer 0")
	assert_string_contains(diagnostics[1], "texture 304")
	assert_string_contains(diagnostics[2], "texture 305")


func test_no_tiles_gives_no_array_and_a_diagnostic() -> void:
	var diagnostics := PackedStringArray()
	var empty: Array[VloImage] = []
	assert_null(MapSkyTiles.build(empty, TextureLibrary.new(), false, diagnostics))
	assert_eq(diagnostics.size(), 1)


func test_layer_uv_normalises_into_the_padded_layer() -> void:
	var image: VloImage = _tile(301, COLOURS[0])
	assert_eq(MapSkyTiles.layer_uv(Vector2.ZERO, image), Vector2(4, 4) / 40.0)
	assert_eq(MapSkyTiles.layer_uv(Vector2(31, 32), image), Vector2(35, 36) / 40.0, "a HIT_X span ends a column early")
	image.u = 200
	assert_eq(MapSkyTiles.layer_uv(Vector2(32, 0), image), Vector2(36, 4) / 40.0, "the page origin plays no part")


func _tile(texture_id: int, colour: Color) -> VloImage:
	var image := VloImage.new()
	image.texture_id = texture_id
	image.width = 32
	image.height = 32
	image.padded_width = 40
	image.padded_height = 40
	image.u = 4
	image.v = 4
	var pixels := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	pixels.fill(colour)
	image.texture = ImageTexture.create_from_image(pixels)
	return image

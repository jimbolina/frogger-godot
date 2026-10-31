extends GutTest
## TextureBuilder maps a record's in-game region onto its texture at any texture-set scale and
## sizes 2D draws in retail pixels.

const SCALE: int = 4


func _record() -> VloImage:
	var rgb: Array[int] = []
	for y: int in 4:
		for x: int in 6:
			rgb.append_array([x * 40, y * 60, 200])
	return SyntheticVlo.bank([SyntheticVlo.spec(4, 2, 2, 7, 0, SyntheticVlo.abgr(rgb))]).images[0]


func _upscaled(record: VloImage) -> ImageTexture:
	var pixels: Image = record.texture.get_image()
	pixels.resize(record.padded_width * SCALE, record.padded_height * SCALE, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(pixels)


func test_retail_texture_maps_one_to_one() -> void:
	var record: VloImage = _record()
	assert_eq(Vector2i(record.padded_width, record.padded_height), Vector2i(6, 4))
	assert_eq(TextureBuilder.texture_scale(record, record.texture), Vector2.ONE)
	assert_eq(TextureBuilder.texture_scale(record, null), Vector2.ONE, "no texture draws one to one")
	assert_eq(TextureBuilder.texture_rect(record, record.texture), Rect2(1, 1, 4, 2))
	assert_eq(TextureBuilder.texture_rect(record, record.texture), Rect2(TextureBuilder.pixel_rect(record)))
	assert_eq(TextureBuilder.retail_size(record, record.texture), Vector2(6, 4))
	assert_eq(TextureBuilder.retail_size(record, null), Vector2(6, 4))


func test_upscaled_texture_scales_the_region_but_not_the_retail_size() -> void:
	var record: VloImage = _record()
	var texture: ImageTexture = _upscaled(record)
	assert_eq(TextureBuilder.texture_scale(record, texture), Vector2(SCALE, SCALE))
	assert_eq(TextureBuilder.texture_rect(record, texture), Rect2(4, 4, 16, 8))
	assert_eq(TextureBuilder.retail_size(record, texture), Vector2(6, 4), "drawn at the padded size")
	var uv: Rect2 = TextureBuilder.uv_rect(record)
	assert_eq(TextureBuilder.texture_rect(record, texture), Rect2(uv.position * texture.get_size(), uv.size * texture.get_size()))


func test_unpadded_texture_clips_the_given_texture() -> void:
	var record: VloImage = _record()
	var retail: AtlasTexture = TextureBuilder.unpadded_texture(record) as AtlasTexture
	assert_eq(retail.atlas, record.texture)
	assert_eq(retail.region, Rect2(1, 1, 4, 2))
	var texture: ImageTexture = _upscaled(record)
	var upscaled: AtlasTexture = TextureBuilder.unpadded_texture(record, texture) as AtlasTexture
	assert_eq(upscaled.atlas, texture)
	assert_eq(upscaled.region, Rect2(4, 4, 16, 8))
	assert_true(upscaled.filter_clip)


func test_unpadded_image_crops_the_given_texture() -> void:
	var record: VloImage = _record()
	var retail: Image = TextureBuilder.build_unpadded_image(record)
	assert_eq(retail.get_size(), Vector2i(4, 2))
	var upscaled: Image = TextureBuilder.build_unpadded_image(record, _upscaled(record))
	assert_eq(upscaled.get_size(), Vector2i(4 * SCALE, 2 * SCALE))
	for y: int in 2:
		for x: int in 4:
			assert_eq(upscaled.get_pixel(x * SCALE, y * SCALE), retail.get_pixel(x, y))
			assert_eq(upscaled.get_pixel(x * SCALE + SCALE - 1, y * SCALE + SCALE - 1), retail.get_pixel(x, y))


func test_build_image_reads_the_given_texture() -> void:
	var record: VloImage = _record()
	assert_eq(TextureBuilder.build_image(record).get_size(), Vector2i(6, 4))
	var upscaled: Image = TextureBuilder.build_image(record, _upscaled(record))
	assert_eq(upscaled.get_size(), Vector2i(6 * SCALE, 4 * SCALE))
	assert_eq(upscaled.get_format(), Image.FORMAT_RGBA8)
	assert_false(upscaled.has_mipmaps())

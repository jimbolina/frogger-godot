extends GutTest
## VloFile, TextureBuilder and TextureLibrary on small hand-built PC texture banks.


func _two_image_bank() -> PackedByteArray:
	var a: SyntheticVlo.Spec = SyntheticVlo.spec(3, 1, 0, 500, VloImage.FLAG_BLACK_IS_TRANSPARENT | VloImage.FLAG_2D_SPRITE,
		SyntheticVlo.abgr([0, 0, 0, 7, 7, 7, 8, 0, 0]))
	var colours: Array[int] = []
	for i: int in 16:
		colours.append_array([i, 100 + i, 200 + i])
	var b: SyntheticVlo.Spec = SyntheticVlo.spec(2, 2, 2, 501, VloImage.FLAG_TRANSLUCENT, SyntheticVlo.abgr(colours, 0x55))
	b.vram_x = 16
	b.vram_y = 256 + 8
	b.blend_mode = 1
	return SyntheticVlo.build_vlo([a, b])


func test_headers() -> void:
	var vlo: VloFile = VloFile.parse(_two_image_bank())
	assert_eq(vlo.error, "")
	assert_eq(vlo.size(), 2)
	var b: VloImage = vlo.images[1]
	assert_eq([b.texture_id, b.padded_width, b.padded_height, b.width, b.height], [501, 4, 4, 2, 2])
	assert_eq([b.page(), b.blend_mode(), b.u, b.v], [1, 1, 17, 9])
	assert_eq([b.left_padding(), b.top_padding()], [1, 1])
	assert_true(b.has_flag(VloImage.FLAG_TRANSLUCENT))
	assert_eq(vlo.find_texture(500), vlo.images[0])
	assert_null(vlo.find_texture(7))


func test_pixels_decode_to_rgba_with_black_transparent_below_8() -> void:
	var a: VloImage = VloFile.parse(_two_image_bank()).images[0]
	assert_eq(a.pixels, PackedByteArray([0, 0, 0, 0, 7, 7, 7, 0, 8, 0, 0, 255]),
		"black and near-black are transparent; (8,0,0) is not")


func test_stored_alpha_is_ignored_and_order_is_kept() -> void:
	var b: VloImage = VloFile.parse(_two_image_bank()).images[1]
	assert_eq(b.pixels.size(), 4 * 4 * 4)
	for i: int in 16:
		var got := PackedByteArray([b.pixels[4 * i], b.pixels[4 * i + 1], b.pixels[4 * i + 2], b.pixels[4 * i + 3]])
		assert_eq(got, PackedByteArray([i, 100 + i, 200 + i, 255]), "pixel %d" % i)
	var inner: PackedByteArray = b.unpadded_pixels()
	assert_eq(inner.size(), 16)
	assert_eq([inner[0], inner[4], inner[8], inner[12]], [5, 6, 9, 10])


func test_headers_only() -> void:
	var vlo: VloFile = VloFile.parse(_two_image_bank(), false)
	assert_eq(vlo.error, "")
	assert_eq(vlo.images[1].pixels.size(), 0)


func test_froglord_texture_names() -> void:
	var names := PackedByteArray()
	names.append_array("FROGLORD".to_ascii_buffer())
	names.append(0)
	names.append_array(PackedByteArray([1, 0]))
	names.append_array(PackedByteArray([1, 0, 5]))
	names.append_array("water".to_ascii_buffer())
	var a: SyntheticVlo.Spec = SyntheticVlo.spec(1, 1, 0, 1, 0, SyntheticVlo.abgr([1, 2, 3]))
	var b: SyntheticVlo.Spec = SyntheticVlo.spec(1, 1, 0, 2, 0, SyntheticVlo.abgr([4, 5, 6]))
	var vlo: VloFile = VloFile.parse(SyntheticVlo.build_vlo([a, b], names))
	assert_eq(vlo.error, "")
	assert_eq(vlo.images[1].custom_name, "water")
	assert_eq(vlo.images[0].custom_name, "")


func test_rejects_bad_files() -> void:
	assert_ne(VloFile.parse("2GRV".to_ascii_buffer()).error, "", "PlayStation banks are not read")
	var bytes: PackedByteArray = _two_image_bank()
	var wrong_page: PackedByteArray = bytes.duplicate()
	wrong_page.encode_u16(12 + 24 + 14, 0)
	assert_string_contains(VloFile.parse(wrong_page).error, "texture page word")
	var wrong_offset: PackedByteArray = bytes.duplicate()
	wrong_offset.encode_s32(12 + 8, 100)
	assert_string_contains(VloFile.parse(wrong_offset).error, "pixels at")
	var truncated: PackedByteArray = bytes.slice(0, bytes.size() - 4)
	assert_string_contains(VloFile.parse(truncated).error, "past the end")
	var junk: PackedByteArray = bytes.duplicate()
	junk.append_array("JUNKJUNK".to_ascii_buffer())
	assert_ne(VloFile.parse(junk).error, "")


func test_texture_builder() -> void:
	var b: VloImage = VloFile.parse(_two_image_bank()).images[1]
	var image: Image = TextureBuilder.build_image(b)
	assert_eq([image.get_width(), image.get_height(), image.has_mipmaps()], [4, 4, false])
	assert_eq(image.get_pixel(1, 0), Color8(1, 101, 201, 255))
	assert_eq(TextureBuilder.uv_rect(b), Rect2(0.25, 0.25, 0.5, 0.5))
	assert_eq(TextureBuilder.pixel_rect(b), Rect2i(1, 1, 2, 2))
	var inner: Image = TextureBuilder.build_unpadded_image(b)
	assert_eq(inner.get_pixel(0, 0), Color8(5, 105, 205, 255))
	var texture: ImageTexture = TextureBuilder.build_texture(b)
	assert_eq(texture.get_size(), Vector2(4, 4))


func test_texture_library_lookup_order() -> void:
	var first: VloFile = VloFile.parse(SyntheticVlo.build_vlo([SyntheticVlo.spec(1, 1, 0, 10, 0, SyntheticVlo.abgr([1, 1, 1])), SyntheticVlo.spec(1, 1, 0, 11, 0, SyntheticVlo.abgr([2, 2, 2]))]))
	var second: VloFile = VloFile.parse(SyntheticVlo.build_vlo([SyntheticVlo.spec(1, 1, 0, 10, 0, SyntheticVlo.abgr([3, 3, 3]))]))
	var library := TextureLibrary.new()
	library.add_bank(first, "FIRST.VLO")
	library.add_bank(second, "SECOND.VLO")
	assert_eq(library.bank_count(), 2)
	assert_eq(library.texture_id_count(), 2)
	assert_eq(library.image_for_id(10), second.images[0], "the later bank wins")
	assert_eq(library.image_for_id(10, first), first.images[0], "unless the caller prefers a bank")
	assert_eq(library.image_for_id(11, second), first.images[1], "falls back when the preferred bank lacks it")
	assert_null(library.image_for_id(12))
	assert_eq(library.find_bank("FIRST.VLO"), first)
	var remap := TextureRemap.new()
	remap.texture_ids = PackedInt32Array([11, 10])
	assert_eq(library.image_for_local(remap, 0), first.images[1])
	assert_null(library.image_for_local(remap, 2))
	var texture: ImageTexture = library.texture_for_id(11)
	assert_same(library.texture_for_id(11), texture, "textures are built once")

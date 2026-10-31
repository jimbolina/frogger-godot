class_name VloFileReader
extends RefCounted
## Decodes PC texture banks ("VLO", signature [code]2GRP[/code]) into [VloFile]s.
##
## Layout and the pixel decoding rule are described on [VloFile]; image headers
## on [VloImage].


## True if [param bytes] start with the PC bank signature.
static func is_vlo(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 4 and bytes.slice(0, 4) == VloFile.SIGNATURE.to_ascii_buffer()


## Parses [param bytes]. Each image gets its decoded pixels and, as an
## imported image has, a [member VloImage.texture] of them. With
## [param decode_pixels] false only the headers are read (no pixels or
## texture). Check [member VloFile.error].
static func parse(bytes: PackedByteArray, decode_pixels: bool = true) -> VloFile:
	var vlo := VloFile.new()
	var reader := ByteReader.new(bytes)
	if not reader.expect_signature(VloFile.SIGNATURE):
		vlo.error = "not a PC texture bank: %s" % reader.error
		return vlo
	var count: int = reader.read_s32()
	var headers_at: int = reader.read_s32()
	if headers_at != VloFile.HEADER_SIZE or count < 0:
		vlo.error = "bad header (%d images, headers at %d)" % [count, headers_at]
		return vlo
	for i: int in count:
		var image: VloImage = _read_header(reader, i)
		if reader.has_error():
			vlo.error = "image %d header: %s" % [i, reader.error]
			return vlo
		var problem: String = _check_header(image)
		if not problem.is_empty():
			vlo.error = "image %d: %s" % [i, problem]
			return vlo
		vlo.images.append(image)
	for image: VloImage in vlo.images:
		var start: int = reader.get_position()
		reader.align(4)
		if reader.has_error() or bytes.slice(start, reader.get_position()).count(0) != reader.get_position() - start:
			vlo.error = "image %d: bad alignment before its pixels" % image.index
			return vlo
		if image.data_offset != reader.get_position():
			vlo.error = "image %d: pixels at %d, expected %d" % [image.index, image.data_offset, reader.get_position()]
			return vlo
		var byte_count: int = image.padded_width * image.padded_height * 4
		if reader.remaining() < byte_count:
			vlo.error = "image %d: pixels run past the end of the file" % image.index
			return vlo
		if decode_pixels:
			image.pixels = VloFile.decode_rgba(bytes.slice(image.data_offset, image.data_offset + byte_count),
				image.padded_width, image.padded_height, image.has_flag(VloImage.FLAG_BLACK_IS_TRANSPARENT))
			image.texture = ImageTexture.create_from_image(Image.create_from_data(image.padded_width,
				image.padded_height, false, Image.FORMAT_RGBA8, image.pixels))
		reader.skip(byte_count)
	reader.align(4)
	if reader.has_more():
		_read_names(vlo, reader)
	return vlo


static func _read_header(reader: ByteReader, i: int) -> VloImage:
	var image := VloImage.new()
	image.index = i
	image.vram_x = reader.read_s16()
	image.vram_y = reader.read_s16()
	image.padded_width = reader.read_s16()
	image.padded_height = reader.read_s16()
	image.data_offset = reader.read_s32()
	image.texture_id = reader.read_s16()
	image.texture_page_word = reader.read_u16()
	image.flags = reader.read_u16()
	image.clut_id = reader.read_s16()
	image.u = reader.read_u8()
	image.v = reader.read_u8()
	var w: int = reader.read_u8()
	var h: int = reader.read_u8()
	image.width = w if w != 0 else 256
	image.height = h if h != 0 else 256
	return image


static func _check_header(image: VloImage) -> String:
	if image.padded_width < image.width or image.padded_height < image.height:
		return "padded size %dx%d is smaller than %dx%d" % [image.padded_width, image.padded_height, image.width, image.height]
	var expected_page_word: int = (image.page() & 0xFF) | (image.blend_mode() << 8)
	if image.texture_page_word != expected_page_word:
		return "texture page word %d, expected %d for page %d" % [image.texture_page_word, expected_page_word, image.page()]
	return ""


static func _read_names(vlo: VloFile, reader: ByteReader) -> void:
	if not reader.expect_signature(VloFile.NAMES_SIGNATURE):
		vlo.error = "unexpected data after the pixels: %s" % reader.error
		return
	reader.read_u8()
	var count: int = reader.read_u16()
	for _i: int in count:
		var image_index: int = reader.read_u16()
		var length: int = reader.read_u8()
		var text: String = reader.read_fixed_string(length)
		if reader.has_error():
			vlo.error = "texture names: %s" % reader.error
			return
		if image_index < vlo.images.size():
			vlo.images[image_index].custom_name = text

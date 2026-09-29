class_name VloFile
extends RefCounted
## A PC texture bank ("VLO", signature [code]2GRP[/code]): a list of [VloImage]s.
##
## Layout (FrogLord's [code]vlo2/VloFile[/code], PC form):
## [codeblock]
## "2GRP"   s32 image count   s32 offset of the image headers (always 12)
## image headers, 24 bytes each (see VloImage)
## for each image, aligned to 4 bytes with zeros: padded w x h pixels, 4 bytes each
## optional: FrogLord's texture names (see below)
## [/codeblock]
## Pixels are stored as the bytes A, B, G, R. They decode to RGBA8 as:
## [br]- R, G, B are copied;
## [br]- A is 255, except 0 when the image has
##   [constant VloImage.FLAG_BLACK_IS_TRANSPARENT] and R, G and B are all below 8
##   ([code](r | g | b) & 0xF8 == 0[/code], FrogLord's test: the game turns
##   pixels into 5 bits per channel before its colour-key test). The stored A byte
##   is ignored, as the game never reads it (it is zero in all retail data).
## [br]Translucency ([constant VloImage.FLAG_TRANSLUCENT]) is a drawing mode,
## not pixel alpha, and is left to the renderer.
##
## When FrogLord renames textures it appends, after the pixel data:
## [code]"FROGLORD" u8 version u16 count[/code], then per name
## [code]u16 image index, u8 length, the name's bytes[/code].

## The file signature of a PC bank.
const SIGNATURE: String = "2GRP"
## Size of the file header.
const HEADER_SIZE: int = 12
## Size of an image header.
const IMAGE_HEADER_SIZE: int = 24
## Signature of FrogLord's appended texture names.
const NAMES_SIGNATURE: String = "FROGLORD"

## The images in stored order.
var images: Array[VloImage] = []
## Why parsing failed, or "".
var error: String = ""

var _by_texture_id: Dictionary[int, VloImage] = {}


## True if [param bytes] start with the PC bank signature.
static func is_vlo(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 4 and bytes.slice(0, 4) == SIGNATURE.to_ascii_buffer()


## Parses [param bytes]. With [param decode_pixels] false only the headers
## are read (pixels stay empty). Check [member error].
static func parse(bytes: PackedByteArray, decode_pixels: bool = true) -> VloFile:
	var vlo := VloFile.new()
	var reader := ByteReader.new(bytes)
	if not reader.expect_signature(SIGNATURE):
		vlo.error = "not a PC texture bank: %s" % reader.error
		return vlo
	var count: int = reader.read_s32()
	var headers_at: int = reader.read_s32()
	if headers_at != HEADER_SIZE or count < 0:
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
		if not vlo._by_texture_id.has(image.texture_id):
			vlo._by_texture_id[image.texture_id] = image
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
			image.pixels = decode_rgba(bytes.slice(image.data_offset, image.data_offset + byte_count),
				image.padded_width, image.padded_height, image.has_flag(VloImage.FLAG_BLACK_IS_TRANSPARENT))
		reader.skip(byte_count)
	reader.align(4)
	if reader.has_more():
		vlo._read_names(reader)
	return vlo


## Converts [param width] x [param height] stored pixels (A, B, G, R) to RGBA8
## by the rule in this class's description.
static func decode_rgba(stored: PackedByteArray, width: int, height: int, black_is_transparent: bool) -> PackedByteArray:
	# Reversing the whole buffer turns every A,B,G,R into R,G,B,A but also
	# reverses the pixel order, which flipping both ways undoes. All native.
	var swapped: PackedByteArray = stored.duplicate()
	swapped.reverse()
	var image: Image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, swapped)
	image.flip_x()
	image.flip_y()
	image.convert(Image.FORMAT_RGB8) # Drops the stored alpha ...
	image.convert(Image.FORMAT_RGBA8) # ... and makes every pixel opaque.
	var rgba: PackedByteArray = image.get_data()
	if black_is_transparent:
		var words: PackedInt32Array = rgba.to_int32_array()
		for i: int in words.size():
			if words[i] & 0x00F8F8F8 == 0:
				rgba[i * 4 + 3] = 0
	return rgba


## Number of images.
func size() -> int:
	return images.size()


## The first image with texture id [param texture_id], or null.
func find_texture(texture_id: int) -> VloImage:
	return _by_texture_id[texture_id] if _by_texture_id.has(texture_id) else null


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


# The checks FrogLord makes when loading an image header.
static func _check_header(image: VloImage) -> String:
	if image.padded_width < image.width or image.padded_height < image.height:
		return "padded size %dx%d is smaller than %dx%d" % [image.padded_width, image.padded_height, image.width, image.height]
	var expected_page_word: int = (image.page() & 0xFF) | (image.blend_mode() << 8)
	if image.texture_page_word != expected_page_word:
		return "texture page word %d, expected %d for page %d" % [image.texture_page_word, expected_page_word, image.page()]
	return ""


func _read_names(reader: ByteReader) -> void:
	if not reader.expect_signature(NAMES_SIGNATURE):
		error = "unexpected data after the pixels: %s" % reader.error
		return
	reader.read_u8() # Format version (FrogLord reads any, warning about newer ones).
	var count: int = reader.read_u16()
	for _i: int in count:
		var image_index: int = reader.read_u16()
		var length: int = reader.read_u8()
		var text: String = reader.read_fixed_string(length)
		if reader.has_error():
			error = "texture names: %s" % reader.error
			return
		if image_index < images.size():
			images[image_index].custom_name = text

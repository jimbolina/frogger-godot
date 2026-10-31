class_name VloFile
extends Resource
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
@export var images: Array[VloImage] = []
## Why parsing failed, or "".
@export var error: String = ""

var _by_texture_id: Dictionary[int, VloImage] = {}


## Converts [param width] x [param height] stored pixels (A, B, G, R) to RGBA8
## by the rule in this class's description.
static func decode_rgba(stored: PackedByteArray, width: int, height: int, black_is_transparent: bool) -> PackedByteArray:
	var swapped: PackedByteArray = stored.duplicate()
	swapped.reverse()
	var image: Image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, swapped)
	image.flip_x()
	image.flip_y()
	image.convert(Image.FORMAT_RGB8)
	image.convert(Image.FORMAT_RGBA8)
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
	if _by_texture_id.is_empty():
		for image: VloImage in images:
			if not _by_texture_id.has(image.texture_id):
				_by_texture_id[image.texture_id] = image
	return _by_texture_id[texture_id] if _by_texture_id.has(texture_id) else null

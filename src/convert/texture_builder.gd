class_name TextureBuilder
extends RefCounted
## Turns decoded [VloImage]s into Godot images and textures.
##
## One [ImageTexture] per game texture, holding the whole stored image
## including its padding, without mipmaps (the game had none; filtering is
## chosen where the texture is drawn). [method uv_rect] says where the in-game
## image sits inside it, for mapping game UVs.


## An [Image] (RGBA8, padded size, no mipmaps) of [param image]'s pixels.
static func build_image(image: VloImage) -> Image:
	return Image.create_from_data(image.padded_width, image.padded_height, false, Image.FORMAT_RGBA8, image.pixels)


## An [Image] of only the in-game region (padding removed), as FrogLord exports it.
static func build_unpadded_image(image: VloImage) -> Image:
	return Image.create_from_data(image.width, image.height, false, Image.FORMAT_RGBA8, image.unpadded_pixels())


## An [ImageTexture] of [param image] (padded, no mipmaps).
static func build_texture(image: VloImage) -> ImageTexture:
	return ImageTexture.create_from_image(build_image(image))


## The in-game region inside the padded texture, in normalised texture
## coordinates (0..1): use it as the UV rectangle of a sprite, or offset map
## UVs by it.
static func uv_rect(image: VloImage) -> Rect2:
	var w: float = image.padded_width
	var h: float = image.padded_height
	return Rect2(image.left_padding() / w, image.top_padding() / h, image.width / w, image.height / h)


## The in-game region inside the padded texture, in pixels.
static func pixel_rect(image: VloImage) -> Rect2i:
	return Rect2i(image.left_padding(), image.top_padding(), image.width, image.height)

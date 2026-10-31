class_name TextureBuilder
extends RefCounted
## Turns decoded [VloImage]s into Godot images and textures.
##
## One texture per game texture, holding the whole stored image including its
## padding, without mipmaps (the game had none; filtering is chosen where the
## texture is drawn). [method uv_rect] says where the in-game image sits inside
## it, for mapping game UVs. An imported image has no [member VloImage.pixels]
## but carries its [member VloImage.texture]; images are then read back from
## that texture.


## An [Image] (RGBA8, padded size, no mipmaps) of [param image]'s pixels, or of
## its imported texture when it has no pixels.
static func build_image(image: VloImage) -> Image:
	if image.pixels.is_empty() and image.texture != null:
		var imported: Image = image.texture.get_image()
		if imported != null:
			if imported.is_compressed():
				imported.decompress()
			imported.convert(Image.FORMAT_RGBA8)
			return imported
	return Image.create_from_data(image.padded_width, image.padded_height, false, Image.FORMAT_RGBA8, image.pixels)


## An [Image] of only the in-game region (padding removed), as FrogLord exports it.
static func build_unpadded_image(image: VloImage) -> Image:
	if image.pixels.is_empty() and image.texture != null:
		return build_image(image).get_region(pixel_rect(image))
	return Image.create_from_data(image.width, image.height, false, Image.FORMAT_RGBA8, image.unpadded_pixels())


## An [ImageTexture] of [param image] (padded, no mipmaps).
static func build_texture(image: VloImage) -> ImageTexture:
	return ImageTexture.create_from_image(build_image(image))


## A 2D texture of only the in-game region: an [AtlasTexture] over the imported
## texture (clipped so filtering never reads the padding) when the image has
## one, else an [ImageTexture] of [method build_unpadded_image]. Not for 3D
## materials, which ignore an atlas region.
static func unpadded_texture(image: VloImage) -> Texture2D:
	if image.texture != null:
		var region := AtlasTexture.new()
		region.atlas = image.texture
		region.region = Rect2(pixel_rect(image))
		region.filter_clip = true
		return region
	return ImageTexture.create_from_image(build_unpadded_image(image))


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

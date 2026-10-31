class_name TextureBuilder
extends RefCounted
## Reads [VloImage]s' textures back as images and maps the in-game region.
##
## Each game texture is one [member VloImage.texture] holding the whole stored
## image including its padding, without mipmaps (the game had none; filtering
## is chosen where the texture is drawn). [method uv_rect] says where the
## in-game image sits inside it, for mapping game UVs.


## An [Image] (RGBA8, padded size, no mipmaps) of [param image]'s texture, or
## null when it has none.
static func build_image(image: VloImage) -> Image:
	var pixels: Image = image.texture.get_image() if image.texture != null else null
	if pixels == null:
		return null
	if pixels.is_compressed():
		pixels.decompress()
	pixels.convert(Image.FORMAT_RGBA8)
	return pixels


## An [Image] of only the in-game region (padding removed), as FrogLord
## exports it, or null when the image has no texture.
static func build_unpadded_image(image: VloImage) -> Image:
	var padded: Image = build_image(image)
	return padded.get_region(pixel_rect(image)) if padded != null else null


## A 2D texture of only the in-game region: an [AtlasTexture] over the image's
## texture, clipped so filtering never reads the padding; null when it has no
## texture. Not for 3D materials, which ignore an atlas region.
static func unpadded_texture(image: VloImage) -> Texture2D:
	if image.texture == null:
		return null
	var region := AtlasTexture.new()
	region.atlas = image.texture
	region.region = Rect2(pixel_rect(image))
	region.filter_clip = true
	return region


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

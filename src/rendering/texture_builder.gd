class_name TextureBuilder
extends RefCounted
## Reads [VloImage]s' textures back as images and maps the in-game region.
##
## Each game texture holds the whole stored image including its padding: the
## record's own [member VloImage.texture], or the image a catalog draws in its
## place (a texture pack's or a lettering image), which keeps the layout at a
## whole multiple of the padded size. An upscaled texture
## ([method is_upscaled]) samples linearly with mipmaps. [method uv_rect]
## says where the in-game image sits inside it, for mapping game UVs;
## [method texture_rect] says the same in a given texture's pixels, and 2D
## draws crop that region and draw it at the record's retail size. A
## [CanvasTexture] stands for its [member CanvasTexture.diffuse_texture].


## An [Image] (RGBA8, the texture's size, no mipmaps) of [param texture], or
## of [param image]'s own texture without one; null when there is none.
static func build_image(image: VloImage, texture: Texture2D = null) -> Image:
	var source: Texture2D = source_texture(texture if texture != null else image.texture)
	var pixels: Image = source.get_image() if source != null else null
	if pixels == null:
		return null
	if pixels.is_compressed():
		pixels.decompress()
	if pixels.has_mipmaps():
		pixels.clear_mipmaps()
	pixels.convert(Image.FORMAT_RGBA8)
	return pixels


## The texture whose pixels [param texture] draws: the
## [member CanvasTexture.diffuse_texture] of a [CanvasTexture], otherwise
## [param texture] itself (null for null).
static func source_texture(texture: Texture2D) -> Texture2D:
	var canvas: CanvasTexture = texture as CanvasTexture
	return canvas.diffuse_texture if canvas != null else texture


## An [Image] of only the in-game region (padding removed) of [param texture],
## or of [param image]'s own texture without one, as FrogLord exports it; null
## when there is none. Its size is the record's in-game size times the
## texture's scale.
static func build_unpadded_image(image: VloImage, texture: Texture2D = null) -> Image:
	var source: Texture2D = texture if texture != null else image.texture
	var padded: Image = build_image(image, source)
	return padded.get_region(Rect2i(texture_rect(image, source))) if padded != null else null


## A 2D texture of only the in-game region: an [AtlasTexture] over
## [param texture], or [param image]'s own texture without one, clipped so
## filtering never reads the padding; null when there is none. Not for 3D
## materials, which ignore an atlas region.
static func unpadded_texture(image: VloImage, texture: Texture2D = null) -> Texture2D:
	var source: Texture2D = texture if texture != null else image.texture
	if source == null:
		return null
	var region := AtlasTexture.new()
	region.atlas = source
	region.region = texture_rect(image, source)
	region.filter_clip = true
	return region


## The in-game region inside the padded texture, in normalised texture
## coordinates (0..1): use it as the UV rectangle of a sprite, or offset map
## UVs by it.
static func uv_rect(image: VloImage) -> Rect2:
	var w: float = image.padded_width
	var h: float = image.padded_height
	return Rect2(image.left_padding() / w, image.top_padding() / h, image.width / w, image.height / h)


## The in-game region inside the padded texture, in the record's pixels.
static func pixel_rect(image: VloImage) -> Rect2i:
	return Rect2i(image.left_padding(), image.top_padding(), image.width, image.height)


## Pixels of [param texture] per record pixel of [param image] on each axis:
## its size over the padded size, [constant Vector2.ONE] for a null texture.
static func texture_scale(image: VloImage, texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ONE
	return Vector2(texture.get_size()) / Vector2(image.padded_width, image.padded_height)


## True when [param texture] is larger than [param image]'s padded size: a
## texture pack's image at a scale above 1 or a lettering image, drawn with
## linear filtering and mipmaps. False for null or a record without a size.
static func is_upscaled(image: VloImage, texture: Texture2D) -> bool:
	return texture != null and image != null and image.padded_width > 0 and texture.get_width() > image.padded_width


## The in-game region inside [param texture], a whole padded texture of
## [param image] at any scale, in that texture's pixels: [method uv_rect]
## scaled by its size. Use it as the source rectangle of a 2D draw.
static func texture_rect(image: VloImage, texture: Texture2D) -> Rect2:
	var scale: Vector2 = texture_scale(image, texture)
	var pixels := Rect2(pixel_rect(image))
	return Rect2(pixels.position * scale, pixels.size * scale)


## The size to draw the whole of [param texture], a padded texture of
## [param image] at any scale, at on the retail 640x480 canvas: its size over
## [method texture_scale], which is the record's padded size.
static func retail_size(image: VloImage, texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2(image.padded_width, image.padded_height)
	return (Vector2(texture.get_size()) / texture_scale(image, texture)).round()

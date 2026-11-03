class_name ScaledTextureCatalog
extends AssetCatalog
## A catalog for tests that draws each record's texture enlarged [member scale]
## times by repeating pixels, with mipmaps, as a texture pack's image at that
## scale would be; with [member only] set, just those texture ids.

## Pixels per retail pixel of the textures drawn.
var scale: int = 4
## The texture ids drawn enlarged; empty for every texture.
var only: Dictionary[int, bool] = {}
var _scaled: Dictionary[VloImage, Texture2D] = {}


func texture_of(image: VloImage) -> Texture2D:
	if image == null or image.texture == null:
		return image.texture if image != null else null
	if not only.is_empty() and not only.has(image.texture_id):
		return image.texture
	if not _scaled.has(image):
		var pixels: Image = image.texture.get_image()
		pixels.resize(image.padded_width * scale, image.padded_height * scale, Image.INTERPOLATE_NEAREST)
		pixels.generate_mipmaps()
		_scaled[image] = ImageTexture.create_from_image(pixels)
	return _scaled[image]

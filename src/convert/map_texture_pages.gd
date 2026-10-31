class_name MapTexturePages
extends RefCounted
## The PC 256x256 VRAM pages a map samples with byte-wrapped UVs, from the
## [TexturePageSet] baked for its two banks. A page's colour key applies to
## all its pixels, including neighbouring images, and is already baked in.

## Missing page observations; callers may show a visible fallback.
var diagnostics := PackedStringArray()
var _set: TexturePageSet
var _images: Dictionary[int, Image] = {}
var _textures: Dictionary[int, Texture2D] = {}

## Uses the pages of [param page_set]; with none, every page is missing.
func configure_set(page_set: TexturePageSet) -> void:
	_set = page_set
	_images.clear()
	_textures.clear()
	diagnostics.clear()

## Cached texture of the page containing an image, without per-image UV clamping.
func texture_for(image: VloImage) -> Texture2D:
	return texture_for_page(image.page()) if image != null else null

## Texture of a physical page; null for an invalid page or a missing set.
func texture_for_page(page: int) -> Texture2D:
	var texture: Texture2D = _set.page(page) if _set != null else null
	if texture == null:
		_warn("Invalid PC texture page %d" % page)
		return null
	_textures[page] = texture
	return texture

## The RGBA pixels of a page, useful for pixel-level verification.
func image_for_page(page: int) -> Image:
	if _images.has(page):
		return _images[page]
	var texture: Texture2D = texture_for_page(page)
	var pixels: Image = texture.get_image() if texture != null else null
	if pixels == null:
		return null
	if pixels.is_compressed():
		pixels.decompress()
	pixels.convert(Image.FORMAT_RGBA8)
	_images[page] = pixels
	return pixels

## The baked sky-land atlas of the configured page set, or null when it has none.
func baked_sky_atlas() -> Texture2D:
	return _set.sky_atlas if _set != null else null

## Number of page textures handed out; animation never adds per-frame textures.
func cached_texture_count() -> int:
	return _textures.size()

## Stable IDs of the page textures handed out, for playback allocation checks.
func cached_texture_ids() -> PackedInt64Array:
	var ids := PackedInt64Array()
	for texture: Texture2D in _textures.values():
		ids.append(texture.get_instance_id())
	ids.sort()
	return ids

func _warn(message: String) -> void:
	if not diagnostics.has(message):
		diagnostics.append(message)

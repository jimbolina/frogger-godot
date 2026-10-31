class_name MapTexturePages
extends RefCounted
## Reconstructs PC 256x256 VRAM pages in bank upload order for byte-wrapped map UVs.
## A page's colour key applies to all pixels, including neighbouring images.
## Map runtime follows frozen PC exact RGB zero, overriding P3 decoded image alpha.
## Imported assets supply the pages already baked as a [TexturePageSet]
## ([method configure_set]); otherwise they are composed from the banks'
## pixels ([method configure]).

const PAGE_SIZE: int = 256
const PAGE_COUNT: int = 14
## Invalid upload observations; callers may show a black fallback page.
var diagnostics := PackedStringArray()
var _library: TextureLibrary
var _set: TexturePageSet
var _bank_count: int = -1
var _images: Dictionary[int, Image] = {}
var _textures: Dictionary[int, Texture2D] = {}

## Starts a scene-owned lazy cache. Later banks overwrite earlier physical pixels.
func configure(library: TextureLibrary) -> void:
	_library = library
	_set = null
	_bank_count = library.bank_count()
	_images.clear()
	_textures.clear()
	diagnostics.clear()

## Uses the baked pages of [param page_set] instead of composing them.
func configure_set(page_set: TexturePageSet) -> void:
	_library = null
	_set = page_set
	_bank_count = -1
	_images.clear()
	_textures.clear()
	diagnostics.clear()

## Cached texture of the page containing an image, without per-image UV clamping.
func texture_for(image: VloImage) -> Texture2D:
	return texture_for_page(image.page()) if image != null else null

## Cached texture of a physical page; null for an invalid page or missing library.
func texture_for_page(page: int) -> Texture2D:
	if _set != null:
		return _baked_texture(page)
	var pixels: Image = image_for_page(page)
	if pixels == null:
		return null
	if not _textures.has(page):
		_textures[page] = ImageTexture.create_from_image(pixels)
	return _textures[page]

## Reconstructed RGBA page, useful for pixel-level verification.
func image_for_page(page: int) -> Image:
	if _set != null:
		return _baked_image(page)
	if _library == null or page < 0 or page >= PAGE_COUNT:
		_warn("Invalid PC texture page %d" % page)
		return null
	if _library.bank_count() != _bank_count:
		configure(_library)
	if _images.has(page):
		return _images[page]
	var result: Image = Image.create(PAGE_SIZE, PAGE_SIZE, false, Image.FORMAT_RGBA8)
	result.fill(Color.BLACK)
	var black_key: bool = false
	var page_rect := Rect2i(0, page * PAGE_SIZE, PAGE_SIZE, PAGE_SIZE)
	for bank_index: int in _library.bank_count():
		var bank: VloFile = _library.bank_at(bank_index)
		for image: VloImage in bank.images:
			if not _valid_upload(image):
				continue
			if image.page() == page and image.has_flag(VloImage.FLAG_BLACK_IS_TRANSPARENT):
				black_key = true
			var upload := Rect2i(image.vram_x, image.vram_y, image.padded_width, image.padded_height)
			var overlap: Rect2i = upload.intersection(page_rect)
			if not overlap.has_area():
				continue
			var source: Image = TextureBuilder.build_image(image)
			result.blit_rect(source, Rect2i(overlap.position - upload.position, overlap.size), overlap.position - page_rect.position)
	var bytes: PackedByteArray = result.get_data()
	var words: PackedInt32Array = bytes.to_int32_array()
	for index: int in words.size():
		bytes[index * 4 + 3] = 0 if black_key and words[index] & 0x00ffffff == 0 else 255
	result.set_data(PAGE_SIZE, PAGE_SIZE, false, Image.FORMAT_RGBA8, bytes)
	_images[page] = result
	return result

## The baked sky-land atlas of the configured page set, or null when the pages
## are composed from banks or the set has none.
func baked_sky_atlas() -> Texture2D:
	return _set.sky_atlas if _set != null else null

## Number of page textures allocated; animation never adds per-frame textures.
func cached_texture_count() -> int:
	return _textures.size()

func _baked_texture(page: int) -> Texture2D:
	var texture: Texture2D = _set.page(page)
	if texture == null:
		_warn("Invalid PC texture page %d" % page)
		return null
	_textures[page] = texture
	return texture

func _baked_image(page: int) -> Image:
	if _images.has(page):
		return _images[page]
	var texture: Texture2D = _baked_texture(page)
	var pixels: Image = texture.get_image() if texture != null else null
	if pixels == null:
		return null
	if pixels.is_compressed():
		pixels.decompress()
	pixels.convert(Image.FORMAT_RGBA8)
	_images[page] = pixels
	return pixels

func _valid_upload(image: VloImage) -> bool:
	if image.vram_x < 0 or image.vram_y < 0 or image.padded_width <= 0 or image.padded_height <= 0 or image.vram_x + image.padded_width > PAGE_SIZE or image.vram_y + image.padded_height > PAGE_COUNT * PAGE_SIZE or image.pixels.size() != image.padded_width * image.padded_height * 4:
		_warn("Texture %d has an invalid physical VRAM upload" % image.texture_id)
		return false
	return true

func _warn(message: String) -> void:
	if not diagnostics.has(message):
		diagnostics.append(message)


## Stable IDs of allocated page textures, for playback allocation checks.
func cached_texture_ids() -> PackedInt64Array:
	var ids := PackedInt64Array()
	for texture: Texture2D in _textures.values():
		ids.append(texture.get_instance_id())
	ids.sort()
	return ids

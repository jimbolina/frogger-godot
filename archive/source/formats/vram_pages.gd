class_name VramPages
extends RefCounted
## Composes the PC game's 256 x 256 VRAM texture pages and the sky-land atlas
## from decoded texture banks, as the importer bakes them into a
## [TexturePageSet].
##
## A page starts black; every valid upload of each bank is copied in bank
## upload order, so later banks overwrite earlier physical pixels, and an upload
## may run on into the next page. When a texture whose own page it is has
## [constant VloImage.FLAG_BLACK_IS_TRANSPARENT], exact RGB zero anywhere on the
## page is transparent and every other pixel opaque, as the frozen PC sampler
## does, overriding the decoded image alpha; otherwise the page is opaque.

const PAGE_SIZE: int = TexturePageSet.PAGE_SIZE
const PAGE_COUNT: int = TexturePageSet.PAGE_COUNT


## Page [param page] of [param banks] in upload order, or null outside 0-13
## (with a line in [param diagnostics]). Each invalid upload adds one line.
static func compose_page(banks: Array[VloFile], page: int, diagnostics: PackedStringArray) -> Image:
	if page < 0 or page >= PAGE_COUNT:
		_warn(diagnostics, "Invalid PC texture page %d" % page)
		return null
	var result: Image = Image.create(PAGE_SIZE, PAGE_SIZE, false, Image.FORMAT_RGBA8)
	result.fill(Color.BLACK)
	var page_rect := Rect2i(0, page * PAGE_SIZE, PAGE_SIZE, PAGE_SIZE)
	for bank: VloFile in banks:
		for image: VloImage in bank.images:
			if not fits(image) or image.pixels.size() != image.padded_width * image.padded_height * 4:
				_warn(diagnostics, "Texture %d has an invalid physical VRAM upload" % image.texture_id)
				continue
			var upload := Rect2i(image.vram_x, image.vram_y, image.padded_width, image.padded_height)
			var overlap: Rect2i = upload.intersection(page_rect)
			if not overlap.has_area():
				continue
			var source: Image = Image.create_from_data(image.padded_width, image.padded_height, false, Image.FORMAT_RGBA8, image.pixels)
			result.blit_rect(source, Rect2i(overlap.position - upload.position, overlap.size), overlap.position - page_rect.position)
	var keyed: bool = colour_keyed(banks, page)
	var bytes: PackedByteArray = result.get_data()
	var words: PackedInt32Array = bytes.to_int32_array()
	for index: int in words.size():
		bytes[index * 4 + 3] = 0 if keyed and words[index] & 0x00ffffff == 0 else 255
	result.set_data(PAGE_SIZE, PAGE_SIZE, false, Image.FORMAT_RGBA8, bytes)
	return result


## The fourteen pages of [param banks], null where a page cannot be composed.
static func compose_pages(banks: Array[VloFile], diagnostics: PackedStringArray) -> Array[Image]:
	var pages: Array[Image] = []
	for page: int in PAGE_COUNT:
		pages.append(compose_page(banks, page, diagnostics))
	return pages


## True when a valid upload whose own page is [param page] has the colour-key flag.
static func colour_keyed(banks: Array[VloFile], page: int) -> bool:
	for bank: VloFile in banks:
		for image: VloImage in bank.images:
			if image.page() == page and image.has_flag(VloImage.FLAG_BLACK_IS_TRANSPARENT) and fits(image):
				return true
	return false


## True when [param image]'s padded upload lies inside the fourteen pages.
static func fits(image: VloImage) -> bool:
	return image.vram_x >= 0 and image.vram_y >= 0 and image.padded_width > 0 and image.padded_height > 0 \
		and image.vram_x + image.padded_width <= PAGE_SIZE and image.vram_y + image.padded_height <= PAGE_COUNT * PAGE_SIZE


## The sky atlas page order of [param sky]: the page of each tile's image
## through [param remap], from [param theme] when it has the texture, else from
## [param general], in first-seen order; -1 stands for a missing image.
static func sky_order(general: VloFile, theme: VloFile, sky: SkyLandFile, remap: TextureRemap) -> PackedInt32Array:
	var order := PackedInt32Array()
	for local_id: int in sky.texture_ids:
		var texture_id: int = remap.global_id(local_id)
		var image: VloImage = theme.find_texture(texture_id) if texture_id >= 0 else null
		if image == null and texture_id >= 0:
			image = general.find_texture(texture_id)
		var page: int = image.page() if image != null else -1
		if not order.has(page):
			order.append(page)
	return order


## The sky atlas: 256 wide and [constant TexturePageSet.SKY_SLOT_HEIGHT] rows
## per slot of [param order], magenta, each page in rows 1-256 of its slot
## with its first and last rows repeated above and below. A page that is
## missing from [param pages] (or -1) leaves its slot magenta.
static func sky_atlas(pages: Array[Image], order: PackedInt32Array) -> Image:
	var atlas: Image = Image.create(PAGE_SIZE, TexturePageSet.SKY_SLOT_HEIGHT * maxi(1, order.size()), false, Image.FORMAT_RGBA8)
	atlas.fill(Color.MAGENTA)
	for slot: int in order.size():
		var page: int = order[slot]
		if page < 0 or page >= pages.size() or pages[page] == null:
			continue
		var top: int = slot * TexturePageSet.SKY_SLOT_HEIGHT
		atlas.blit_rect(pages[page], Rect2i(0, 0, PAGE_SIZE, PAGE_SIZE), Vector2i(0, top + 1))
		atlas.blit_rect(pages[page], Rect2i(0, 0, PAGE_SIZE, 1), Vector2i(0, top))
		atlas.blit_rect(pages[page], Rect2i(0, PAGE_SIZE - 1, PAGE_SIZE, 1), Vector2i(0, top + PAGE_SIZE + 1))
	return atlas


## A [TexturePageSet] held in memory for banks [param general] then
## [param theme] (called [param names]), with [ImageTexture] pages; with
## [param with_sky] it also holds the sky atlas of [param sky_pages].
## Composition problems are added to [param diagnostics].
static func page_set(names: PackedStringArray, general: VloFile, theme: VloFile, diagnostics: PackedStringArray,
		with_sky: bool = false, sky_pages: PackedInt32Array = PackedInt32Array()) -> TexturePageSet:
	var banks: Array[VloFile] = [general, theme]
	var result := TexturePageSet.new()
	result.set_name = TexturePageSet.name_for(names)
	result.resource_name = result.set_name
	result.bank_names = names
	var pages: Array[Image] = compose_pages(banks, diagnostics)
	for page: int in PAGE_COUNT:
		result.pages.append(ImageTexture.create_from_image(pages[page]) if pages[page] != null else null)
		result.colour_keyed.append(colour_keyed(banks, page))
	if with_sky:
		result.sky_pages = sky_pages
		result.sky_atlas = ImageTexture.create_from_image(sky_atlas(pages, result.sky_pages))
	return result


static func _warn(diagnostics: PackedStringArray, message: String) -> void:
	if not diagnostics.has(message):
		diagnostics.append(message)

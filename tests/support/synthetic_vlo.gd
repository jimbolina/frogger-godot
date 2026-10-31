class_name SyntheticVlo
extends RefCounted
## Describes small PC texture banks for tests and builds them as [VloFile]
## records, with the values a bank laid out the same way decodes to.


## One image for [method bank]: header values and stored A,B,G,R pixels.
class Spec:
	extends RefCounted
	var vram_x: int = 0
	var vram_y: int = 0
	var padded_width: int = 1
	var padded_height: int = 1
	var width: int = 1
	var height: int = 1
	var texture_id: int = 0
	var flags: int = 0
	var blend_mode: int = 0
	## Stored pixels, A,B,G,R per pixel.
	var abgr := PackedByteArray()


static func spec(w: int, h: int, pad: int, texture_id: int, flags: int, stored: PackedByteArray) -> Spec:
	var s := Spec.new()
	s.padded_width = w + pad
	s.padded_height = h + pad
	s.width = w
	s.height = h
	s.texture_id = texture_id
	s.flags = flags
	s.abgr = stored
	return s


## Stored pixels from R,G,B triples, with alpha byte [param stored_alpha].
static func abgr(rgb: Array[int], stored_alpha: int = 0) -> PackedByteArray:
	var out := PackedByteArray()
	for i: int in range(0, rgb.size(), 3):
		out.append_array(PackedByteArray([stored_alpha, rgb[i + 2], rgb[i + 1], rgb[i]]))
	return out


## The bank of [param specs], each image holding its pixels and a
## [member VloImage.texture] of them; with [param decode_pixels] false the
## images keep neither.
static func bank(specs: Array[Spec], decode_pixels: bool = true) -> VloFile:
	var vlo := VloFile.new()
	var offset: int = VloFile.HEADER_SIZE + 24 * specs.size()
	for i: int in specs.size():
		var s: Spec = specs[i]
		offset = (offset + 3) & ~3
		var image := VloImage.new()
		image.index = i
		image.vram_x = s.vram_x
		image.vram_y = s.vram_y
		image.padded_width = s.padded_width
		image.padded_height = s.padded_height
		image.data_offset = offset
		image.texture_id = s.texture_id
		image.texture_page_word = ((s.vram_y / 256) & 0xFF) | (s.blend_mode << 8)
		image.flags = s.flags
		image.u = ((s.vram_x % 256) + (s.padded_width - s.width) / 2) & 0xFF
		image.v = ((s.vram_y % 256) + (s.padded_height - s.height) / 2) & 0xFF
		image.width = s.width & 0xFF if s.width & 0xFF != 0 else 256
		image.height = s.height & 0xFF if s.height & 0xFF != 0 else 256
		if decode_pixels:
			image.pixels = VloFile.decode_rgba(s.abgr, s.padded_width, s.padded_height,
				image.has_flag(VloImage.FLAG_BLACK_IS_TRANSPARENT))
			image.texture = ImageTexture.create_from_image(Image.create_from_data(s.padded_width, s.padded_height,
				false, Image.FORMAT_RGBA8, image.pixels))
		vlo.images.append(image)
		offset += s.abgr.size()
	return vlo


## A [TexturePageSet] of [param banks]: each image's texture copied onto
## black pages at its VRAM position in bank order, without a colour key; with
## [param with_sky] also a magenta sky atlas with a slot per page of
## [param sky_pages].
static func page_set(banks: Array[VloFile], with_sky: bool = false, sky_pages: PackedInt32Array = PackedInt32Array()) -> TexturePageSet:
	var result := TexturePageSet.new()
	for page: int in TexturePageSet.PAGE_COUNT:
		var pixels: Image = Image.create(TexturePageSet.PAGE_SIZE, TexturePageSet.PAGE_SIZE, false, Image.FORMAT_RGBA8)
		pixels.fill(Color.BLACK)
		var page_rect := Rect2i(0, page * TexturePageSet.PAGE_SIZE, TexturePageSet.PAGE_SIZE, TexturePageSet.PAGE_SIZE)
		for source: VloFile in banks:
			for image: VloImage in source.images:
				var upload := Rect2i(image.vram_x, image.vram_y, image.padded_width, image.padded_height)
				var overlap: Rect2i = upload.intersection(page_rect)
				if image.texture != null and overlap.has_area():
					pixels.blit_rect(image.texture.get_image(), Rect2i(overlap.position - upload.position, overlap.size),
						overlap.position - page_rect.position)
		result.pages.append(ImageTexture.create_from_image(pixels))
		result.colour_keyed.append(false)
	if with_sky:
		var atlas: Image = Image.create(TexturePageSet.PAGE_SIZE, TexturePageSet.SKY_SLOT_HEIGHT * maxi(1, sky_pages.size()),
			false, Image.FORMAT_RGBA8)
		atlas.fill(Color.MAGENTA)
		result.sky_atlas = ImageTexture.create_from_image(atlas)
		result.sky_pages = sky_pages
	return result

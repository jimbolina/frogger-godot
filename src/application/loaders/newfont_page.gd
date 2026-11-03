class_name NewfontPage
extends RefCounted
## Builds the page of the [code]newfont[/code] bitmap font from an image of
## texture 310 at runtime, the way [code]tools/make_font_newfont.py[/code]
## builds its golden page, so a texture pack that redraws the font is drawn
## by the font too.
##
## Texture 310 holds the 96 glyphs of ASCII 32..127 in 8 x 8 cells, 32 to a
## row in three rows. The page holds them at [constant PAGE_SCALE] page
## pixels per retail pixel: an image at a scale dividing it is enlarged by
## repeating pixels, any other scale is resampled with Lanczos. Each glyph
## sits inside a [constant BORDER]-pixel transparent border, and the
## [constant FILL_RINGS] rings of transparent pixels around its opaque pixels
## within its cell take the per-channel maximum colour of their filled
## neighbours, so linear filtering does not darken the edges. The glyph
## layout of [NewfontFont] therefore fits the page at any source scale.

## The bitmap font's name in the catalog.
const FONT_NAME: String = "newfont"
## The texture id of the glyph grid.
const TEXTURE_ID: int = 310
## The retail glyph cell in pixels.
const CELL: int = 8
## Glyphs per row.
const COLUMNS: int = 32
## Rows of glyphs.
const ROWS: int = 3
## Page pixels per retail pixel.
const PAGE_SCALE: int = 4
## A glyph's size on the page.
const GLYPH: int = CELL * PAGE_SCALE
## The transparent border around each glyph on the page.
const BORDER: int = PAGE_SCALE
## A page cell: the glyph and its border.
const STRIDE: int = GLYPH + 2 * BORDER
## Rings of edge colour filled around each glyph.
const FILL_RINGS: int = 2
## The padded size of texture 310 in retail pixels.
const RETAIL_SIZE: Vector2i = Vector2i(COLUMNS * CELL, ROWS * CELL)
## The page's size.
const PAGE_SIZE: Vector2i = Vector2i(COLUMNS * STRIDE, ROWS * STRIDE)
## The cache size key of the font's page, as Godot's BMFont importer stores it.
const CACHE_SIZE: Vector2i = Vector2i(GLYPH, 0)


## The RGBA8 page built from [param source], an image of texture 310 at a
## whole multiple of [constant RETAIL_SIZE], or null when it is not one.
static func build(source: Image) -> Image:
	if source == null:
		return null
	var scale: int = TextureSet.scale_for(source.get_size(), RETAIL_SIZE)
	if scale == 0:
		return null
	var grid: Image = source.duplicate() as Image
	if grid.is_compressed():
		grid.decompress()
	grid.clear_mipmaps()
	grid.convert(Image.FORMAT_RGBA8)
	if scale != PAGE_SCALE:
		var interpolation: Image.Interpolation = Image.INTERPOLATE_NEAREST if PAGE_SCALE % scale == 0 \
			else Image.INTERPOLATE_LANCZOS
		grid.resize(RETAIL_SIZE.x * PAGE_SCALE, RETAIL_SIZE.y * PAGE_SCALE, interpolation)
	var pixels: PackedByteArray = grid.get_data()
	var grid_width: int = RETAIL_SIZE.x * PAGE_SCALE
	var width: int = PAGE_SIZE.x
	var height: int = PAGE_SIZE.y
	var page := PackedByteArray()
	page.resize(width * height * 4)
	var filled := PackedByteArray()
	filled.resize(width * height)
	for index: int in COLUMNS * ROWS:
		var column: int = index % COLUMNS
		@warning_ignore("integer_division")
		var row: int = index / COLUMNS
		for y: int in GLYPH:
			var from_row: int = (row * GLYPH + y) * grid_width + column * GLYPH
			var to_row: int = (row * STRIDE + BORDER + y) * width + column * STRIDE + BORDER
			for x: int in GLYPH:
				var from: int = (from_row + x) * 4
				var to: int = to_row + x
				page[to * 4] = pixels[from]
				page[to * 4 + 1] = pixels[from + 1]
				page[to * 4 + 2] = pixels[from + 2]
				page[to * 4 + 3] = pixels[from + 3]
				filled[to] = 1 if pixels[from + 3] != 0 else 0
	for ring: int in FILL_RINGS:
		_fill_ring(page, filled, width, height)
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, page)


static func _fill_ring(page: PackedByteArray, filled: PackedByteArray, width: int, height: int) -> void:
	var cell_x: PackedInt32Array = _cells(width)
	var cell_y: PackedInt32Array = _cells(height)
	var colour := PackedByteArray()
	colour.resize(width * height * 3)
	var reached := PackedByteArray()
	reached.resize(width * height)
	for y: int in height:
		for x: int in width:
			var at: int = y * width + x
			if filled[at] == 0:
				continue
			for dy: int in range(-1, 2):
				var ny: int = y + dy
				if ny < 0 or ny >= height or cell_y[ny] != cell_y[y]:
					continue
				for dx: int in range(-1, 2):
					var nx: int = x + dx
					if (dx == 0 and dy == 0) or nx < 0 or nx >= width or cell_x[nx] != cell_x[x]:
						continue
					var near: int = ny * width + nx
					if filled[near] != 0:
						continue
					for channel: int in 3:
						colour[near * 3 + channel] = maxi(colour[near * 3 + channel], page[at * 4 + channel])
					reached[near] = 1
	for at: int in width * height:
		if reached[at] == 0:
			continue
		page[at * 4] = colour[at * 3]
		page[at * 4 + 1] = colour[at * 3 + 1]
		page[at * 4 + 2] = colour[at * 3 + 2]
		filled[at] = 1


static func _cells(length: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	cells.resize(length)
	for at: int in length:
		@warning_ignore("integer_division")
		var cell: int = at / STRIDE
		cells[at] = cell
	return cells

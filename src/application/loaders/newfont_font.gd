class_name NewfontFont
extends RefCounted
## Builds the [code]newfont[/code] bitmap font at runtime around a page from
## [NewfontPage], with the glyph layout that [code]tools/make_font_newfont.py[/code]
## writes into the committed [code]newfont.fnt[/code] and Godot's BMFont
## importer reads from it.
##
## A packaged build ships no font page, because the page holds texture 310's
## retail pixels; the catalog then builds the font from the player's imported
## texture 310. The layout is fixed by the page geometry alone: 96 glyphs of
## ASCII 32..127, 32 to a row, each a [constant NewfontPage.STRIDE]-pixel cell
## drawn [constant NewfontPage.BORDER] pixels up and left of its pen position
## and advancing one glyph width, at a fixed size of one glyph height with
## fractional scaling and no antialiasing.

## The first character code on the page.
const FIRST_CHARACTER: int = 32


## A [FontFile] drawing [param page], a page of [constant NewfontPage.PAGE_SIZE],
## or null when [param page] is null or of another size.
static func build(page: Image) -> FontFile:
	if page == null or page.get_size() != NewfontPage.PAGE_SIZE:
		return null
	var font := FontFile.new()
	font.font_name = NewfontPage.FONT_NAME
	font.fixed_size = NewfontPage.GLYPH
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.generate_mipmaps = false
	font.multichannel_signed_distance_field = false
	font.msdf_pixel_range = 14
	font.msdf_size = 128
	font.allow_system_fallback = false
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var size: Vector2i = NewfontPage.CACHE_SIZE
	font.set_cache_ascent(0, size.x, float(NewfontPage.GLYPH))
	font.set_cache_descent(0, size.x, 0.0)
	font.set_texture_image(0, size, 0, page)
	var cell := Vector2(NewfontPage.STRIDE, NewfontPage.STRIDE)
	var offset := Vector2(-NewfontPage.BORDER, -NewfontPage.BORDER - NewfontPage.GLYPH)
	for index: int in NewfontPage.COLUMNS * NewfontPage.ROWS:
		var glyph: int = FIRST_CHARACTER + index
		var column: int = index % NewfontPage.COLUMNS
		@warning_ignore("integer_division")
		var row: int = index / NewfontPage.COLUMNS
		font.set_glyph_advance(0, size.x, glyph, Vector2(NewfontPage.GLYPH, 0))
		font.set_glyph_offset(0, size, glyph, offset)
		font.set_glyph_size(0, size, glyph, cell)
		font.set_glyph_uv_rect(0, size, glyph, Rect2(Vector2(column, row) * cell, cell))
		font.set_glyph_texture_idx(0, size, glyph, 0)
	return font

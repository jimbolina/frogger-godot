extends AssetTest
## The committed newfont bitmap fonts (assets/fonts/<set>/newfont.fnt and its
## page newfont.png, written by tools/make_font_newfont.py) import as the glyph
## grid of texture 310: 96 glyphs of ASCII 32..127 in cells of 8 retail pixels
## times the set's scale, 32 to a row, with the texture's pixels kept exactly
## and a string measured at size 8 the same in both sets.

const FONT: String = "newfont"
const TEXTURE_ID: int = 310
const FIRST: int = 32
const COUNT: int = 96
const COLUMNS: int = 32
const RETAIL_CELL: int = 8

var _x4: ImportedAssets


func before_all() -> void:
	_x4 = ImportedAssets.open(ASSETS, TextureSet.X4)


func _sets() -> Array[Dictionary]:
	return [
		{"name": "retail", "catalog": catalog(), "scale": 1, "png": "res://assets/textures/images/t0310.png"},
		{"name": "x4", "catalog": _x4, "scale": 4, "png": "res://assets/textures/images_x4/t0310.png"},
	]


func _png(path: String) -> Image:
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func _font_of(set_name: String, assets: ImportedAssets) -> FontFile:
	var loaded: Font = assets.font(FONT)
	var font: FontFile = loaded as FontFile
	assert_not_null(font, "the %s catalog serves %s as a FontFile" % [set_name, FONT])
	return font


func test_the_x4_catalog_opens_cleanly() -> void:
	assert_eq(_x4.error, "")
	assert_eq(_x4.warnings, PackedStringArray())
	assert_eq(_x4.texture_set().set_name, TextureSet.X4)


func test_fonts_hold_the_glyph_grid() -> void:
	var mismatches := PackedStringArray()
	for entry: Dictionary in _sets():
		var set_name: String = entry["name"]
		var assets: ImportedAssets = entry["catalog"]
		var scale: int = entry["scale"]
		var font: FontFile = _font_of(set_name, assets)
		if font == null:
			continue
		var prefix: String = "res://assets/fonts/%s/" % set_name
		if not font.resource_path.begins_with(prefix):
			mismatches.append("%s: font loads from %s, not %s" % [set_name, font.resource_path, prefix])
		var cell: int = RETAIL_CELL * scale
		var size := Vector2i(cell, 0)
		var fixed_size: int = font.fixed_size
		var scale_mode: int = font.fixed_size_scale_mode
		var ascent: float = font.get_cache_ascent(0, cell)
		var descent: float = font.get_cache_descent(0, cell)
		if fixed_size != cell:
			mismatches.append("%s: fixed size %d, expected %d" % [set_name, fixed_size, cell])
		if scale_mode != TextServer.FIXED_SIZE_SCALE_ENABLED:
			mismatches.append("%s: fixed size scale mode %d, expected %d" % [set_name, scale_mode, TextServer.FIXED_SIZE_SCALE_ENABLED])
		if ascent != cell or descent != 0.0:
			mismatches.append("%s: ascent %s and descent %s, expected %d and 0" % [set_name, ascent, descent, cell])
		for code: int in range(FIRST, FIRST + COUNT):
			var at: int = code - FIRST
			var uv_rect := Rect2((at % COLUMNS) * cell, (at / COLUMNS) * cell, cell, cell)
			var got_uv: Rect2 = font.get_glyph_uv_rect(0, size, code)
			var got_size: Vector2 = font.get_glyph_size(0, size, code)
			var got_advance: Vector2 = font.get_glyph_advance(0, cell, code)
			var got_offset: Vector2 = font.get_glyph_offset(0, size, code)
			if got_uv != uv_rect:
				mismatches.append("%s glyph %d: uv rect %s, expected %s" % [set_name, code, got_uv, uv_rect])
			if got_size != Vector2(cell, cell):
				mismatches.append("%s glyph %d: size %s, expected %d" % [set_name, code, got_size, cell])
			if got_advance != Vector2(cell, 0):
				mismatches.append("%s glyph %d: advance %s, expected %d" % [set_name, code, got_advance, cell])
			if got_offset != Vector2(0, -cell):
				mismatches.append("%s glyph %d: offset %s, expected (0, %d)" % [set_name, code, got_offset, -cell])
	for mismatch: String in mismatches.slice(0, 10):
		fail_test(mismatch)
	assert_eq(mismatches.size(), 0, "both newfont fonts hold the %d-glyph grid" % COUNT)


func test_fonts_keep_the_texture_pixels() -> void:
	var mismatches := PackedStringArray()
	var digests := PackedStringArray()
	for row: PackedStringArray in fact_rows("vlo_images.tsv"):
		if int(row[2]) == TEXTURE_ID:
			digests.append(row[14])
	assert_gt(digests.size(), 0, "vlo_images.tsv lists texture %d" % TEXTURE_ID)
	for entry: Dictionary in _sets():
		var set_name: String = entry["name"]
		var assets: ImportedAssets = entry["catalog"]
		var scale: int = entry["scale"]
		var png: String = entry["png"]
		var font: FontFile = _font_of(set_name, assets)
		if font == null:
			continue
		var cell: int = RETAIL_CELL * scale
		var image: Image = font.get_texture_image(0, Vector2i(cell, 0), 0)
		if image == null:
			mismatches.append("%s font %s has no texture image" % [set_name, font.resource_path])
			continue
		if image.has_mipmaps():
			mismatches.append("%s font %s has mipmaps" % [set_name, font.resource_path])
		image.convert(Image.FORMAT_RGBA8)
		var expected_size := Vector2i(256 * scale, 24 * scale)
		if image.get_size() != expected_size:
			mismatches.append("%s font %s is %s, expected %s" % [set_name, font.resource_path, image.get_size(), expected_size])
			continue
		var source: Image = _png(png)
		if source == null or source.get_data() != image.get_data():
			mismatches.append("%s font %s: pixels differ from %s" % [set_name, font.resource_path, png])
		if scale == 1:
			var digest: String = sha256_hex(image.get_data())
			var asset: String = png.trim_prefix(ASSETS + "/")
			for retail: String in digests:
				if digest != expected(asset, "vlo_images", "padded_rgba_sha256", retail):
					mismatches.append("%s font %s: RGBA digest differs from texture %d" % [set_name, font.resource_path, TEXTURE_ID])
	for mismatch: String in mismatches.slice(0, 10):
		fail_test(mismatch)
	assert_eq(mismatches.size(), 0, "both newfont fonts keep their texture's pixels")


func test_a_string_measures_the_same_in_both_sets() -> void:
	for entry: Dictionary in _sets():
		var set_name: String = entry["name"]
		var assets: ImportedAssets = entry["catalog"]
		var font: FontFile = _font_of(set_name, assets)
		if font == null:
			continue
		var measured: Vector2 = font.get_string_size("1 UP", HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		assert_eq(measured, Vector2(32, 8), "%s font measures \"1 UP\" at size 8" % set_name)
	assert_eq(_x4.problems, PackedStringArray())


func test_an_unknown_font_is_null_with_a_problem() -> void:
	var assets: ImportedAssets = catalog()
	var before: int = assets.problems.size()
	var missing: Font = assets.font("no_such_font")
	assert_null(missing)
	assert_eq(assets.problems.size(), before + 1, "one problem line for the missing font")
	if assets.problems.size() > before:
		var line: String = assets.problems[before]
		assert_string_contains(line, "no_such_font")

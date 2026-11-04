extends AssetTest
## The newfont bitmap font, built at runtime from the imported texture 310,
## holds the glyph grid of texture 310: 96 glyphs of ASCII 32..127, 32 to a
## row, each a 32-pixel glyph (the texture enlarged to 4 page pixels per
## retail pixel) inside a 4-pixel transparent border, with the texture's
## pixels kept exactly. A texture pack's t0310.png is drawn by a font with the
## same grid, and a string measures the same in both. NewfontPage rebuilds the
## page tools/content/make_font_newfont.py generates (into the folder
## [constant AssetTest.GENERATED_VARIABLE] names) exactly from the retail
## texture at scales 1, 2 and 4, so the runtime builder and the generator agree.

const FONT: String = "newfont"
const TEXTURE_ID: int = 310
const FIRST: int = 32
const COUNT: int = 96
const COLUMNS: int = 32
const RETAIL_CELL: int = 8
const PAGE_SCALE: int = 4
const GLYPH: int = RETAIL_CELL * PAGE_SCALE
const BORDER: int = PAGE_SCALE
const STRIDE: int = GLYPH + 2 * BORDER

const PACKS: String = "user://test_asset_fonts_packs"
const RETAIL_PNG: String = "res://assets/textures/images/t0310.png"
const PACK_PNG: String = PACKS + "/tinted/t0310.png"

var _pack: ImportedAssets


func before_all() -> void:
	_remove(PACKS)
	assert_eq(DirAccess.make_dir_recursive_absolute(PACK_PNG.get_base_dir()), OK)
	var config := ConfigFile.new()
	config.set_value("pack", "name", "Tinted newfont")
	config.set_value("pack", "base_build", catalog().version_name)
	assert_eq(config.save(PACK_PNG.get_base_dir().path_join("pack.cfg")), OK)
	var tinted: Image = _scaled_retail(4)
	for y: int in tinted.get_height():
		for x: int in tinted.get_width():
			var pixel: Color = tinted.get_pixel(x, y)
			if pixel.a8 != 0:
				tinted.set_pixel(x, y, Color8(pixel.r8, pixel.g8 / 2, 255 - pixel.b8, pixel.a8))
	assert_eq(tinted.save_png(PACK_PNG), OK)
	_pack = ImportedAssets.open(ASSETS, "tinted", "", ImportedAssets.SHIPPABLE_ROOT, PackedStringArray([PACKS]))


func after_all() -> void:
	_remove(PACKS)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func _scaled_retail(scale: int) -> Image:
	var image: Image = _png(RETAIL_PNG)
	image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	return image


func _sets() -> Array[Dictionary]:
	return [
		{"name": "retail", "catalog": catalog(), "scale": 1, "png": RETAIL_PNG},
		{"name": "pack", "catalog": _pack, "scale": 4, "png": PACK_PNG},
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


func test_the_pack_catalog_opens_cleanly() -> void:
	assert_eq(_pack.error, "")
	assert_eq(_pack.warnings, PackedStringArray())
	assert_eq(_pack.texture_set().pack_name(), "tinted")
	assert_true(_pack.texture_set().has_source(TEXTURE_ID))


func test_the_runtime_page_rebuilds_the_generated_page() -> void:
	var folder: String = generated_folder("newfont")
	if folder.is_empty():
		return
	var page: Image = Image.load_from_file(folder.path_join("newfont.png"))
	assert_not_null(page, "the generator's newfont.png loads")
	if page == null:
		return
	page.convert(Image.FORMAT_RGBA8)
	for scale: int in [1, 2, 4]:
		var built: Image = NewfontPage.build(_scaled_retail(scale))
		assert_not_null(built, "scale %d builds a page" % scale)
		if built == null:
			continue
		assert_eq(built.get_size(), page.get_size(), "scale %d page size" % scale)
		var differing: int = 0
		for y: int in page.get_height():
			for x: int in page.get_width():
				if built.get_pixel(x, y) != page.get_pixel(x, y):
					differing += 1
		assert_eq(differing, 0, "scale %d: the runtime page matches tools/content/make_font_newfont.py pixel for pixel" % scale)
	assert_null(NewfontPage.build(Image.create(300, 24, false, Image.FORMAT_RGBA8)), "a size that is no multiple builds nothing")


func test_newfont_is_built_at_runtime_with_and_without_the_pack() -> void:
	assert_same(_pack.font("angular"), catalog().font("angular"))
	assert_eq(catalog().font(FONT).resource_path, "", "built at runtime from the imported texture 310")
	assert_ne(_pack.font(FONT), catalog().font(FONT), "the pack's t0310 gives its own font")
	assert_eq(_pack.font(FONT).resource_path, "", "built at runtime")


func test_fonts_hold_the_glyph_grid() -> void:
	var mismatches := PackedStringArray()
	for entry: Dictionary in _sets():
		var set_name: String = entry["name"]
		var assets: ImportedAssets = entry["catalog"]
		var font: FontFile = _font_of(set_name, assets)
		if font == null:
			continue
		if not font.resource_path.is_empty():
			mismatches.append("%s: font loads from %s instead of being built" % [set_name, font.resource_path])
		var cell: int = GLYPH
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
			var uv_rect := Rect2((at % COLUMNS) * STRIDE, (at / COLUMNS) * STRIDE, STRIDE, STRIDE)
			var got_uv: Rect2 = font.get_glyph_uv_rect(0, size, code)
			var got_size: Vector2 = font.get_glyph_size(0, size, code)
			var got_advance: Vector2 = font.get_glyph_advance(0, cell, code)
			var got_offset: Vector2 = font.get_glyph_offset(0, size, code)
			if got_uv != uv_rect:
				mismatches.append("%s glyph %d: uv rect %s, expected %s" % [set_name, code, got_uv, uv_rect])
			if got_size != Vector2(STRIDE, STRIDE):
				mismatches.append("%s glyph %d: size %s, expected %d" % [set_name, code, got_size, STRIDE])
			if got_advance != Vector2(cell, 0):
				mismatches.append("%s glyph %d: advance %s, expected %d" % [set_name, code, got_advance, cell])
			if got_offset != Vector2(-BORDER, -cell - BORDER):
				mismatches.append("%s glyph %d: offset %s, expected (%d, %d)" % [set_name, code, got_offset, -BORDER, -cell - BORDER])
	for mismatch: String in mismatches.slice(0, 10):
		fail_test(mismatch)
	assert_eq(mismatches.size(), 0, "the retail and pack newfont fonts hold the %d-glyph grid" % COUNT)


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
		var page: Image = font.get_texture_image(0, Vector2i(GLYPH, 0), 0)
		if page == null:
			mismatches.append("%s font %s has no texture image" % [set_name, font.resource_path])
			continue
		if page.has_mipmaps():
			mismatches.append("%s font %s has mipmaps" % [set_name, font.resource_path])
		page.convert(Image.FORMAT_RGBA8)
		var expected_size := Vector2i(COLUMNS * STRIDE, (COUNT / COLUMNS) * STRIDE)
		if page.get_size() != expected_size:
			mismatches.append("%s font %s is %s, expected %s" % [set_name, font.resource_path, page.get_size(), expected_size])
			continue
		var source: Image = _png(png)
		if source == null or source.get_size() != Vector2i(256 * scale, 24 * scale):
			mismatches.append("%s: %s is missing or not %d x %d" % [set_name, png, 256 * scale, 24 * scale])
			continue
		var factor: int = PAGE_SCALE / scale
		var differing: int = 0
		for index: int in COUNT:
			var cell_x: int = (index % COLUMNS) * STRIDE
			var cell_y: int = (index / COLUMNS) * STRIDE
			var glyph_x: int = (index % COLUMNS) * GLYPH
			var glyph_y: int = (index / COLUMNS) * GLYPH
			for y: int in STRIDE:
				for x: int in STRIDE:
					var got: Color = page.get_pixel(cell_x + x, cell_y + y)
					var inside: bool = x >= BORDER and x < BORDER + GLYPH and y >= BORDER and y < BORDER + GLYPH
					if not inside:
						if got.a8 != 0:
							differing += 1
						continue
					var want: Color = source.get_pixel((glyph_x + x - BORDER) / factor, (glyph_y + y - BORDER) / factor)
					if got.a8 != want.a8 or (want.a8 != 0 and got != want):
						differing += 1
		if differing != 0:
			mismatches.append("%s font %s: %d page pixels differ from %s" % [set_name, font.resource_path, differing, png])
		if scale == 1:
			var digest: String = sha256_hex(source.get_data())
			for retail: String in digests:
				if digest != retail:
					mismatches.append("%s: %s RGBA digest differs from texture %d" % [set_name, png, TEXTURE_ID])
	for mismatch: String in mismatches.slice(0, 10):
		fail_test(mismatch)
	assert_eq(mismatches.size(), 0, "the retail and pack newfont fonts keep their texture's pixels")


func test_a_string_measures_the_same_with_and_without_the_pack() -> void:
	for entry: Dictionary in _sets():
		var set_name: String = entry["name"]
		var assets: ImportedAssets = entry["catalog"]
		var font: FontFile = _font_of(set_name, assets)
		if font == null:
			continue
		var measured: Vector2 = font.get_string_size("1 UP", HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		assert_eq(measured, Vector2(32, 8), "%s font measures \"1 UP\" at size 8" % set_name)
	assert_eq(_pack.problems, PackedStringArray())


func test_an_unknown_font_is_null_with_a_problem() -> void:
	var assets: ImportedAssets = catalog()
	var before: int = assets.problems.size()
	var missing: Font = assets.font("no_such_font")
	assert_null(missing)
	assert_eq(assets.problems.size(), before + 1, "one problem line for the missing font")
	if assets.problems.size() > before:
		var line: String = assets.problems[before]
		assert_string_contains(line, "no_such_font")

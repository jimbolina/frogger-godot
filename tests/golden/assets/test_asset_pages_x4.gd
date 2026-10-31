extends AssetTest
## The locally baked x4 texture pages (assets/textures/pages_x4/, written by
## tools/bake_pages_x4.py from the committed images) match the independent
## facts of texture_pages_x4.tsv: one page set per retail set with the same
## banks, colour keys and sky order, every page and sky atlas at the scaled
## size with its RGBA8 digest and opaque pixel count.

const PAGES_X4: String = "res://assets/textures/pages_x4"
const FACTS: String = "texture_pages_x4.tsv"
const SCALE: int = 4

var _x4: ImportedAssets


func before_all() -> void:
	_x4 = ImportedAssets.open(ASSETS, TextureSet.X4)


func _png(path: String) -> Image:
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func _opaque_pixels(image: Image) -> int:
	var alpha_only: Image = image.duplicate() as Image
	alpha_only.adjust_bcs(0.0, 1.0, 1.0)
	alpha_only.convert(Image.FORMAT_LA8)
	return alpha_only.get_data().count(255)


func test_the_x4_catalog_draws_the_x4_set() -> void:
	assert_eq(_x4.error, "")
	assert_eq(_x4.warnings, PackedStringArray())
	assert_eq(_x4.texture_set().scale, SCALE)


func test_every_retail_set_has_a_baked_x4_set() -> void:
	var retail: ImportedAssets = catalog()
	for set_name: String in retail.index.page_sets:
		var baked: TexturePageSet = _x4.page_set(set_name)
		var original: TexturePageSet = retail.page_set(set_name)
		assert_not_null(baked, set_name)
		if baked == null or original == null:
			continue
		assert_true(baked.resource_path.begins_with(PAGES_X4), baked.resource_path)
		assert_eq(baked.set_name, original.set_name)
		assert_eq(baked.bank_names, original.bank_names)
		assert_eq(baked.colour_keyed, original.colour_keyed)
		assert_eq(baked.sky_pages, original.sky_pages)
		assert_eq(baked.scale(), SCALE, set_name)
		assert_eq(baked.pages.size(), TexturePageSet.PAGE_COUNT)
		assert_eq(baked.sky_atlas == null, original.sky_atlas == null, set_name)
	assert_eq(_x4.problems, PackedStringArray())


func test_x4_pages_match_the_facts() -> void:
	var mismatches := PackedStringArray()
	var sets: Dictionary[String, bool] = {}
	var rows: Array[PackedStringArray] = imported_rows(FACTS)
	for row: PackedStringArray in rows:
		var set_name: String = TexturePageSet.name_for(row[0].split("+"))
		sets[set_name] = true
		var page_set: TexturePageSet = _x4.page_set(set_name)
		if page_set == null or not page_set.resource_path.begins_with(PAGES_X4):
			mismatches.append("no baked x4 page set %s" % set_name)
			continue
		var texture: Texture2D
		if row[1].begins_with("sky:"):
			texture = page_set.sky_atlas
			var order := PackedStringArray()
			for page: int in page_set.sky_pages:
				order.append(str(page))
			if "sky:" + ",".join(order) != row[1]:
				mismatches.append("%s: sky pages %s, golden %s" % [set_name, order, row[1]])
		else:
			texture = page_set.page(int(row[1]))
		var image: Image = _png(texture.resource_path) if texture != null else null
		if image == null:
			mismatches.append("%s %s has no PNG" % [set_name, row[1]])
			continue
		if image.get_size() != Vector2i(int(row[2]), int(row[3])):
			mismatches.append("%s %s is %s, golden %sx%s" % [set_name, row[1], image.get_size(), row[2], row[3]])
			continue
		var asset: String = texture.resource_path.trim_prefix(ASSETS + "/")
		if sha256_hex(image.get_data()) != expected(asset, "texture_pages_x4", "rgba_sha256", row[4]):
			mismatches.append("%s %s: RGBA digest differs" % [set_name, row[1]])
		var opaque: int = _opaque_pixels(image)
		if str(opaque) != expected(asset, "texture_pages_x4", "opaque_pixels", row[5]):
			mismatches.append("%s %s: %d opaque pixels, golden %s" % [set_name, row[1], opaque, row[5]])
	for mismatch: String in mismatches.slice(0, 10):
		fail_test(mismatch)
	assert_eq(mismatches.size(), 0, "%d x4 pages and atlases match" % rows.size())
	assert_eq(_x4.index.page_sets.size(), sets.size(), "one baked set per golden set")


func test_x4_pages_import_with_mipmaps() -> void:
	var page_set: TexturePageSet = _x4.page_set("GEN_VRAM+SKY_VRAM_WIN95")
	assert_not_null(page_set)
	if page_set == null:
		return
	var page: Texture2D = page_set.page(0)
	assert_true(page is CompressedTexture2D)
	assert_true(page.get_image().has_mipmaps(), "a baked x4 page carries mipmaps")
	assert_true(page_set.sky_atlas.get_image().has_mipmaps(), "the x4 sky atlas carries mipmaps")
	var retail: TexturePageSet = catalog().page_set("GEN_VRAM+SKY_VRAM_WIN95")
	assert_false(retail.page(0).get_image().has_mipmaps(), "retail pages stay without mipmaps")
	var general: ThemeBookEntry = _x4.theme_book_entry(FroggerIds.THEME_GENERAL)
	var image: VloImage = _x4.read_texture_bank(general.vlo_id()).images[0]
	assert_true(_x4.texture_of(image).get_image().has_mipmaps(), "an x4 image carries mipmaps")
	assert_false(image.texture.get_image().has_mipmaps(), "its retail image does not")

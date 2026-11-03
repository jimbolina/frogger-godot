extends GutTest
## A catalog builds newfont from texture 310 (a texture pack's, else the base
## root's runtime-imported image), and one without lettering images draws
## every retail image, with no problems. Synthetic images only.

const ROOT: String = "user://test_newfont_font"
const BASE: String = ROOT + "/assets/0123456789abcdef"
const SHIPPABLE: String = ROOT + "/shippable"
const PACK_IMAGE: String = ROOT + "/packs/sharp/t0310.png"


func before_each() -> void:
	_remove(ROOT)
	assert_eq(DirAccess.make_dir_recursive_absolute(BASE.path_join("textures/images")), OK)
	assert_eq(DirAccess.make_dir_recursive_absolute(SHIPPABLE), OK)


func after_all() -> void:
	_remove(ROOT)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func _grid(scale: int, seed_value: int) -> Image:
	var size: Vector2i = NewfontPage.RETAIL_SIZE * scale
	var image: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y: int in size.y:
		for x: int in size.x:
			@warning_ignore("integer_division")
			var on: bool = ((x / scale) * 7 + (y / scale) * 3 + seed_value) % 5 == 0
			image.set_pixel(x, y, Color8(200, 180 + seed_value, 40, 255) if on else Color(0, 0, 0, 0))
	return image


func _save_runtime_texture(texture_id: int, image: Image) -> Texture2D:
	var path: String = BASE.path_join("textures/images/t%04d.res" % texture_id)
	assert_eq(ResourceSaver.save(ImageTexture.create_from_image(image), path), OK)
	var texture: Texture2D = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	texture.take_over_path(path)
	return texture


func _catalog() -> ImportedAssets:
	var catalog := ImportedAssets.new()
	catalog.root = BASE
	catalog.index_root = BASE
	catalog.shippable_root = SHIPPABLE
	return catalog


func _same_pixels(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	var left: Image = a.duplicate() as Image
	var right: Image = b.duplicate() as Image
	left.convert(Image.FORMAT_RGBA8)
	right.convert(Image.FORMAT_RGBA8)
	return left.get_data() == right.get_data()


func test_a_page_of_another_size_builds_nothing() -> void:
	assert_null(NewfontFont.build(null))
	assert_null(NewfontFont.build(Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)))


func test_the_built_font_lays_out_the_glyph_grid() -> void:
	var page: Image = NewfontPage.build(_grid(1, 0))
	var font: FontFile = NewfontFont.build(page)
	assert_not_null(font)
	var size := Vector2i(32, 0)
	assert_eq(font.fixed_size, 32)
	assert_eq(font.fixed_size_scale_mode, TextServer.FIXED_SIZE_SCALE_ENABLED)
	assert_eq(font.antialiasing, TextServer.FONT_ANTIALIASING_NONE)
	assert_eq(font.get_glyph_list(0, size).size(), 96)
	assert_eq(font.get_cache_ascent(0, 32), 32.0)
	assert_eq(font.get_cache_descent(0, 32), 0.0)
	assert_eq(font.get_glyph_uv_rect(0, size, 65), Rect2(40, 40, 40, 40), "A is the second cell of the second row")
	assert_eq(font.get_glyph_uv_rect(0, size, 127), Rect2(1240, 80, 40, 40))
	assert_eq(font.get_glyph_offset(0, size, 65), Vector2(-4, -36))
	assert_eq(font.get_glyph_size(0, size, 65), Vector2(40, 40))
	assert_eq(font.get_glyph_advance(0, 32, 65), Vector2(32, 0))
	assert_eq(font.get_string_size("Hello", HORIZONTAL_ALIGNMENT_LEFT, -1, NewfontText.DRAW_SIZE),
		Vector2(5 * NewfontText.CELL, NewfontText.CELL))
	assert_true(_same_pixels(font.get_texture_image(0, size, 0), page))


func test_the_font_is_built_from_the_imported_texture() -> void:
	var grid: Image = _grid(1, 1)
	_save_runtime_texture(NewfontPage.TEXTURE_ID, grid)
	var catalog: ImportedAssets = _catalog()
	var font: FontFile = catalog.font(NewfontPage.FONT_NAME) as FontFile
	assert_not_null(font)
	if font == null:
		return
	assert_eq(font.resource_path, "", "built at runtime")
	assert_true(_same_pixels(font.get_texture_image(0, NewfontPage.CACHE_SIZE, 0), NewfontPage.build(grid)))
	assert_same(catalog.font(NewfontPage.FONT_NAME), font, "cached")
	assert_eq(catalog.problems, PackedStringArray())


func test_a_pack_texture_310_wins_over_the_imported_one() -> void:
	_save_runtime_texture(NewfontPage.TEXTURE_ID, _grid(1, 1))
	assert_eq(DirAccess.make_dir_recursive_absolute(PACK_IMAGE.get_base_dir()), OK)
	var drawn: Image = _grid(2, 3)
	assert_eq(drawn.save_png(PACK_IMAGE), OK)
	var catalog: ImportedAssets = _catalog()
	catalog.textures = TextureSet.of_pack(TexturePack.new(), {NewfontPage.TEXTURE_ID: PACK_IMAGE})
	var font: FontFile = catalog.font(NewfontPage.FONT_NAME) as FontFile
	assert_not_null(font)
	if font == null:
		return
	assert_true(_same_pixels(font.get_texture_image(0, NewfontPage.CACHE_SIZE, 0), NewfontPage.build(drawn)))
	assert_eq(catalog.problems, PackedStringArray())


func test_without_texture_310_there_is_no_font_and_one_problem() -> void:
	var catalog: ImportedAssets = _catalog()
	assert_null(catalog.font(NewfontPage.FONT_NAME))
	assert_eq(catalog.problems.size(), 1, "\n".join(catalog.problems))
	assert_string_contains(catalog.problems[0], "no texture 310 under %s" % BASE)


func test_without_lettering_images_the_retail_image_draws_without_problems() -> void:
	var retail: Texture2D = _save_runtime_texture(263, _grid(1, 2))
	var catalog: ImportedAssets = _catalog()
	assert_same(catalog.texture_counterpart(retail), retail)
	assert_same(catalog.texture_counterpart(retail), retail, "cached")
	assert_eq(catalog.problems, PackedStringArray())

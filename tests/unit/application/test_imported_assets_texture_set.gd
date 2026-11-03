extends GutTest
## The imported assets draw from the texture set a launch asks for: the x4
## set's files stand in for the retail ones where they exist, an uninstalled
## or unknown set falls back to retail with a warning, and tests that open the
## catalog without a name get the retail set. A lettering image under the
## shippable root replaces its retail image in every set, whatever the retail
## image's extension. A launch on another
## renderer than Forward+ leaves a warning.

const SCRATCH: String = "user://texture_set_test"
const LETTERING_ROOT: String = "res://tests/fixtures/lettering"
const LETTERED: String = "res://assets/textures/images/t0263.png"
const UNLETTERED: String = "res://assets/textures/images/t0000.png"
const LETTERING_SCALE: int = 8


func after_each() -> void:
	_remove(SCRATCH)


func _lettered(texture_set_name: String) -> ImportedAssets:
	var catalog := ImportedAssets.new()
	catalog.shippable_root = LETTERING_ROOT
	catalog.textures = TextureSet.named(texture_set_name)
	return catalog


func _record(texture: Texture2D) -> VloImage:
	var record := VloImage.new()
	record.texture_id = 263
	record.texture = texture
	record.padded_width = texture.get_width()
	record.padded_height = texture.get_height()
	record.width = record.padded_width - 2
	record.height = record.padded_height - 2
	return record


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func test_the_default_is_the_retail_set() -> void:
	var assets: ImportedAssets = ImportedAssets.open()
	assert_true(assets.is_valid())
	assert_true(assets.texture_set().is_retail())
	assert_eq(assets.warnings, PackedStringArray())


func test_an_uninstalled_or_unknown_set_falls_back_to_retail() -> void:
	var warnings := PackedStringArray()
	assert_eq(DirAccess.make_dir_recursive_absolute(SCRATCH.path_join("textures/images")), OK)
	assert_true(ImportedAssets.resolve_texture_set(SCRATCH, "x4", warnings).is_retail())
	assert_eq(warnings.size(), 1)
	assert_true(warnings[0].contains("not installed"), warnings[0])
	warnings.clear()
	assert_true(ImportedAssets.resolve_texture_set(SCRATCH, "x8", warnings).is_retail())
	assert_eq(warnings.size(), 1)
	assert_true(warnings[0].contains("unknown texture set x8"), warnings[0])
	warnings.clear()
	assert_eq(DirAccess.make_dir_recursive_absolute(SCRATCH.path_join("textures/images_x4")), OK)
	assert_eq(ImportedAssets.resolve_texture_set(SCRATCH, "x4", warnings).scale, 4)
	assert_eq(warnings, PackedStringArray())


func test_the_x4_set_serves_upscaled_textures() -> void:
	var assets: ImportedAssets = ImportedAssets.open("res://assets", "x4")
	assert_true(assets.is_valid())
	assert_eq(assets.warnings, PackedStringArray())
	assert_eq(assets.texture_set().scale, 4)
	var general: ThemeBookEntry = assets.theme_book_entry(FroggerIds.THEME_GENERAL)
	var bank: VloFile = assets.read_texture_bank(general.vlo_id())
	assert_not_null(bank)
	var image: VloImage = bank.images[0]
	var retail: Texture2D = image.texture
	var upscaled: Texture2D = assets.texture_of(image)
	assert_ne(upscaled, retail)
	assert_eq(upscaled.resource_path, "res://assets/textures/images_x4/t%04d.png" % image.texture_id)
	assert_eq(upscaled.get_size(), retail.get_size() * 4)
	assert_same(assets.texture_of(image), upscaled, "a counterpart resolves once")
	assert_same(assets.texture_counterpart(retail), upscaled)
	var cel := ImageTexture.create_from_image(Image.create_empty(2, 2, false, Image.FORMAT_RGBA8))
	assert_same(assets.texture_counterpart(cel), cel, "a texture outside the retail folders is itself")
	assert_eq(assets.problems, PackedStringArray())
	var library := TextureLibrary.new()
	library.catalog = assets
	library.add_bank(bank, "general")
	assert_same(library.texture_for(image), upscaled)
	assert_true(library.linear_filter())


func test_retail_textures_stay_retail() -> void:
	var assets: ImportedAssets = ImportedAssets.open("res://assets", "retail")
	var general: ThemeBookEntry = assets.theme_book_entry(FroggerIds.THEME_GENERAL)
	var bank: VloFile = assets.read_texture_bank(general.vlo_id())
	var image: VloImage = bank.images[0]
	assert_same(assets.texture_of(image), image.texture)
	assert_same(assets.texture_counterpart(image.texture), image.texture)


func test_the_lettering_path_sits_under_the_shippable_root() -> void:
	assert_eq(TextureSet.lettering_path(LETTERED), "textures/lettering/t0263.png")
	assert_eq(TextureSet.lettering_path("user://assets/0123456789abcdef/textures/images/t0263.res"),
		"textures/lettering/t0263.png", "a runtime-imported image still finds the committed lettering")
	assert_eq(TextureSet.lettering_path("res://assets/textures/images_x4/t0263.png"), "")
	assert_eq(TextureSet.lettering_path("res://assets/models/HI_A/mesh.res"), "")
	assert_true(TextureSet.is_lettering_path(LETTERING_ROOT.path_join("textures/lettering/t0263.png")))
	assert_false(TextureSet.is_lettering_path(LETTERED))


func test_lettering_wins_over_the_retail_and_x4_images() -> void:
	var retail: Texture2D = load(LETTERED) as Texture2D
	var plain: Texture2D = load(UNLETTERED) as Texture2D
	for texture_set_name: String in [TextureSet.RETAIL, TextureSet.X4]:
		var catalog: ImportedAssets = _lettered(texture_set_name)
		var drawn: Texture2D = catalog.texture_counterpart(retail)
		assert_eq(drawn.resource_path, LETTERING_ROOT.path_join("textures/lettering/t0263.png"), texture_set_name)
		assert_eq(drawn.get_size(), retail.get_size() * LETTERING_SCALE, texture_set_name)
		assert_true(drawn.get_image().has_mipmaps(), "lettering is imported with mipmaps")
		assert_same(catalog.texture_counterpart(retail), drawn, "a lettering image resolves once")
		assert_same(catalog.texture_of(_record(retail)), drawn)
		assert_eq(catalog.problems, PackedStringArray())
	assert_same(_lettered(TextureSet.RETAIL).texture_counterpart(plain), plain, "retail without lettering is unchanged")
	assert_eq(_lettered(TextureSet.X4).texture_counterpart(plain).resource_path,
		"res://assets/textures/images_x4/t0000.png", "x4 without lettering is unchanged")


func test_texture_for_wraps_lettering_in_a_linear_mipmapped_canvas_texture() -> void:
	var retail: Texture2D = load(LETTERED) as Texture2D
	var record: VloImage = _record(retail)
	var library := TextureLibrary.new()
	library.catalog = _lettered(TextureSet.RETAIL)
	var drawn: CanvasTexture = library.texture_for(record) as CanvasTexture
	assert_not_null(drawn)
	assert_eq(drawn.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	assert_true(TextureSet.is_lettering_path(drawn.diffuse_texture.resource_path))
	assert_same(TextureBuilder.source_texture(drawn), drawn.diffuse_texture)
	assert_same(library.texture_for(record), drawn, "one wrapper per lettering image")
	assert_eq(drawn.get_size(), retail.get_size() * LETTERING_SCALE)
	assert_eq(TextureBuilder.texture_scale(record, drawn), Vector2.ONE * LETTERING_SCALE)
	assert_eq(TextureBuilder.retail_size(record, drawn), retail.get_size())
	assert_eq(TextureBuilder.texture_rect(record, drawn), Rect2(Vector2(1, 1) * LETTERING_SCALE,
		(retail.get_size() - Vector2(2, 2)) * LETTERING_SCALE))
	assert_eq(TextureBuilder.build_image(record, drawn).get_size(), Vector2i(retail.get_size()) * LETTERING_SCALE)
	var material: ShaderMaterial = ModelShaders.material(drawn, ModelShaders.Blend.OPAQUE, false, false)
	var model_image: Texture2D = material.get_shader_parameter("image")
	assert_same(model_image, drawn.diffuse_texture, "3D materials draw the image itself")
	assert_same(material.shader, ModelShaders.shader(true, ModelShaders.Blend.OPAQUE, true, false))
	var terrain: ShaderMaterial = MapShaders.material(record, drawn, ModelShaders.Blend.OPAQUE, false, -1)
	var terrain_image: Texture2D = terrain.get_shader_parameter("image_linear")
	var terrain_linear: bool = terrain.get_shader_parameter("linear_filter")
	assert_same(terrain_image, drawn.diffuse_texture)
	assert_true(terrain_linear)
	var plain: Texture2D = load(UNLETTERED) as Texture2D
	assert_same(library.texture_for(_record(plain)), plain, "other images are not wrapped")


func test_a_renderer_note_lands_in_the_warnings_only_on_another_renderer() -> void:
	var catalog := AssetCatalog.new()
	assert_eq(catalog.note_renderer(AssetCatalog.RENDERING_METHOD), "")
	assert_eq(catalog.warnings, PackedStringArray())
	var note: String = catalog.note_renderer("gl_compatibility")
	assert_eq(note, "rendering on gl_compatibility; the game targets forward_plus, shadows and lighting may differ")
	assert_eq(catalog.warnings, PackedStringArray([note]))

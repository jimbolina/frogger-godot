extends GutTest
## The imported assets draw from the texture set a launch asks for: the x4
## set's files stand in for the retail ones where they exist, an uninstalled
## or unknown set falls back to retail with a warning, and tests that open the
## catalog without a name get the retail set. A launch on another renderer
## than Forward+ leaves a warning.

const SCRATCH: String = "user://texture_set_test"


func after_each() -> void:
	_remove(SCRATCH)


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


func test_a_renderer_note_lands_in_the_warnings_only_on_another_renderer() -> void:
	var catalog := AssetCatalog.new()
	assert_eq(catalog.note_renderer(AssetCatalog.RENDERING_METHOD), "")
	assert_eq(catalog.warnings, PackedStringArray())
	var note: String = catalog.note_renderer("gl_compatibility")
	assert_eq(note, "rendering on gl_compatibility; the game targets forward_plus, shadows and lighting may differ")
	assert_eq(catalog.warnings, PackedStringArray([note]))

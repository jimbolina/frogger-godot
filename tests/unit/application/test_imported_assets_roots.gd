extends GutTest
## A catalog over a base root under user:// still reads fonts, lettering and the
## emissive table from the shippable root, and an x4 launch over a base root
## without upscaled images draws the retail set with a warning instead of failing.

const BASE: String = "user://imported_assets_roots/assets/0123456789abcdef"
const SHIPPABLE: String = "res://assets"
const RUNTIME_IMAGE: String = BASE + "/textures/images/t0263.res"


func before_each() -> void:
	_remove("user://imported_assets_roots")
	assert_eq(DirAccess.make_dir_recursive_absolute(BASE.path_join("textures/images")), OK)
	assert_eq(DirAccess.copy_absolute(SHIPPABLE.path_join(ImportedAssets.INDEX_FILE), BASE.path_join(ImportedAssets.INDEX_FILE)), OK)


func after_all() -> void:
	_remove("user://imported_assets_roots")


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func test_the_shippable_files_come_from_the_shippable_root() -> void:
	var catalog: ImportedAssets = ImportedAssets.open(BASE, "", "", SHIPPABLE)
	assert_true(catalog.is_valid(), catalog.error)
	assert_eq(catalog.root, BASE)
	assert_eq(catalog.index_root, BASE)
	assert_eq(catalog.shippable_root, SHIPPABLE)
	var font: Font = catalog.font("newfont")
	assert_not_null(font)
	assert_eq(font.resource_path, SHIPPABLE.path_join("fonts/retail/newfont.fnt"))
	assert_not_null(catalog.font("angular"))
	assert_gt(catalog.emissive_images().entries.size(), 0)
	assert_eq(catalog.problems, PackedStringArray())


func test_a_runtime_imported_image_draws_the_committed_lettering() -> void:
	var image: Image = Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	assert_eq(ResourceSaver.save(ImageTexture.create_from_image(image), RUNTIME_IMAGE), OK)
	var retail: Texture2D = ResourceLoader.load(RUNTIME_IMAGE, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	assert_not_null(retail)
	retail.take_over_path(RUNTIME_IMAGE)
	var catalog: ImportedAssets = ImportedAssets.open(BASE, "", "", SHIPPABLE)
	var drawn: Texture2D = catalog.texture_counterpart(retail)
	assert_eq(drawn.resource_path, SHIPPABLE.path_join("textures/lettering/t0263.png"))


func test_the_base_root_does_not_serve_shippable_files() -> void:
	var catalog: ImportedAssets = ImportedAssets.open(SHIPPABLE, "", "", BASE)
	assert_true(catalog.is_valid(), catalog.error)
	assert_null(catalog.font("newfont"))
	assert_eq(catalog.emissive_images().entries.size(), 0)
	assert_eq(catalog.problems.size(), 2, "\n".join(catalog.problems))


func test_x4_without_upscaled_images_under_the_base_root_draws_retail_with_a_warning() -> void:
	var catalog: ImportedAssets = ImportedAssets.open(BASE, TextureSet.X4, "", SHIPPABLE)
	assert_true(catalog.is_valid(), catalog.error)
	assert_true(catalog.texture_set().is_retail())
	assert_eq(catalog.warnings.size(), 1, "\n".join(catalog.warnings))
	assert_string_contains(catalog.warnings[0], "texture set x4 is not installed at %s" % BASE.path_join("textures/images_x4"))
	assert_eq(catalog.font("newfont").resource_path, SHIPPABLE.path_join("fonts/retail/newfont.fnt"),
		"the fallback draws the retail font too")
	var located: ImportedAssets = AssetLocation.resolve(PackedStringArray(["--assets-root=" + BASE, "--texture-set=x4"]), null).open(TextureSet.X4)
	assert_true(located.is_valid(), located.error)
	assert_true(located.texture_set().is_retail())
	assert_eq(located.root, BASE)

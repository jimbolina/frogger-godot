extends GutTest
## The imported assets draw the texture pack a launch names over synthetic
## retail textures: a partial pack replaces only the textures it supplies,
## each at its own scale, and the rest stay retail; an image of the wrong size
## is rejected with a problem and a logged warning and falls back; a pack wins over a lettering
## image, which wins over the retail image; a pack that is missing or not a
## pack, or drawn for another build, leaves a warning. Upscaled textures come
## wrapped for linear, mipmapped 2D sampling and draw at their retail size,
## and pick the linear 3D shaders. A launch on another renderer than Forward+
## leaves a warning.

const SCRATCH: String = "user://test_imported_assets_texture_set"
const PACKS: String = SCRATCH + "/texture_packs"
const RETAIL: String = SCRATCH + "/base/textures/images"
const LETTERING_ROOT: String = "res://tests/fixtures/lettering"
const LETTERED: String = "res://assets/textures/images/t0263.png"
const UNLETTERED: String = "res://assets/textures/images/t0000.png"
const LETTERING_SCALE: int = 8
const LETTERED_SIZE: Vector2i = Vector2i(34, 34)
const PADDED: Vector2i = Vector2i(10, 6)
const BUILD: String = "pc-retail-v3.0e"


func before_each() -> void:
	_remove(SCRATCH)
	assert_eq(DirAccess.make_dir_recursive_absolute(PACKS), OK)


func after_all() -> void:
	_remove(SCRATCH)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func _pack(name: String, images: Dictionary[String, Vector2i], base_build: String = BUILD) -> void:
	var folder: String = PACKS.path_join(name)
	assert_eq(DirAccess.make_dir_recursive_absolute(folder), OK)
	var config := ConfigFile.new()
	config.set_value("pack", "name", name.capitalize())
	config.set_value("pack", "base_build", base_build)
	assert_eq(config.save(folder.path_join("pack.cfg")), OK)
	for file: String in images:
		var image := Image.create(images[file].x, images[file].y, false, Image.FORMAT_RGBA8)
		image.fill(Color(1.0, 0.0, 1.0, 1.0))
		assert_eq(image.save_png(folder.path_join(file)), OK)


func _retail(texture_id: int, size: Vector2i = PADDED) -> Texture2D:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.5, 0.0, 1.0))
	var texture := ImageTexture.create_from_image(image)
	texture.take_over_path(RETAIL.path_join("t%04d.png" % texture_id))
	return texture


func _record(texture: Texture2D, texture_id: int) -> VloImage:
	var record := VloImage.new()
	record.texture_id = texture_id
	record.texture = texture
	record.padded_width = texture.get_width()
	record.padded_height = texture.get_height()
	record.width = record.padded_width - 2
	record.height = record.padded_height - 2
	return record


func _catalog(pack_name: String) -> ImportedAssets:
	var catalog := ImportedAssets.new()
	catalog.shippable_root = LETTERING_ROOT
	catalog.version_name = BUILD
	catalog.names = GameNameLists.new()
	catalog.names.images = SyntheticNames.indexed("263=hi_a\n", "Image")
	catalog.textures = catalog.resolve_texture_pack(pack_name, PackedStringArray([PACKS]))
	return catalog


func test_the_default_is_the_original_textures() -> void:
	var assets: ImportedAssets = ImportedAssets.open()
	assert_true(assets.is_valid())
	assert_true(assets.texture_set().is_retail())
	assert_eq(assets.warnings, PackedStringArray())
	var catalog: ImportedAssets = _catalog("")
	assert_true(catalog.texture_set().is_retail())
	var retail: Texture2D = _retail(12)
	assert_same(catalog.texture_counterpart(retail), retail)
	assert_eq(catalog.warnings, PackedStringArray())


func test_a_partial_pack_replaces_only_its_textures_each_at_its_own_scale() -> void:
	_pack("crisp", {"t0012.png": PADDED * 2, "t0013.png": PADDED * 4, "t0015.png": PADDED})
	var catalog: ImportedAssets = _catalog("crisp")
	assert_eq(catalog.warnings, PackedStringArray())
	assert_eq(catalog.texture_set().pack_name(), "crisp")
	var doubled: Texture2D = _retail(12)
	var quadrupled: Texture2D = _retail(13)
	var omitted: Texture2D = _retail(14)
	var same_size: Texture2D = _retail(15)
	var two: Texture2D = catalog.texture_counterpart(doubled)
	var four: Texture2D = catalog.texture_counterpart(quadrupled)
	assert_eq(Vector2i(two.get_size()), PADDED * 2)
	assert_eq(Vector2i(four.get_size()), PADDED * 4)
	assert_eq(two.get_image().get_pixel(3, 3), Color(1.0, 0.0, 1.0, 1.0), "the pack's pixels")
	assert_true(two.get_image().has_mipmaps())
	assert_eq(catalog.texture_set().scale_of(12), 2)
	assert_eq(catalog.texture_set().scale_of(13), 4)
	assert_same(catalog.texture_counterpart(omitted), omitted, "a texture the pack omits stays retail")
	assert_eq(Vector2i(catalog.texture_counterpart(same_size).get_size()), PADDED, "a pack may redraw at retail size")
	assert_eq(catalog.texture_set().scale_of(15), 1)
	assert_same(catalog.texture_counterpart(doubled), two, "an image loads once per catalog")
	assert_same(catalog.texture_of(_record(doubled, 12)), two)
	var cel := ImageTexture.create_from_image(Image.create_empty(2, 2, false, Image.FORMAT_RGBA8))
	assert_same(catalog.texture_counterpart(cel), cel, "a texture outside the retail folders is itself")
	assert_eq(catalog.problems, PackedStringArray())


func test_a_wrong_size_image_is_rejected_and_falls_back_to_retail() -> void:
	_pack("crisp", {"t0012.png": Vector2i(25, 15), "t0013.png": Vector2i(20, 18)})
	var catalog: ImportedAssets = _catalog("crisp")
	var retail: Texture2D = _retail(12)
	assert_same(catalog.texture_counterpart(retail), retail)
	assert_eq(Vector2i(catalog.texture_counterpart(_retail(13)).get_size()), PADDED, "the wrong aspect falls back too")
	assert_eq(catalog.problems.size(), 2, "\n".join(catalog.problems))
	assert_string_contains(catalog.problems[0], "texture pack crisp: ")
	assert_string_contains(catalog.problems[0], "t0012.png is 25x15, not a whole multiple from 1 to 16 of the retail padded size 10x6")
	assert_string_contains(catalog.problems[0], "drawing texture 12 without the pack")
	assert_false(catalog.texture_set().has_source(12))
	assert_same(catalog.texture_counterpart(retail), retail)
	assert_eq(catalog.problems.size(), 2, "a rejection is noted once")
	assert_engine_error(2, "each rejection is also logged as a warning")


func test_a_pack_wins_over_lettering_which_wins_over_retail() -> void:
	var lettered: Texture2D = _retail(263, LETTERED_SIZE)
	var lettering: Texture2D = _catalog("").texture_counterpart(lettered)
	assert_eq(lettering.resource_path, LETTERING_ROOT.path_join("lettering/t0263.png"))
	assert_eq(Vector2i(lettering.get_size()), LETTERED_SIZE * LETTERING_SCALE)
	_pack("lettered", {"hi_a.png": LETTERED_SIZE * 2})
	var drawn: Texture2D = _catalog("lettered").texture_counterpart(lettered)
	assert_eq(Vector2i(drawn.get_size()), LETTERED_SIZE * 2, "the pack's own image, named by FrogLord name, wins")
	assert_eq(drawn.resource_path, "")
	_pack("other", {"t0012.png": PADDED * 2})
	assert_same(_catalog("other").texture_counterpart(lettered), lettering, "a pack without the texture keeps the lettering")
	_pack("bad_lettered", {"t0263.png": Vector2i(35, 35)})
	var rejected: ImportedAssets = _catalog("bad_lettered")
	assert_same(rejected.texture_counterpart(lettered), lettering, "a rejected pack image falls back to the lettering")
	assert_eq(rejected.problems.size(), 1)
	assert_engine_error(1, "the rejection is logged as a warning")


func test_a_missing_or_unusable_pack_draws_the_original_textures_with_a_warning() -> void:
	var absent: ImportedAssets = _catalog("absent")
	assert_true(absent.texture_set().is_retail())
	assert_eq(absent.warnings, PackedStringArray([
		"texture pack absent is not installed in %s; drawing the original textures" % PACKS]))
	assert_eq(DirAccess.make_dir_recursive_absolute(PACKS.path_join("bare")), OK)
	var bare: ImportedAssets = _catalog("bare")
	assert_true(bare.texture_set().is_retail())
	assert_eq(bare.warnings.size(), 2, "\n".join(bare.warnings))
	assert_string_contains(bare.warnings[0], "has no pack.cfg")
	assert_eq(bare.warnings[1], "texture pack bare cannot be used; drawing the original textures")


func test_a_pack_for_another_build_warns_and_still_draws() -> void:
	_pack("old", {"t0012.png": PADDED * 2, "stray.png": PADDED}, "pc-retail-v1.0")
	var catalog: ImportedAssets = _catalog("old")
	assert_false(catalog.texture_set().is_retail())
	assert_eq(catalog.warnings.size(), 2, "\n".join(catalog.warnings))
	assert_eq(catalog.warnings[0], "texture pack old was drawn for pc-retail-v1.0, not %s; its images may not match" % BUILD)
	assert_string_contains(catalog.warnings[1], "stray.png names no texture")
	assert_eq(Vector2i(catalog.texture_counterpart(_retail(12)).get_size()), PADDED * 2)


func test_upscaled_pack_images_draw_linearly_at_their_retail_size() -> void:
	_pack("crisp", {"t0012.png": PADDED * 2, "t0013.png": PADDED})
	var library := TextureLibrary.new()
	library.catalog = _catalog("crisp")
	var record: VloImage = _record(_retail(12), 12)
	var drawn: CanvasTexture = library.texture_for(record) as CanvasTexture
	assert_not_null(drawn, "an upscaled image comes wrapped")
	assert_eq(drawn.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	assert_same(library.texture_for(record), drawn, "one wrapper per image")
	assert_true(TextureBuilder.is_upscaled(record, drawn))
	assert_eq(TextureBuilder.texture_scale(record, drawn), Vector2(2, 2))
	assert_eq(TextureBuilder.retail_size(record, drawn), Vector2(PADDED), "2D draws keep the retail size")
	assert_eq(TextureBuilder.texture_rect(record, drawn), Rect2(2, 2, 16, 8), "the in-game region in the pack's pixels")
	var material: ShaderMaterial = ModelShaders.material(drawn, ModelShaders.Blend.OPAQUE, false, false)
	assert_same(material.shader, ModelShaders.shader(true, ModelShaders.Blend.OPAQUE, true, false))
	var terrain: ShaderMaterial = MapShaders.material(record, drawn, ModelShaders.Blend.OPAQUE, false, -1)
	var terrain_linear: bool = terrain.get_shader_parameter("linear_filter")
	assert_true(terrain_linear)
	var same_size: VloImage = _record(_retail(13), 13)
	var plain: Texture2D = library.texture_for(same_size)
	assert_false(plain is CanvasTexture, "a retail-size pack image is drawn nearest like retail")
	assert_ne(plain, same_size.texture)
	assert_false(TextureBuilder.is_upscaled(same_size, plain))
	var nearest: ShaderMaterial = ModelShaders.material(plain, ModelShaders.Blend.OPAQUE, false, false)
	assert_same(nearest.shader, ModelShaders.shader(true, ModelShaders.Blend.OPAQUE, false, false))


func test_the_lettering_path_sits_under_the_shippable_root() -> void:
	assert_eq(TextureSet.lettering_path(LETTERED), "lettering/t0263.png")
	assert_eq(TextureSet.lettering_path("user://assets/0123456789abcdef/textures/images/t0263.res"),
		"lettering/t0263.png", "a runtime-imported image still finds the committed lettering")
	assert_eq(TextureSet.lettering_path("res://assets/models/HI_A/mesh.res"), "")
	assert_eq(TextureSet.lettering_mask_path(LETTERED, "green_pad"), "lettering/masks/green_pad/t0263.png")
	assert_eq(TextureSet.lettering_mask_path("res://assets/models/HI_A/mesh.res", "log"), "")
	assert_true(TextureSet.is_lettering_path(LETTERING_ROOT.path_join("lettering/t0263.png")))
	assert_false(TextureSet.is_lettering_path(LETTERED))


func test_texture_for_wraps_lettering_in_a_linear_mipmapped_canvas_texture() -> void:
	var retail: Texture2D = load(LETTERED) as Texture2D
	var record: VloImage = _record(retail, 263)
	var library := TextureLibrary.new()
	library.catalog = _catalog("")
	var drawn: CanvasTexture = library.texture_for(record) as CanvasTexture
	assert_not_null(drawn)
	assert_eq(drawn.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	assert_true(TextureSet.is_lettering_path(drawn.diffuse_texture.resource_path))
	assert_true(drawn.diffuse_texture.get_image().has_mipmaps(), "lettering is imported with mipmaps")
	assert_same(TextureBuilder.source_texture(drawn), drawn.diffuse_texture)
	assert_eq(drawn.get_size(), retail.get_size() * LETTERING_SCALE)
	assert_eq(TextureBuilder.retail_size(record, drawn), retail.get_size())
	assert_eq(TextureBuilder.build_image(record, drawn).get_size(), Vector2i(retail.get_size()) * LETTERING_SCALE)
	var material: ShaderMaterial = ModelShaders.material(drawn, ModelShaders.Blend.OPAQUE, false, false)
	var model_image: Texture2D = material.get_shader_parameter("image")
	assert_same(model_image, drawn.diffuse_texture, "3D materials draw the image itself")
	var plain: Texture2D = load(UNLETTERED) as Texture2D
	assert_same(library.texture_for(_record(plain, 0)), plain, "other images are not wrapped")


func test_a_renderer_note_lands_in_the_warnings_only_on_another_renderer() -> void:
	var catalog := AssetCatalog.new()
	assert_eq(catalog.note_renderer(AssetCatalog.RENDERING_METHOD), "")
	assert_eq(catalog.warnings, PackedStringArray())
	var note: String = catalog.note_renderer("gl_compatibility")
	assert_eq(note, "rendering on gl_compatibility; the game targets forward_plus, shadows and lighting may differ")
	assert_eq(catalog.warnings, PackedStringArray([note]))

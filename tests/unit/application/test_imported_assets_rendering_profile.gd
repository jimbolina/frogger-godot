extends GutTest
## The imported assets carry the rendering profile a launch asks for: an
## unknown name falls back to retail with a warning, and a catalog opened
## without a name is retail. The profile is chosen before the asset index is
## read, so an empty assets folder is enough.

const SCRATCH: String = "user://rendering_profile_test"


func before_each() -> void:
	assert_eq(DirAccess.make_dir_recursive_absolute(SCRATCH), OK)


func after_each() -> void:
	DirAccess.remove_absolute(SCRATCH)


func test_an_unknown_profile_falls_back_to_retail() -> void:
	var warnings := PackedStringArray()
	assert_false(ImportedAssets.resolve_rendering_profile("ultra", warnings).is_modern())
	assert_eq(warnings, PackedStringArray(["unknown rendering profile ultra; drawing the retail profile"]))


func test_named_profiles_resolve_without_warnings() -> void:
	var warnings := PackedStringArray()
	assert_true(ImportedAssets.resolve_rendering_profile("modern", warnings).is_modern())
	assert_false(ImportedAssets.resolve_rendering_profile("retail", warnings).is_modern())
	assert_false(ImportedAssets.resolve_rendering_profile("", warnings).is_modern())
	assert_eq(warnings, PackedStringArray())


func test_a_catalog_opened_as_modern_reports_it() -> void:
	var assets: ImportedAssets = ImportedAssets.open(SCRATCH, "", "modern")
	assert_true(assets.rendering_profile().is_modern())
	assert_eq(assets.warnings, PackedStringArray())
	var library := TextureLibrary.new()
	library.catalog = assets
	assert_true(library.rendering_profile().is_modern())


func test_a_catalog_opened_without_a_profile_is_retail() -> void:
	var assets: ImportedAssets = ImportedAssets.open(SCRATCH)
	assert_false(assets.rendering_profile().is_modern())
	assert_eq(assets.warnings, PackedStringArray())
	assert_false(TextureLibrary.new().rendering_profile().is_modern())
	assert_false(AssetCatalog.new().rendering_profile().is_modern())


func test_a_renderer_note_lands_in_the_warnings_only_on_another_renderer() -> void:
	var assets: ImportedAssets = ImportedAssets.open(SCRATCH, "", "modern")
	assert_eq(assets.note_renderer(RenderingProfile.FORWARD_PLUS), "")
	assert_eq(assets.warnings, PackedStringArray())
	var note: String = assets.note_renderer(RenderingProfile.COMPATIBILITY)
	assert_false(note.is_empty())
	assert_eq(assets.warnings, PackedStringArray([note]))

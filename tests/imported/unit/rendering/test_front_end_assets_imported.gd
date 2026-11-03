extends GutTest
## FrontEndAssets opened from the local import carries the texture set's
## newfont bitmap font and the localised pause quit label.


func test_the_imported_catalog_serves_the_newfont_bitmap_font() -> void:
	var assets: FrontEndAssets = FrontEndAssets.from_data(ImportedAssets.open())
	assert_eq(assets.error, "")
	var font: Font = assets.font
	assert_true(font is FontFile, "the bundle carries the texture set's newfont FontFile")


func test_the_pause_quit_label_localises_without_a_prefix_family() -> void:
	assert_eq(GameLanguage.localized_name("quit", GameLanguage.Id.GERMAN), "quit_g")
	assert_eq(GameLanguage.localized_name("quit", GameLanguage.Id.FRENCH), "quit_f")
	var assets: FrontEndAssets = FrontEndAssets.from_data(ImportedAssets.open(), GameLanguage.Id.ITALIAN)
	assert_eq(assets.error, "")
	assert_eq(assets.source_name("quit"), "quit_i")
	assert_not_null(assets.texture("quit"))
	assert_gt(assets.retail_size("quit").x, 0.0)

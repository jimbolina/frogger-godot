extends AssetTest
## The catalog opened from the local import serves the committed angular font
## (content/fonts/angular/frogger_angular.ttf) by name, without problems.

const FONT_PATH: String = "res://content/fonts/angular/frogger_angular.ttf"


func test_the_catalog_serves_the_font_by_name() -> void:
	var assets: ImportedAssets = ImportedAssets.open(ASSETS)
	var served: FontFile = assets.font("angular") as FontFile
	assert_not_null(served, "the catalog serves the angular font")
	if served != null:
		assert_eq(served.resource_path, FONT_PATH, "the catalog draws the committed font")
	assert_eq(assets.problems, PackedStringArray(), "the catalog serves the font without problems")

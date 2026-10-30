extends RetailTest
## Every front-end text image and arcade level-select image resolves from the retail English banks.


func test_every_named_and_level_image_resolves() -> void:
	var data: GameData = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))
	assert_eq(data.error, "")
	if not data.is_valid():
		return
	var assets: FrontEndAssets = FrontEndAssets.from_data(data)
	assert_eq(assets.error, "")
	for image_name: String in FrontEndAssets.NAMES:
		var image: Texture2D = assets.texture(image_name)
		assert_not_null(image, image_name)
		if image != null:
			assert_gt(image.get_width(), 0, image_name)
	var table: LevelSelectTable = data.tables.level_select()
	assert_eq(table.arcade.size(), 33)
	for row: LevelSelectEntry in table.arcade:
		for kind: FrontEndAssets.LevelImage in FrontEndAssets.LEVEL_IMAGES:
			var label: String = "%s %s" % [FroggerIds.level_code(row.level), FrontEndAssets.LevelImage.keys()[kind]]
			var image: Texture2D = assets.level_texture(row.level, kind)
			assert_not_null(image, label)
			if image != null:
				assert_gt(image.get_width(), 0, label)
	assert_null(assets.texture("opt_start_missing"))
	assert_null(assets.level_texture(table.race[0].level, FrontEndAssets.LevelImage.SCREENSHOT))
	data.close()

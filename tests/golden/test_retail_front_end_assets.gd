extends RetailTest
## Every front-end text image, water image and arcade level-select image resolves from the retail
## English banks, each language draws the images in pc-retail-v3.0e/frontend_language.tsv, and the
## supplied executable holds the language table of synthetic/frontend_language.json.

const LANGUAGE_TSV: String = "res://tests/golden/pc-retail-v3.0e/frontend_language.tsv"
const LANGUAGE_JSON: String = "res://tests/golden/synthetic/frontend_language.json"


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
	assert_eq(assets.texture("opt_env_sky").get_size(), Vector2(254, 254), "im_opt_env_sky without padding")
	assert_eq(assets.texture("opt_bank3").get_size(), Vector2(30, 30), "im_opt_bank3 without padding")
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


func test_every_language_draws_its_localized_images() -> void:
	var data: GameData = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))
	assert_eq(data.error, "")
	if not data.is_valid():
		return
	var rows: Dictionary[int, Array] = {}
	for line: String in FileAccess.get_file_as_string(LANGUAGE_TSV).split("\n", false):
		if not line.begins_with("#"):
			var fields: PackedStringArray = line.split("\t")
			var language: int = fields[0].to_int()
			if not rows.has(language):
				rows[language] = []
			rows[language].append(fields)
	assert_eq(rows.size(), GameLanguage.COUNT)
	var banks: Dictionary[String, TextureLibrary] = {}
	for language: int in GameLanguage.COUNT:
		var assets: FrontEndAssets = FrontEndAssets.from_data(data, language)
		var label: String = GameLanguage.NAMES[language]
		assert_eq(assets.error, "", label)
		assert_eq(assets.diagnostics, PackedStringArray(), label)
		assert_eq(rows[language].size(), FrontEndAssets.NAMES.size(), label)
		for entry: Variant in rows[language]:
			var fields: PackedStringArray = entry
			var row_label: String = "%s %s" % [label, fields[1]]
			assert_eq(assets.source_name(fields[1]), fields[2], row_label)
			assert_eq(data.tables.names.images.index_of(fields[2]), fields[3].to_int(), row_label)
			if not banks.has(fields[4]):
				var only := TextureLibrary.new()
				only.add_bank(data.read_texture_bank(data.find_resource(fields[4]).index), fields[4])
				banks[fields[4]] = only
			var expected: Texture2D = banks[fields[4]].texture_for_id(fields[3].to_int())
			var drawn: Texture2D = assets.texture(fields[1])
			assert_not_null(expected, row_label)
			assert_not_null(drawn, row_label)
			if expected != null and drawn != null:
				assert_eq(drawn.get_image().get_data(), expected.get_image().get_data(), row_label)
	data.close()


func test_executable_holds_the_language_table() -> void:
	var data: GameData = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))
	assert_eq(data.error, "")
	if not data.is_valid():
		return
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LANGUAGE_JSON))
	var exe: Dictionary = document.exe
	var bytes: PackedByteArray = data.exe.bytes
	var prologue: Array = exe.prologue
	var routine: int = _int(exe.routine_offset)
	for index: int in prologue.size():
		assert_eq(bytes[routine + index], _int(prologue[index]), "prologue byte %d" % index)
	var map: int = _int(exe.map_offset)
	for index: int in GameLanguage.PRIMARY_MAP.size():
		assert_eq(bytes[map + index], GameLanguage.PRIMARY_MAP[index], "map byte %d" % index)
	var opcode: Array = exe.store_opcode
	var stores: Array = exe.arm_store_offsets
	for arm: int in stores.size():
		var at: int = _int(stores[arm])
		for index: int in opcode.size():
			assert_eq(bytes[at + index], _int(opcode[index]), "arm %d opcode byte %d" % [arm, index])
		assert_eq(bytes.decode_u32(at + opcode.size()), int(GameLanguage.ARM_LANGUAGES[arm]), "arm %d language" % arm)
	data.close()


static func _int(value: Variant) -> int:
	var number: float = value
	return int(number)

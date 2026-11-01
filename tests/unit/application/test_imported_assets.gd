extends GutTest
## The committed imported assets open as a catalog that serves every playable level.

const BUILD: String = "pc-retail-v3.0e"

var _assets: ImportedAssets


func before_all() -> void:
	_assets = ImportedAssets.open()


func test_catalog_opens_with_the_imported_build() -> void:
	assert_eq(_assets.error, "")
	assert_true(_assets.is_valid())
	assert_eq(_assets.version_name, BUILD)
	assert_not_null(_assets.tables)
	assert_not_null(_assets.mwi)
	assert_not_null(_assets.names)


func test_playable_levels_follow_the_arcade_stack() -> void:
	var codes: PackedStringArray = _assets.playable_level_codes()
	assert_eq(codes.size(), 33)
	assert_eq(codes[0], "ORG1")
	var stack := PackedStringArray()
	for entry: LevelSelectEntry in _assets.tables.level_select().arcade:
		var code: String = FroggerIds.level_code(entry.level)
		if code in codes:
			stack.append(code)
	assert_eq(stack, codes)
	for code: String in ["ORG1", "SUB1", "SUB2", "SUB5", "CAV4", "JUN1", "SWP5", "SKY4"]:
		assert_true(_assets.is_playable_level(FroggerIds.level_from_code(code)), code)
	for code: String in ["SUBM", "CAV2", "SWPM", "ISLAND"]:
		assert_false(_assets.is_playable_level(FroggerIds.level_from_code(code)), code)
	assert_false(_assets.is_playable_level(-1))
	assert_false(_assets.is_playable_level(100))


func test_unaccepted_levels_are_the_mapped_levels_outside_the_playable_list() -> void:
	var codes: PackedStringArray = _assets.unaccepted_level_codes()
	for code: String in ["SUBM", "JUN2", "ORGM"]:
		assert_true(code in codes, code)
		assert_true(_assets.has_level_map(FroggerIds.level_from_code(code)), code)
	for code: String in ["SUB1", "SUB2", "SUB5", "CAV2", "CAV5", "FOR3", "SKY5", "ISLAND"]:
		assert_false(code in codes, code)
	for code: String in ["CAV2", "CAV5", "FOR3", "SKY5"]:
		assert_false(_assets.has_level_map(FroggerIds.level_from_code(code)), code)
	for code: String in _assets.playable_level_codes():
		assert_true(_assets.has_level_map(FroggerIds.level_from_code(code)), code)
	assert_false(_assets.has_level_map(-1))
	assert_false(_assets.has_level_map(100))


func test_every_playable_level_resolves_its_map_theme_remap_and_banks() -> void:
	var general: ThemeBookEntry = _assets.theme_book_entry(FroggerIds.THEME_GENERAL)
	assert_not_null(general)
	for code: String in _assets.playable_level_codes():
		var level: int = FroggerIds.level_from_code(code)
		var row: MapBookEntry = _assets.map_book_entry(level)
		assert_not_null(row, code)
		if row == null:
			continue
		for low_poly: bool in [false, true]:
			var context: String = "%s low poly %s" % [code, low_poly]
			var problems := PackedStringArray()
			var map: MapFile = _assets.read_map(row.map_id(low_poly), problems)
			assert_not_null(map, context)
			assert_eq(problems, PackedStringArray(), context)
			if map == null:
				continue
			var theme: ThemeBookEntry = _assets.theme_book_entry(map.general.theme)
			assert_not_null(theme, context)
			assert_not_null(_assets.remap_for_resource(row.map_id(low_poly)), context)
			if theme == null:
				continue
			for bank_id: int in [general.vlo_id(false, low_poly), theme.vlo_id(false, low_poly)]:
				assert_not_null(_assets.read_texture_bank(bank_id, problems), "%s bank %d" % [context, bank_id])
			assert_eq(problems, PackedStringArray(), context)


func test_every_listed_demo_resolves() -> void:
	var table: DemoTable = _assets.tables.demo_table()
	assert_eq(table.error, "")
	assert_gt(table.size(), 0)
	for row: DemoTableEntry in table.entries:
		if row.is_skipped():
			continue
		for low_poly: bool in [false, true]:
			var setup: DemoSetup = DemoSetup.resolve(_assets, row.level, low_poly)
			var context: String = "level %d low poly %s" % [row.level, low_poly]
			assert_eq(setup.error, "", context)
			assert_not_null(setup.demo, context)


func test_every_sound_bank_resolves() -> void:
	var tables: SoundTables = _assets.tables.sound_tables()
	assert_eq(tables.error, "")
	assert_gt(tables.banks.size(), 0)
	for bank: Vector2i in tables.banks:
		if bank.y <= 0:
			continue
		var setup: SoundBankSetup = SoundBankSetup.from_catalog(_assets, bank.y)
		assert_eq(setup.error, "", "bank %d" % bank.y)
		assert_not_null(setup.header, "bank %d" % bank.y)
	var sounds: LogicalSoundSetup = LogicalSoundSetup.from_data(_assets, PackedInt32Array([FroggerIds.THEME_GENERAL, FroggerIds.THEMES.find("SWAMP")]))
	assert_eq(sounds.error, "")
	assert_gt(sounds.definitions.size(), 0)


func test_unknown_ids_report_problems() -> void:
	const UNKNOWN: int = 999999
	var problems := PackedStringArray()
	assert_null(_assets.read_map(UNKNOWN, problems))
	assert_null(_assets.read_texture_bank(UNKNOWN, problems))
	assert_null(_assets.read_model(UNKNOWN, problems))
	assert_null(_assets.read_demo(UNKNOWN, problems))
	assert_null(_assets.read_sound_bank(UNKNOWN, problems))
	assert_eq(problems.size(), 5)
	assert_string_contains(SoundBankSetup.from_catalog(_assets, UNKNOWN).error, str(UNKNOWN))
	assert_null(_assets.read_wad(UNKNOWN))
	assert_eq(_assets.counterpart_of(UNKNOWN), -1)


func test_the_emissive_image_table_loads_and_the_base_catalog_has_none() -> void:
	var table: EmissiveImageTable = _assets.emissive_images()
	assert_not_null(table)
	assert_gt(table.entries.size(), 0)
	assert_same(_assets.emissive_images(), table, "loaded once")
	assert_not_null(table.find("vol_lava6"))
	var base: EmissiveImageTable = AssetCatalog.new().emissive_images()
	assert_not_null(base)
	assert_eq(base.entries.size(), 0)


func test_a_missing_emissive_image_table_is_empty_and_noted() -> void:
	var catalog := ImportedAssets.new()
	catalog.root = "res://no_such_assets"
	assert_eq(catalog.emissive_images().entries.size(), 0)
	assert_eq(catalog.problems.size(), 1)
	assert_string_contains(catalog.problems[0], "res://no_such_assets/rendering/emissive_images.tres")

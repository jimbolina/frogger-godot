extends GutTest
## The FrogLord files shipped in third_party/ parse and expose the documented values.

var _library: FrogLordConfigLibrary


func before_each() -> void:
	_library = FrogLordConfigLibrary.new()


func test_the_pc_versions_are_shipped() -> void:
	var names: PackedStringArray = _library.version_names()
	for wanted: String in ["pc-retail-v3.0e", "pc-retail-v1.0", "pc-retail-v3.0e-vogons"]:
		assert_has(names, wanted)


func test_retail_v3_0e_addresses() -> void:
	var v: GameVersionConfig = _library.load_version("pc-retail-v3.0e")
	assert_not_null(v)
	assert_true(v.is_valid(), ", ".join(v.errors))
	assert_eq(v.display_name, "PC Retail v3.0e (Worldwide?)")
	assert_eq(v.platform, "WINDOWS")
	assert_true(v.is_pc())
	assert_eq(v.exe_checksums, PackedInt64Array([378672750, 269827179]))
	assert_eq(v.mwi_offset, 0x8AE20)
	assert_eq(v.mwi_length, 48840)
	assert_eq(v.ram_offset, 0x401000)
	assert_eq(v.map_book, 0x70100)
	assert_eq(v.theme_book, 0x70970)
	assert_eq(v.arcade_level_address, 0x70CB8)
	assert_eq(v.music_address, 0x80400)
	assert_eq(v.bmp_pointer_address, 0x77858)
	assert_eq(v.pickup_data, 0x759B8)
	assert_eq(v.scripts, 0x7B598)
	assert_eq(v.txl_sky_land, 0x7A020)
	assert_eq(v.pointer_to_file_offset(0x471100), 0x70100)
	assert_eq(v.file_offset_to_pointer(0x70100), 0x471100)
	assert_eq(v.hidden_parts["GEN_FROG.XAR"], PackedInt64Array([15]))


func test_retail_v3_0e_name_lists_with_froglord_defaults() -> void:
	var v: GameVersionConfig = _library.load_version("pc-retail-v3.0e")
	var lists: Dictionary[String, String] = v.referenced_name_lists()
	assert_eq(lists["anims"], "main-pc")
	assert_eq(lists["sounds"], "1997-11-19-pc-retail")
	assert_eq(lists["images"], "1997-11-15-pc-retail")
	assert_eq(lists["vlo"], "1997-11-15-pc-retail-1.0")
	assert_eq(lists["forms"], GameVersionConfig.DEFAULT_FORM_LIST, "the PC config names no form list")
	assert_eq(lists["entities"], GameVersionConfig.DEFAULT_ENTITY_LIST)
	assert_eq(lists["scripts"], GameVersionConfig.DEFAULT_SCRIPT_LIST)


func test_other_retail_builds() -> void:
	var v1: GameVersionConfig = _library.load_version("pc-retail-v1.0")
	assert_eq(v1.mwi_offset, 0x86DC0)
	assert_eq(v1.ram_offset, 0x401A00)
	assert_eq(v1.extra_bmp_pointers, 1)
	assert_eq(v1.exe_checksums, PackedInt64Array([1359970581]))
	var vogons: GameVersionConfig = _library.load_version("pc-retail-v3.0e-vogons")
	assert_eq(vogons.mwi_offset, 0x8B220)
	assert_eq(vogons.exe_checksums, PackedInt64Array([4183648227]))


func test_checksum_lookup() -> void:
	var found: Array[GameVersionConfig] = _library.find_versions_by_exe_checksum(378672750)
	assert_eq(found.size(), 1)
	assert_eq(found[0].internal_name, "pc-retail-v3.0e")
	assert_eq(_library.find_versions_by_exe_checksum(12345).size(), 0)


func test_every_shipped_version_file_parses() -> void:
	for version_name: String in _library.version_names():
		var v: GameVersionConfig = _library.load_version(version_name)
		assert_not_null(v, version_name)
		if v != null:
			assert_true(v.is_valid(), "%s: %s" % [version_name, ", ".join(v.errors)])


func test_every_referenced_name_list_exists_and_loads() -> void:
	for version_name: String in _library.version_names():
		var lists: Dictionary[String, String] = _library.load_version(version_name).referenced_name_lists()
		for folder: String in lists:
			if folder == "vlo":
				assert_true(FileAccess.file_exists(_library.root.path_join("vlo").path_join(lists[folder] + ".cfg")))
				continue
			var bank: NameBank = _library.load_image_names(lists[folder]) if folder == "images" \
				else _library.load_name_bank(folder, lists[folder])
			assert_not_null(bank, "%s: %s/%s" % [version_name, folder, lists[folder]])


func test_sound_names() -> void:
	var sounds: NameBank = _library.load_name_bank("sounds", "1997-11-19-pc-retail")
	assert_eq(sounds.get_name(0), "GEN_FLY_BUZZ")
	assert_eq(sounds.get_name(4), "GEN_FROG_FALL", "the trailing comment is stripped")
	assert_eq(sounds.index_of("gen_frog_croak"), 3)
	assert_not_null(sounds.get_sub_bank("GENERIC"))
	assert_eq(sounds.get_name(100000), "Unknown Sound [100000]")


func test_image_names() -> void:
	var images: NameBank = _library.load_image_names("1997-11-15-pc-retail")
	assert_eq(images.get_name(0), "gen_frogeye")
	assert_eq(images.get_name(1), "sub_lorry")
	assert_true(images.size() > 100)


func test_scripts_keep_sections_separate() -> void:
	var scripts: NameBank = _library.load_name_bank("scripts", GameVersionConfig.DEFAULT_SCRIPT_LIST)
	assert_not_null(scripts.get_sub_bank("CallbackNames"))
	assert_eq(scripts.names.find(scripts.get_sub_bank("CallbackNames").names[0]), -1,
		"callback names are not part of the main script numbering")


func test_missing_file_reports_an_error() -> void:
	assert_null(_library.load_version("no-such-build"))
	assert_string_contains(_library.error, "no-such-build")

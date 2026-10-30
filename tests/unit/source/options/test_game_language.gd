extends GutTest
## GameLanguage detects retail's language from locale ids and names, names its banks and
## resolves localized image names with an English fallback.


func _images(pairs: String) -> NameBank:
	return NameBank.from_indexed_config(FrogLordConfig.parse_legacy(pairs), "Image")


func test_enum_follows_retail_order() -> void:
	assert_eq(int(GameLanguage.Id.ENGLISH), 0)
	assert_eq(int(GameLanguage.Id.ITALIAN), 1)
	assert_eq(int(GameLanguage.Id.GERMAN), 2)
	assert_eq(int(GameLanguage.Id.FRENCH), 3)
	assert_eq(int(GameLanguage.Id.SPANISH), 4)
	assert_eq(GameLanguage.COUNT, 5)
	assert_eq(GameLanguage.LETTERS, PackedStringArray(["E", "I", "G", "F", "S"]))


func test_lcid_uses_the_primary_language_id() -> void:
	assert_eq(GameLanguage.from_lcid(0x0407), GameLanguage.Id.GERMAN)
	assert_eq(GameLanguage.from_lcid(0x0807), GameLanguage.Id.GERMAN, "Swiss German")
	assert_eq(GameLanguage.from_lcid(0x0410), GameLanguage.Id.ITALIAN)
	assert_eq(GameLanguage.from_lcid(0x040C), GameLanguage.Id.FRENCH)
	assert_eq(GameLanguage.from_lcid(0x0C0C), GameLanguage.Id.FRENCH, "Canadian French")
	assert_eq(GameLanguage.from_lcid(0x0C0A), GameLanguage.Id.SPANISH)
	assert_eq(GameLanguage.from_lcid(0x0409), GameLanguage.Id.ENGLISH)


func test_other_lcids_are_english() -> void:
	for lcid: int in [0, 0x0406, 0x0408, 0x040B, 0x040D, 0x040E, 0x040F, 0x0411, 0x0419, 0x3FF]:
		assert_eq(GameLanguage.from_lcid(lcid), GameLanguage.Id.ENGLISH, "lcid %x" % lcid)


func test_locale_names_map_through_the_retail_table() -> void:
	assert_eq(GameLanguage.from_locale_name("de_DE"), GameLanguage.Id.GERMAN)
	assert_eq(GameLanguage.from_locale_name("de-AT"), GameLanguage.Id.GERMAN)
	assert_eq(GameLanguage.from_locale_name("it"), GameLanguage.Id.ITALIAN)
	assert_eq(GameLanguage.from_locale_name("FR_ca"), GameLanguage.Id.FRENCH)
	assert_eq(GameLanguage.from_locale_name("es_MX"), GameLanguage.Id.SPANISH)
	for other: String in ["en_US", "el_GR", "fi", "ja_JP", "pt_BR", "", "_"]:
		assert_eq(GameLanguage.from_locale_name(other), GameLanguage.Id.ENGLISH, other)


func test_saved_setting_wins_over_the_locale() -> void:
	assert_eq(GameLanguage.resolve(GameLanguage.AUTO, "fr_FR"), GameLanguage.Id.FRENCH)
	assert_eq(GameLanguage.resolve(GameLanguage.Id.ITALIAN, "fr_FR"), GameLanguage.Id.ITALIAN)
	assert_eq(GameLanguage.resolve(9, "de_DE"), GameLanguage.Id.GERMAN)
	assert_true(GameLanguage.is_setting(GameLanguage.AUTO))
	assert_false(GameLanguage.is_language(GameLanguage.AUTO))
	assert_false(GameLanguage.is_setting(5))


func test_bank_names() -> void:
	assert_eq(GameLanguage.fixed_bank(GameLanguage.Id.ENGLISH), "FIXE_VRAM.VLO")
	assert_eq(GameLanguage.fixed_bank(GameLanguage.Id.GERMAN), "FIXG_VRAM.VLO")
	assert_eq(GameLanguage.option_bank(GameLanguage.Id.ITALIAN), "OPTI_RAM.VLO")
	assert_eq(GameLanguage.option_bank(GameLanguage.Id.SPANISH), "OPTS_RAM.VLO")
	assert_eq(GameLanguage.option_bank(7), "OPTE_RAM.VLO")


func test_localized_name_rule() -> void:
	assert_eq(GameLanguage.localized_name("opt_start", GameLanguage.Id.GERMAN), "optg_start")
	assert_eq(GameLanguage.localized_name("sel_loading", GameLanguage.Id.FRENCH), "self_loading")
	assert_eq(GameLanguage.localized_name("select1", GameLanguage.Id.ITALIAN), "select1_i")
	assert_eq(GameLanguage.localized_name("zone_complete", GameLanguage.Id.SPANISH), "zone_complete_s")
	assert_eq(GameLanguage.localized_name("opt_start", GameLanguage.Id.ENGLISH), "opt_start")


func test_image_name_falls_back_to_the_shared_english_name() -> void:
	var images: NameBank = _images("1=opt_start\n2=optg_start\n3=select1\n4=select1_g\n5=newfont\n6=opt_env_sky\n")
	assert_eq(GameLanguage.image_name("opt_start", GameLanguage.Id.GERMAN, images), "optg_start")
	assert_eq(GameLanguage.image_name("select1", GameLanguage.Id.GERMAN, images), "select1_g")
	assert_eq(GameLanguage.image_name("newfont", GameLanguage.Id.GERMAN, images), "newfont")
	assert_eq(GameLanguage.image_name("opt_env_sky", GameLanguage.Id.GERMAN, images), "opt_env_sky")
	assert_eq(GameLanguage.image_name("opt_start", GameLanguage.Id.FRENCH, images), "opt_start")
	assert_eq(GameLanguage.image_name("opt_start", GameLanguage.Id.GERMAN, null), "opt_start")

extends GutTest
## The setup screen's notices name the game version and credit the traced
## lettering, carry the importer's
## FrogLord credit with its MIT licence, Godot's licence and every engine
## component with its copyright holders and licence.


func test_the_notices_hold_the_game_froglord_and_godot() -> void:
	var notices: String = ThirdPartyNotices.text("9.8.7", "Example notice\nLine two")
	assert_string_contains(notices, "version 9.8.7")
	assert_string_contains(notices,
		"The angular lettering font and images are traced from the 1997 alpha's letter models by StarmanUltra.")
	assert_lt(notices.find("StarmanUltra"), notices.find("FrogLord\n="), "among the game's own lines")
	assert_string_contains(notices, "FrogLord\n========\n\nExample notice\nLine two")
	assert_string_contains(notices, Engine.get_license_text().strip_edges().get_slice("\n", 0))
	var info: Array[Dictionary] = Engine.get_copyright_info()
	assert_gt(info.size(), 0)
	assert_string_contains(notices, str(info[0]["name"]))
	for licence: Variant in Engine.get_license_info().keys():
		assert_string_contains(notices, str(licence))


func test_no_importer_notice_leaves_out_the_froglord_section() -> void:
	assert_false(ThirdPartyNotices.text("1", "").contains("FrogLord\n="))


func test_components_list_holders_and_licences() -> void:
	var info: Array[Dictionary] = [
		{"name": "Thing", "parts": [{"files": ["a"], "copyright": PackedStringArray(["2020 Someone", "2021 Other"]), "license": "MIT"}]},
	]
	assert_eq(ThirdPartyNotices.components(info), "Thing\n  (c) 2020 Someone\n  (c) 2021 Other\n  Licence: MIT")


func test_the_shipped_importer_credits_froglord_with_its_licence() -> void:
	var notice: String = AssetImporterFactory.create().third_party_notice()
	assert_string_contains(notice, "https://github.com/Kneesnap/FrogLord")
	assert_string_contains(notice, "MIT License")
	assert_string_contains(notice, "Copyright (c) 2018-2024 Kneesnap")

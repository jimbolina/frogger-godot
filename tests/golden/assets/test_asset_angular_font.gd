extends AssetTest
## The committed angular vector font (content/fonts/angular/frogger_angular.ttf,
## written by tools/make_angular_font.py) imports as an MSDF [FontFile] that
## holds every capital, digit and derived character with a positive advance
## and no lowercase. The character list here is independent of the generator:
## it must equal the SVG sources' names plus derived.json's keys, both read
## with Godot's own directory listing and JSON parser.

const FONT_PATH: String = "res://content/fonts/angular/frogger_angular.ttf"
const SVG_DIR: String = "res://content/fonts/angular/svg"
const DERIVED_PATH: String = "res://content/fonts/angular/derived.json"
const LETTERS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const DIGITS: String = "0123456789"
## The derived characters: punctuation, the back arrow and the accented capitals.
const DERIVED: String = "!¡':-.=◀ÉÓÍÙÄÜÇ"
const MEASURE_SIZE: int = 64


func _font() -> FontFile:
	var loaded: Resource = load(FONT_PATH)
	var font: FontFile = loaded as FontFile
	assert_not_null(font, "%s loads as a FontFile" % FONT_PATH)
	return font


func _characters(text: String) -> PackedStringArray:
	var result := PackedStringArray()
	for index: int in text.length():
		result.append(text[index])
	result.sort()
	return result


func test_the_catalog_serves_the_font_by_name() -> void:
	var assets: ImportedAssets = ImportedAssets.open(ASSETS)
	var served: FontFile = assets.font("angular") as FontFile
	assert_not_null(served, "the catalog serves the angular font")
	if served != null:
		assert_eq(served.resource_path, FONT_PATH, "the catalog draws the committed font")
	assert_eq(assets.problems, PackedStringArray(), "the catalog serves the font without problems")


func test_the_font_draws_with_msdf() -> void:
	var font: FontFile = _font()
	if font == null:
		return
	assert_true(font.multichannel_signed_distance_field, "the angular font is imported as MSDF")
	assert_eq(font.hinting, TextServer.HINTING_NONE, "the angular font has no hinting")


func test_every_character_has_a_glyph_and_an_advance() -> void:
	var font: FontFile = _font()
	if font == null:
		return
	var mismatches := PackedStringArray()
	for character: String in _characters(LETTERS + DIGITS + DERIVED + " "):
		var code: int = character.unicode_at(0)
		if not font.has_char(code):
			mismatches.append("%s (U+%04X) is missing from the font" % [character, code])
			continue
		var advance: float = font.get_char_size(code, MEASURE_SIZE).x
		if advance <= 0.0:
			mismatches.append("%s (U+%04X) has advance %s" % [character, code, advance])
	for character: String in _characters(LETTERS.to_lower()):
		if font.has_char(character.unicode_at(0)):
			mismatches.append("lowercase %s is in the font" % character)
	for mismatch: String in mismatches:
		fail_test(mismatch)
	assert_eq(mismatches.size(), 0, "the font holds the capitals, digits and derived characters")


func test_the_character_list_matches_the_sources() -> void:
	var sources := PackedStringArray()
	for file_name: String in DirAccess.get_files_at(SVG_DIR):
		if file_name.get_extension() == "svg":
			sources.append(file_name.get_basename())
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DERIVED_PATH))
	assert_true(parsed is Dictionary, "%s parses as a JSON object" % DERIVED_PATH)
	if parsed is Dictionary:
		var derived: Dictionary = parsed
		for key: Variant in derived:
			var name: String = key
			if not name.begins_with("_"):
				sources.append(name)
	sources.sort()
	var listed: PackedStringArray = _characters(LETTERS + DIGITS + DERIVED)
	for character: String in sources:
		if not listed.has(character):
			fail_test("%s is in the sources but not in this test's list" % character)
	for character: String in listed:
		if not sources.has(character):
			fail_test("%s is in this test's list but not in the sources" % character)
	assert_eq(sources, listed, "the sources define exactly the listed characters")

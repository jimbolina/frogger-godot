extends GutTest
## GameLanguage and FrontEndAssets agree with the independent language facts in
## tests/golden/synthetic/frontend_language.json (tools/make_golden_language.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_language.json"

var _document: Dictionary = {}
var _images: NameBank


func before_all() -> void:
	_document = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	var library := FrogLordConfigLibrary.new()
	_images = GameNameListsReader.load_for(library.load_version("pc-retail-v3.0e"), library).images


static func _int(value: Variant) -> int:
	var number: float = value
	return int(number)


static func _ints(values: Variant) -> PackedInt32Array:
	var items: Array = values
	var result := PackedInt32Array()
	for value: Variant in items:
		result.append(_int(value))
	return result


static func _text(value: Variant) -> String:
	var text: String = value
	return text


static func _texts(values: Variant) -> PackedStringArray:
	var items: Array = values
	var result := PackedStringArray()
	for value: Variant in items:
		result.append(_text(value))
	return result


static func _rows(value: Variant) -> Array:
	var rows: Array = value
	return rows


func test_languages_and_banks() -> void:
	var languages: Array = _rows(_document.languages)
	assert_eq(languages.size(), GameLanguage.COUNT)
	assert_eq(_int(_document.auto), GameLanguage.AUTO)
	for entry: Variant in languages:
		var language: Dictionary = entry
		var id: int = _int(language.id)
		var key: String = GameLanguage.Id.keys()[id]
		assert_eq(key, _text(language.key))
		assert_eq(GameLanguage.NAMES[id], _text(language.name))
		assert_eq(GameLanguage.letter(id), _text(language.letter))
		assert_eq(GameLanguage.CODES[id], _text(language.code))
		assert_eq(GameLanguage.fixed_bank(id), _text(language.fixed_bank))
		assert_eq(GameLanguage.option_bank(id), _text(language.option_bank))
		assert_eq(FrontEndAssets.banks_for(id), _texts(language.front_end_banks), _text(language.name))


func test_locale_id_table() -> void:
	var lcid: Dictionary = _document.lcid
	assert_eq(_int(lcid.mask), GameLanguage.LCID_MASK)
	assert_eq(_int(lcid.primary_bias), GameLanguage.PRIMARY_BIAS)
	assert_eq(_int(lcid.primary_bound), GameLanguage.PRIMARY_MAP.size() - 1)
	var map := PackedInt32Array()
	for arm: int in GameLanguage.PRIMARY_MAP:
		map.append(arm)
	assert_eq(_ints(lcid.primary_map), map)
	var arms := PackedInt32Array()
	for language: GameLanguage.Id in GameLanguage.ARM_LANGUAGES:
		arms.append(language)
	assert_eq(_ints(lcid.arm_languages), arms)
	var primary: Dictionary = _document.locale_primary_ids
	assert_eq(primary.size(), GameLanguage.LOCALE_PRIMARY_IDS.size())
	for code: String in GameLanguage.LOCALE_PRIMARY_IDS:
		assert_eq(_int(primary.get(code, -1)), GameLanguage.LOCALE_PRIMARY_IDS[code], code)


func test_locale_ids_and_names_select_the_retail_language() -> void:
	for entry: Variant in _rows(_document.lcid_cases):
		var pair: PackedInt32Array = _ints(entry)
		assert_eq(int(GameLanguage.from_lcid(pair[0])), pair[1], "lcid 0x%04x" % pair[0])
	for entry: Variant in _rows(_document.locale_cases):
		var pair: Array = entry
		assert_eq(int(GameLanguage.from_locale_name(_text(pair[0]))), _int(pair[1]), "locale '%s'" % _text(pair[0]))


func test_every_localized_family_follows_the_name_rule() -> void:
	var rule: Dictionary = _document.name_rule
	assert_eq(GameLanguage.PREFIX_FAMILIES, _texts(rule.prefix_families))
	var order: PackedStringArray = _texts(rule.order)
	for entry: Variant in _rows(_document.families):
		var family: PackedStringArray = _texts(entry)
		for slot: int in order.size():
			var language: int = GameLanguage.LETTERS.find(order[slot])
			assert_eq(GameLanguage.localized_name(family[0], language), family[slot + 1], family[0])
			assert_eq(GameLanguage.image_name(family[0], language, _images), family[slot + 1], family[0])


func test_front_end_images_resolve_or_share_the_english_name() -> void:
	var names := PackedStringArray()
	var order: PackedStringArray = _texts(_document.name_rule.order)
	for entry: Variant in _rows(_document.front_end_images):
		var image: Dictionary = entry
		var english: String = _text(image.name)
		names.append(english)
		var localized: Array = image.localized
		for slot: int in order.size():
			var language: int = GameLanguage.LETTERS.find(order[slot])
			var expected: String = english if localized[slot] == null else _text(localized[slot])
			assert_eq(GameLanguage.image_name(english, language, _images), expected, "%s %s" % [english, order[slot]])
		assert_eq(GameLanguage.image_name(english, GameLanguage.Id.ENGLISH, _images), english)
	assert_eq(names, FrontEndAssets.NAMES)

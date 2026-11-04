extends GutTest
## GameLanguage's localised family and front-end image names, resolved against
## the imported FrogLord image names, agree with the independent language
## facts in tests/golden/synthetic/frontend_language.json
## (tools/golden/make_golden_language.py).

const GOLDEN: String = "res://tests/golden/synthetic/frontend_language.json"

var _document: Dictionary = {}
var _images: NameBank


func before_all() -> void:
	_document = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	var names: GameNameLists = ImportedNames.lists()
	_images = names.images if names != null else null


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

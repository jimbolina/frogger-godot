class_name GameLanguage
extends RefCounted
## Retail PC's five game languages: locale detection, language banks and localized image names.
##
## Retail has no language screen. Its startup page masks the Windows locale id to
## the primary language id and maps it through a ten-byte table to one of five
## stores into [code]Game_language[/code]; every other id is English. The port
## reaches the same table from a locale name such as [code]de_DE[/code] through
## the primary ids of the languages the table spans.
##
## Each language has its own fixed-UI bank ([code]FIX?_VRAM.VLO[/code]) and options
## text bank ([code]OPT?_RAM.VLO[/code]). FrogLord names localized images in two
## ways: names whose first word is in [constant PREFIX_FAMILIES] put the language
## letter after that word ([code]opt_start[/code] becomes [code]optg_start[/code]),
## and every other name appends it ([code]select1[/code] becomes [code]select1_g[/code]).
## A name with no localized entry is shared by every language.

## Game_language values, in retail's order.
enum Id { ENGLISH, ITALIAN, GERMAN, FRENCH, SPANISH }

## Number of languages.
const COUNT: int = 5
## Saved-setting value meaning "follow the operating-system locale".
const AUTO: int = -1
## Mask that keeps the primary language id of a Windows locale id.
const LCID_MASK: int = 0x3FF
## Lowest primary language id the retail table covers.
const PRIMARY_BIAS: int = 0x07
## Arm index for each primary id from [constant PRIMARY_BIAS] upward.
const PRIMARY_MAP: PackedByteArray = [0, 4, 4, 1, 4, 2, 4, 4, 4, 3]
## Language stored by each arm of the retail jump table.
const ARM_LANGUAGES: Array[Id] = [Id.GERMAN, Id.SPANISH, Id.FRENCH, Id.ITALIAN, Id.ENGLISH]
## Windows primary language id of each ISO 639-1 code the retail table spans.
const LOCALE_PRIMARY_IDS: Dictionary[String, int] = {
	"de": 0x07, "el": 0x08, "en": 0x09, "es": 0x0A, "fi": 0x0B,
	"fr": 0x0C, "he": 0x0D, "hu": 0x0E, "is": 0x0F, "it": 0x10,
}
## Bank letter of each language.
const LETTERS: PackedStringArray = ["E", "I", "G", "F", "S"]
## ISO 639-1 code of each language.
const CODES: PackedStringArray = ["en", "it", "de", "fr", "es"]
## English name of each language.
const NAMES: PackedStringArray = ["English", "Italian", "German", "French", "Spanish"]
## First name words that take the language letter as a prefix rather than a suffix.
const PREFIX_FAMILIES: PackedStringArray = ["opt", "sel"]


## True when [param value] is one of the five languages.
static func is_language(value: int) -> bool:
	return value >= 0 and value < COUNT


## True when [param value] is a language or [constant AUTO].
static func is_setting(value: int) -> bool:
	return value == AUTO or is_language(value)


## The language retail chooses for Windows locale id [param lcid].
static func from_lcid(lcid: int) -> Id:
	var index: int = (lcid & LCID_MASK) - PRIMARY_BIAS
	if index < 0 or index >= PRIMARY_MAP.size():
		return Id.ENGLISH
	return ARM_LANGUAGES[PRIMARY_MAP[index]]


## The language for a locale name such as [code]de_DE[/code], [code]fr-CA[/code] or [code]it[/code].
static func from_locale_name(locale_name: String) -> Id:
	var code: String = locale_name.strip_edges().to_lower().replace("-", "_").get_slice("_", 0)
	if not LOCALE_PRIMARY_IDS.has(code):
		return Id.ENGLISH
	return from_lcid(LOCALE_PRIMARY_IDS[code])


## The language a saved [param setting] selects: itself when valid, else the one for [param locale_name].
static func resolve(setting: int, locale_name: String) -> Id:
	if is_language(setting):
		return setting as Id
	return from_locale_name(locale_name)


## The language's bank letter, or "E" outside the five languages.
static func letter(language: int) -> String:
	return LETTERS[language] if is_language(language) else LETTERS[Id.ENGLISH]


## The language's fixed-UI bank, e.g. [code]FIXG_VRAM.VLO[/code].
static func fixed_bank(language: int) -> String:
	return "FIX%s_VRAM.VLO" % letter(language)


## The language's options text bank, e.g. [code]OPTG_RAM.VLO[/code].
static func option_bank(language: int) -> String:
	return "OPT%s_RAM.VLO" % letter(language)


## The candidate localized name of English image [param english_name]; English returns it unchanged.
static func localized_name(english_name: String, language: int) -> String:
	if not is_language(language) or language == Id.ENGLISH:
		return english_name
	var mark: String = letter(language).to_lower()
	var split: int = english_name.find("_")
	if split > 0 and PREFIX_FAMILIES.has(english_name.substr(0, split)):
		return english_name.substr(0, split) + mark + english_name.substr(split)
	return english_name + "_" + mark


## The image name [param language] draws for [param english_name]: the localized
## name when [param images] names it, else the shared English name.
static func image_name(english_name: String, language: int, images: NameBank) -> String:
	var candidate: String = localized_name(english_name, language)
	if candidate != english_name and images != null and images.index_of(candidate) >= 0:
		return candidate
	return english_name

class_name FrontEndAssets
extends RefCounted
## Main-menu, options, level-select and pause text images in one [GameLanguage], resolved by
## FrogLord names and level-select texture records from the player's archive.
##
## English loads [constant BANKS]. Another language also loads its fixed-UI and options
## text banks after the English ones and draws each name's localized image
## ([method GameLanguage.image_name]). A missing language bank or localized image
## falls back to English and is recorded in [member diagnostics].
##
## Only the arcade rows are covered: the race rows' screenshots and names live
## in the multiplayer bank [code]LS_ALLM.VLO[/code], which belongs to the
## multiplayer pages. The logo [code]froglogo[/code] lives in the start bank.
## The water images come from the options bank [code]OPT_VRAM.VLO[/code]
## (HSInitialiseWater's textures), which [code]LS_ALL.VLO[/code] also carries, without
## their padding because the water maps texture coordinates over the in-game image.

## World and level images of one level-select row, in the row's record order.
enum LevelImage { WORLD_UNLOCKED, WORLD_VISITED, WORLD_NOT_TRIED, SCREENSHOT, STACK_NAME, GAME_NAME }

## Banks loaded, in upload order (later banks win for a shared texture id).
const BANKS: PackedStringArray = ["OPT_VRAM.VLO", "STARTNTSC.VLO", "FIXE_VRAM.VLO", "OPTE_RAM.VLO", "LS_ALL.VLO"]
## English names of the images every front-end page may draw.
const NAMES: PackedStringArray = [
	"opt_start", "opt_options", "opt_exit", "opt_race", "select_level", "zone_complete",
	"press_fire", "sel_loading", "opt_big_continue", "opt_yes", "opt_no", "opt_paused",
	"froglogo", "newfont", "select1", "select2", "select5", "ls_gold_frog",
	"opt_view_hs", "opt_ctrl_config", "opt_insert_pad", "select7", "opt_keyboard",
	"opt_arrow_small_left", "opt_arrow_small_right", "select3", "skip_hi_score", "opt_arrow",
]
## The bank the water images are read from.
const WATER_BANK: String = "OPT_VRAM.VLO"
## The water surface and riverbed images (im_opt_env_sky, im_opt_bank3).
const WATER_NAMES: PackedStringArray = ["opt_env_sky", "opt_bank3"]
## The high-score level stack's checker tiles (SelectLevelCreateBG's im_*_col pairs), unpadded.
const BACKGROUND_NAMES: PackedStringArray = ["jun_col", "des_col", "cav_col", "vol_col", "sky_col", "org_col", "for_col", "sub_col"]
## Level images resolved for every arcade row.
const LEVEL_IMAGES: Array[LevelImage] = [
	LevelImage.WORLD_UNLOCKED, LevelImage.WORLD_NOT_TRIED, LevelImage.SCREENSHOT, LevelImage.STACK_NAME,
]

## Why loading failed, or "" (a failed load holds no textures).
var error: String = ""
## The [enum GameLanguage.Id] drawn (English when the request is not a language).
var language: int = GameLanguage.Id.ENGLISH
## English fallbacks taken for a missing language bank or localized image.
var diagnostics: PackedStringArray = PackedStringArray()
## The loaded banks, for drawing [method image_record] images as sprites; empty when loading failed.
var texture_library: TextureLibrary = TextureLibrary.new()

var _textures: Dictionary[String, Texture2D] = {}
var _images: Dictionary[String, VloImage] = {}
var _source_names: Dictionary[String, String] = {}
var _level_textures: Dictionary[Vector2i, Texture2D] = {}


## The banks loaded for [param for_language], in upload order.
static func banks_for(for_language: int) -> PackedStringArray:
	var banks := PackedStringArray(BANKS)
	if not GameLanguage.is_language(for_language) or for_language == GameLanguage.Id.ENGLISH:
		return banks
	var after_english: int = banks.find(GameLanguage.option_bank(GameLanguage.Id.ENGLISH)) + 1
	banks.insert(after_english, GameLanguage.option_bank(for_language))
	banks.insert(after_english, GameLanguage.fixed_bank(for_language))
	return banks


## Loads the front-end banks for [param for_language] without retaining the archive or
## copying retail pixels to disk.
static func from_data(data: AssetCatalog, for_language: int = GameLanguage.Id.ENGLISH) -> FrontEndAssets:
	var result := FrontEndAssets.new()
	result.language = for_language if GameLanguage.is_language(for_language) else GameLanguage.Id.ENGLISH
	if not GameLanguage.is_language(for_language):
		result.diagnostics.append("Language %d is unknown; using English" % for_language)
	if data == null or not data.is_valid() or data.names.images == null:
		result.error = "Front end requires valid player data and named images"
		return result
	var library := TextureLibrary.new()
	var problems := PackedStringArray()
	for bank_name: String in banks_for(result.language):
		var entry: MwiEntry = data.find_resource(bank_name)
		if entry == null and not BANKS.has(bank_name):
			result.diagnostics.append("%s bank %s is missing; using English" % [
				GameLanguage.NAMES[result.language], bank_name])
			continue
		if entry == null:
			result.error = "Front-end bank is missing: " + bank_name
			return result
		var bank: VloFile = data.read_texture_bank(entry.index, problems)
		if bank == null or not problems.is_empty():
			result.error = "Front-end bank %s: %s" % [bank_name, "; ".join(problems)]
			return result
		library.add_bank(bank, bank_name)
	var textures: Dictionary[String, Texture2D] = {}
	var images: Dictionary[String, VloImage] = {}
	var source_names: Dictionary[String, String] = {}
	for image_name: String in NAMES:
		var drawn_name: String = GameLanguage.image_name(image_name, result.language, data.names.images)
		if drawn_name != image_name:
			var localized: int = data.names.images.index_of(drawn_name)
			var localized_image: Texture2D = library.texture_for_id(localized)
			if localized_image != null:
				textures[image_name] = localized_image
				images[image_name] = library.image_for_id(localized)
				source_names[image_name] = drawn_name
				continue
			result.diagnostics.append("%s image %s (texture %d) is missing; using %s" % [
				GameLanguage.NAMES[result.language], drawn_name, localized, image_name])
		var identity: int = data.names.images.index_of(image_name)
		var image: Texture2D = library.texture_for_id(identity) if identity >= 0 else null
		if image == null:
			result.error = "Front-end image %s (texture %d) is missing from the supplied banks" % [image_name, identity]
			return result
		textures[image_name] = image
		images[image_name] = library.image_for_id(identity)
		source_names[image_name] = image_name
	for image_name: String in WATER_NAMES:
		var identity: int = data.names.images.index_of(image_name)
		var record: VloImage = library.image_for_id(identity, library.find_bank(WATER_BANK)) if identity >= 0 else null
		if record == null:
			result.error = "Front-end image %s (texture %d) is missing from %s" % [image_name, identity, WATER_BANK]
			return result
		textures[image_name] = ImageTexture.create_from_image(TextureBuilder.build_unpadded_image(record))
		source_names[image_name] = image_name
	for image_name: String in BACKGROUND_NAMES:
		var identity: int = data.names.images.index_of(image_name)
		var record: VloImage = library.image_for_id(identity) if identity >= 0 else null
		if record == null:
			result.diagnostics.append("Level-stack background image %s (texture %d) is missing" % [image_name, identity])
			continue
		textures[image_name] = ImageTexture.create_from_image(TextureBuilder.build_unpadded_image(record))
		source_names[image_name] = image_name
	var table: LevelSelectTable = data.tables.level_select()
	var pointers: BmpPointers = data.tables.bmp_pointers()
	if not table.error.is_empty() or not pointers.error.is_empty():
		result.error = "Front-end level images need the level-select table: %s" % (table.error + pointers.error)
		return result
	var level_textures: Dictionary[Vector2i, Texture2D] = {}
	for row: LevelSelectEntry in table.arcade:
		for kind: LevelImage in LEVEL_IMAGES:
			var identity: int = pointers.texture_id_for_pointer(row.image_pointers[kind])
			var image: Texture2D = library.texture_for_id(identity) if identity > 0 else null
			if image == null:
				result.error = "Front-end %s image of level %d (texture %d) is missing from the supplied banks" % [
					LevelImage.keys()[kind], row.level, identity]
				return result
			level_textures[Vector2i(row.level, kind)] = image
	result._textures = textures
	result._images = images
	result.texture_library = library
	result._source_names = source_names
	result._level_textures = level_textures
	return result


## The image called [param image_name] (one of [constant NAMES], [constant WATER_NAMES] or
## [constant BACKGROUND_NAMES]), or null.
func texture(image_name: String) -> Texture2D:
	return _textures.get(image_name, null)


## The texture record drawn for [param image_name] (one of [constant NAMES]), or null.
func image_record(image_name: String) -> VloImage:
	return _images.get(image_name, null)


## The FrogLord name drawn for English [param image_name] in this language, or "" when not loaded.
func source_name(image_name: String) -> String:
	return _source_names.get(image_name, "")


## The [param kind] image of arcade level [param level] (one of [constant LEVEL_IMAGES]), or null.
func level_texture(level: int, kind: LevelImage) -> Texture2D:
	return _level_textures.get(Vector2i(level, kind), null)

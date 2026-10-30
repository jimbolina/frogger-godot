class_name FrontEndAssets
extends RefCounted
## English main-menu, level-select and pause text images, resolved by FrogLord names
## and level-select texture records from the player's archive.
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
## Named English images every front-end page may draw.
const NAMES: PackedStringArray = [
	"opt_start", "opt_options", "opt_exit", "opt_race", "select_level", "zone_complete",
	"press_fire", "sel_loading", "opt_big_continue", "opt_yes", "opt_no", "opt_paused",
	"froglogo", "newfont", "select1", "select2", "select5", "ls_gold_frog",
]
## The bank the water images are read from.
const WATER_BANK: String = "OPT_VRAM.VLO"
## The water surface and riverbed images (im_opt_env_sky, im_opt_bank3).
const WATER_NAMES: PackedStringArray = ["opt_env_sky", "opt_bank3"]
## Level images resolved for every arcade row.
const LEVEL_IMAGES: Array[LevelImage] = [
	LevelImage.WORLD_UNLOCKED, LevelImage.WORLD_NOT_TRIED, LevelImage.SCREENSHOT, LevelImage.STACK_NAME,
]

## Why loading failed, or "" (a failed load holds no textures).
var error: String = ""

var _textures: Dictionary[String, Texture2D] = {}
var _level_textures: Dictionary[Vector2i, Texture2D] = {}


## Loads the front-end banks without retaining the archive or copying retail pixels to disk.
static func from_data(data: GameData) -> FrontEndAssets:
	var result := FrontEndAssets.new()
	if data == null or not data.is_valid() or data.tables.names.images == null:
		result.error = "Front end requires valid player data and named images"
		return result
	var library := TextureLibrary.new()
	var problems := PackedStringArray()
	for bank_name: String in BANKS:
		var entry: MwiEntry = data.find_resource(bank_name)
		if entry == null:
			result.error = "Front-end bank is missing: " + bank_name
			return result
		var bank: VloFile = data.read_texture_bank(entry.index, problems)
		if bank == null or not problems.is_empty():
			result.error = "Front-end bank %s: %s" % [bank_name, "; ".join(problems)]
			return result
		library.add_bank(bank, bank_name)
	var textures: Dictionary[String, Texture2D] = {}
	for image_name: String in NAMES:
		var identity: int = data.tables.names.images.index_of(image_name)
		var image: Texture2D = library.texture_for_id(identity) if identity >= 0 else null
		if image == null:
			result.error = "Front-end image %s (texture %d) is missing from the supplied banks" % [image_name, identity]
			return result
		textures[image_name] = image
	for image_name: String in WATER_NAMES:
		var identity: int = data.tables.names.images.index_of(image_name)
		var record: VloImage = library.image_for_id(identity, library.find_bank(WATER_BANK)) if identity >= 0 else null
		if record == null:
			result.error = "Front-end image %s (texture %d) is missing from %s" % [image_name, identity, WATER_BANK]
			return result
		textures[image_name] = ImageTexture.create_from_image(TextureBuilder.build_unpadded_image(record))
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
	result._level_textures = level_textures
	return result


## The image called [param image_name] (one of [constant NAMES] or [constant WATER_NAMES]), or null.
func texture(image_name: String) -> Texture2D:
	return _textures.get(image_name, null)


## The [param kind] image of arcade level [param level] (one of [constant LEVEL_IMAGES]), or null.
func level_texture(level: int, kind: LevelImage) -> Texture2D:
	return _level_textures.get(Vector2i(level, kind), null)

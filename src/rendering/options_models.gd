class_name OptionsModels
extends RefCounted
## The options page's models, frog, sprite images and lights from the player's files, the same in
## every language.
##
## The lily, log, volume, static, turtle and high-score letter models come from the high-poly
## options WAD by FrogLord name (OPTIONSH.WAD; retail picks the high or _WIN95 twin at the call
## site, KEY_FACTS KF-110) with the options texture bank [code]OPT_VRAM.VLO[/code] first, then the
## GENERAL bank. The frog is the high-detail GEN_FROG.XAR ([TerrainFrogAssets]). The name-entry
## frog is the flipbook GENM_FROG.XMR (MODEL_MOF_FROG_FLIPBOOK_0) from GENERAL's high-poly
## multiplayer WAD and bank, its actions resolved by FrogLord name; when it cannot be loaded the
## page falls back to GEN_FROG and the reason is a diagnostic. The landing splash shows ripples 3-6 and the
## frog's jump shadow the frog shadow images, both resolved as the level effects resolve them
## ([EffectResources]). [member lighting] holds the options viewport's lights (options.c:446-454):
## ambient 0x606060 and one parallel light 0xa0a0c0 whose frame at (0x800, -0x1000, -0x1000) is
## pointed at the origin, so it shines along the origin less that position.

enum Kind {
	LILY, LOG, MUSIC, EFFECTS, BULLRUSH, STATIC_LILY, TURTLE,
	HI_A, HI_B, HI_C, HI_D, HI_E, HI_F, HI_G, HI_H, HI_I, HI_J, HI_K, HI_L, HI_M,
	HI_N, HI_O, HI_P, HI_Q, HI_R, HI_S, HI_T, HI_U, HI_V, HI_W, HI_X, HI_Y, HI_Z,
	HI_DOT, HI_BACK, HI_END,
}

## The WAD holding the options models.
const WAD_NAME: String = "OPTIONSH.WAD"
## FrogLord file name of each [enum Kind].
const FILE_NAMES: PackedStringArray = [
	"OPT_LILLYPAD_BLANK.XMR", "HI_LOG.XMR", "OPT_MUSIC.XMU", "OPT_SFX.XMU", "OPT_STAT_BULLRUSH.XMR",
	"OPT_STAT_LILLY.XMR", "OPT_TURTLE.XMR",
	"HI_A.XMR", "HI_B.XMR", "HI_C.XMR", "HI_D.XMR", "HI_E.XMR", "HI_F.XMR", "HI_G.XMR", "HI_H.XMR",
	"HI_I.XMR", "HI_J.XMR", "HI_K.XMR", "HI_L.XMR", "HI_M.XMR", "HI_N.XMR", "HI_O.XMR", "HI_P.XMR",
	"HI_Q.XMR", "HI_R.XMR", "HI_S.XMR", "HI_T.XMR", "HI_U.XMR", "HI_V.XMR", "HI_W.XMR", "HI_X.XMR",
	"HI_Y.XMR", "HI_Z.XMR", "HI_DOT.XMR", "HI_BACK.XMR", "HI_END.XMR",
]
## The name-entry frog's flipbook model and its FrogLord action list section.
const ENTRY_FROG_NAME: String = "GENM_FROG.XMR"
const ENTRY_FROG_ACTIONS: String = "GENM_FROG"
## Options viewport ambient light and parallel light colour (MR_CVEC words: red in the low byte).
const AMBIENT_COLOUR: int = 0x606060
const PARALLEL_COLOUR: int = 0xa0a0c0
## The parallel light frame's position; its Z axis points from there at the origin.
const PARALLEL_FRAME: Vector3i = Vector3i(0x800, -0x1000, -0x1000)
## High_score_splash_animlist's ripple images.
const SPLASH_SYMBOLS: PackedStringArray = ["im_ripple_tim3", "im_ripple_tim4", "im_ripple_tim5", "im_ripple_tim6"]
## The main menu's translucent cloud behind its sprites (im_opt_menu_cloud, tempopt.c:1243), from
## the GENERAL theme bank.
const CLOUD_IMAGE: String = "opt_menu_cloud"
## The sub-folder of the imported models built with the options page's banks.
const MESH_FOLDER: String = "options"
## MapLight types for the ambient and parallel lights.
const AMBIENT_LIGHT: int = 1
const PARALLEL_LIGHT: int = 2

## Why loading failed, or "".
var error: String = ""
## Problems that leave the page drawable, such as a missing effect image.
var diagnostics: PackedStringArray = PackedStringArray()
## Decoded model of each [enum Kind].
var files: Array[MofFile] = []
## Mesh of each [enum Kind], shared by every instance.
var meshes: Array[ModelMesh] = []
## The frog's model, mesh and action lengths; its player is not used by the page.
var frog: TerrainFrogAssets
## The options viewport's lights.
var lighting: MapLighting = MapLighting.new()
## The GENERAL and options banks the models draw from; it also builds the sprite images' textures.
var library: TextureLibrary = TextureLibrary.new()
## Splash and frog shadow images by effect symbol.
var images: Dictionary[String, VloImage] = {}
## The name-entry frog's flipbook model, or null when it could not be loaded.
var entry_frog: MofFile
## Mesh of [member entry_frog].
var entry_frog_mesh: ModelMesh
## The GENERAL and multiplayer banks the name-entry frog draws from, for its poly pieces too.
var entry_frog_library: TextureLibrary
## The multiplayer bank preferred for the name-entry frog's textures.
var entry_frog_bank: VloFile
## The name-entry frog's flipbook action index by FrogLord name.
var entry_frog_actions: Dictionary[StringName, int] = {}


## Loads every model, image and light from [param data].
static func from_data(data: AssetCatalog) -> OptionsModels:
	var result := OptionsModels.new()
	result.lighting = options_lighting()
	if data == null or not data.is_valid():
		result.error = "Options models require valid player data"
		return result
	var wad: MwiEntry = data.find_resource(WAD_NAME)
	var general: ThemeBookEntry = data.theme_book_entry(FroggerIds.THEME_GENERAL)
	if wad == null or general == null:
		result.error = "Options models need %s and the GENERAL theme" % WAD_NAME
		return result
	var problems := PackedStringArray()
	var own: VloFile = data.read_texture_bank(data.texture_bank_for_wad(wad.index), problems)
	var general_bank: VloFile = data.read_texture_bank(general.high_vlo_id, problems)
	if own == null or general_bank == null:
		result.error = "Options texture banks cannot be read: " + "; ".join(problems)
		return result
	result.library.catalog = data
	result.library.add_bank(general_bank, "general")
	result.library.add_bank(own, "options")
	var children := PackedInt32Array()
	var wad_file: WadFile = data.read_wad(wad.index)
	if wad_file != null:
		for child: WadFile.Child in wad_file.children:
			children.append(child.resource_id)
	for file_name: String in FILE_NAMES:
		var entry: MwiEntry = data.find_resource(file_name)
		if entry == null or not children.has(entry.index):
			result.error = "Options model %s is not in %s" % [file_name, WAD_NAME]
			return result
		var file: MofFile = data.read_model(entry.index, problems)
		if file == null or not file.error.is_empty() or file.static_models.is_empty():
			result.error = "Options model %s cannot be decoded: %s" % [file_name, "; ".join(problems)]
			return result
		result.files.append(file)
		result.meshes.append(ModelMeshLibrary.mesh_for(data, entry.index, result.library, own, MESH_FOLDER))
	result.frog = TerrainFrogAssets.from_data(data)
	if not result.frog.error.is_empty():
		result.error = result.frog.error
		return result
	result._load_entry_frog(data, general, general_bank)
	var scene := MapSceneData.new()
	scene.library = result.library
	scene.preferred = own
	var effects: EffectResources = EffectResources.from_scene(data, scene)
	var wanted := PackedStringArray(SPLASH_SYMBOLS)
	for symbol: String in FrogShadowGeometry.PHASE_TEXTURES:
		if not wanted.has(symbol):
			wanted.append(symbol)
	for symbol: String in wanted:
		var record: VloImage = effects.images.get(symbol, null)
		if record == null:
			result.diagnostics.append("Options sprite image %s is unavailable" % symbol)
			continue
		result.images[symbol] = record
	var cloud_id: int = data.names.images.index_of(CLOUD_IMAGE) if data.names.images != null else -1
	var cloud: VloImage = result.library.image_for_id(cloud_id, general_bank) if cloud_id >= 0 else null
	if cloud == null:
		result.diagnostics.append("Options sprite image %s is unavailable" % CLOUD_IMAGE)
	else:
		result.images[CLOUD_IMAGE] = cloud
	return result


## The main menu's cloud texture from [param data]'s GENERAL bank alone, or null when it is
## missing; the attract demo draws the menu over the game without loading the options models.
static func cloud_texture(data: AssetCatalog) -> ImageTexture:
	if data == null or not data.is_valid() or data.names.images == null:
		return null
	var general: ThemeBookEntry = data.theme_book_entry(FroggerIds.THEME_GENERAL)
	if general == null:
		return null
	var problems := PackedStringArray()
	var general_bank: VloFile = data.read_texture_bank(general.high_vlo_id, problems)
	if general_bank == null:
		return null
	var bank_library := TextureLibrary.new()
	bank_library.catalog = data
	bank_library.add_bank(general_bank, "general")
	var cloud_id: int = data.names.images.index_of(CLOUD_IMAGE)
	var record: VloImage = bank_library.image_for_id(cloud_id, general_bank) if cloud_id >= 0 else null
	if record == null:
		return null
	return ImageTexture.create_from_image(TextureBuilder.build_unpadded_image(record, bank_library.texture_for(record)))


## The unpadded texture of named image [param symbol] from [member images] as the catalog
## draws it, or null; it is that texture's scale times the record's in-game size.
func image_texture(symbol: String) -> ImageTexture:
	var record: VloImage = images.get(symbol, null)
	if record == null:
		return null
	return ImageTexture.create_from_image(TextureBuilder.build_unpadded_image(record, library.texture_for(record)))


## The options viewport's ambient and parallel lights.
static func options_lighting() -> MapLighting:
	var ambient := MapLight.new()
	ambient.light_type = AMBIENT_LIGHT
	ambient.enabled = true
	ambient.color = _colour(AMBIENT_COLOUR)
	var parallel := MapLight.new()
	parallel.light_type = PARALLEL_LIGHT
	parallel.enabled = true
	parallel.color = _colour(PARALLEL_COLOUR)
	parallel.direction = -PARALLEL_FRAME
	var lights: Array[MapLight] = [ambient, parallel]
	var result := MapLighting.new()
	result.configure(lights)
	return result


## The [enum Kind] of the model called [param file_name] by FrogLord, or -1.
static func kind_of(file_name: String) -> int:
	return FILE_NAMES.find(file_name)


## The model file called [param file_name], or null.
func model_by_name(file_name: String) -> MofFile:
	var kind: int = kind_of(file_name)
	return model_file(kind) if kind >= 0 else null


## The mesh of the model called [param file_name], or null.
func mesh_by_name(file_name: String) -> ModelMesh:
	var kind: int = kind_of(file_name)
	return model_mesh(kind) if kind >= 0 else null


## The model file of [param kind], a [enum Kind].
func model_file(kind: int) -> MofFile:
	return files[kind] if kind < files.size() else null


## The mesh of [param kind], a [enum Kind].
func model_mesh(kind: int) -> ModelMesh:
	return meshes[kind] if kind < meshes.size() else null


func _load_entry_frog(data: AssetCatalog, general: ThemeBookEntry, general_bank: VloFile) -> void:
	var problems := PackedStringArray()
	var entry: MwiEntry = data.find_resource(ENTRY_FROG_NAME)
	var wad: WadFile = data.read_wad(general.high_multiplayer_wad_id) if general.high_multiplayer_wad_id != 0 else null
	var held: bool = false
	if wad != null and entry != null:
		for child: WadFile.Child in wad.children:
			held = held or child.resource_id == entry.index
	if not held:
		diagnostics.append("%s is not in GENERAL's multiplayer WAD; the name-entry frog uses GEN_FROG" % ENTRY_FROG_NAME)
		return
	var bank: VloFile = data.read_texture_bank(data.texture_bank_for_wad(general.high_multiplayer_wad_id), problems)
	var file: MofFile = data.read_model(entry.index, problems)
	if bank == null or file == null or not file.error.is_empty() or file.static_models.is_empty():
		diagnostics.append("%s cannot be decoded (%s); the name-entry frog uses GEN_FROG" % [ENTRY_FROG_NAME, "; ".join(problems)])
		return
	var names: NameBank = data.names.anims.get_sub_bank(ENTRY_FROG_ACTIONS) if data.names.anims != null else null
	if names == null:
		diagnostics.append("FrogLord names no %s actions; the name-entry frog uses GEN_FROG" % ENTRY_FROG_ACTIONS)
		return
	var actions: Dictionary[StringName, int] = {}
	for index: int in names.size():
		actions[StringName(names.name_of(index))] = index
	entry_frog_library = TextureLibrary.new()
	entry_frog_library.catalog = data
	entry_frog_library.add_bank(general_bank, "general")
	entry_frog_library.add_bank(bank, "multiplayer")
	entry_frog_bank = bank
	entry_frog = file
	entry_frog_mesh = ModelMeshLibrary.mesh_for(data, entry.index, entry_frog_library, bank, MESH_FOLDER)
	entry_frog_actions = actions


static func _colour(word: int) -> Color:
	return Color8(word & 0xff, (word >> 8) & 0xff, (word >> 16) & 0xff)

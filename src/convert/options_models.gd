class_name OptionsModels
extends RefCounted
## The options page's models, frog, sprite images and lights from the player's files, the same in
## every language.
##
## The lily, log, volume and static models come from the high-poly options WAD by FrogLord name
## (OPTIONSH.WAD; retail picks the high or _WIN95 twin at the call site, KEY_FACTS KF-110) with the
## options texture bank [code]OPT_VRAM.VLO[/code] first, then the GENERAL bank. The frog is the
## high-detail GEN_FROG.XAR ([TerrainFrogAssets]). The landing splash shows ripples 3-6 and the
## frog's jump shadow the frog shadow images, both resolved as the level effects resolve them
## ([EffectResources]). [member lighting] holds the options viewport's lights (options.c:446-454):
## ambient 0x606060 and one parallel light 0xa0a0c0 whose frame at (0x800, -0x1000, -0x1000) is
## pointed at the origin, so it shines along the origin less that position.

enum Kind { LILY, LOG, MUSIC, EFFECTS, BULLRUSH, STATIC_LILY }

## The WAD holding the options models.
const WAD_NAME: String = "OPTIONSH.WAD"
## FrogLord file name of each [enum Kind].
const FILE_NAMES: PackedStringArray = [
	"OPT_LILLYPAD_BLANK.XMR", "HI_LOG.XMR", "OPT_MUSIC.XMU", "OPT_SFX.XMU", "OPT_STAT_BULLRUSH.XMR",
	"OPT_STAT_LILLY.XMR",
]
## Options viewport ambient light and parallel light colour (MR_CVEC words: red in the low byte).
const AMBIENT_COLOUR: int = 0x606060
const PARALLEL_COLOUR: int = 0xa0a0c0
## The parallel light frame's position; its Z axis points from there at the origin.
const PARALLEL_FRAME: Vector3i = Vector3i(0x800, -0x1000, -0x1000)
## High_score_splash_animlist's ripple images.
const SPLASH_SYMBOLS: PackedStringArray = ["im_ripple_tim3", "im_ripple_tim4", "im_ripple_tim5", "im_ripple_tim6"]
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


## Loads every model, image and light from [param data] without retaining the archive.
static func from_data(data: GameData) -> OptionsModels:
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
	result.library.add_bank(general_bank, "general")
	result.library.add_bank(own, "options")
	var children := PackedInt32Array()
	var wad_file: WadFile = data.read_wad(wad.index)
	if wad_file != null:
		for child: WadFile.Child in wad_file.children:
			children.append(child.resource_id)
	var builder := ModelMeshBuilder.new(result.library, own)
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
		result.meshes.append(builder.build_animated(file))
	result.frog = TerrainFrogAssets.from_data(data)
	if not result.frog.error.is_empty():
		result.error = result.frog.error
		return result
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
	return result


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


## The model file of [param kind], a [enum Kind].
func model_file(kind: int) -> MofFile:
	return files[kind] if kind < files.size() else null


## The mesh of [param kind], a [enum Kind].
func model_mesh(kind: int) -> ModelMesh:
	return meshes[kind] if kind < meshes.size() else null


static func _colour(word: int) -> Color:
	return Color8(word & 0xff, (word >> 8) & 0xff, (word >> 16) & 0xff)

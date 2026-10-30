class_name EffectResources
extends RefCounted
## One level's effect images, particle generator parameters and pop colours, in one place for presentation.
##
## Each effect image symbol resolves to a texture id by the first rule that
## names it, recorded in [member resolutions]:
## [br]- [code]exe[/code]: executable data the port reads. The hilite fire,
## frog slip, frog on-fire and stone-to-gold generators' user data 2 give
## [code]im_frog_smoke1[/code]; the water bubble gives [code]im_wake2[/code];
## both swarms give [code]im_for_swarm[/code]; the hilite dust texture list
## gives [code]im_bison1[/code]-[code]6[/code]; [code]Score_library[/code]
## gives the score, time and extra-life images; both splash animation lists
## give the six ripples ([ExeSplashAnimLists]).
## [br]- [code]name[/code]: FrogLord's image name for the build, the symbol
## without [code]im_[/code] ([code]gen_shadow[/code], [code]tongue_tip[/code],
## [code]frog_shadow0[/code]-[code]2[/code], and any symbol the executable
## did not give).
## [br]- [code]fixed[/code]: the PC glow, texture 1727, which the PC engine
## draws for the pickup and gold frog glows.
## [br]A symbol no rule names is listed in [member missing] with a
## diagnostic. Images are then looked up in the scene's general and theme
## banks and the resident [code]FIXE_VRAM.VLO[/code] and
## [code]GEN_VRAM.VLO[/code] banks; a resolved symbol whose image is in none
## of them is also listed in [member missing], without a diagnostic, since
## most effect images exist only in some themes. Effects degrade; the scene
## never fails because of them.
##
## [member generators] holds the executable's generator records, or the
## frozen C constants when they cannot be located; the generator textures of
## the C constants are then resolved through these symbols.

## Effect image symbols, in the source's order of use.
const SYMBOLS: PackedStringArray = [
	"im_frog_smoke1", "im_gen_shadow", "im_frog_shadow0", "im_frog_shadow1", "im_frog_shadow2", "im_wake2",
	"im_ripple_tim1", "im_ripple_tim2", "im_ripple_tim3", "im_ripple_tim4", "im_ripple_tim5", "im_ripple_tim6",
	"im_bison1", "im_bison2", "im_bison3", "im_bison4", "im_bison5", "im_bison6", "im_tongue_tip", "im_for_swarm",
	"im_score_10", "im_score_25", "im_score_50", "im_score_75", "im_score_100", "im_score_150", "im_score_200",
	"im_score_250", "im_score_500", "im_score_1000", "im_score_5000", "im_time_plus2", "im_time_plus5",
	"im_time_plus10", "im_score_minus500", "im_1up1", "glow_1727",
]
## The PC glow image symbol and its fixed texture id.
const GLOW_SYMBOL: String = "glow_1727"
const GLOW_TEXTURE_ID: int = 1727
## Source score.C Score_library image per entry ("" = NULL).
const SCORE_SYMBOLS: PackedStringArray = [
	"", "im_score_10", "im_score_25", "im_score_50", "im_score_75", "im_score_100", "im_score_150", "im_score_200",
	"im_score_250", "im_score_500", "im_score_1000", "im_score_5000", "", "", "", "im_time_plus2", "im_time_plus5",
	"im_time_plus10", "im_score_minus500", "", "im_1up1", "", "", "",
]
## Generators whose user data 2 is the named image in the frozen C.
const GENERATOR_IMAGES: Dictionary[String, String] = {
	"PGIN_hilite_fire": "im_frog_smoke1",
	"PGIN_frog_slip_effect": "im_frog_smoke1",
	"PGIN_frog_on_fire": "im_frog_smoke1",
	"PGIN_stone_to_gold_frog": "im_frog_smoke1",
	"PGIN_frog_water_bubble": "im_wake2",
	"PGIN_for_swarm": "im_for_swarm",
	"PGIN_for_swarm_multiplayer": "im_for_swarm",
}
## Generator whose texture list holds the bison dust images.
const DUST_GENERATOR: String = "PGIN_hilite_dust"
const DUST_SYMBOLS: PackedStringArray = ["im_bison1", "im_bison2", "im_bison3", "im_bison4", "im_bison5", "im_bison6"]
const RIPPLE_SYMBOLS: PackedStringArray = ["im_ripple_tim1", "im_ripple_tim2", "im_ripple_tim3", "im_ripple_tim4", "im_ripple_tim5", "im_ripple_tim6"]
## Resident sprite banks searched after the scene's own banks.
const RESIDENT_BANKS: PackedStringArray = ["FIXE_VRAM.VLO", "GEN_VRAM.VLO"]

## Texture id by symbol, for every resolved symbol.
var texture_ids: Dictionary[String, int] = {}
## Rule that resolved each symbol: "exe", "name" or "fixed".
var resolutions: Dictionary[String, String] = {}
## Image by symbol, for symbols present in this scene's banks.
var images: Dictionary[String, VloImage] = {}
## Symbols with no usable image in this scene.
var missing: PackedStringArray = PackedStringArray()
## Particle generator records: the executable's, or the frozen C constants.
var generators: ExeParticleGenerators
## Score_library texture id per entry, -1 for none.
var score_texture_ids: PackedInt32Array = PackedInt32Array()
## Resolution problems and fallbacks.
var diagnostics: PackedStringArray = PackedStringArray()


## Resolves the effect resources of [param scene] from [param data].
static func from_scene(data: GameData, scene: MapSceneData) -> EffectResources:
	var bmp: BmpPointers = data.tables.bmp_pointers()
	var result: EffectResources = resolve(ExeParticleGenerators.read(data.exe, bmp), ExeSplashAnimLists.read(data.exe, bmp), data.tables.scores(), bmp, data.tables.names.images)
	var resident := TextureLibrary.new()
	for bank_name: String in RESIDENT_BANKS:
		var entry: MwiEntry = data.find_resource(bank_name) if data.mwi != null else null
		if entry == null:
			result.diagnostics.append("Effect sprite bank %s is missing" % bank_name)
			continue
		var bank: VloFile = data.read_texture_bank(entry.index, result.diagnostics)
		if bank != null:
			resident.add_bank(bank, bank_name)
	var libraries: Array[TextureLibrary] = [scene.library, resident]
	result.attach_images(libraries, scene.preferred)
	return result


## Resolves every symbol from executable [param read_generators], splash
## lists [param splash], score table [param scores] (through [param bmp])
## and FrogLord image names [param names]; any of them may be null.
static func resolve(read_generators: ExeParticleGenerators, splash: ExeSplashAnimLists, scores: ScoreTable, bmp: BmpPointers, names: NameBank) -> EffectResources:
	var result := EffectResources.new()
	var sources: Dictionary[String, PackedInt32Array] = {}
	if read_generators != null:
		result.diagnostics.append_array(read_generators.warnings)
	if read_generators != null and read_generators.from_executable:
		result.generators = read_generators
		for generator_name: String in GENERATOR_IMAGES:
			var record: ParticleGeneratorRecord = read_generators.find(generator_name)
			if record != null and record.texture_kind == ParticleGeneratorRecord.TextureKind.TEXTURE:
				result._add_source(sources, GENERATOR_IMAGES[generator_name], record.texture_ids[0])
		var dust: ParticleGeneratorRecord = read_generators.find(DUST_GENERATOR)
		if dust != null and dust.texture_kind == ParticleGeneratorRecord.TextureKind.TEXTURE_LIST and dust.texture_ids.size() == DUST_SYMBOLS.size():
			for slot: int in DUST_SYMBOLS.size():
				result._add_source(sources, DUST_SYMBOLS[slot], dust.texture_ids[slot])
	else:
		result.generators = ExeParticleGenerators.c_constants()
		result.diagnostics.append("Effects use the frozen C particle generators")
	if splash != null:
		result.diagnostics.append_array(splash.warnings)
		var ripples: PackedInt32Array = splash.ripple_texture_ids()
		for slot: int in ripples.size():
			result._add_source(sources, RIPPLE_SYMBOLS[slot], ripples[slot])
	if scores != null and scores.error.is_empty() and bmp != null:
		for slot: int in scores.texture_pointers.size():
			var pointer: int = scores.texture_pointers[slot]
			var id: int = bmp.texture_id_for_pointer(pointer) if pointer != 0 else -1
			result.score_texture_ids.append(id)
			if slot < SCORE_SYMBOLS.size() and not SCORE_SYMBOLS[slot].is_empty() and id >= 0:
				result._add_source(sources, SCORE_SYMBOLS[slot], id)
	elif scores != null:
		result.diagnostics.append("Effect score images: %s" % scores.error)
	for symbol: String in SYMBOLS:
		if symbol == GLOW_SYMBOL:
			result.texture_ids[symbol] = GLOW_TEXTURE_ID
			result.resolutions[symbol] = "fixed"
			continue
		var named: int = names.index_of(symbol.trim_prefix("im_")) if names != null else -1
		if sources.has(symbol):
			result.texture_ids[symbol] = sources[symbol][0]
			result.resolutions[symbol] = "exe"
			if named >= 0 and named != sources[symbol][0]:
				result.diagnostics.append("Effect image %s is texture %d in the executable but FrogLord names texture %d" % [symbol, sources[symbol][0], named])
		elif named >= 0:
			result.texture_ids[symbol] = named
			result.resolutions[symbol] = "name"
		else:
			result.missing.append(symbol)
			result.diagnostics.append("Effect image %s is not named by the executable or FrogLord's image list" % symbol)
	return result


## Looks up each resolved symbol's image in [param libraries] in order,
## asking [param preferred] first; unresolved or absent symbols are listed in
## [member missing].
func attach_images(libraries: Array[TextureLibrary], preferred: VloFile = null) -> void:
	images.clear()
	missing.clear()
	for symbol: String in SYMBOLS:
		if not texture_ids.has(symbol):
			missing.append(symbol)
			continue
		var image: VloImage = null
		for library: TextureLibrary in libraries:
			if library == null:
				continue
			image = library.image_for_id(texture_ids[symbol], preferred)
			if image != null:
				break
		if image != null:
			images[symbol] = image
		else:
			missing.append(symbol)


## The texture id of [param symbol], or -1.
func texture_id(symbol: String) -> int:
	return texture_ids.get(symbol, -1)


## The texture ids the generator called [param generator_name] draws, in list
## order: the executable's, or the C constant's image symbols resolved here.
func generator_texture_ids(generator_name: String) -> PackedInt32Array:
	var result := PackedInt32Array()
	var record: ParticleGeneratorRecord = generators.find(generator_name) if generators != null else null
	if record == null:
		return result
	if generators.from_executable:
		return record.texture_ids.duplicate()
	for symbol: String in record.texture_symbols:
		result.append(texture_id(symbol))
	return result


func _add_source(sources: Dictionary[String, PackedInt32Array], symbol: String, id: int) -> void:
	if not sources.has(symbol):
		sources[symbol] = PackedInt32Array([id])
		return
	if not sources[symbol].has(id):
		diagnostics.append("Effect image %s has executable sources that disagree (%d and %d); using %d" % [symbol, sources[symbol][0], id, sources[symbol][0]])

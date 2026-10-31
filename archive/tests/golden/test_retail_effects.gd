extends RetailTest
## Retail MOF hilites, particle generator records, effect images, score library and pop colours
## against tests/golden/pc-retail-v3.0e/effect_resources.tsv from tools/make_golden_effect_resources.py.

const GOLDEN: String = "effect_resources.tsv"
## Source ENTITY.H HILITE_TYPE_* names.
const HILITE_TYPES: PackedStringArray = ["COLLISION", "3DSPRITE_SPLASH", "3DSPRITE_WAKE", "PARTICLE_EXHAUST", "PARTICLE_CLOUD", "PARTICLE_SMOKE", "PARTICLE_FIRE", "MESH", "ANIM"]
const SPRITE_TYPES: PackedInt32Array = [1, 2]
## Source FROG_PARTICLE_* names.
const FROG_PARTICLES: PackedStringArray = ["FROG_PARTICLE_SLIDE", "FROG_PARTICLE_WATER_BUBBLE", "FROG_PARTICLE_ON_FIRE"]
## Source score.H SCORE_* identities in Score_library order.
const SCORE_IDS: PackedStringArray = ["SCORE_5", "SCORE_10", "SCORE_25", "SCORE_50", "SCORE_75", "SCORE_100", "SCORE_150", "SCORE_200",
	"SCORE_250", "SCORE_500", "SCORE_1000", "SCORE_5000", "LIGHT_5", "LIGHT_8", "ADD_SUPER_LIGHT", "TIME_MIN", "TIME_MED", "TIME_MAX",
	"REDUCE_SCORE_100", "ADD_TIMER_SPEED", "ADD_EXTRA_LIFE", "ADD_SUPER_TONGUE", "ADD_QUICK_JUMP", "ADD_AUTO_HOP"]
## The level whose banks are searched for each image; ORG1 otherwise.
const IMAGE_LEVELS: Dictionary[String, String] = {
	"im_gen_shadow": "DES1",
	"im_bison1": "DES1", "im_bison2": "DES1", "im_bison3": "DES1", "im_bison4": "DES1", "im_bison5": "DES1", "im_bison6": "DES1",
	"im_for_swarm": "FOR1",
	"glow_1727": "CAV1",
}
const DEFAULT_IMAGE_LEVEL: String = "ORG1"

var _data: GameData
var _generators: ExeParticleGenerators

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))
		_generators = ExeParticleGeneratorsReader.read(_data.exe, _data.tables.bmp_pointers())

func after_all() -> void:
	if _data != null:
		_data.close()

func _golden(kinds: PackedStringArray) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	for row: PackedStringArray in GoldenFiles.rows(GOLDEN):
		if row[0] in kinds:
			result.append(row)
	return result

func _match(label: String, got: Array[PackedStringArray], kinds: PackedStringArray) -> void:
	var differences: PackedStringArray = GoldenFiles.differences(label, got, _golden(kinds))
	for difference: String in differences:
		fail_test(difference)
	assert_eq(differences.size(), 0, "%s rows match" % label)

func _row(values: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for value: Variant in values:
		result.append(str(value))
	return result

func _special(static_index: int, hilite_type: int) -> String:
	if static_index > 0:
		return "unused"
	if hilite_type in SPRITE_TYPES:
		return "sprite"
	if hilite_type < _generators.special_generators.size() and not _generators.special_generators[hilite_type].is_empty():
		return _generators.special_generators[hilite_type]
	return "none" if hilite_type == 0 else "assert"

func _expected_hilites(rows: Array[PackedStringArray], resource_id: int) -> Array[String]:
	var result: Array[String] = []
	for row: PackedStringArray in rows:
		if row[1].to_int() == resource_id and row[3] == "0" and row[10].begins_with("PGIN_hilite_"):
			result.append("%d:%s:%s" % [EffectSetup.kind_for_generator(row[10]), row[4], row[9]])
	return result

func _texts(hilites: Array[ParticleHilite]) -> Array[String]:
	var result: Array[String] = []
	for hilite: ParticleHilite in hilites:
		result.append("%d:%d:%d" % [hilite.kind, hilite.part, hilite.vertex])
	return result

func test_hilites_and_census_match_independent_facts() -> void:
	assert_eq(_data.error, "")
	assert_true(_generators.from_executable, "; ".join(_generators.warnings))
	var problems := PackedStringArray()
	var rows: Array[PackedStringArray] = []
	var borrowed: Array[PackedStringArray] = []
	var counts: Dictionary[int, int] = {}
	var files: Dictionary[int, Dictionary] = {}
	for entry: MwiEntry in _data.model_entries():
		var model: MofFile = _data.read_model(entry.index, problems)
		if model == null:
			continue
		for static_index: int in model.static_models.size():
			for part: MofPart in model.static_models[static_index].parts:
				if part.borrows:
					if part.hilite_count > 0:
						borrowed.append(_row(["hilite_borrowed", entry.index, entry.display_name(), static_index, part.index, part.hilite_count, _data.counterpart_of(entry.index)]))
					continue
				for hilite_index: int in part.hilites.size():
					var hilite: MofPart.Hilite = part.hilites[hilite_index]
					rows.append(_row(["hilite", entry.index, entry.display_name(), static_index, part.index, hilite_index, hilite.type,
						HILITE_TYPES[hilite.type] if hilite.type < HILITE_TYPES.size() else "-", hilite.attach, hilite.index, _special(static_index, hilite.type)]))
					var seen: int = counts.get(hilite.type, 0)
					counts[hilite.type] = seen + 1
					if not files.has(hilite.type):
						files[hilite.type] = {}
					files[hilite.type][entry.display_name()] = true
	assert_eq(problems.size(), 0, "; ".join(problems))
	rows.append_array(borrowed)
	for hilite_type: int in HILITE_TYPES.size():
		var count: int = counts.get(hilite_type, 0)
		rows.append(_row(["hilite_census", hilite_type, HILITE_TYPES[hilite_type], count, files[hilite_type].size() if files.has(hilite_type) else 0]))
	for hilite_type: int in HILITE_TYPES.size():
		var generator: String = _generators.special_generators[hilite_type]
		rows.append(_row(["hilite_generator", hilite_type, HILITE_TYPES[hilite_type], generator if not generator.is_empty() else "-"]))
	_match("hilites", rows, PackedStringArray(["hilite", "hilite_borrowed", "hilite_census", "hilite_generator"]))
	var golden: Array[PackedStringArray] = _golden(PackedStringArray(["hilite"]))
	var particle_models: Dictionary[int, bool] = {}
	for row: PackedStringArray in golden:
		if row[10].begins_with("PGIN_hilite_"):
			particle_models[row[1].to_int()] = true
	for resource_id: int in particle_models:
		var diagnostics := PackedStringArray()
		var hilites: Array[ParticleHilite] = EffectSetup.hilites_of(_data.read_model(resource_id), _generators.special_generators, str(resource_id), diagnostics)
		assert_eq(_texts(hilites), _expected_hilites(golden, resource_id), "model %d particle hilites" % resource_id)
		assert_eq(diagnostics.size(), 0, "; ".join(diagnostics))
	var covered: Dictionary[int, bool] = {}
	var kinds: Dictionary[int, bool] = {}
	var theme_book: ThemeBook = _data.tables.theme_book()
	for code: String in _data.playable_level_codes():
		var level: int = FroggerIds.level_from_code(code)
		var map: MapFile = _data.read_map(_data.map_book_entry(level).map_id(false), problems)
		assert_not_null(map, code)
		if map == null:
			continue
		var setup: EntitySetup = EntitySetup.from_map(map, theme_book, code, _data.map_book_entry(level).map_id(false), _data.version_name, true, _data.names)
		var diagnostics := PackedStringArray()
		EffectSetup.resolve_hilites(_data, level, setup.definitions, diagnostics, _generators, map.general.theme)
		assert_eq(diagnostics.size(), 0, code + ": " + "; ".join(diagnostics))
		for definition: EntityDefinition in setup.definitions:
			var form: FormBookEntry = theme_book.get_form(map.general.theme, definition.form_id)
			var model_id: int = EntityModelSelection.resource_for(_data, level, form, definition) if form != null and not form.has_flag(FormBookEntry.FLAG_NO_MODEL) else -1
			var expected: Array[String] = []
			if particle_models.has(model_id):
				expected = _expected_hilites(golden, model_id)
			assert_eq(_texts(definition.particle_hilites), expected, "%s entity %d model %d" % [code, definition.entity_index, model_id])
			if not expected.is_empty():
				covered[model_id] = true
				for hilite: ParticleHilite in definition.particle_hilites:
					kinds[hilite.kind] = true
	assert_gt(covered.size(), 0, "some level entity uses a particle hilite model")
	assert_eq(kinds.size(), ParticleHilite.Kind.size(), "level entities start exhaust, dust and fire")

func test_generator_records_tables_and_pop_colours_match_independent_facts() -> void:
	assert_eq(_data.error, "")
	assert_true(_generators.from_executable, "; ".join(_generators.warnings))
	assert_eq(_generators.warnings.size(), 0, "; ".join(_generators.warnings))
	var reference: ExeParticleGenerators = ExeParticleGenerators.c_constants()
	var resources: EffectResources = EffectResources.resolve(_generators, ExeSplashAnimListsReader.read(_data.exe, _data.tables.bmp_pointers()), _data.tables.scores(), _data.tables.bmp_pointers(), _data.names.images)
	var rows: Array[PackedStringArray] = []
	for record: ParticleGeneratorRecord in _generators.records:
		var user2: String = ["0", "texture", "texture_list"][record.texture_kind]
		var textures := PackedStringArray()
		for id: int in record.texture_ids:
			textures.append(str(id))
		var differences := PackedStringArray(["absent_from_c"])
		var c: ParticleGeneratorRecord = reference.find(record.name) if not record.name.is_empty() else null
		if c != null:
			differences = record.differences_from(c, resources.texture_ids)
		rows.append(_row(["pgen", record.name if not record.name.is_empty() else "-", GoldenFiles.hex(record.address), GoldenFiles.hex(record.flags),
			record.prim_size, record.max_particles, record.generator_life, record.particle_min_life, record.particle_max_life, record.gravity_16,
			GoldenFiles.hex(record.user_data_1), user2, ",".join(textures) if not textures.is_empty() else "-",
			",".join(differences) if not differences.is_empty() else "-"]))
	for slot: int in FROG_PARTICLES.size():
		var multi: String = _generators.frog_particle_multi[slot]
		rows.append(_row(["frog_particle", slot, FROG_PARTICLES[slot], GoldenFiles.hex(_generators.frog_particle_flags[slot]),
			_generators.frog_particle_single[slot], multi if not multi.is_empty() else "-"]))
	for player: int in _generators.pop_colours.size():
		var colour: int = _generators.pop_colours[player]
		rows.append(_row(["pop_colour", player, "0x%06X" % colour, colour & 255, (colour >> 8) & 255, (colour >> 16) & 255]))
	_match("generators", rows, PackedStringArray(["pgen", "frog_particle", "pop_colour"]))
	for generator_name: String in ["PGIN_hilite_exhaust", "PGIN_hilite_fire"]:
		var record: ParticleGeneratorRecord = _generators.find(generator_name)
		assert_not_null(record, generator_name)
		if record != null:
			assert_eq(resources.generator_texture_ids(generator_name), record.texture_ids, generator_name + " draws the executable's texture")

func test_effect_images_and_score_library_match_independent_facts() -> void:
	assert_eq(_data.error, "")
	var scenes: Dictionary[String, MapSceneData] = {}
	var rows: Array[PackedStringArray] = []
	for golden: PackedStringArray in _golden(PackedStringArray(["image"])):
		var symbol: String = golden[1]
		var code: String = IMAGE_LEVELS.get(symbol, DEFAULT_IMAGE_LEVEL)
		if not scenes.has(code):
			scenes[code] = MapSceneData.load_level(_data, FroggerIds.level_from_code(code))
			assert_eq(scenes[code].error, "", code)
		var effects: EffectResources = scenes[code].effects
		assert_not_null(effects, code)
		if effects == null:
			return
		assert_eq(effects.diagnostics.size(), 0, "; ".join(effects.diagnostics))
		var image: VloImage = effects.images.get(symbol, null)
		assert_not_null(image, "%s is in the %s banks" % [symbol, code])
		assert_false(symbol in effects.missing, symbol)
		var expected_rule: String = "fixed" if golden[3].contains("fixed:") else ("exe" if golden[3].contains("exe:") and not symbol.begins_with("im_frog_shadow") else "name")
		var rule: String = effects.resolutions.get(symbol, "")
		assert_eq(rule, expected_rule, symbol + " resolution")
		rows.append(_row(["image", symbol, effects.texture_id(symbol), image.width if image != null else -1, image.height if image != null else -1, image.blend_mode() if image != null else -1]))
	var want: Array[PackedStringArray] = []
	for golden: PackedStringArray in _golden(PackedStringArray(["image"])):
		want.append(PackedStringArray([golden[0], golden[1], golden[2], golden[4], golden[5], golden[7]]))
	var differences: PackedStringArray = GoldenFiles.differences("images", rows, want)
	for difference: String in differences:
		fail_test(difference)
	assert_eq(differences.size(), 0, "image rows match")
	var effects: EffectResources = scenes[DEFAULT_IMAGE_LEVEL].effects
	var scores: ScoreTable = _data.tables.scores()
	assert_eq(scores.error, "")
	var library: Array[PackedStringArray] = []
	for slot: int in scores.values.size():
		var symbol: String = EffectResources.SCORE_SYMBOLS[slot]
		library.append(_row(["score_library", slot, SCORE_IDS[slot], scores.values[slot], symbol if not symbol.is_empty() else "-",
			effects.score_texture_ids[slot], scores.flags[slot]]))
	_match("score library", library, PackedStringArray(["score_library"]))

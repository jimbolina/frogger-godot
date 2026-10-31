extends RetailTest
## Cave frogger-light payloads, pickup counts, whole-map admission and the firefly callback identity.

const LEVELS: PackedStringArray = ["CAV1", "CAV3", "CAV4"]

var _data: GameData

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func _facts() -> Dictionary[int, PackedStringArray]:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("cave_lights.tsv")
	rows.pop_front()
	var result: Dictionary[int, PackedStringArray] = {}
	for row: PackedStringArray in rows:
		result[row[0].to_int()] = row
	return result

func test_light_payloads_and_pickup_counts_match_independent_facts() -> void:
	assert_eq(_data.error, "")
	var facts: Dictionary[int, PackedStringArray] = _facts()
	assert_eq(facts.size(), 6)
	for resource_id: int in facts:
		var row: PackedStringArray = facts[resource_id]
		var problems := PackedStringArray()
		var map: MapFile = _data.read_map(resource_id, problems)
		assert_not_null(map, row[1])
		if map == null:
			continue
		var counts: Dictionary[String, int] = {"FIREFLY": 0, "CAV_FAT_FIRE_FLY": 0, "GLOWWORM": 0}
		var light := PackedInt64Array()
		for span: MapEntitySpan in map.entities:
			var form: FormBookEntry = _data.tables.theme_book().get_form(map.general.theme, span.form_id)
			assert_not_null(form, row[1])
			if form == null:
				continue
			if form.entity_name == "CAV_FROGGER_LIGHT":
				light.append_array([span.unique_id, span.payload.decode_u32(32), span.payload.decode_u32(36), span.payload.decode_u32(40)])
			elif counts.has(form.entity_name):
				counts[form.entity_name] += 1
			elif form.entity_name == "BONUS_FLY" and span.payload.size() >= 34 and span.payload.decode_u16(32) == 8:
				counts["GLOWWORM"] += 1
		assert_eq(light, PackedInt64Array([row[2].to_int(), row[3].to_int(), row[4].to_int(), row[5].to_int()]), row[1])
		assert_eq([counts["FIREFLY"], counts["CAV_FAT_FIRE_FLY"], counts["GLOWWORM"], map.entities.size()],
			[row[11].to_int(), row[12].to_int(), row[13].to_int(), row[14].to_int()], row[1])
		var setup: EntitySetup = EntitySetup.from_map(map, _data.tables.theme_book(), "cave", resource_id, _data.version_name, true, _data.names)
		var lights: Array[EntityDefinition] = []
		for definition: EntityDefinition in setup.definitions:
			if definition.behavior.kind == EntityBehavior.Kind.CAVE_LIGHT:
				lights.append(definition)
		assert_eq(lights.size(), 1, row[1])
		if lights.size() != 1 or lights[0].cave == null:
			continue
		var cave: EntityCaveDefinition = lights[0].cave
		assert_eq([cave.light_min_squared, cave.light_max_squared, cave.light_die],
			[row[6].to_int(), row[7].to_int(), row[8].to_int()], row[1])
		var environment := EntityEnvironmentState.new()
		EntityCaveLight.initialize(lights[0], EntitySnapshot.new(), environment)
		assert_eq([environment.light_min_squared, environment.light_max_squared], [row[9].to_int(), row[10].to_int()], row[1])

func test_cave_levels_admit_with_their_frogger_light() -> void:
	var facts: Dictionary[int, PackedStringArray] = _facts()
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(_data)
	assert_eq(assets.error, "")
	if not assets.error.is_empty():
		return
	for code: String in LEVELS:
		var number: int = FroggerIds.level_from_code(code)
		var resource_id: int = _data.map_book_entry(number).map_id(false)
		assert_true(facts.has(resource_id), code)
		var problems := PackedStringArray()
		var map: MapFile = _data.read_map(resource_id, problems)
		assert_not_null(map, code)
		if map == null or not facts.has(resource_id):
			continue
		var setup: GameplaySetup = GameplaySetup.from_data(_data, number, map, assets.model, assets.action_lengths)
		assert_eq(setup.error, "", code)
		if setup.definition == null:
			continue
		assert_true(setup.definition.cave_light, code)
		var maximum: int = -1
		for definition: EntityDefinition in setup.definition.entity_collision.entities:
			if definition.behavior.kind == EntityBehavior.Kind.CAVE_LIGHT and definition.cave != null:
				maximum = definition.cave.light_max_squared
		assert_eq(maximum, facts[resource_id][7].to_int(), code)

func test_firefly_form_bonus_callback_resolves_to_its_typed_reaction() -> void:
	var cave: int = FroggerIds.THEMES.find("CAVE")
	var callbacks := PackedInt64Array()
	for form: FormBookEntry in _data.tables.theme_book().get_entry(cave).forms:
		if form.entity_name == "FIREFLY":
			callbacks.append(form.bonus_callback)
	assert_eq(callbacks, PackedInt64Array([0x43D060]))
	assert_eq(FormCallbackCatalog.resolve("pc-retail-v3.0e", 0x43D060, true), FormCallback.Kind.CAV_FIREFLY_SCORE)

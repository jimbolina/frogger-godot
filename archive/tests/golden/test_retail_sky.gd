extends RetailTest
## Sky payload decoding, script registers, models, primitives, callbacks, FORM grids and SKY1–SKY4 admission.

const LEVELS: PackedStringArray = ["SKY1", "SKY2", "SKY3", "SKY4"]
const ENTITY_ROWS: int = 599
const ADMISSION_DIAGNOSTICS: PackedStringArray = ["unknown_behavior", "invalid_payload", "incompatible_callback"]
const COUNTED_KINDS: Array[EntityBehavior.Kind] = [EntityBehavior.Kind.TRIGGER, EntityBehavior.Kind.MOVING_PLATFORM, EntityBehavior.Kind.PATH_FOLLOWER]

var _data: GameData

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func _fields(row: PackedStringArray) -> Dictionary[String, String]:
	var result: Dictionary[String, String] = {}
	for pair: String in row[6].split(" ", false):
		var split: int = pair.find("=")
		result[pair.substr(0, split)] = pair.substr(split + 1)
	return result

func _ints(text: String) -> PackedInt32Array:
	var result := PackedInt32Array()
	if text == "-":
		return result
	for value: String in text.split(",", false):
		result.append(value.to_int())
	return result

func _vector(text: String) -> Vector3i:
	var values: PackedInt32Array = _ints(text)
	return Vector3i(values[0], values[1], values[2])

func _records(kind: String) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	for row: PackedStringArray in GoldenFiles.rows("sky_entities.tsv"):
		if row[0] == kind:
			result.append(row)
	return result

## Maps each SKY1–SKY4 map resource to its level number and detail.
func _maps() -> Dictionary[int, Vector2i]:
	var result: Dictionary[int, Vector2i] = {}
	for code: String in LEVELS:
		var level: int = FroggerIds.level_from_code(code)
		for low: int in 2:
			result[_data.map_book_entry(level).map_id(low == 1)] = Vector2i(level, low)
	return result

func _definition(setup: EntitySetup, entity_index: int) -> EntityDefinition:
	for candidate: EntityDefinition in setup.definitions:
		if candidate.entity_index == entity_index:
			return candidate
	return null

func test_sky_payloads_match_independent_facts() -> void:
	assert_eq(_data.error, "")
	var maps: Dictionary[int, Vector2i] = _maps()
	var setups: Dictionary[int, EntitySetup] = {}
	var payloads: Dictionary[int, MapFile] = {}
	var theme_book: ThemeBook = _data.tables.theme_book()
	var bank: NameBank = _data.names.scripts
	var checked: int = 0
	for row: PackedStringArray in _records("entity"):
		var resource_id: int = row[1].to_int()
		var label: String = "%s entity %s" % [row[2], row[3]]
		assert_true(maps.has(resource_id), label)
		if not payloads.has(resource_id):
			var map: MapFile = _data.read_map(resource_id, PackedStringArray())
			assert_not_null(map, label)
			if map == null:
				return
			payloads[resource_id] = map
			setups[resource_id] = EntitySetup.from_map(map, theme_book, "sky", resource_id, _data.version.internal_name, true, _data.names)
		var definition: EntityDefinition = _definition(setups[resource_id], row[3].to_int())
		assert_not_null(definition, label)
		if definition == null:
			continue
		var facts: Dictionary[String, String] = _fields(row)
		var map: MapFile = payloads[resource_id]
		var payload: PackedByteArray = map.entities[definition.entity_index].payload
		assert_eq(definition.entity_name, row[5], label)
		assert_eq(definition.unique_id, row[4].to_int(), label)
		assert_eq(definition.form_name, facts["form"], label)
		assert_eq(definition.form_id, facts["form_id"].to_int(), label)
		assert_eq(definition.form_grid_id, facts["form_grid_id"].to_int(), label)
		assert_eq(definition.flags, facts["entity_flags"].to_int(), label)
		assert_eq(definition.form_flags, facts["form_flags"].to_int(), label)
		assert_eq(definition.script_id, facts["script"].to_int(), label)
		assert_eq(payload.size(), facts["payload_bytes"].to_int(), label + " payload bytes")
		var form: FormBookEntry = theme_book.get_form(map.general.theme, definition.form_id)
		assert_not_null(form, label)
		if form != null:
			assert_eq([form.death_type, form.death_type_name()], [facts["death"].to_int(), facts["death_name"]], label + " death")
		if facts.has("path_id"):
			assert_eq(definition.behavior.layout, EntityBehavior.Layout.PATH, label)
			assert_not_null(definition.path_definition, label)
			if definition.path_definition != null:
				assert_eq(definition.path_definition.path_index, facts["path_id"].to_int(), label)
				assert_eq([definition.path_start.segment_index, definition.path_start.distance, definition.path_start.flags & 14, definition.path_start.speed],
					[facts["segment_id"].to_int(), facts["segment_dist"].to_int(), facts["motion"].to_int(), facts["speed"].to_int()], label + " PATH_INFO")
				assert_eq(bool(definition.path_start.flags & PathStart.ACTIVE), not bool(definition.flags & EntityDefinition.NO_MOVEMENT), label + " runner active")
		else:
			assert_eq(definition.matrix12, _ints(facts["matrix"]), label + " matrix")
		if facts.has("initial_movement"):
			assert_not_null(definition.volcano, label)
			if definition.volcano != null:
				assert_eq(definition.volcano.initial_movement, facts["initial_movement"].to_int(), label + " initial movement")
				assert_eq(definition.volcano.play_chain_sound, facts["chain_sound"] == "1", label + " chain sound")
		if facts.has("trigger_type"):
			assert_eq(definition.behavior.kind, EntityBehavior.Kind.TRIGGER, label)
			assert_not_null(definition.trigger, label)
			if definition.trigger != null:
				assert_eq(definition.trigger.trigger_type, facts["trigger_type"].to_int(), label + " trigger type")
				assert_eq(definition.trigger.target_ids, _ints(facts["trigger_ids"]), label + " trigger ids")
		if facts["script"].to_int() != 0:
			var scripts: EntityScriptSetup = EntityScriptSetup.from_tables(_data.tables.scripts(), bank, definition.script_id, definition.behavior, payload)
			assert_eq(scripts.error, "", label + " script")
			if scripts.definition != null:
				assert_eq(bank.name_of(scripts.definition.root_id), facts["root_script"], label + " root script")
				assert_eq(scripts.definition.payload_registers, _ints(facts["registers"]), label + " registers")
				if facts["register_offset"].to_int() >= 0:
					assert_eq(scripts.definition.payload_offset, facts["register_offset"].to_int(), label + " register offset")
		checked += 1
	assert_eq(checked, ENTITY_ROWS, "Sky-form entities across SKY1–SKY4 at both detail levels")

func test_sky_models_primitives_and_callbacks_match_independent_facts() -> void:
	assert_eq(_data.error, "")
	var resources: int = 0
	for row: PackedStringArray in _records("actions"):
		var label: String = "%s actions" % row[2]
		var model: MofFile = _data.read_model(row[1].to_int(), PackedStringArray())
		assert_not_null(model, label)
		if model == null:
			continue
		assert_eq(GameplaySetup.model_action_lengths(model), _ints(_fields(row)["lengths"]), label)
		resources += 1
	assert_eq(resources, 18, "animated and flipbook Sky model resources at both detail levels")
	var primitives: int = 0
	for row: PackedStringArray in _records("collprim"):
		var facts: Dictionary[String, String] = _fields(row)
		var label: String = "%s primitive %s" % [row[2], facts["primitive"]]
		var model: MofFile = _data.read_model(row[1].to_int(), PackedStringArray())
		assert_not_null(model, label)
		if model == null:
			continue
		var part: MofPart = model.static_models[0].parts[facts["part"].to_int()]
		var index: int = facts["primitive"].to_int()
		assert_lt(index, part.collprims.size(), label)
		if index >= part.collprims.size():
			continue
		var primitive: MofPart.Collprim = part.collprims[index]
		assert_eq([primitive.type, primitive.flags, primitive.offset, primitive.radius_squared, primitive.size, primitive.user, primitive.matrix_index],
			[facts["type"].to_int(), facts["flags"].to_int(), _vector(facts["offset"]), facts["radius_squared"].to_int(), _vector(facts["extents"]), facts["user"].to_int(), facts["matrix_index"].to_int()], label)
		primitives += 1
	assert_eq(primitives, 2, "magical balloon primitives at both detail levels")
	var theme_book: ThemeBook = _data.tables.theme_book()
	var bank: NameBank = _data.names.scripts
	var callbacks: int = 0
	for row: PackedStringArray in _records("callback"):
		var facts: Dictionary[String, String] = _fields(row)
		var address: int = facts["address"].hex_to_int()
		var form: FormBookEntry = theme_book.get_form(8, row[3].to_int())
		assert_not_null(form, facts["form"])
		if form == null:
			continue
		assert_eq(form.form_name, facts["form"])
		assert_eq(form.entity_name, row[5], facts["form"])
		assert_eq([form.collision_callback, form.bonus_callback, form.script_id], [address, facts["bonus"].hex_to_int(), facts["script"].to_int()], facts["form"])
		if form.script_id != 0:
			assert_eq(bank.name_of(form.script_id), facts["root_script"], facts["form"])
		var kind: FormCallback.Kind = FormCallbackCatalog.resolve(_data.version.internal_name, address)
		assert_eq(kind, FormCallback.Kind.TRIGGER if facts["callback"] == "TriggerEntityCallback" else FormCallback.Kind.NONE, facts["form"])
		if address != 0:
			var callback_name: String = FormCallbackCatalog.NAMES.get(address, "")
			assert_eq(callback_name, facts["callback"], facts["form"])
		callbacks += 1
	assert_eq(callbacks, 28, "every Sky form")

func test_sky_levels_admit_through_whole_map_setup() -> void:
	assert_eq(_data.error, "")
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(_data)
	assert_eq(assets.error, "")
	if not assets.error.is_empty():
		return
	var grids: Dictionary[String, PackedStringArray] = {}
	for row: PackedStringArray in _records("form_grid"):
		grids["%s:%s" % [row[1], _fields(row)["form_grid_id"]]] = row
	var census: Dictionary[int, Dictionary] = {}
	for row: PackedStringArray in _records("census"):
		var resource_id: int = row[1].to_int()
		if not census.has(resource_id):
			census[resource_id] = {}
		var kind: EntityBehavior.Kind = EntityBehaviorCatalog.resolve(row[5]).kind
		if kind in COUNTED_KINDS:
			var counts: Dictionary = census[resource_id]
			var previous: int = counts.get(kind, 0)
			counts[kind] = previous + _fields(row)["count"].to_int()
	var theme_book: ThemeBook = _data.tables.theme_book()
	var forms_checked: int = 0
	for code: String in LEVELS:
		var level: int = FroggerIds.level_from_code(code)
		assert_true(GameplaySetup.supports_level(level), "%s is a whole-map level; add it to GameplaySetup.LEVEL_CODES" % code)
		if not GameplaySetup.supports_level(level):
			continue
		var resource_id: int = _data.map_book_entry(level).map_id(false)
		var map: MapFile = _data.read_map(resource_id, PackedStringArray())
		assert_not_null(map, code)
		if map == null:
			continue
		var entities: EntitySetup = EntitySetup.from_map(map, theme_book, code, resource_id, _data.version.internal_name, true, _data.names)
		assert_eq(entities.error, "", code)
		for diagnostic: EntitySetupDiagnostic in entities.diagnostics:
			assert_false(diagnostic.code in ADMISSION_DIAGNOSTICS, "%s entity %d: %s %s" % [code, diagnostic.entity_index, diagnostic.code, diagnostic.message])
		assert_eq(entities.definitions.size(), map.entities.size(), "%s entity setup omits no entity" % code)
		var setup: GameplaySetup = GameplaySetup.from_data(_data, level, map, assets.model, assets.action_lengths)
		assert_eq(setup.error, "", "%s whole-map setup" % code)
		if setup.definition == null:
			continue
		var collision: EntityCollisionDefinition = setup.definition.entity_collision
		assert_eq(collision.entities.size(), map.entities.size(), "%s admits every entity" % code)
		var counts: Dictionary = {}
		for definition: EntityDefinition in collision.entities:
			var kind: EntityBehavior.Kind = definition.behavior.kind
			if kind in COUNTED_KINDS:
				var previous: int = counts.get(kind, 0)
				counts[kind] = previous + 1
		var expected: Dictionary = census.get(resource_id, {})
		for kind: EntityBehavior.Kind in COUNTED_KINDS:
			var want: int = expected.get(kind, 0)
			var got: int = counts.get(kind, 0)
			assert_eq(got, want, "%s %s" % [code, EntityBehavior.Kind.keys()[kind]])
		for contact: FormContactDefinition in collision.contacts:
			if not contact.form_name.begins_with("SKY_"):
				continue
			var key: String = "%d:%d" % [resource_id, contact.form_grid_id]
			var label: String = "%s %s entity %d" % [code, contact.form_name, contact.entity_index]
			assert_true(grids.has(key), label)
			if not grids.has(key):
				continue
			var facts: Dictionary[String, String] = _fields(grids[key])
			if facts["form_datas"].to_int() > 0:
				assert_eq([contact.dimensions, contact.offsets, contact.height, contact.max_y, contact.has_form_data],
					[Vector2i(facts["form_xnum"].to_int(), facts["form_znum"].to_int()), Vector2i(facts["form_xofs"].to_int(), facts["form_zofs"].to_int()),
					facts["height"].to_int(), facts["runtime_max_y"].to_int(), true], label + " form")
				assert_eq(contact.grid_flags, _ints(facts["grid_flags"]), label + " squares")
			else:
				assert_false(contact.has_form_data, label + " has no FORM_DATA")
			assert_eq(contact.callback_kind, FormCallback.Kind.TRIGGER if contact.form_name == "SKY_FROGGERS_MAGICAL_POPPING_BALLOON" else FormCallback.Kind.NONE, label + " callback")
			forms_checked += 1
	assert_gt(forms_checked, 0, "SKY1–SKY4 Sky-form contacts")

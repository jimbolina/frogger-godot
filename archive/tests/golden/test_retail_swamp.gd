extends RetailTest
## Swamp payload decoding, script registers, models, primitives, callbacks, FORM squares and SWP1–SWP5 admission.

const LEVELS: PackedStringArray = ["SWP1", "SWP2", "SWP3", "SWP4", "SWP5"]
const PATH_KINDS: Array[EntityBehavior.Kind] = [EntityBehavior.Kind.SWP_SLUG, EntityBehavior.Kind.NUCLEAR_BARREL]
const ENTITY_ROWS: int = 364

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
	for row: PackedStringArray in GoldenFiles.rows("swamp_entities.tsv"):
		if row[0] == kind:
			result.append(row)
	return result

## Maps each SWP1–SWP5 map resource to its level number and detail.
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

func test_swamp_payloads_match_independent_facts() -> void:
	assert_eq(_data.error, "")
	var maps: Dictionary[int, Vector2i] = _maps()
	var setups: Dictionary[int, EntitySetup] = {}
	var payloads: Dictionary[int, MapFile] = {}
	var theme_book: ThemeBook = _data.tables.theme_book()
	var bank: NameBank = _data.tables.names.scripts
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
			setups[resource_id] = EntitySetup.from_map(map, theme_book, "swamp", resource_id, _data.version.internal_name, true, _data.tables.names)
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
		var kind: EntityBehavior.Kind = definition.behavior.kind
		if kind in PATH_KINDS:
			assert_eq(definition.path_definition.path_index, facts["path_id"].to_int(), label)
			assert_eq([definition.path_start.segment_index, definition.path_start.distance, definition.path_start.flags & 14, definition.path_start.speed],
				[facts["segment_id"].to_int(), facts["segment_dist"].to_int(), facts["motion"].to_int(), facts["speed"].to_int()], label)
		elif kind == EntityBehavior.Kind.SWP_STAT_WEIR:
			assert_eq(definition.matrix12, _ints(facts["weir_matrix"]), label + " weir matrix")
			assert_eq(EntitySetup.weir_matrix(_ints(facts["matrix"])), _ints(facts["weir_matrix"]), label + " weir override")
		else:
			assert_eq(definition.matrix12, _ints(facts["matrix"]), label + " matrix")
		if facts["script"].to_int() != 0:
			var scripts: EntityScriptSetup = EntityScriptSetup.from_tables(_data.tables.scripts(), bank, definition.script_id, definition.behavior, payload)
			assert_eq(scripts.error, "", label + " script")
			if scripts.definition != null:
				assert_eq(bank.get_name(scripts.definition.root_id), facts["root_script"], label + " root script")
				assert_eq(scripts.definition.payload_registers, _ints(facts["registers"]), label + " registers")
				if facts["register_offset"].to_int() >= 0:
					assert_eq(scripts.definition.payload_offset, facts["register_offset"].to_int(), label + " register offset")
		var swamp: EntitySwampDefinition = definition.swamp
		match kind:
			EntityBehavior.Kind.SWP_SQUIRT:
				assert_not_null(swamp, label)
				if swamp != null:
					assert_eq([swamp.time_delay, swamp.drop_time, swamp.target], [facts["time_delay"].to_int(), facts["drop_time"].to_int(), _vector(facts["target"])], label + " squirt")
			EntityBehavior.Kind.SWP_CRUSHER, EntityBehavior.Kind.SWP_PRESS:
				assert_not_null(swamp, label)
				if swamp != null:
					assert_eq([swamp.speed, swamp.distance, swamp.direction, swamp.delay],
						[facts["speed"].to_int(), facts["distance"].to_int(), facts["direction"].to_int(), facts["delay"].to_int()], label + " motion")
			EntityBehavior.Kind.SWP_RAT:
				assert_not_null(swamp, label)
				if swamp != null:
					var xs: PackedInt32Array = _ints(facts["target_x"])
					var ys: PackedInt32Array = _ints(facts["target_y"])
					var zs: PackedInt32Array = _ints(facts["target_z"])
					var targets: Array[Vector3i] = []
					for index: int in xs.size():
						targets.append(Vector3i(xs[index], ys[index], zs[index]))
					assert_eq(swamp.rat_speed, facts["speed"].to_int(), label + " speed")
					assert_eq(swamp.rat_targets, targets, label + " targets")
					assert_eq([swamp.run_speed, swamp.jump1_time, swamp.jump1_sine_step, swamp.run_time, swamp.jump2_time, swamp.jump2_sine_step],
						[facts["run_speed"].to_int(), facts["jump1_time"].to_int(), facts["jump1_sine_step"].to_int(), facts["run_time"].to_int(), facts["jump2_time"].to_int(), facts["jump2_sine_step"].to_int()], label + " timing")
					assert_eq([swamp.jump1_velocity_4, swamp.run_velocity_4, swamp.jump2_velocity_4],
						[_vector(facts["jump1_velocity_4"]), _vector(facts["run_velocity_4"]), _vector(facts["jump2_velocity_4"])], label + " velocities")
			EntityBehavior.Kind.SWP_SLUG:
				assert_not_null(swamp, label)
				if swamp != null:
					assert_eq(swamp.motion_type, facts["motion_type"].to_int(), label + " motion type")
		checked += 1
	assert_eq(checked, ENTITY_ROWS, "Swamp custom entities across SWP1–SWP5 at both detail levels")

func test_swamp_models_primitives_and_callbacks_match_independent_facts() -> void:
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
	assert_eq(resources, 4, "rat and slug model resources at both detail levels")
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
	assert_eq(primitives, 6, "crusher, crusher2 and press primitives at both detail levels")
	var theme_book: ThemeBook = _data.tables.theme_book()
	var callbacks: int = 0
	for row: PackedStringArray in _records("callback"):
		var facts: Dictionary[String, String] = _fields(row)
		var address: int = facts["address"].hex_to_int()
		var found: bool = false
		for form: FormBookEntry in theme_book.all_forms:
			if form.form_name == facts["form"]:
				found = true
				assert_eq(form.collision_callback, address, facts["form"])
		assert_true(found, facts["form"])
		var kind: FormCallback.Kind = FormCallbackCatalog.resolve(_data.version.internal_name, address) if address != 0 else FormCallback.Kind.NONE
		assert_eq(kind, FormCallback.Kind.CRUSHER_BOUNCE_BACK if facts["callback"] == "SwpCrusherCallback" else FormCallback.Kind.NONE, facts["form"])
		if address != 0:
			var callback_name: String = FormCallbackCatalog.NAMES.get(address, "")
			assert_eq(callback_name, facts["callback"], facts["form"])
		callbacks += 1
	assert_eq(callbacks, 3, "crusher, crusher2 and press callbacks")

func test_swamp_levels_admit_through_whole_map_setup() -> void:
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
		if kind in EntityBehavior.SWAMP_KINDS:
			var counts: Dictionary = census[resource_id]
			var previous: int = counts.get(kind, 0)
			counts[kind] = previous + _fields(row)["count"].to_int()
	var forms_checked: int = 0
	for code: String in LEVELS:
		var level: int = FroggerIds.level_from_code(code)
		assert_true(GameplaySetup.supports_level(level), "%s is a whole-map level" % code)
		var resource_id: int = _data.map_book_entry(level).map_id(false)
		var map: MapFile = _data.read_map(resource_id, PackedStringArray())
		assert_not_null(map, code)
		if map == null:
			continue
		var setup: GameplaySetup = GameplaySetup.from_data(_data, level, map, assets.model, assets.action_lengths)
		assert_eq(setup.error, "", "%s whole-map setup" % code)
		if setup.definition == null:
			continue
		var collision: EntityCollisionDefinition = setup.definition.entity_collision
		assert_eq(collision.entities.size(), map.entities.size(), "%s admits every entity" % code)
		assert_true(collision.lifecycle.source_allocation, code)
		var counts: Dictionary = {}
		for definition: EntityDefinition in collision.entities:
			var kind: EntityBehavior.Kind = definition.behavior.kind
			if kind in EntityBehavior.SWAMP_KINDS:
				var previous: int = counts.get(kind, 0)
				counts[kind] = previous + 1
		var expected: Dictionary = census.get(resource_id, {})
		for kind: EntityBehavior.Kind in EntityBehavior.SWAMP_KINDS:
			var want: int = expected.get(kind, 0)
			var got: int = counts.get(kind, 0)
			assert_eq(got, want, "%s %s" % [code, EntityBehavior.Kind.keys()[kind]])
		for contact: FormContactDefinition in collision.contacts:
			var key: String = "%d:%d" % [resource_id, contact.form_grid_id]
			if contact.form_name not in ["SWP_CRUSHER", "SWP_CRUSHER2", "SWP_PRESS"]:
				continue
			var label: String = "%s %s entity %d" % [code, contact.form_name, contact.entity_index]
			assert_true(grids.has(key), label)
			if not grids.has(key):
				continue
			var facts: Dictionary[String, String] = _fields(grids[key])
			assert_eq([contact.dimensions, contact.offsets, contact.height, contact.max_y, contact.has_form_data],
				[Vector2i(facts["form_xnum"].to_int(), facts["form_znum"].to_int()), Vector2i(facts["form_xofs"].to_int(), facts["form_zofs"].to_int()),
				facts["height"].to_int(), facts["runtime_max_y"].to_int(), facts["form_datas"].to_int() > 0], label + " form")
			assert_eq(contact.grid_flags, _ints(facts["grid_flags"]), label + " squares")
			assert_eq(contact.callback_kind, FormCallback.Kind.NONE if contact.form_name == "SWP_PRESS" else FormCallback.Kind.CRUSHER_BOUNCE_BACK, label + " callback")
			assert_eq(contact.primitives.size(), 1, label + " collision primitive")
			forms_checked += 1
	assert_eq(forms_checked, 76, "SWP3 and SWP5 crusher and press contacts")

extends RetailTest
## Jungle payload decoding, plinth models, action lengths, the crusher callback and JUN1 whole-map admission.

const LEVELS: PackedStringArray = ["JUN1", "JUN2"]
const CALLBACK_ADDRESS: int = 0x4241c0
const JUN1_COUNTS: Dictionary[EntityBehavior.Kind, int] = {
	EntityBehavior.Kind.JUN_PLANT: 8,
	EntityBehavior.Kind.JUN_ROPE_BRIDGE: 1,
	EntityBehavior.Kind.JUN_HIPPO: 5,
	EntityBehavior.Kind.JUN_SCORPION: 2,
	EntityBehavior.Kind.JUN_BOUNCY_MUSHROOM: 1,
	EntityBehavior.Kind.JUN_OUTRO: 1,
	EntityBehavior.Kind.JUN_OUTRO_DOOR: 2,
	EntityBehavior.Kind.JUN_PLINTH: 8,
	EntityBehavior.Kind.JUN_GOLD_FROG: 9,
	EntityBehavior.Kind.JUN_STONE_FROG: 8,
}

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

func _records(kind: String) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	for row: PackedStringArray in GoldenFiles.rows("jungle_entities.tsv"):
		if row[0] == kind:
			result.append(row)
	return result

## Maps each JUN1/JUN2 map resource to its level number and detail.
func _maps() -> Dictionary[int, Vector2i]:
	var result: Dictionary[int, Vector2i] = {}
	for code: String in LEVELS:
		var level: int = FroggerIds.level_from_code(code)
		for low: int in 2:
			result[_data.map_book_entry(level).map_id(low == 1)] = Vector2i(level, low)
	return result

func _definitions(maps: Dictionary[int, Vector2i]) -> Dictionary[int, EntitySetup]:
	var result: Dictionary[int, EntitySetup] = {}
	for resource_id: int in maps:
		var map: MapFile = _data.read_map(resource_id, PackedStringArray())
		assert_not_null(map, "map %d" % resource_id)
		if map != null:
			result[resource_id] = EntitySetup.from_map(map, _data.tables.theme_book(), "jungle", resource_id, _data.version_name, true, _data.names)
	return result

func _definition(setup: EntitySetup, entity_index: int) -> EntityDefinition:
	for candidate: EntityDefinition in setup.definitions:
		if candidate.entity_index == entity_index:
			return candidate
	return null

func test_jungle_payloads_match_independent_facts() -> void:
	assert_eq(_data.error, "")
	var maps: Dictionary[int, Vector2i] = _maps()
	var setups: Dictionary[int, EntitySetup] = _definitions(maps)
	var payloads: Dictionary[int, MapFile] = {}
	var theme_book: ThemeBook = _data.tables.theme_book()
	var bank: NameBank = _data.names.scripts
	var checked: int = 0
	for row: PackedStringArray in _records("entity"):
		var resource_id: int = row[1].to_int()
		var label: String = "%s entity %s" % [row[2], row[3]]
		assert_true(setups.has(resource_id), label)
		if not setups.has(resource_id):
			continue
		if not payloads.has(resource_id):
			payloads[resource_id] = _data.read_map(resource_id, PackedStringArray())
		var definition: EntityDefinition = _definition(setups[resource_id], row[3].to_int())
		assert_not_null(definition, label)
		if definition == null:
			continue
		var facts: Dictionary[String, String] = _fields(row)
		var map: MapFile = payloads[resource_id]
		assert_eq(definition.entity_name, row[5], label)
		assert_eq(definition.unique_id, row[4].to_int(), label)
		assert_eq(definition.form_name, facts["form"], label)
		assert_eq(definition.form_id, facts["form_id"].to_int(), label)
		assert_eq(definition.form_grid_id, facts["form_grid_id"].to_int(), label)
		assert_eq(definition.flags, facts["entity_flags"].to_int(), label)
		assert_eq(definition.form_flags, facts["form_flags"].to_int(), label)
		assert_eq(definition.script_id, facts["script"].to_int(), label)
		assert_eq(map.entities[definition.entity_index].payload.size(), facts["payload_bytes"].to_int(), label + " payload bytes")
		var form: FormBookEntry = theme_book.get_form(map.general.theme, definition.form_id)
		assert_not_null(form, label)
		if form != null:
			assert_eq([form.death_type, form.death_type_name()], [facts["death"].to_int(), facts["death_name"]], label + " death")
		var kind: EntityBehavior.Kind = definition.behavior.kind
		if kind in EntityBehavior.JUNGLE_PATH_KINDS:
			assert_eq(definition.path_definition.path_index, facts["path_id"].to_int(), label)
			assert_eq([definition.path_start.segment_index, definition.path_start.distance, definition.path_start.flags & 14, definition.path_start.speed],
				[facts["segment_id"].to_int(), facts["segment_dist"].to_int(), facts["motion"].to_int(), facts["speed"].to_int()], label)
		else:
			assert_eq(definition.matrix12, _ints(facts["matrix"]), label + " matrix")
		var jungle: EntityJungleDefinition = definition.jungle
		match kind:
			EntityBehavior.Kind.JUN_PLANT:
				assert_not_null(jungle, label)
				if jungle != null:
					assert_eq([jungle.snap_time, jungle.snap_delay], [facts["snap_time"].to_int(), facts["snap_delay"].to_int()], label + " snap")
			EntityBehavior.Kind.JUN_ROPE_BRIDGE:
				assert_not_null(jungle, label)
				if jungle != null:
					assert_eq([jungle.fall_delay, jungle.hops_before], [facts["fall_delay"].to_int(), facts["hops_before"].to_int()], label + " bridge")
			EntityBehavior.Kind.JUN_HIPPO:
				var scripts: EntityScriptSetup = EntityScriptSetup.from_tables(_data.tables.scripts(), bank, definition.script_id, definition.behavior, map.entities[definition.entity_index].payload)
				assert_eq(scripts.error, "", label)
				if scripts.definition != null:
					assert_eq(scripts.definition.payload_registers, PackedInt32Array([facts["dive_delay"].to_int(), facts["rise_delay"].to_int(), facts["turtle_type"].to_int()]), label + " registers")
					assert_eq(bank.name_of(scripts.definition.root_id), facts["root_script"], label + " root script")
			EntityBehavior.Kind.JUN_OUTRO:
				assert_not_null(jungle, label)
				if jungle != null:
					var xs: PackedInt32Array = _ints(facts["target_x"])
					var ys: PackedInt32Array = _ints(facts["target_y"])
					var zs: PackedInt32Array = _ints(facts["target_z"])
					var targets: Array[Vector3i] = []
					for index: int in xs.size():
						targets.append(Vector3i(xs[index], ys[index], zs[index]))
					assert_eq(jungle.outro_targets, targets, label + " targets")
					var times := PackedInt64Array()
					for value: int in _ints(facts["target_time"]):
						times.append(value)
					assert_eq(jungle.outro_times, times, label + " times")
			EntityBehavior.Kind.JUN_PLINTH, EntityBehavior.Kind.JUN_GOLD_FROG, EntityBehavior.Kind.JUN_STONE_FROG:
				assert_not_null(jungle, label)
				if jungle != null:
					assert_eq(jungle.op_id, facts["op_id"].to_int(), label + " op id")
		checked += 1
	assert_eq(checked, 166, "JUN1/JUN2 Jungle entities at both detail levels")
	var plinths: int = 0
	for row: PackedStringArray in _records("plinth"):
		var resource_id: int = row[1].to_int()
		var label: String = "%s plinth %s" % [row[2], row[3]]
		var facts: Dictionary[String, String] = _fields(row)
		var definition: EntityDefinition = _definition(setups[resource_id], row[3].to_int())
		assert_not_null(definition, label)
		if definition == null or definition.jungle == null:
			continue
		var level: Vector2i = maps[resource_id]
		var book: MapBookEntry = _data.map_book_entry(level.x)
		assert_eq(book.wad_id(level.y == 1), facts["wad"].to_int(), label + " wad")
		assert_eq(EntityModelSelection.PLINTH_WAD_SLOTS[definition.jungle.op_id], facts["slot"].to_int(), label + " slot")
		var form: FormBookEntry = theme_book.get_form(payloads[resource_id].general.theme, definition.form_id)
		assert_eq(EntityModelSelection.resource_for(_data, level.x, form, definition, level.y == 1), facts["model_resource"].to_int(), label + " model")
		plinths += 1
	assert_eq(plinths, 32, "plinths across JUN1/JUN2 detail levels")
	var resources: int = 0
	for row: PackedStringArray in _records("actions"):
		var label: String = "%s actions" % row[2]
		var model: MofFile = _data.read_model(row[1].to_int(), PackedStringArray())
		assert_not_null(model, label)
		if model == null:
			continue
		assert_eq(GameplaySetup.model_action_lengths(model), _ints(_fields(row)["lengths"]), label)
		resources += 1
	assert_eq(resources, 12, "Jungle model resources with action facts")
	var callbacks: Array[PackedStringArray] = _records("callback")
	assert_eq(callbacks.size(), 1)
	for row: PackedStringArray in callbacks:
		var facts: Dictionary[String, String] = _fields(row)
		var address: int = facts["address"].hex_to_int()
		assert_eq(address, CALLBACK_ADDRESS)
		var name: String = FormCallbackCatalog.NAMES.get(address, "")
		assert_eq(name, row[5])
		assert_eq(FormCallbackCatalog.resolve(_data.version_name, address), FormCallback.Kind.CRUSHER_BOUNCE_BACK)
		var forms := PackedStringArray()
		for form: FormBookEntry in theme_book.all_forms:
			if form.collision_callback == address:
				forms.append(form.form_name)
		forms.sort()
		assert_eq(",".join(forms), facts["forms"], "forms using %s" % row[5])

func test_jun1_admits_through_whole_map_setup() -> void:
	assert_eq(_data.error, "")
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(_data)
	assert_eq(assets.error, "")
	if not assets.error.is_empty():
		return
	var level: int = FroggerIds.level_from_code("JUN1")
	assert_true(_data.is_playable_level(level), "JUN1 is a whole-map level")
	var map: MapFile = _data.read_map(_data.map_book_entry(level).map_id(false), PackedStringArray())
	assert_not_null(map)
	if map == null:
		return
	var setup: GameplaySetup = GameplaySetup.from_data(_data, level, map, assets.model, assets.action_lengths)
	assert_eq(setup.error, "", "JUN1 whole-map setup")
	if setup.definition == null:
		return
	var counts: Dictionary[EntityBehavior.Kind, int] = {}
	for definition: EntityDefinition in setup.definition.entity_collision.entities:
		var kind: EntityBehavior.Kind = definition.behavior.kind
		if JUN1_COUNTS.has(kind):
			var previous: int = counts.get(kind, 0)
			counts[kind] = previous + 1
	for kind: EntityBehavior.Kind in JUN1_COUNTS:
		var count: int = counts.get(kind, 0)
		assert_eq(count, JUN1_COUNTS[kind], "JUN1 %s" % EntityBehavior.Kind.keys()[kind])

extends RetailTest
## Desert payload decoding, rock-target resolution, explosion and action facts, and whole-map admission.

const LEVELS: PackedStringArray = ["DES1", "DES2", "DES3", "DES4", "DES5"]
const PATH_KINDS: Array[EntityBehavior.Kind] = [EntityBehavior.Kind.DES_SNAKE, EntityBehavior.Kind.DES_VULTURE, EntityBehavior.Kind.DES_TUMBLE_WEED, EntityBehavior.Kind.DES_ROLLING_ROCK]

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
	for value: String in text.split(",", false):
		result.append(value.to_int())
	return result

func _records(kind: String) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	for row: PackedStringArray in GoldenFiles.rows("desert_entities.tsv"):
		if row[0] == kind:
			result.append(row)
	return result

func _high_detail_maps() -> Dictionary[int, String]:
	var result: Dictionary[int, String] = {}
	for code: String in LEVELS:
		result[_data.map_book_entry(FroggerIds.level_from_code(code)).map_id(false)] = code
	return result

func test_desert_payloads_match_independent_facts() -> void:
	assert_eq(_data.error, "")
	var maps: Dictionary[int, String] = _high_detail_maps()
	var setups: Dictionary[int, EntitySetup] = {}
	var checked: int = 0
	for row: PackedStringArray in _records("entity"):
		var resource_id: int = row[1].to_int()
		if not maps.has(resource_id):
			continue
		var label: String = "%s entity %s" % [row[2], row[3]]
		if not setups.has(resource_id):
			var problems := PackedStringArray()
			var map: MapFile = _data.read_map(resource_id, problems)
			assert_not_null(map, label)
			if map == null:
				return
			setups[resource_id] = EntitySetup.from_map(map, _data.tables.theme_book(), "desert", resource_id, _data.version.internal_name, true, _data.tables.names)
		var definition: EntityDefinition = null
		for candidate: EntityDefinition in setups[resource_id].definitions:
			if candidate.entity_index == row[3].to_int():
				definition = candidate
		assert_not_null(definition, label)
		if definition == null:
			continue
		var facts: Dictionary[String, String] = _fields(row)
		assert_eq(definition.entity_name, row[5], label)
		assert_eq(definition.unique_id, row[4].to_int(), label)
		assert_eq(definition.form_name, facts["form"], label)
		assert_eq(definition.flags, facts["entity_flags"].to_int(), label)
		assert_eq(definition.form_flags, facts["form_flags"].to_int(), label)
		assert_eq(definition.script_id, facts["script"].to_int(), label)
		if definition.behavior.kind in PATH_KINDS:
			assert_eq(definition.path_definition.path_index, facts["path_id"].to_int(), label)
			assert_eq([definition.path_start.segment_index, definition.path_start.distance, definition.path_start.flags & 14, definition.path_start.speed],
				[facts["segment_id"].to_int(), facts["segment_dist"].to_int(), facts["motion"].to_int(), facts["speed"].to_int()], label)
		else:
			assert_eq(definition.matrix12, _ints(facts["matrix"]), label)
		var desert: EntityDesertDefinition = definition.desert
		match definition.behavior.kind:
			EntityBehavior.Kind.DES_FALLING_ROCK:
				assert_not_null(desert, label)
				if desert == null:
					continue
				assert_eq([desert.rock_delay, desert.rock_bounces, desert.rock_flags], [facts["delay"].to_int(), facts["bounces"].to_int(), facts["rock_flags"].to_int()], label)
				assert_eq(desert.rock_times.slice(0, desert.rock_bounces), _ints(facts["times"]), label)
			EntityBehavior.Kind.DES_CROC_HEAD:
				assert_not_null(desert, label)
				if desert == null:
					continue
				assert_eq([desert.rise_height, desert.rise_speed, desert.snap_delay, desert.pause_delay, desert.snap_flag, desert.submerged_delay],
					[facts["rise_height"].to_int(), facts["rise_speed"].to_int(), facts["snap_delay"].to_int(), facts["pause_delay"].to_int(), facts["snap_flag"].to_int(), facts["submerged_delay"].to_int()], label)
			EntityBehavior.Kind.DES_CRACK:
				assert_not_null(desert, label)
				if desert == null:
					continue
				assert_eq([desert.fall_delay, desert.hops_before], [facts["fall_delay"].to_int(), facts["hops_before"].to_int()], label)
		checked += 1
	assert_eq(checked, 152, "high-detail Desert custom entities")

func test_desert_levels_admit_with_resolved_targets_explosions_and_actions() -> void:
	assert_eq(_data.error, "")
	var assets: TerrainFrogAssets = TerrainFrogAssets.from_data(_data)
	assert_eq(assets.error, "")
	if not assets.error.is_empty():
		return
	var targets: Dictionary[String, Array] = {}
	for row: PackedStringArray in _records("rock_target"):
		var facts: Dictionary[String, String] = _fields(row)
		assert_eq(facts["error"], "0", row[2])
		var key: String = "%s:%s" % [row[1], row[3]]
		if not targets.has(key):
			targets[key] = []
		targets[key].append(_ints(facts["resolved"]))
	var explosions: Dictionary[String, PackedStringArray] = {}
	for row: PackedStringArray in _records("explosion"):
		if _fields(row)["detail"] == "high":
			explosions[row[5]] = row
	var actions: Dictionary[String, PackedInt32Array] = {}
	for row: PackedStringArray in _records("actions"):
		actions[row[5]] = _ints(_fields(row)["lengths"])
	var resolved_rocks: int = 0
	for code: String in LEVELS:
		var number: int = FroggerIds.level_from_code(code)
		var resource_id: int = _data.map_book_entry(number).map_id(false)
		var problems := PackedStringArray()
		var map: MapFile = _data.read_map(resource_id, problems)
		assert_not_null(map, code)
		if map == null:
			continue
		var setup: GameplaySetup = GameplaySetup.from_data(_data, number, map, assets.model, assets.action_lengths)
		assert_eq(setup.error, "", code)
		if setup.definition == null:
			continue
		assert_true(setup.definition.entity_collision.lifecycle.source_allocation, code)
		var explosion: PackedStringArray = explosions[code]
		assert_eq(EntityModelSelection.explosion_resource_for(_data, number), _fields(explosion)["model_resource"].to_int(), code)
		for definition: EntityDefinition in setup.definition.entity_collision.entities:
			var label: String = "%s entity %d" % [code, definition.entity_index]
			var kind: EntityBehavior.Kind = definition.behavior.kind
			if kind in [EntityBehavior.Kind.DES_FALLING_ROCK, EntityBehavior.Kind.DES_ROLLING_ROCK]:
				assert_eq(definition.desert.explosion_action_lengths, PackedInt32Array([_fields(explosion)["cels"].to_int()]), label)
			if kind == EntityBehavior.Kind.DES_FALLING_ROCK:
				var key: String = "%d:%d" % [resource_id, definition.entity_index]
				assert_true(definition.desert.rock_targets_resolved, label)
				assert_true(targets.has(key), label)
				if not targets.has(key):
					continue
				var expected: Array = targets[key]
				assert_eq(expected.size(), definition.desert.rock_bounces, label)
				for index: int in expected.size():
					var want: PackedInt32Array = expected[index]
					assert_eq(definition.desert.rock_targets[index], Vector3i(want[0], want[1], want[2]), "%s target %d" % [label, index])
				resolved_rocks += 1
			if actions.has(definition.entity_name) and kind != EntityBehavior.Kind.PATH_FOLLOWER:
				assert_eq(definition.action_lengths, actions[definition.entity_name], label)
	assert_eq(resolved_rocks, 69, "falling rocks across DES1-DES5")

extends GutTest
## Synthetic source identities, name resolution and isolated entity rejection.

func _book() -> ThemeBook:
	var book := ThemeBook.new()
	for theme: int in FroggerIds.THEMES.size():
		var entry := ThemeBookEntry.new()
		entry.theme = theme
		book.entries.append(entry)
	for label: String in ["STATIC", "MOVING", "UNKNOWN"]:
		var form := FormBookEntry.new()
		form.form_name = "TEST_" + label
		form.entity_name = label
		book.entries[1].forms.append(form)
	var general := FormBookEntry.new()
	general.form_name = "GEN_STATIC_OVERRIDE"
	general.entity_name = "STATIC"
	book.entries[FroggerIds.THEME_GENERAL].forms.append(general)
	return book

func test_dog_wait_payload_is_unsigned_and_truncation_is_reported() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[1].entity_name = "SUB_DOG"
	var map: MapFile = _map()
	_add_path(map)
	var payload: PackedByteArray = _path_info(0)
	payload.resize(16)
	payload.encode_u32(12, 4294967295)
	_add_entity(map, 1, 0, payload)
	var setup: EntitySetup = EntitySetup.from_map(map, book, "dog.map", 1, "pc-retail-v3.0e", true)
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 1)
	assert_eq(setup.definitions[0].authored_delay, 4294967295)
	map.entities[0].payload.resize(12)
	setup = EntitySetup.from_map(map, book, "dog.map", 1, "pc-retail-v3.0e", true)
	assert_true(setup.definitions.is_empty())
	assert_eq(setup.diagnostics[0].code, "invalid_payload")
	assert_eq(setup.diagnostics[0].source_id, "dog.map")

func test_butterfly_callback_reads_its_payload_in_both_roles_and_repointed_types() -> void:
	for bonus: bool in [true, false]:
		var book: ThemeBook = _book()
		book.entries[1].forms[0].entity_name = "BONUS_FLY"
		if bonus:
			book.entries[1].forms[0].bonus_callback = 0x4284e0
		else:
			book.entries[1].forms[0].collision_callback = 0x4284e0
		var map: MapFile = _map()
		var payload: PackedByteArray = _matrix()
		payload.resize(36)
		payload.encode_u16(12, 13)
		payload.encode_u16(32, 7)
		_add_entity(map, 0, 0, payload)
		var setup: EntitySetup = EntitySetup.from_map(map, book, "butterfly.map", 1, "pc-retail-v3.0e", true)
		assert_eq(setup.error, "")
		assert_eq(setup.definitions.size(), 1)
		assert_eq(setup.definitions[0].butterfly_type, 13)
		assert_eq(setup.definitions[0].pickup_type, 7)
		map.entities[0].payload.encode_u16(12, 19)
		setup = EntitySetup.from_map(map, book, "butterfly.map", 1, "pc-retail-v3.0e", true)
		assert_true(setup.definitions.is_empty())
		assert_eq(setup.diagnostics[0].code, "invalid_payload")
		map.entities[0].payload.resize(12)
		setup = EntitySetup.from_map(map, book, "butterfly.map", 1, "pc-retail-v3.0e", true)
		assert_true(setup.definitions.is_empty())
		assert_eq(setup.diagnostics[0].source_id, "butterfly.map")

func test_multipoint_has_explicit_source_located_multiplayer_exclusion() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[0].entity_name = "MULTIPOINT"
	var map: MapFile = _map()
	_add_entity(map, 0, 0, _matrix())
	var setup: EntitySetup = EntitySetup.from_map(map, book, "modified.map", 24, "pc-retail-v3.0e")
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 0)
	assert_eq(setup.diagnostics.size(), 1)
	assert_eq(setup.diagnostics[0].code, "multiplayer_only")
	assert_eq(setup.diagnostics[0].source_offset, 100)
	assert_eq(setup.diagnostics[0].source_id, "modified.map")

func _matrix() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(32)
	for index: int in 3:
		bytes.encode_s16((index * 3 + index) * 2, 4096)
	bytes.encode_s32(20, 100)
	return bytes

func _map() -> MapFile:
	var map := MapFile.new()
	map.general.theme = 1
	var entity_packet := MapPacket.new()
	entity_packet.identifier = "EMTP"
	map.packets["EMTP"] = entity_packet
	var path_packet := MapPacket.new()
	path_packet.identifier = "PATH"
	map.packets["PATH"] = path_packet
	return map

func _add_entity(map: MapFile, form_id: int, flags: int, payload: PackedByteArray, unique_id: int = 1) -> void:
	var span := MapEntitySpan.new()
	span.source_offset = 100 + map.entities.size() * 50
	span.end_offset = span.source_offset + 24 + payload.size()
	span.form_id = form_id
	span.flags = flags
	span.unique_id = unique_id
	span.form_grid_id = 7
	span.payload = payload
	map.packets["EMTP"].offsets.append(span.source_offset)
	map.packets["EMTP"].count += 1
	map.entities.append(span)

func _path_info(path_index: int, flags: int = 8) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(12)
	bytes.encode_u16(0, path_index)
	bytes.encode_u16(6, flags)
	bytes.encode_u16(8, 16)
	return bytes

func _add_path(map: MapFile, valid: bool = true) -> void:
	var path := MapPath.new()
	path.path_index = map.paths.size()
	path.source_offset = 1000 + 100 * path.path_index
	var segment := MapPathSegment.new()
	segment.segment_type = 2
	segment.length = 160 if valid else 0
	segment.source_offset = path.source_offset + 12
	segment.start = Vector3i.ZERO
	segment.end = Vector3i(10, 0, 0)
	path.segments.append(segment)
	map.packets["PATH"].offsets.append(path.source_offset)
	map.packets["PATH"].count += 1
	map.paths.append(path)

func test_static_names_general_form_and_duplicate_ids_keep_source_identity() -> void:
	var map: MapFile = _map()
	_add_entity(map, 0, 1 | 2 | 8, _matrix(), 55)
	_add_entity(map, FormBookEntry.GENERAL_BIT, 0, _matrix(), 55)
	var setup: EntitySetup = EntitySetup.from_map(map, _book(), "ORG1", 9, "pc-retail-v3.0e")
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 2)
	assert_eq(setup.definitions[0].entity_index, 0)
	assert_eq(setup.definitions[1].entity_index, 1)
	assert_eq(setup.definitions[0].unique_id, 55)
	assert_eq(setup.definitions[1].unique_id, 55)
	assert_eq(setup.definitions[1].form_name, "GEN_STATIC_OVERRIDE")
	assert_eq(setup.definitions[0].matrix12[9], 100)
	map.entities[0].payload.encode_s32(20, 500)
	assert_eq(setup.definitions[0].matrix12[9], 100)

func test_invalid_neighbors_are_omitted_with_source_diagnostics() -> void:
	var map: MapFile = _map()
	_add_entity(map, 99, 0, _matrix())
	_add_entity(map, 2, 0, _matrix())
	_add_entity(map, 0, 128, _matrix())
	_add_entity(map, 0, 32, _matrix())
	_add_entity(map, 0, 0, PackedByteArray([1, 2]))
	_add_entity(map, 0, 0, _matrix())
	var setup: EntitySetup = EntitySetup.from_map(map, _book(), "SUB1", 8, "pc-retail-v1.0")
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 1)
	assert_eq(setup.definitions[0].entity_index, 5)
	assert_eq(EntityRun.create(setup.definitions).error, "")
	assert_eq(setup.diagnostics.size(), 5)
	assert_eq(setup.diagnostics[0].code, "invalid_form")
	assert_eq(setup.diagnostics[1].code, "unknown_behavior")
	assert_eq(setup.diagnostics[2].code, "unknown_flags")
	assert_eq(setup.diagnostics[3].code, "unsupported_transform")
	assert_eq(setup.diagnostics[4].code, "invalid_payload")
	assert_string_contains(setup.diagnostics[4].to_text(), "entity 4")

func test_path_uses_authored_index_after_omitted_path_and_no_movement() -> void:
	var map: MapFile = _map()
	_add_path(map, false)
	_add_path(map)
	_add_entity(map, 1, 4, _path_info(1), 2)
	_add_entity(map, 1, 0, _path_info(0), 3)
	_add_entity(map, 1, 0, _path_info(1, 1), 4)
	var setup: EntitySetup = EntitySetup.from_map(map, _book())
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 1)
	assert_eq(setup.definitions[0].path_definition.path_index, 1)
	assert_eq(EntityRun.create(setup.definitions).error, "")
	assert_eq(setup.definitions[0].path_start.flags, PathStart.REPEAT)
	assert_eq(setup.diagnostics[0].code, "invalid_path")
	assert_eq(setup.diagnostics[1].code, "unsupported_motion_flags")

func test_unexecuted_hooks_warn_without_rejecting_transform() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[0].script_id = 3
	book.entries[1].forms[0].collision_callback = 0x1234
	book.entries[1].forms[0].bonus_callback = 0x5678
	var map: MapFile = _map()
	_add_entity(map, 0, 0, _matrix())
	var setup: EntitySetup = EntitySetup.from_map(map, book)
	assert_eq(setup.definitions.size(), 1)
	assert_eq(setup.definitions[0].script_id, 3)
	assert_eq(setup.definitions[0].collision_callback, 0x1234)
	assert_eq(setup.definitions[0].bonus_callback, 0x5678)
	assert_eq(setup.diagnostics[0].code, "unexecuted_hooks")

func test_structural_map_failure_is_setup_error() -> void:
	var map: MapFile = _map()
	map.error = "bad pointer"
	assert_string_contains(EntitySetup.from_map(map, _book()).error, "bad pointer")
	map.error = ""
	map.packets["EMTP"].count = 1
	assert_string_contains(EntitySetup.from_map(map, _book()).error, "count")

func test_all_supported_build_name_lists_include_base_types_and_override() -> void:
	var library := FrogLordConfigLibrary.new()
	for build: String in ["pc-retail-v3.0e", "pc-retail-v1.0", "pc-retail-v3.0e-vogons"]:
		var version: GameVersionConfig = library.load_version(build)
		var names: GameNameLists = GameNameLists.load_for(version, library)
		assert_eq(names.errors.size(), 0, build)
		assert_eq(names.entity_name_for("UNNAMED", names.entities.index_of("STATIC")), "STATIC", build)
		assert_eq(names.entity_name_for("UNNAMED", names.entities.index_of("MOVING")), "MOVING", build)
		assert_eq(names.entity_name_for("CAV_SNAIL", names.entities.index_of("STATIC")), "MOVING", build)
		assert_true(names.forms.get_sub_bank("GENERAL").index_of("GEN_CHECKPOINT_1") >= 0, build)

func test_bonus_fly_payload_types_and_source_located_rejection() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[0].entity_name = "BONUS_FLY"
	var map: MapFile = _map()
	for pickup_type: int in 20:
		var payload: PackedByteArray = _matrix()
		payload.resize(36)
		payload.encode_u16(32, pickup_type)
		_add_entity(map, 0, 0, payload)
	_add_entity(map, 0, 0, _matrix())
	var setup: EntitySetup = EntitySetup.from_map(map, book, "modified.map", 24, "pc-retail-v3.0e", true)
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 19)
	for index: int in 19:
		assert_eq(setup.definitions[index].pickup_type, index)
		assert_eq(setup.definitions[index].behavior.kind, EntityBehavior.Kind.PICKUP)
	assert_eq(setup.diagnostics.size(), 2)
	assert_eq(setup.diagnostics[0].code, "invalid_payload")
	assert_eq(setup.diagnostics[0].source_id, "modified.map")
	assert_eq(setup.diagnostics[0].resource_id, 24)
	assert_eq(setup.diagnostics[0].source_offset, 1050)
	assert_eq(setup.diagnostics[1].source_offset, 1100)

func test_froglord_switch_payload_uses_56_bytes_and_repointed_behavior() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[0].entity_name = "VOL_COLOUR_SWITCH"
	book.entries[1].forms[0].collision_callback = 0x41d7e0
	var map: MapFile = _map()
	var payload: PackedByteArray = _matrix()
	payload.resize(56)
	payload.encode_u16(32, 2)
	payload.encode_u16(34, 8)
	for index: int in 10:
		payload.encode_s16(36 + index * 2, -1 if index > 2 else -2 if index == 2 else 40 + index)
	_add_entity(map, 0, 0, payload)
	var setup: EntitySetup = EntitySetup.from_map(map, book, "mod.map", 1, "pc-retail-v3.0e", true)
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 1)
	if setup.definitions.is_empty():
		return
	assert_eq(setup.definitions[0].volcano.trigger_type, 2)
	assert_eq(setup.definitions[0].volcano.colour, 8)
	assert_eq(setup.definitions[0].volcano.target_ids, PackedInt32Array([40, 41, 65534, -1, -1, -1, -1, -1, -1, -1]))
	map.entities[0].payload.resize(55)
	setup = EntitySetup.from_map(map, book, "mod.map", 1, "pc-retail-v3.0e", true)
	assert_true(setup.definitions.is_empty())
	assert_eq(setup.diagnostics[0].code, "invalid_payload")
	assert_eq(setup.diagnostics[0].source_id, "mod.map")
	map.entities[0].payload = payload
	book.entries[1].forms[0].entity_name = "STATIC"
	setup = EntitySetup.from_map(map, book, "mod.map", 1, "pc-retail-v3.0e", true)
	assert_true(setup.definitions.is_empty())
	assert_eq(setup.diagnostics[0].code, "incompatible_callback")

func test_volcano_platform_payloads_retain_unsigned_source_operands() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[1].entity_name = "MOVING_PLATFORM"
	book.entries[1].forms[0].entity_name = "VOL_FALLING_PLATFORM"
	var map: MapFile = _map()
	_add_path(map)
	var path_payload: PackedByteArray = _path_info(0)
	path_payload.resize(16)
	path_payload.encode_u32(12, 1)
	_add_entity(map, 1, 0, path_payload, 8)
	var matrix_payload: PackedByteArray = _matrix()
	matrix_payload.resize(36)
	matrix_payload.encode_u16(32, 65535)
	matrix_payload.encode_u16(34, 2)
	_add_entity(map, 0, 0, matrix_payload, 9)
	var setup: EntitySetup = EntitySetup.from_map(map, book, "vol.map", 1, "pc-retail-v3.0e", true)
	assert_eq(setup.definitions.size(), 2)
	if setup.definitions.size() != 2:
		return
	assert_eq(setup.definitions[0].volcano.initial_movement, 1)
	assert_eq(setup.definitions[1].authored_delay, 65535)
	assert_eq(setup.definitions[1].volcano.hops_before, 2)

func test_colour_switch_callback_roles_require_compatible_behavior() -> void:
	for bonus: bool in [false, true]:
		var book: ThemeBook = _book()
		var form: FormBookEntry = book.entries[1].forms[0]
		if bonus:
			form.bonus_callback = 0x41d7e0
		else:
			form.collision_callback = 0x41d7e0
		var map: MapFile = _map()
		var payload: PackedByteArray = _matrix()
		payload.resize(56)
		for index: int in 10:
			payload.encode_s16(36 + index * 2, -1)
		_add_entity(map, 0, 0, payload)
		var setup: EntitySetup = EntitySetup.from_map(map, book, "callback-mod.map", 1, "pc-retail-v3.0e", true)
		assert_true(setup.definitions.is_empty())
		assert_eq(setup.diagnostics[0].code, "incompatible_callback")
		assert_eq(setup.diagnostics[0].source_id, "callback-mod.map")
		form.entity_name = "VOL_COLOUR_SWITCH"
		setup = EntitySetup.from_map(map, book, "callback-mod.map", 1, "pc-retail-v3.0e", true)
		assert_eq(setup.definitions.size(), 1)
		assert_eq(setup.error, "")

func _light(min_radius: int, max_radius: int, die_speed: int) -> PackedByteArray:
	var payload: PackedByteArray = _matrix()
	payload.resize(48)
	payload.encode_s32(32, min_radius)
	payload.encode_s32(36, max_radius)
	payload.encode_s32(40, die_speed)
	return payload

func test_frogger_light_precomputes_unsigned_radii_and_rejects_invalid_operands() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[0].entity_name = "CAV_FROGGER_LIGHT"
	book.entries[1].forms[0].flags = FormBookEntry.FLAG_NO_MODEL
	var map: MapFile = _map()
	_add_entity(map, 0, 0, _light(2, 4, 90), 1)
	_add_entity(map, 0, 0, _light(5, 10, 100), 2)
	_add_entity(map, 0, 0, _light(2, 255, -1), 3)
	var truncated: PackedByteArray = _light(2, 4, 90)
	truncated.resize(47)
	_add_entity(map, 0, 0, truncated, 4)
	_add_entity(map, 0, 0, _light(1, 4, 90), 5)
	_add_entity(map, 0, 0, _light(4, 4, 90), 6)
	_add_entity(map, 0, 0, _light(2, 256, 90), 7)
	var setup: EntitySetup = EntitySetup.from_map(map, book, "cave.map", 3, "pc-retail-v3.0e", true)
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 3)
	if setup.definitions.size() != 3:
		return
	var light: EntityCaveDefinition = setup.definitions[0].cave
	assert_eq(setup.definitions[0].behavior.kind, EntityBehavior.Kind.CAVE_LIGHT)
	assert_eq(setup.definitions[0].behavior.execution, EntityBehavior.Execution.UPDATE)
	assert_eq([light.min_radius, light.max_radius, light.die_speed], [2, 4, 90])
	assert_eq(light.light_min_squared, 262144)
	assert_eq(light.light_max_squared, 1048576)
	assert_eq(light.light_die, 2304)
	assert_eq(setup.definitions[1].cave.light_min_squared, 1638400)
	assert_eq(setup.definitions[1].cave.light_max_squared, 6553600)
	assert_eq(setup.definitions[1].cave.light_die, 2842)
	assert_eq(setup.definitions[2].cave.light_max_squared, 4261478400)
	assert_eq(setup.definitions[2].cave.light_die, 5294144)
	var copied: EntityDefinition = setup.definitions[0].copy()
	assert_eq(copied.cave.light_die, 2304)
	assert_ne(copied.cave, light)
	assert_eq(setup.diagnostics.size(), 4)
	for diagnostic: EntitySetupDiagnostic in setup.diagnostics:
		assert_eq(diagnostic.code, "invalid_payload")
		assert_eq(diagnostic.source_id, "cave.map")
	assert_string_contains(setup.diagnostics[0].message, "min/max radii and die speed")
	assert_eq(setup.diagnostics[1].entity_index, 4)
	assert_eq(setup.diagnostics[2].entity_index, 5)
	assert_eq(setup.diagnostics[3].entity_index, 6)

func test_cave_lights_and_fat_fire_flies_require_custom_behaviors() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[0].entity_name = "CAV_FROGGER_LIGHT"
	var map: MapFile = _map()
	_add_entity(map, 0, 0, _light(2, 4, 90))
	var setup: EntitySetup = EntitySetup.from_map(map, book, "cave.map", 3, "pc-retail-v3.0e")
	assert_true(setup.definitions.is_empty())
	assert_eq(setup.diagnostics[0].code, "unknown_behavior")

func test_fat_fire_fly_reads_bonus_fly_reward_type() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[0].entity_name = "CAV_FAT_FIRE_FLY"
	book.entries[1].forms[0].flags = FormBookEntry.FLAG_NO_MODEL
	var map: MapFile = _map()
	for fly_type: int in 20:
		var payload: PackedByteArray = _matrix()
		payload.resize(44)
		payload.encode_u16(32, fly_type)
		_add_entity(map, 0, 0, payload, fly_type + 1)
	_add_entity(map, 0, 0, _matrix(), 30)
	var setup: EntitySetup = EntitySetup.from_map(map, book, "cave.map", 3, "pc-retail-v3.0e", true)
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 19)
	for index: int in setup.definitions.size():
		assert_eq(setup.definitions[index].pickup_type, index)
		assert_eq(setup.definitions[index].behavior.kind, EntityBehavior.Kind.FAT_FIRE_FLY)
		assert_eq(setup.definitions[index].behavior.execution, EntityBehavior.Execution.UPDATE)
	assert_eq(setup.diagnostics.size(), 2)
	assert_eq(setup.diagnostics[0].code, "invalid_payload")
	assert_eq(setup.diagnostics[0].entity_index, 19)
	assert_eq(setup.diagnostics[1].entity_index, 20)

func test_firefly_follows_path_and_requires_bonus_callback() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[1].entity_name = "FIREFLY"
	book.entries[1].forms[1].flags = FormBookEntry.FLAG_NO_MODEL | FormBookEntry.FLAG_DONT_FADE_COLOR
	var map: MapFile = _map()
	_add_path(map)
	_add_entity(map, 1, 0, _path_info(0))
	var setup: EntitySetup = EntitySetup.from_map(map, book, "cave.map", 3, "pc-retail-v3.0e", true)
	assert_true(setup.definitions.is_empty())
	assert_eq(setup.diagnostics[0].code, "incompatible_callback")
	assert_string_contains(setup.diagnostics[0].message, "Firefly requires a verified bonus callback")
	book.entries[1].forms[1].bonus_callback = 0x43d060
	setup = EntitySetup.from_map(map, book, "cave.map", 3, "pc-retail-v3.0e", true)
	assert_eq(setup.definitions.size(), 1)
	if setup.definitions.is_empty():
		return
	assert_eq(setup.definitions[0].behavior.kind, EntityBehavior.Kind.FIREFLY)
	assert_eq(setup.definitions[0].bonus_kind, FormCallback.Kind.CAV_FIREFLY_SCORE)
	assert_eq(setup.definitions[0].path_definition.path_index, 0)
	assert_true(setup.definitions[0].behavior.tongueable)

func test_project_on_land_admits_path_movers_only_with_custom_behaviors() -> void:
	var book: ThemeBook = _book()
	var map: MapFile = _map()
	_add_path(map)
	_add_entity(map, 1, 32, _path_info(0), 1)
	_add_entity(map, 1, 64, _path_info(0), 2)
	_add_entity(map, 0, 32, _matrix(), 3)
	var setup: EntitySetup = EntitySetup.from_map(map, book, "cave.map", 3, "pc-retail-v3.0e", true)
	assert_eq(setup.definitions.size(), 1)
	if setup.definitions.is_empty():
		return
	assert_eq(setup.definitions[0].unique_id, 1)
	assert_eq(setup.definitions[0].flags, 32)
	assert_eq(setup.diagnostics.size(), 2)
	assert_eq(setup.diagnostics[0].code, "unsupported_transform")
	assert_eq(setup.diagnostics[1].code, "unsupported_transform")
	setup = EntitySetup.from_map(map, book, "cave.map", 3, "pc-retail-v3.0e", false)
	assert_true(setup.definitions.is_empty())
	assert_eq(setup.diagnostics[0].code, "unsupported_transform")

func test_froglord_entity_override_is_reported_without_omission() -> void:
	var library := FrogLordConfigLibrary.new()
	var names: GameNameLists = GameNameLists.load_for(library.load_version("pc-retail-v3.0e"), library)
	var book: ThemeBook = _book()
	var form: FormBookEntry = book.entries[1].forms[1]
	form.form_name = "CAV_SNAIL"
	form.entity_type = names.entities.index_of("STATIC")
	form.entity_name = names.entity_name_for(form.form_name, form.entity_type)
	book.entries[1].forms[0].entity_type = names.entities.index_of("STATIC")
	var map: MapFile = _map()
	_add_path(map)
	_add_entity(map, 1, 0, _path_info(0), 1)
	_add_entity(map, 0, 0, _matrix(), 2)
	var setup: EntitySetup = EntitySetup.from_map(map, book, "CAV3", 3, "pc-retail-v3.0e", true, names)
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 2)
	assert_eq(setup.definitions[0].behavior.kind, EntityBehavior.Kind.PATH_FOLLOWER)
	assert_eq(setup.diagnostics.size(), 1)
	if setup.diagnostics.is_empty():
		return
	assert_eq(setup.diagnostics[0].code, "entity_override")
	assert_eq(setup.diagnostics[0].entity_index, 0)
	assert_eq(setup.diagnostics[0].message, "FrogLord names this form MOVING; the executable entity type is STATIC")
	assert_eq(setup.diagnostics[0].fallback, "Base transform remains available for inspection")

func _rock(bounces: int, times: PackedInt32Array, flags: int = 0) -> PackedByteArray:
	var payload: PackedByteArray = _matrix()
	payload.resize(188)
	for index: int in 12:
		var offset: int = 32 + index * 12
		payload.encode_s16(offset, -300 + index)
		payload.encode_s16(offset + 2, -1000 - index)
		payload.encode_s16(offset + 4, 700 + index)
		payload.encode_u16(offset + 6, 0x7777)
		payload.encode_u16(offset + 8, times[index] if index < times.size() else 0)
	payload.encode_u16(176, 65535)
	payload.encode_u8(178, bounces)
	payload.encode_s32(180, flags)
	payload.encode_s32(184, -1)
	return payload

func test_falling_rock_reads_froglord_targets_and_rejects_invalid_counts() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[0].entity_name = "DES_FALLING_ROCK"
	var map: MapFile = _map()
	_add_entity(map, 0, 0, _rock(2, PackedInt32Array([30, 65535])), 1)
	_add_entity(map, 0, 0, _rock(12, PackedInt32Array([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]), 1), 2)
	_add_entity(map, 0, 0, _rock(0, PackedInt32Array([30])), 3)
	_add_entity(map, 0, 0, _rock(13, PackedInt32Array([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])), 4)
	_add_entity(map, 0, 0, _rock(2, PackedInt32Array([30, 0])), 5)
	var truncated: PackedByteArray = _rock(1, PackedInt32Array([30]))
	truncated.resize(187)
	_add_entity(map, 0, 0, truncated, 6)
	var setup: EntitySetup = EntitySetup.from_map(map, book, "des.map", 4, "pc-retail-v3.0e", true)
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 2)
	if setup.definitions.size() != 2:
		return
	var rock: EntityDesertDefinition = setup.definitions[0].desert
	assert_eq(setup.definitions[0].behavior.kind, EntityBehavior.Kind.DES_FALLING_ROCK)
	assert_eq(setup.definitions[0].behavior.execution, EntityBehavior.Execution.UPDATE)
	assert_eq(setup.definitions[0].matrix12[9], 100)
	assert_eq(rock.rock_targets.size(), 12)
	assert_eq(rock.rock_targets[0], Vector3i(-300, -1000, 700))
	assert_eq(rock.rock_targets[11], Vector3i(-289, -1011, 711))
	assert_eq(rock.rock_times.slice(0, 3), PackedInt32Array([30, 65535, 0]))
	assert_eq(rock.rock_delay, 65535)
	assert_eq(rock.rock_bounces, 2)
	assert_eq(rock.rock_flags, 0)
	assert_false(rock.rock_targets_resolved)
	assert_eq(setup.definitions[1].desert.rock_bounces, 12)
	assert_true(setup.definitions[1].desert.rock_targets_resolved)
	assert_eq(setup.diagnostics.size(), 4)
	for diagnostic: EntitySetupDiagnostic in setup.diagnostics:
		assert_eq(diagnostic.code, "invalid_payload")
	assert_eq([setup.diagnostics[0].entity_index, setup.diagnostics[1].entity_index, setup.diagnostics[2].entity_index, setup.diagnostics[3].entity_index], [2, 3, 4, 5])
	assert_string_contains(setup.diagnostics[2].message, "target 1")

func test_desert_croc_head_and_crack_read_unsigned_operands() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[0].entity_name = "DES_CROC_HEAD"
	book.entries[1].forms[2].entity_name = "DES_CRACK"
	var map: MapFile = _map()
	var croc: PackedByteArray = _matrix()
	croc.resize(44)
	for index: int in 6:
		croc.encode_u16(32 + index * 2, 65535 - index)
	_add_entity(map, 0, 0, croc, 1)
	var crack: PackedByteArray = _matrix()
	crack.resize(36)
	crack.encode_u16(32, 40000)
	crack.encode_u16(34, 3)
	_add_entity(map, 2, 0, crack, 2)
	var short_croc: PackedByteArray = croc.duplicate()
	short_croc.resize(43)
	_add_entity(map, 0, 0, short_croc, 3)
	var short_crack: PackedByteArray = crack.duplicate()
	short_crack.resize(35)
	_add_entity(map, 2, 0, short_crack, 4)
	var setup: EntitySetup = EntitySetup.from_map(map, book, "des.map", 4, "pc-retail-v3.0e", true)
	assert_eq(setup.definitions.size(), 2)
	if setup.definitions.size() != 2:
		return
	var head: EntityDesertDefinition = setup.definitions[0].desert
	assert_eq([head.rise_height, head.rise_speed, head.snap_delay, head.pause_delay, head.snap_flag, head.submerged_delay], [65535, 65534, 65533, 65532, 65531, 65530])
	assert_eq(setup.definitions[1].desert.fall_delay, 40000)
	assert_eq(setup.definitions[1].desert.hops_before, 3)
	for definition: EntityDefinition in setup.definitions:
		assert_eq(definition.behavior.execution, EntityBehavior.Execution.UPDATE)
	assert_eq(setup.diagnostics.size(), 2)
	assert_eq(setup.diagnostics[0].entity_index, 2)
	assert_eq(setup.diagnostics[1].entity_index, 3)
	setup = EntitySetup.from_map(map, book, "des.map", 4, "pc-retail-v3.0e")
	assert_true(setup.definitions.is_empty())
	assert_eq(setup.diagnostics[0].code, "unknown_behavior")

func test_desert_path_runners_update_from_path_info_alone() -> void:
	for name: String in ["DES_ROLLING_ROCK", "DES_TUMBLE_WEED", "DES_SNAKE", "DES_VULTURE"]:
		var book: ThemeBook = _book()
		book.entries[1].forms[1].entity_name = name
		var map: MapFile = _map()
		_add_path(map)
		_add_entity(map, 1, 0, _path_info(0))
		var setup: EntitySetup = EntitySetup.from_map(map, book, "des.map", 4, "pc-retail-v3.0e", true)
		assert_eq(setup.definitions.size(), 1, name)
		if setup.definitions.is_empty():
			continue
		assert_eq(setup.definitions[0].behavior.execution, EntityBehavior.Execution.UPDATE, name)
		assert_not_null(setup.definitions[0].path_start, name)
		assert_null(setup.definitions[0].desert, name)
		setup = EntitySetup.from_map(map, book, "des.map", 4, "pc-retail-v3.0e")
		assert_true(setup.definitions.is_empty(), name)
		_add_entity(map, 1, 32, _path_info(0), 2)
		setup = EntitySetup.from_map(map, book, "des.map", 4, "pc-retail-v3.0e", true)
		assert_eq(setup.diagnostics[0].code, "unsupported_transform", name)

func test_jungle_plant_and_rope_bridge_read_froglord_operands() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[0].entity_name = "JUN_PLANT"
	book.entries[1].forms[2].entity_name = "JUN_ROPE_BRIDGE"
	var map: MapFile = _map()
	var plant: PackedByteArray = _matrix()
	plant.resize(36)
	plant.encode_s16(32, -6)
	plant.encode_s16(34, 30)
	_add_entity(map, 0, 0, plant, 1)
	var bridge: PackedByteArray = _matrix()
	bridge.resize(36)
	bridge.encode_u16(32, 65535)
	bridge.encode_u16(34, 40000)
	_add_entity(map, 2, 0, bridge, 2)
	var short_plant: PackedByteArray = plant.duplicate()
	short_plant.resize(35)
	_add_entity(map, 0, 0, short_plant, 3)
	var short_bridge: PackedByteArray = bridge.duplicate()
	short_bridge.resize(35)
	_add_entity(map, 2, 0, short_bridge, 4)
	var setup: EntitySetup = EntitySetup.from_map(map, book, "jun.map", 656, "pc-retail-v3.0e", true)
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 2)
	if setup.definitions.size() != 2:
		return
	assert_eq([setup.definitions[0].jungle.snap_time, setup.definitions[0].jungle.snap_delay], [-6, 30])
	assert_eq([setup.definitions[1].jungle.fall_delay, setup.definitions[1].jungle.hops_before], [65535, 40000])
	for definition: EntityDefinition in setup.definitions:
		assert_eq(definition.behavior.execution, EntityBehavior.Execution.UPDATE)
		assert_eq(definition.matrix12[9], 100)
		assert_null(definition.desert)
	assert_eq(setup.diagnostics.size(), 2)
	for diagnostic: EntitySetupDiagnostic in setup.diagnostics:
		assert_eq(diagnostic.code, "invalid_payload")
	assert_eq([setup.diagnostics[0].entity_index, setup.diagnostics[1].entity_index], [2, 3])
	setup = EntitySetup.from_map(map, book, "jun.map", 656, "pc-retail-v3.0e")
	assert_true(setup.definitions.is_empty())
	assert_eq(setup.diagnostics[0].code, "unknown_behavior")

func test_jungle_outro_targets_and_plinth_ids() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[0].entity_name = "JUN_OUTRO"
	book.entries[1].forms[1].entity_name = "JUN_PLINTH"
	book.entries[1].forms[2].entity_name = "JUN_GOLD_FROG"
	var map: MapFile = _map()
	var outro: PackedByteArray = _matrix()
	outro.resize(164)
	for index: int in 11:
		var offset: int = 32 + index * 12
		outro.encode_s16(offset, -100 - index)
		outro.encode_s16(offset + 2, 200 + index)
		outro.encode_s16(offset + 4, -32768 + index)
		outro.encode_s16(offset + 6, 77)
		outro.encode_u32(offset + 8, 4294967295 - index)
	_add_entity(map, 0, 2, outro, 1)
	for op_id: int in [0, 8, 9, -1]:
		var plinth: PackedByteArray = _matrix()
		plinth.resize(36)
		plinth.encode_s32(32, op_id)
		_add_entity(map, 1, 0, plinth, 10 + op_id)
	var frog: PackedByteArray = _matrix()
	frog.resize(36)
	frog.encode_s32(32, -7)
	_add_entity(map, 2, 0, frog, 30)
	var short_outro: PackedByteArray = outro.duplicate()
	short_outro.resize(163)
	_add_entity(map, 0, 0, short_outro, 31)
	var setup: EntitySetup = EntitySetup.from_map(map, book, "jun.map", 656, "pc-retail-v3.0e", true)
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 4)
	if setup.definitions.size() != 4:
		return
	var targets: EntityJungleDefinition = setup.definitions[0].jungle
	assert_eq(targets.outro_targets.size(), 11)
	assert_eq(targets.outro_targets[0], Vector3i(-100, 200, -32768))
	assert_eq(targets.outro_targets[10], Vector3i(-110, 210, -32758))
	assert_eq(targets.outro_times[0], 4294967295)
	assert_eq(targets.outro_times[10], 4294967285)
	assert_eq([setup.definitions[1].jungle.op_id, setup.definitions[2].jungle.op_id, setup.definitions[3].jungle.op_id], [0, 8, -7])
	assert_eq(setup.definitions[3].behavior.kind, EntityBehavior.Kind.JUN_GOLD_FROG)
	assert_eq(setup.diagnostics.size(), 3)
	assert_eq([setup.diagnostics[0].entity_index, setup.diagnostics[1].entity_index, setup.diagnostics[2].entity_index], [3, 4, 6])
	assert_string_contains(setup.diagnostics[0].message, "plinth id 9")

func test_jungle_statics_decode_matrix_only() -> void:
	for name: String in ["JUN_BOUNCY_MUSHROOM", "JUN_OUTRO_DOOR"]:
		var book: ThemeBook = _book()
		book.entries[1].forms[0].entity_name = name
		var map: MapFile = _map()
		_add_entity(map, 0, 0, _matrix())
		var setup: EntitySetup = EntitySetup.from_map(map, book, "jun.map", 656, "pc-retail-v3.0e", true)
		assert_eq(setup.definitions.size(), 1, name)
		if setup.definitions.is_empty():
			continue
		assert_null(setup.definitions[0].jungle, name)
		assert_eq(setup.definitions[0].behavior.execution, EntityBehavior.Execution.UPDATE, name)

func test_jungle_path_followers_read_path_info_and_hippo_requires_its_type() -> void:
	for name: String in ["JUN_HIPPO", "JUN_SCORPION"]:
		var book: ThemeBook = _book()
		book.entries[1].forms[1].entity_name = name
		var map: MapFile = _map()
		_add_path(map)
		var payload: PackedByteArray = _path_info(0)
		payload.resize(24)
		payload.encode_s32(20, 1)
		_add_entity(map, 1, 0, payload)
		_add_entity(map, 1, 0, _path_info(0), 2)
		var setup: EntitySetup = EntitySetup.from_map(map, book, "jun.map", 657, "pc-retail-v3.0e", true)
		assert_eq(setup.definitions.size(), 1 if name == "JUN_HIPPO" else 2, name)
		if setup.definitions.is_empty():
			continue
		assert_not_null(setup.definitions[0].path_start, name)
		assert_eq(setup.definitions[0].behavior.execution, EntityBehavior.Execution.TRANSFORM, name)
		assert_false(setup.definitions[0].behavior.has_custom_update(), name)
		assert_null(setup.definitions[0].jungle, name)
		if name == "JUN_HIPPO":
			assert_eq(setup.diagnostics[0].code, "invalid_payload")
			assert_eq(setup.diagnostics[0].entity_index, 1)
		setup = EntitySetup.from_map(map, book, "jun.map", 657, "pc-retail-v3.0e")
		assert_true(setup.definitions.is_empty(), name)

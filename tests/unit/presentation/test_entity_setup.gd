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

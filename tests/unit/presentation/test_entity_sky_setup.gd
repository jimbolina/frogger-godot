extends GutTest
## Synthetic Sky trigger capabilities, ENTSTR_TRIGGER decoding, callback roles and plain moving-platform PATH_INFO.

func _book(names: PackedStringArray) -> ThemeBook:
	var book := ThemeBook.new()
	for theme: int in FroggerIds.THEMES.size():
		var entry := ThemeBookEntry.new()
		entry.theme = theme
		book.entries.append(entry)
	for label: String in names:
		var form := FormBookEntry.new()
		form.form_name = "TEST_" + label
		form.entity_name = label
		book.entries[1].forms.append(form)
	return book

func _matrix(size: int = 32) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(32)
	for index: int in 3:
		bytes.encode_s16((index * 3 + index) * 2, 4096)
	bytes.encode_s32(20, 100)
	bytes.encode_s32(24, -200)
	bytes.encode_s32(28, 300)
	bytes.resize(size)
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
	span.source_offset = 100 + map.entities.size() * 60
	span.end_offset = span.source_offset + 24 + payload.size()
	span.form_id = form_id
	span.flags = flags
	span.unique_id = unique_id
	span.form_grid_id = 7
	span.payload = payload
	map.packets["EMTP"].offsets.append(span.source_offset)
	map.packets["EMTP"].count += 1
	map.entities.append(span)

func _add_path(map: MapFile) -> void:
	var path := MapPath.new()
	path.path_index = map.paths.size()
	path.source_offset = 1000 + 100 * path.path_index
	var segment := MapPathSegment.new()
	segment.segment_type = 2
	segment.length = 160
	segment.source_offset = path.source_offset + 12
	segment.start = Vector3i.ZERO
	segment.end = Vector3i(10, 0, 0)
	path.segments.append(segment)
	map.packets["PATH"].offsets.append(path.source_offset)
	map.packets["PATH"].count += 1
	map.paths.append(path)

func _path_info(path_index: int, flags: int = 8) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(12)
	bytes.encode_u16(0, path_index)
	bytes.encode_u16(6, flags)
	bytes.encode_u16(8, 16)
	return bytes

func _trigger_payload(trigger_type: int) -> PackedByteArray:
	var payload: PackedByteArray = _matrix(60)
	payload.encode_u32(32, trigger_type)
	for index: int in 10:
		payload.encode_s16(36 + index * 2, -1 if index > 2 else -2 if index == 2 else 1632 + index)
	payload.encode_u32(56, 0xffffffff)
	return payload

func _setup(book: ThemeBook, map: MapFile) -> EntitySetup:
	var setup: EntitySetup = EntitySetup.from_map(map, book, "sky.map", 800, "pc-retail-v3.0e", true)
	assert_eq(setup.error, "")
	return setup

func test_catalog_capabilities_of_the_trigger() -> void:
	var behavior: EntityBehavior = EntityBehaviorCatalog.resolve("TRIGGER")
	assert_eq(behavior.kind, EntityBehavior.Kind.TRIGGER)
	assert_eq(behavior.layout, EntityBehavior.Layout.MATRIX)
	assert_true(behavior.immortal)
	assert_true(behavior.group_moving)
	assert_true(behavior.has_form_contact())
	assert_false(behavior.tongueable)
	assert_false(behavior.one_shot)
	assert_eq(behavior.payload_register_count, 0)
	behavior.execution = EntityBehavior.Execution.UPDATE
	assert_true(behavior.has_custom_update())

func test_trigger_payload_reads_type_and_ten_target_ids() -> void:
	var map: MapFile = _map()
	_add_entity(map, 0, 0, _trigger_payload(EntityTrigger.Type.BEGIN), 1673)
	var short: PackedByteArray = _trigger_payload(EntityTrigger.Type.BEGIN)
	short.resize(55)
	_add_entity(map, 0, 0, short, 2)
	_add_entity(map, 0, 0, _trigger_payload(4), 3)
	var setup: EntitySetup = _setup(_book(PackedStringArray(["TRIGGER"])), map)
	assert_eq(setup.definitions.size(), 1)
	if setup.definitions.is_empty():
		return
	var definition: EntityDefinition = setup.definitions[0]
	assert_eq(definition.behavior.kind, EntityBehavior.Kind.TRIGGER)
	assert_eq(definition.behavior.execution, EntityBehavior.Execution.UPDATE)
	assert_true(definition.behavior.has_custom_update())
	assert_eq(definition.trigger.trigger_type, EntityTrigger.Type.BEGIN)
	assert_eq(definition.trigger.target_ids, PackedInt32Array([1632, 1633, 65534, -1, -1, -1, -1, -1, -1, -1]))
	assert_eq(definition.matrix12.slice(9, 12), PackedInt32Array([100, -200, 300]))
	assert_eq(setup.diagnostics.size(), 2)
	assert_eq([setup.diagnostics[0].code, setup.diagnostics[0].entity_index], ["invalid_payload", 1])
	assert_string_contains(setup.diagnostics[0].message, "ten target IDs")
	assert_eq([setup.diagnostics[1].code, setup.diagnostics[1].entity_index], ["invalid_payload", 2])
	assert_string_contains(setup.diagnostics[1].message, "source range")
	setup = EntitySetup.from_map(map, _book(PackedStringArray(["TRIGGER"])), "sky.map", 800, "pc-retail-v3.0e")
	assert_true(setup.definitions.is_empty())
	assert_eq(setup.diagnostics[0].code, "unknown_behavior")

func test_trigger_callback_roles_require_trigger_behavior() -> void:
	for bonus: bool in [false, true]:
		var book: ThemeBook = _book(PackedStringArray(["STATIC"]))
		var form: FormBookEntry = book.entries[1].forms[0]
		if bonus:
			form.bonus_callback = 0x42ba00
		else:
			form.collision_callback = 0x42ba00
		var map: MapFile = _map()
		_add_entity(map, 0, 0, _trigger_payload(EntityTrigger.Type.BEGIN))
		var setup: EntitySetup = _setup(book, map)
		assert_true(setup.definitions.is_empty())
		assert_eq(setup.diagnostics[0].code, "incompatible_callback")
		form.entity_name = "TRIGGER"
		setup = _setup(book, map)
		assert_eq(setup.definitions.size(), 1)

func test_moving_platform_reads_plain_path_info_and_optional_initial_movement() -> void:
	var map: MapFile = _map()
	_add_path(map)
	_add_entity(map, 0, EntityDefinition.NO_MOVEMENT, _path_info(0), 1632)
	var volcano: PackedByteArray = _path_info(0)
	volcano.resize(16)
	volcano.encode_u32(12, 1)
	_add_entity(map, 0, 0, volcano, 2)
	var short: PackedByteArray = _path_info(0)
	short.resize(11)
	_add_entity(map, 0, 0, short, 3)
	var setup: EntitySetup = _setup(_book(PackedStringArray(["MOVING_PLATFORM"])), map)
	assert_eq(setup.definitions.size(), 2)
	if setup.definitions.size() != 2:
		return
	assert_eq(setup.definitions[0].volcano.initial_movement, 0)
	assert_eq(setup.definitions[0].flags, EntityDefinition.NO_MOVEMENT)
	assert_eq(setup.definitions[0].path_start.flags & PathStart.ACTIVE, 0)
	assert_eq(setup.definitions[1].volcano.initial_movement, 1)
	assert_eq(setup.diagnostics.size(), 1)
	assert_eq([setup.diagnostics[0].code, setup.diagnostics[0].entity_index], ["invalid_payload", 2])

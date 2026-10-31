extends GutTest
## Synthetic Swamp capabilities, FrogLord payload decoding, run validation, register payloads and level scope.

const MATRIX_NAMES: PackedStringArray = ["SWP_SQUIRT", "SWP_CRUSHER", "SWP_PRESS", "SWP_RAT", "SWP_STAT_WEIR"]
const PATH_NAMES: PackedStringArray = ["SWP_SLUG", "NUCLEAR_BARREL"]

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

func _rat_payload(speed: int = 60, start_run: Vector3i = Vector3i(400, -600, 200)) -> PackedByteArray:
	var payload: PackedByteArray = _matrix(68)
	payload.encode_s16(32, speed)
	payload.encode_s16(34, 0x7777)
	var targets: Array[Vector3i] = [Vector3i(100, -600, 200), start_run, Vector3i(393, -600, 150), Vector3i(453, 0, 150)]
	for index: int in 4:
		var offset: int = 36 + index * 8
		payload.encode_s16(offset, targets[index].x)
		payload.encode_s16(offset + 2, targets[index].y)
		payload.encode_s16(offset + 4, targets[index].z)
		payload.encode_s16(offset + 6, -1)
	return payload

func _slug_payload(motion_type: int) -> PackedByteArray:
	var payload: PackedByteArray = _path_info(0)
	payload.resize(16)
	payload.encode_u32(12, motion_type)
	return payload

func _setup(book: ThemeBook, map: MapFile) -> EntitySetup:
	var setup: EntitySetup = EntitySetup.from_map(map, book, "swp.map", 700, "pc-retail-v3.0e", true)
	assert_eq(setup.error, "")
	return setup

func test_catalog_capabilities_of_the_seven_swamp_names() -> void:
	var kinds: Array[EntityBehavior.Kind] = [EntityBehavior.Kind.SWP_SQUIRT, EntityBehavior.Kind.SWP_CRUSHER, EntityBehavior.Kind.SWP_PRESS, EntityBehavior.Kind.SWP_RAT, EntityBehavior.Kind.SWP_STAT_WEIR, EntityBehavior.Kind.SWP_SLUG, EntityBehavior.Kind.NUCLEAR_BARREL]
	var names: PackedStringArray = MATRIX_NAMES + PATH_NAMES
	for index: int in names.size():
		var label: String = names[index]
		var behavior: EntityBehavior = EntityBehaviorCatalog.resolve(label)
		var path: bool = label in PATH_NAMES
		assert_eq(behavior.kind, kinds[index], label)
		assert_eq(behavior.layout, EntityBehavior.Layout.PATH if path else EntityBehavior.Layout.MATRIX, label)
		assert_true(behavior.immortal, label)
		assert_eq(behavior.group_moving, label != "SWP_STAT_WEIR", label)
		assert_true(behavior.has_form_contact(), label)
		assert_false(behavior.tongueable, label)
		assert_false(behavior.one_shot, label)
		assert_eq(behavior.payload_register_count, 0, label)
		behavior.execution = EntityBehavior.Execution.UPDATE
		assert_eq(behavior.has_custom_update(), not path, label)

func test_matrix_kinds_update_and_require_custom_behaviors() -> void:
	var map: MapFile = _map()
	var book: ThemeBook = _book(MATRIX_NAMES)
	var squirt: PackedByteArray = _matrix(44)
	squirt.encode_s16(34, 1)
	var payloads: Array[PackedByteArray] = [squirt, _matrix(40), _matrix(40), _rat_payload(), _matrix()]
	for index: int in payloads.size():
		_add_entity(map, index, 0, payloads[index], index + 1)
	var setup: EntitySetup = _setup(book, map)
	assert_eq(setup.definitions.size(), 5)
	assert_eq(setup.diagnostics.size(), 0)
	for definition: EntityDefinition in setup.definitions:
		assert_eq(definition.behavior.execution, EntityBehavior.Execution.UPDATE, definition.entity_name)
		assert_true(definition.behavior.has_custom_update(), definition.entity_name)
		assert_eq(definition.swamp == null, definition.behavior.kind == EntityBehavior.Kind.SWP_STAT_WEIR, definition.entity_name)
	setup = EntitySetup.from_map(map, book, "swp.map", 700, "pc-retail-v3.0e")
	assert_true(setup.definitions.is_empty())
	assert_eq(setup.diagnostics[0].code, "unknown_behavior")

func test_squirt_payload_reads_signed_operands_and_rejects_zero_drop_time() -> void:
	var map: MapFile = _map()
	var payload: PackedByteArray = _matrix(44)
	payload.encode_s16(32, -5)
	payload.encode_s16(34, 30)
	payload.encode_s16(36, -32768)
	payload.encode_s16(38, 32767)
	payload.encode_s16(40, -1)
	payload.encode_s16(42, 99)
	_add_entity(map, 0, 0, payload, 1)
	var short: PackedByteArray = payload.duplicate()
	short.resize(43)
	_add_entity(map, 0, 0, short, 2)
	var zero: PackedByteArray = payload.duplicate()
	zero.encode_s16(34, 0)
	_add_entity(map, 0, 0, zero, 3)
	var setup: EntitySetup = _setup(_book(PackedStringArray(["SWP_SQUIRT"])), map)
	assert_eq(setup.definitions.size(), 1)
	if setup.definitions.is_empty():
		return
	var swamp: EntitySwampDefinition = setup.definitions[0].swamp
	assert_eq([swamp.time_delay, swamp.drop_time, swamp.target], [-5, 30, Vector3i(-32768, 32767, -1)])
	assert_eq(setup.definitions[0].matrix12.slice(9, 12), PackedInt32Array([100, -200, 300]))
	assert_eq(setup.diagnostics.size(), 2)
	assert_eq([setup.diagnostics[0].code, setup.diagnostics[0].entity_index], ["invalid_payload", 1])
	assert_eq([setup.diagnostics[1].code, setup.diagnostics[1].entity_index], ["invalid_payload", 2])
	assert_string_contains(setup.diagnostics[1].message, "drop time")

func test_crusher_and_press_read_signed_operands() -> void:
	var map: MapFile = _map()
	for form_id: int in 2:
		var payload: PackedByteArray = _matrix(40)
		payload.encode_s16(32, -7 - form_id)
		payload.encode_s16(34, 512)
		payload.encode_s16(36, 3)
		payload.encode_s16(38, -32768)
		_add_entity(map, form_id, 0, payload, form_id + 1)
		var short: PackedByteArray = payload.duplicate()
		short.resize(39)
		_add_entity(map, form_id, 0, short, form_id + 10)
	var setup: EntitySetup = _setup(_book(PackedStringArray(["SWP_CRUSHER", "SWP_PRESS"])), map)
	assert_eq(setup.definitions.size(), 2)
	if setup.definitions.size() != 2:
		return
	for index: int in 2:
		var swamp: EntitySwampDefinition = setup.definitions[index].swamp
		assert_eq([swamp.speed, swamp.distance, swamp.direction, swamp.delay], [-7 - index, 512, 3, -32768])
	assert_eq(setup.definitions[1].behavior.kind, EntityBehavior.Kind.SWP_PRESS)
	assert_eq(setup.diagnostics.size(), 2)
	for diagnostic: EntitySetupDiagnostic in setup.diagnostics:
		assert_eq(diagnostic.code, "invalid_payload")
	assert_eq([setup.diagnostics[0].entity_index, setup.diagnostics[1].entity_index], [1, 3])

func test_rat_payload_reads_targets_and_resolves_creation_timing() -> void:
	var map: MapFile = _map()
	_add_entity(map, 0, 0, _rat_payload(), 1)
	var short: PackedByteArray = _rat_payload()
	short.resize(67)
	_add_entity(map, 0, 0, short, 2)
	_add_entity(map, 0, 0, _rat_payload(60, Vector3i(129, -600, 200)), 3)
	_add_entity(map, 0, 0, _rat_payload(29), 4)
	var setup: EntitySetup = _setup(_book(PackedStringArray(["SWP_RAT"])), map)
	assert_eq(setup.definitions.size(), 1)
	if setup.definitions.is_empty():
		return
	var swamp: EntitySwampDefinition = setup.definitions[0].swamp
	assert_eq(swamp.rat_speed, 60)
	assert_eq(swamp.rat_targets, [Vector3i(100, -600, 200), Vector3i(400, -600, 200), Vector3i(393, -600, 150), Vector3i(453, 0, 150)] as Array[Vector3i])
	assert_eq([swamp.run_speed, swamp.jump1_time, swamp.jump1_velocity_4, swamp.jump1_sine_step], [2, 10, Vector3i(480, 0, 0), 204])
	assert_eq([swamp.run_time, swamp.run_velocity_4], [25, Vector3i(-4, 0, -32)])
	assert_eq([swamp.jump2_time, swamp.jump2_velocity_4, swamp.jump2_sine_step], [20, Vector3i(48, 480, 0), 102])
	assert_eq(setup.definitions[0].matrix12.slice(9, 12), PackedInt32Array([100, -200, 300]), "Setup keeps the authored matrix; creation moves it")
	assert_eq(setup.diagnostics.size(), 3)
	for diagnostic: EntitySetupDiagnostic in setup.diagnostics:
		assert_eq(diagnostic.code, "invalid_payload")
		assert_eq(diagnostic.source_id, "swp.map")
	assert_eq([setup.diagnostics[0].entity_index, setup.diagnostics[1].entity_index, setup.diagnostics[2].entity_index], [1, 2, 3])
	assert_string_contains(setup.diagnostics[1].message, "zero duration")

func test_slug_reads_its_unsigned_motion_type_and_barrel_reads_path_info_alone() -> void:
	var map: MapFile = _map()
	_add_path(map)
	_add_entity(map, 0, 0, _slug_payload(4294967295), 1)
	_add_entity(map, 0, 0, _path_info(0), 2)
	_add_entity(map, 1, 0, _path_info(0), 3)
	var setup: EntitySetup = _setup(_book(PATH_NAMES), map)
	assert_eq(setup.definitions.size(), 2)
	if setup.definitions.size() != 2:
		return
	assert_eq(setup.definitions[0].swamp.motion_type, 4294967295)
	assert_not_null(setup.definitions[0].path_start)
	assert_eq(setup.definitions[1].behavior.kind, EntityBehavior.Kind.NUCLEAR_BARREL)
	assert_null(setup.definitions[1].swamp)
	for definition: EntityDefinition in setup.definitions:
		assert_eq(definition.behavior.execution, EntityBehavior.Execution.TRANSFORM)
		assert_false(definition.behavior.has_custom_update())
	assert_eq(setup.diagnostics.size(), 1)
	assert_eq([setup.diagnostics[0].code, setup.diagnostics[0].entity_index], ["invalid_payload", 1])

func test_weir_rotation_replaces_the_authored_rotation_and_keeps_translation() -> void:
	var map: MapFile = _map()
	var payload: PackedByteArray = _matrix()
	payload.encode_s16(2, 1234)
	payload.encode_s16(8, -77)
	_add_entity(map, 0, 0, payload)
	var setup: EntitySetup = _setup(_book(PackedStringArray(["SWP_STAT_WEIR"])), map)
	assert_eq(setup.definitions.size(), 1)
	if setup.definitions.is_empty():
		return
	assert_eq(setup.definitions[0].matrix12, PackedInt32Array([0, -4096, 0, 4096, 0, 0, 0, 0, 4096, 100, -200, 300]))
	assert_eq(EntitySetup.weir_matrix(PackedInt32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, -1, -2, -3])), PackedInt32Array([0, -4096, 0, 4096, 0, 0, 0, 0, 4096, -1, -2, -3]))

func test_run_requires_rat_and_curvy_slug_actions_and_selects_the_slug_bend() -> void:
	var map: MapFile = _map()
	_add_path(map)
	_add_entity(map, 0, 0, _rat_payload(), 1)
	_add_entity(map, 1, 0, _slug_payload(EntitySwampDefinition.SLUG_CURVY), 2)
	_add_entity(map, 1, 0, _slug_payload(0), 3)
	var setup: EntitySetup = _setup(_book(PackedStringArray(["SWP_RAT", "SWP_SLUG"])), map)
	assert_eq(setup.definitions.size(), 3)
	if setup.definitions.size() != 3:
		return
	var rat: EntityDefinition = setup.definitions[0]
	var curvy: EntityDefinition = setup.definitions[1]
	var straight: EntityDefinition = setup.definitions[2]
	rat.action_lengths = PackedInt32Array([4, 4])
	curvy.action_lengths = PackedInt32Array([3, 5])
	straight.action_lengths = PackedInt32Array([3, 5])
	assert_string_contains(EntityRun.create([rat]).error, "rat")
	rat.action_lengths = PackedInt32Array([4, 4, 4])
	var run: EntityRun = EntityRun.create([rat, curvy, straight])
	assert_eq(run.error, "")
	if not run.error.is_empty():
		return
	var entities: Array[EntitySnapshot] = run.snapshot().entities
	assert_eq(entities[0].custom_state.mode, EntitySwampRat.Mode.RESTART)
	assert_eq(entities[0].matrix12.slice(9, 12), PackedInt32Array([100, -600, 200]))
	assert_eq(entities[1].animation.action, EntitySwampDefinition.SLUG_CURVY)
	assert_eq(entities[2].animation.action, 0)
	curvy.action_lengths = PackedInt32Array([3])
	assert_string_contains(EntityRun.create([curvy]).error, "slug")
	straight.action_lengths = PackedInt32Array([3])
	assert_eq(EntityRun.create([straight]).error, "")
	rat.swamp = null
	assert_ne(EntityRun.create([rat]).error, "")

func _names() -> NameBank:
	return NameBank.from_list_config(FrogLordConfig.parse_legacy("SCRIPT_NONE\n[CallbackNames]\nSCRIPT_CB_HIT_TURTLE\n"), false, "Script")

func _table(names: NameBank, offset: int, count: int) -> ScriptTable:
	var table := ScriptTable.new()
	var script_entry := EntityScript.new()
	script_entry.id = 0
	script_entry.name = names.name_of(0)
	var prepare := EntityScript.Command.new()
	prepare.opcode = 31
	prepare.arguments = PackedInt32Array([offset, count])
	var stop := EntityScript.Command.new()
	stop.opcode = 38
	script_entry.commands = [prepare, stop]
	table.scripts.append(script_entry)
	return table

func _registers(offset: int, count: int, label: String) -> EntityScriptSetup:
	var names: NameBank = _names()
	var payload := PackedByteArray()
	payload.resize(64)
	for index: int in 13:
		payload.encode_s32(index * 4, index - 6)
	return EntityScriptSetup.from_tables(_table(names, offset, count), names, 0, EntityBehaviorCatalog.resolve(label), payload)

func _definition(offset: int, count: int) -> EntityScriptDefinition:
	var definition := EntityScriptDefinition.new()
	definition.root_id = 0
	definition.programs[0] = PackedInt32Array([31, offset, count, 38])
	definition.names[0] = "SCRIPT_NONE"
	definition.payload_offset = offset
	for index: int in count:
		definition.payload_registers.append(index)
	return definition

func test_register_payload_follows_the_layout_offset_with_one_to_six_registers() -> void:
	var path: EntityScriptSetup = _registers(12, 2, "SWP_SLUG")
	assert_eq(path.error, "")
	assert_eq(path.definition.payload_registers, PackedInt32Array([-3, -2]))
	assert_eq(path.definition.validate(PackedInt32Array(), 0, true), "")
	var matrix: EntityScriptSetup = _registers(32, 1, "SWP_SQUIRT")
	assert_eq(matrix.error, "")
	assert_eq(matrix.definition.payload_registers, PackedInt32Array([2]))
	assert_eq(matrix.definition.validate(PackedInt32Array(), 0, false), "")
	assert_eq(_registers(32, 6, "SWP_RAT").error, "")
	for rejected: Array in [[16, 2, "SWP_SLUG"], [12, 0, "SWP_SLUG"], [12, 7, "SWP_SLUG"], [32, 2, "SWP_SLUG"], [12, 1, "SWP_SQUIRT"], [32, 0, "SWP_SQUIRT"], [32, 7, "SWP_SQUIRT"]]:
		var offset: int = rejected[0]
		var count: int = rejected[1]
		var label: String = rejected[2]
		assert_ne(_registers(offset, count, label).error, "", str(rejected))
	assert_eq(_definition(12, 2).validate(PackedInt32Array(), 0, true), "")
	assert_eq(_definition(32, 1).validate(PackedInt32Array(), 0, false), "")
	for rejected: Array in [[16, 2, true], [12, 0, true], [12, 7, true], [32, 2, true], [12, 1, false], [32, 7, false]]:
		var offset: int = rejected[0]
		var count: int = rejected[1]
		var has_path: bool = rejected[2]
		assert_ne(_definition(offset, count).validate(PackedInt32Array(), 0, has_path), "", str(rejected))

func test_swamp_levels_are_supported_without_multiplayer() -> void:
	for code: String in ["SWP1", "SWP2", "SWP3", "SWP4", "SWP5"]:
		assert_true(GameplaySetup.supports_level(FroggerIds.level_from_code(code)), code)
	assert_false(GameplaySetup.supports_level(FroggerIds.level_from_code("SWPM")))

extends GutTest
## Bounded source setup retains geometric contact while diagnosing reaction limits.

func _map() -> MapFile:
	var map := MapFile.new()
	map.general.theme = 1
	map.group_base = Vector3i(-1024, 0, -1024)
	map.group_dimensions = Vector2i(4, 4)
	map.group_size = Vector2i(512, 512)
	for group_index: int in 16:
		var group := MapGroup.new()
		group.counts = PackedInt32Array([1 if group_index == 3 else 0, 0, 2 if group_index == 3 else 0, 0, 0, 0, 0, 0, 7])
		map.groups.append(group)
	var entity_packet := MapPacket.new()
	entity_packet.identifier = "EMTP"
	entity_packet.count = 1
	entity_packet.offsets.append(100)
	map.packets["EMTP"] = entity_packet
	var path_packet := MapPacket.new()
	path_packet.identifier = "PATH"
	map.packets["PATH"] = path_packet
	var form_packet := MapPacket.new()
	form_packet.identifier = "FORM"
	form_packet.count = 1
	form_packet.offsets.append(500)
	map.packets["FORM"] = form_packet
	var span := MapEntitySpan.new()
	span.source_offset = 100
	span.end_offset = 156
	span.form_grid_id = 0
	span.form_id = 0
	span.unique_id = 12
	span.payload.resize(32)
	for axis: int in 3:
		span.payload.encode_s16((axis * 3 + axis) * 2, 4096)
	map.entities.append(span)
	var grid := MapForm.new()
	grid.source_offset = 500
	grid.end_offset = 600
	grid.data_count = 1
	grid.dimensions = Vector2i(5, 1)
	grid.offsets = Vector2i(-640, -128)
	var form_data := MapFormData.new()
	form_data.height = -64
	form_data.grid_flags = PackedInt32Array([4097, 5, 3, 65, 33])
	grid.data.append(form_data)
	map.forms.append(grid)
	return map

func _book() -> ThemeBook:
	var book := ThemeBook.new()
	for theme: int in FroggerIds.THEMES.size():
		var theme_entry := ThemeBookEntry.new()
		theme_entry.theme = theme
		book.entries.append(theme_entry)
	var form := FormBookEntry.new()
	form.theme = 1
	form.local_id = 0
	form.form_name = "TEST_CACTUS"
	form.entity_name = "STATIC"
	form.death_type = 5
	book.entries[1].forms.append(form)
	return book

func _model() -> MofFile:
	var file := MofFile.new()
	file.kind = MofFile.Kind.STATIC
	var model := MofStatic.new()
	var part := MofPart.new()
	var cel := MofPart.Partcel.new()
	cel.bounding_box.resize(24)
	cel.bounding_box[22] = 64
	part.partcels.append(cel)
	model.parts.append(part)
	file.static_models.append(model)
	return file

func test_group_and_form_facts_are_detached_with_source_diagnostics() -> void:
	var map: MapFile = _map()
	var book: ThemeBook = _book()
	var models: Dictionary[int, MofFile] = {0: _model()}
	var setup: EntityCollisionSetup = EntityCollisionSetup.from_map(map, book, models, "TEST", 77, "fixture")
	assert_eq(setup.error, "")
	assert_not_null(setup.definition)
	assert_eq(setup.definition.group_base, map.group_base)
	assert_eq(setup.definition.group_dimensions, map.group_dimensions)
	assert_eq(setup.definition.group_size, map.group_size)
	assert_eq(setup.definition.entities.size(), 1)
	assert_eq(setup.definition.contacts[0].death_type, 5)
	assert_eq(setup.definition.contacts[0].unsupported_reason, "")
	assert_eq(setup.definition.contacts[0].reaction_unsupported_reason, "")
	var unsupported: int = 0
	for diagnostic: EntitySetupDiagnostic in setup.diagnostics:
		if diagnostic.code == "unsupported_form_reaction":
			unsupported += 1
			assert_eq(diagnostic.source_offset, 100)
			assert_eq(diagnostic.resource_id, 77)
	assert_eq(unsupported, 3, "Safe, checkpoint and bounce cells need explicit diagnostics")
	map.forms[0].data[0].grid_flags[0] = 0
	assert_eq(setup.definition.contacts[0].grid_flags[0], 4097)

func test_script_excludes_reaction_only_and_bonus_callback_is_warning() -> void:
	var book: ThemeBook = _book()
	book.entries[1].forms[0].script_id = 8
	book.entries[1].forms[0].bonus_callback = 0x1234
	var models: Dictionary[int, MofFile] = {0: _model()}
	var setup: EntityCollisionSetup = EntityCollisionSetup.from_map(_map(), book, models)
	assert_eq(setup.error, "")
	assert_eq(setup.definition.contacts[0].unsupported_reason, "")
	assert_string_contains(setup.definition.contacts[0].reaction_unsupported_reason, "script")
	var codes := PackedStringArray()
	for diagnostic: EntitySetupDiagnostic in setup.diagnostics:
		codes.append(diagnostic.code)
	assert_true(codes.has("unexecuted_entity_script"))
	assert_true(codes.has("unexecuted_bonus_callback"))
	book.entries[1].forms[0].script_id = 0
	setup = EntityCollisionSetup.from_map(_map(), book, models)
	assert_eq(setup.definition.contacts[0].reaction_unsupported_reason, "")

func test_visibility_setup_copies_eight_terrain_counts_and_rejects_only_authored_zones() -> void:
	var map: MapFile = _map()
	var setup: EntityCollisionSetup = EntityCollisionSetup.from_map(map, _book(), {0: _model()}, "TEST", 77, "fixture", false, true)
	assert_eq(setup.error, "")
	assert_not_null(setup.definition.lifecycle)
	assert_eq(setup.definition.lifecycle.group_base, map.group_base)
	assert_eq(setup.definition.lifecycle.polygon_counts.size(), 16)
	assert_eq(setup.definition.lifecycle.polygon_counts[3], 3, "G2 is excluded from the source scan budget")
	map.groups[3].counts[0] = 9
	assert_eq(setup.definition.lifecycle.polygon_counts[3], 3)
	var zone := MapPacket.new()
	zone.count = 1
	map.packets["ZONE"] = zone
	assert_string_contains(EntityCollisionSetup.from_map(map, _book(), {0: _model()}, "TEST", 77, "fixture", false, true).error, "zones")
	assert_eq(EntityCollisionSetup.from_map(map, _book(), {0: _model()}).error, "")

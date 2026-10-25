extends GutTest
## Synthetic shared FORM writers and bounded contact setup decisions.

func _book() -> ThemeBook:
	var book := ThemeBook.new()
	for theme: int in FroggerIds.THEMES.size():
		var entry := ThemeBookEntry.new()
		entry.theme = theme
		book.entries.append(entry)
	for index: int in 2:
		var form := FormBookEntry.new()
		form.theme = 1
		form.local_id = index
		form.form_name = "TEST_%d" % index
		form.entity_name = "MOVING"
		book.entries[1].forms.append(form)
	return book

func _model(top_y: int, primitive: bool = false) -> MofFile:
	var model := MofFile.new()
	model.kind = MofFile.Kind.STATIC
	var static_model := MofStatic.new()
	var part := MofPart.new()
	var cel := MofPart.Partcel.new()
	cel.bounding_box.resize(24)
	cel.bounding_box[22] = top_y
	part.partcels.append(cel)
	if primitive:
		part.collprims.append(MofPart.Collprim.new())
	static_model.parts.append(part)
	model.static_models.append(static_model)
	return model

func _map() -> MapFile:
	var map := MapFile.new()
	map.general.theme = 1
	var form_packet := MapPacket.new()
	form_packet.identifier = "FORM"
	form_packet.count = 1
	form_packet.offsets.append(500)
	map.packets["FORM"] = form_packet
	var entity_packet := MapPacket.new()
	entity_packet.identifier = "EMTP"
	map.packets["EMTP"] = entity_packet
	var grid := MapForm.new()
	grid.form_index = 0
	grid.source_offset = 500
	grid.end_offset = 600
	grid.data_count = 1
	grid.dimensions = Vector2i(1, 2)
	grid.offsets = Vector2i(-128, -256)
	var data := MapFormData.new()
	data.height_type = 0
	data.height = -90
	data.grid_flags = PackedInt32Array([3, 3])
	grid.data.append(data)
	map.forms.append(grid)
	return map

func _authored(map: MapFile, form_id: int, unique_id: int) -> EntityDefinition:
	var index: int = map.entities.size()
	var span := MapEntitySpan.new()
	span.source_offset = 100 + index * 40
	span.form_grid_id = 0
	span.form_id = form_id
	span.unique_id = unique_id
	map.entities.append(span)
	map.packets["EMTP"].count += 1
	map.packets["EMTP"].offsets.append(span.source_offset)
	var entity := EntityDefinition.new()
	entity.entity_index = index
	entity.source_offset = span.source_offset
	entity.form_grid_id = span.form_grid_id
	entity.form_id = form_id
	entity.form_name = "TEST_%d" % form_id
	entity.entity_name = "MOVING"
	entity.unique_id = unique_id
	return entity

func test_shared_last_writer_includes_omitted_neighbor_and_identity_gaps() -> void:
	var map: MapFile = _map()
	var first: EntityDefinition = _authored(map, 0, 7)
	_authored(map, 1, 7) # Absent from base setup, but still writes shared max Y.
	var book: ThemeBook = _book()
	var models: Dictionary[int, MofFile] = {0: _model(20), 1: _model(40)}
	var setup: FormContactSetup = FormContactSetup.from_map(map, book, [first], models, "ORG1", 658, "pc-retail-v3.0e")
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 1)
	assert_eq(setup.definitions[0].entity_index, 0)
	assert_eq(setup.definitions[0].unique_id, 7)
	assert_eq(setup.definitions[0].max_y, 40)
	assert_eq(setup.definitions[0].radius_squared, 500)
	assert_eq(setup.definitions[0].height, -90)
	assert_eq(setup.definitions[0].grid_flags, PackedInt32Array([3, 3]))
	assert_eq(setup.definitions[0].unsupported_reason, "")
	map.forms[0].data[0].grid_flags[0] = 1
	assert_eq(setup.definitions[0].grid_flags[0], 3)
	var detached: FormContactDefinition = setup.definitions[0].copy()
	setup.definitions[0].grid_flags[0] = 2
	assert_eq(detached.grid_flags[0], 3)

func test_thick_precedes_unit_and_explicit_radius_is_kept() -> void:
	var map: MapFile = _map()
	var first: EntityDefinition = _authored(map, 0, 8)
	var book: ThemeBook = _book()
	book.entries[1].forms[0].flags = FormBookEntry.FLAG_THICK | FormBookEntry.FLAG_UNIT_FORM
	book.entries[1].forms[0].radius_squared = 12345
	var models: Dictionary[int, MofFile] = {0: _model(20)}
	var setup: FormContactSetup = FormContactSetup.from_map(map, book, [first], models)
	assert_eq(setup.definitions[0].max_y, 0x7fff)
	assert_eq(setup.definitions[0].radius_squared, 12345)

func test_no_model_form_still_writes_shared_maximum_when_mof_is_loaded() -> void:
	var map: MapFile = _map()
	var first: EntityDefinition = _authored(map, 0, 8)
	_authored(map, 1, 9)
	var book: ThemeBook = _book()
	book.entries[1].forms[1].flags = FormBookEntry.FLAG_NO_MODEL
	var models: Dictionary[int, MofFile] = {0: _model(20), 1: _model(50)}
	var setup: FormContactSetup = FormContactSetup.from_map(map, book, [first], models)
	assert_eq(setup.definitions[0].unsupported_reason, "")
	assert_eq(setup.definitions[0].max_y, 50)

func test_multiple_data_records_use_first_with_diagnostic() -> void:
	var map: MapFile = _map()
	var first: EntityDefinition = _authored(map, 0, 1)
	map.forms[0].data_count = 2
	var second := MapFormData.new()
	second.height = 999
	second.grid_flags = PackedInt32Array([1, 1])
	map.forms[0].data.append(second)
	var models: Dictionary[int, MofFile] = {0: _model(20)}
	var setup: FormContactSetup = FormContactSetup.from_map(map, _book(), [first], models)
	assert_eq(setup.definitions[0].unsupported_reason, "")
	assert_eq(setup.definitions[0].height, -90)
	assert_eq(setup.diagnostics[0].code, "additional_form_data")

func test_primitive_callback_and_missing_writer_exclude_contact_only() -> void:
	var map: MapFile = _map()
	var first: EntityDefinition = _authored(map, 0, 9)
	var book: ThemeBook = _book()
	var models: Dictionary[int, MofFile] = {0: _model(20, true)}
	var setup: FormContactSetup = FormContactSetup.from_map(map, book, [first], models)
	assert_string_contains(setup.definitions[0].unsupported_reason, "primitives")
	assert_eq(setup.diagnostics.size(), 1)
	assert_eq(setup.diagnostics[0].entity_index, 0)
	models[0] = _model(20)
	book.entries[1].forms[0].collision_callback = 0x1234
	setup = FormContactSetup.from_map(map, book, [first], models)
	assert_string_contains(setup.definitions[0].unsupported_reason, "callback")
	book.entries[1].forms[0].collision_callback = 0
	_authored(map, 1, 10)
	setup = FormContactSetup.from_map(map, book, [first], models)
	assert_string_contains(setup.definitions[0].unsupported_reason, "unavailable")
	assert_eq(map.forms[0].data[0].grid_flags, PackedInt32Array([3, 3]))

func test_unsupported_grid_and_invalid_source_identity_are_visible() -> void:
	var map: MapFile = _map()
	var first: EntityDefinition = _authored(map, 0, 1)
	var models: Dictionary[int, MofFile] = {0: _model(20)}
	map.forms[0].data[0].height_type = 2
	var setup: FormContactSetup = FormContactSetup.from_map(map, _book(), [first], models)
	assert_string_contains(setup.definitions[0].unsupported_reason, "height mode")
	map.forms[0].data[0].height_type = 0
	first.source_offset += 1
	assert_string_contains(FormContactSetup.from_map(map, _book(), [first], models).error, "identity")

func test_primitive_opt_in_keeps_form_fallback_and_rejects_unsupported_shape() -> void:
	var map: MapFile = _map()
	var entity: EntityDefinition = _authored(map, 0, 9)
	var model: MofFile = _model(20, true)
	var source: MofPart.Collprim = model.static_models[0].parts[0].collprims[0]
	source.flags = MofPart.COLLPRIM_LAST
	source.size = Vector3i(80, 50, 100)
	source.user = 1
	var models: Dictionary[int, MofFile] = {0: model}
	var setup: FormContactSetup = FormContactSetup.from_map(map, _book(), [entity], models, "", -1, "", true)
	var contact: FormContactDefinition = setup.definitions[0]
	assert_eq(contact.unsupported_reason, "")
	assert_eq(contact.primitives.size(), 1)
	assert_eq(contact.radius_squared, 500)
	assert_eq(contact.max_y, 20)
	assert_true(contact.has_form_data)
	assert_eq(contact.height, -90)
	assert_eq(contact.grid_flags, PackedInt32Array([3, 3]))
	source.size.x = 1
	assert_eq(contact.primitives[0].half_size.x, 80)
	source.type = 4
	setup = FormContactSetup.from_map(map, _book(), [entity], models, "", -1, "", true)
	assert_false(setup.definitions[0].unsupported_reason.is_empty())
	assert_true(setup.definitions[0].primitives.is_empty())

func test_invalid_grid_id_excludes_one_contact_without_hiding_neighbor() -> void:
	var map: MapFile = _map()
	var invalid: EntityDefinition = _authored(map, 0, 3)
	var valid: EntityDefinition = _authored(map, 0, 3)
	map.entities[0].form_grid_id = 2
	invalid.form_grid_id = 2
	var models: Dictionary[int, MofFile] = {0: _model(20)}
	var setup: FormContactSetup = FormContactSetup.from_map(map, _book(), [invalid, valid], models)
	assert_eq(setup.error, "")
	assert_eq(setup.definitions.size(), 2)
	assert_string_contains(setup.definitions[0].unsupported_reason, "invalid FORM")
	assert_eq(setup.definitions[1].unsupported_reason, "")
	assert_eq(setup.definitions[1].entity_index, 1)

func test_primitive_only_model_admits_absent_form_data_but_not_malformed_records() -> void:
	var map: MapFile = _map()
	var entity: EntityDefinition = _authored(map, 0, 9)
	var model: MofFile = _model(20, true)
	var primitive: MofPart.Collprim = model.static_models[0].parts[0].collprims[0]
	primitive.flags = MofPart.COLLPRIM_LAST
	primitive.size = Vector3i(80, 50, 100)
	primitive.user = 1
	var models: Dictionary[int, MofFile] = {0: model}
	map.forms[0].data_count = 0
	map.forms[0].data.clear()
	var setup: FormContactSetup = FormContactSetup.from_map(map, _book(), [entity], models, "", -1, "", true)
	var contact: FormContactDefinition = setup.definitions[0]
	assert_eq(contact.unsupported_reason, "")
	assert_false(contact.has_form_data)
	assert_eq(contact.primitives.size(), 1)
	assert_eq(contact.radius_squared, 500)
	assert_true(contact.grid_flags.is_empty())
	assert_false(contact.copy().has_form_data)
	map.forms[0].data_count = 1
	setup = FormContactSetup.from_map(map, _book(), [entity], models, "", -1, "", true)
	assert_string_contains(setup.definitions[0].unsupported_reason, "no usable data")
	map.forms[0].data_count = 0
	models.clear()
	setup = FormContactSetup.from_map(map, _book(), [entity], models, "", -1, "", true)
	assert_false(setup.definitions[0].unsupported_reason.is_empty())

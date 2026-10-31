extends RetailTest
## Final-PC FORM records and ORG1 small-log setup against independent text facts.

var _data: GameData

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func _digest(values: PackedInt64Array) -> String:
	return GoldenFiles.list_digest(values) if not values.is_empty() else "-"

func test_every_form_record_matches_independent_facts() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("forms_retail.tsv")
	rows.pop_front()
	assert_eq(rows.size(), 78)
	var problems := PackedStringArray()
	for row: PackedStringArray in rows:
		var map: MapFile = _data.read_map(int(row[0]), problems)
		assert_not_null(map, row[1])
		if map == null:
			continue
		var form_values := PackedInt64Array()
		var data_values := PackedInt64Array()
		var flags_values := PackedInt64Array()
		var data_count: int = 0
		for form: MapForm in map.forms:
			form_values.append_array(PackedInt64Array([form.form_index, form.source_offset,
				form.data_count, form.stored_max_y, form.dimensions.x, form.dimensions.y,
				form.offsets.x, form.offsets.y]))
			for index: int in form.data.size():
				var entry: MapFormData = form.data[index]
				data_values.append_array(PackedInt64Array([form.form_index, index,
					entry.source_offset, entry.height_type, entry.height,
					entry.flags_pointer, entry.heights_pointer]))
				for flag: int in entry.grid_flags:
					flags_values.append(flag)
				data_count += 1
		var observed := PackedStringArray([row[0], row[1], str(map.forms.size()),
			str(data_count), _digest(form_values), _digest(data_values), _digest(flags_values)])
		assert_eq(observed, row, row[1])
	assert_eq(problems.size(), 0, "\n".join(problems))

func test_org1_small_log_contact_setup_matches_independent_facts() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("form_contacts_retail.tsv")
	rows.pop_front()
	assert_eq(rows.size(), 6)
	var problems := PackedStringArray()
	var map: MapFile = _data.read_map(658, problems)
	assert_not_null(map)
	if map == null:
		return
	var entities: EntitySetup = EntitySetup.from_map(map, _data.tables.theme_book(), "ORG1", 658, "pc-retail-v3.0e")
	assert_eq(entities.error, "")
	var setup: FormContactSetup = FormContactSetup.from_data(_data, 24, false, entities.definitions)
	assert_eq(setup.error, "")
	if not setup.error.is_empty():
		return
	var by_index: Dictionary[int, FormContactDefinition] = {}
	for definition: FormContactDefinition in setup.definitions:
		by_index[definition.entity_index] = definition
	for row: PackedStringArray in rows:
		var index: int = int(row[2])
		assert_true(by_index.has(index), "ORG1 entity %d" % index)
		if not by_index.has(index):
			continue
		var definition: FormContactDefinition = by_index[index]
		var form: MapForm = map.forms[definition.form_grid_id]
		var flags := PackedInt64Array()
		for flag: int in definition.grid_flags:
			flags.append(flag)
		var observed := PackedStringArray([str(definition.resource_id), "ORG1.MAP",
			str(definition.entity_index), str(definition.source_offset), str(definition.unique_id),
			str(definition.form_grid_id), str(definition.form_id), definition.form_name,
			str(definition.entity_flags), str(form.source_offset), str(definition.dimensions.x),
			str(definition.dimensions.y), str(definition.offsets.x), str(definition.offsets.y),
			str(definition.height), str(definition.max_y), str(definition.radius_squared),
			_digest(flags)])
		assert_eq(definition.unsupported_reason, "", "ORG1 entity %d" % index)
		assert_eq(observed, row, "ORG1 entity %d" % index)
	assert_eq(problems.size(), 0, "\n".join(problems))

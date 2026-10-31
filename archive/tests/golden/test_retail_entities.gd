extends RetailTest
## Every final-PC entity identity and generic base record against independent facts.

var _data: GameData

func before_all() -> void:
	if retail_skip_reason().is_empty():
		_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))

func after_all() -> void:
	if _data != null:
		_data.close()

func _digest(values: PackedInt64Array) -> String:
	return GoldenFiles.list_digest(values) if not values.is_empty() else "-"

func test_all_entity_identity_base_records_and_setup_census() -> void:
	var rows: Array[PackedStringArray] = GoldenFiles.rows("entities_retail.tsv")
	rows.pop_front()
	assert_eq(rows.size(), 78)
	var book: ThemeBook = _data.tables.theme_book()
	var problems := PackedStringArray()
	for row: PackedStringArray in rows:
		var file: MapFile = _data.read_map(int(row[0]), problems)
		assert_not_null(file, row[1])
		if file == null:
			continue
		var identity := PackedInt64Array()
		var records := PackedInt64Array()
		var static_count: int = 0
		var moving_count: int = 0
		for index: int in file.entities.size():
			var span: MapEntitySpan = file.entities[index]
			var form: FormBookEntry = book.get_form(file.general.theme, span.form_id)
			identity.append_array(PackedInt64Array([index, span.source_offset, span.end_offset,
				span.form_grid_id, span.unique_id, span.form_id, span.flags,
				form.entity_type if form != null else -1,
				form.script_id if form != null else -1,
				form.collision_callback if form != null else -1,
				form.bonus_callback if form != null else -1]))
			if form == null:
				continue
			if form.entity_name == "STATIC":
				var matrix: MapEntityPayload = MapEntityPayload.read_matrix(span)
				assert_eq(matrix.error, "", "%s entity %d" % [row[1], index])
				if matrix.error.is_empty():
					records.append_array(PackedInt64Array([index, 0]))
					for value: int in matrix.matrix12:
						records.append(value)
				static_count += 1
			elif form.entity_name == "MOVING":
				var info: MapEntityPayload = MapEntityPayload.read_path_info(span)
				records.append_array(PackedInt64Array([index, 1, info.path_index,
					info.segment_index, info.segment_distance, info.motion_flags, info.speed]))
				moving_count += 1
		var setup: EntitySetup = EntitySetup.from_map(file, book, row[1], int(row[0]), "pc-retail-v3.0e")
		assert_eq(setup.error, "", row[1])
		var accepted := PackedInt64Array()
		for definition: EntityDefinition in setup.definitions:
			accepted.append_array(PackedInt64Array([definition.entity_index, definition.unique_id]))
		var actual := PackedStringArray([row[0], row[1], str(file.entities.size()),
			str(static_count), str(moving_count), str(setup.definitions.size()),
			_digest(identity), _digest(records), _digest(accepted)])
		assert_eq(actual, row, row[1])
	assert_eq(problems.size(), 0, "\n".join(problems))

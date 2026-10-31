extends RetailTest
## Needs the retail files: every model (MOF) reads to the golden facts in
## tests/golden/pc-retail-v3.0e/mof_*.tsv (made by an independent Python
## reader, see tests/golden/README.md), and every form of every level finds
## the model the golden facts name.

var _data: GameData


func before_all() -> void:
	if not retail_skip_reason().is_empty():
		return
	_data = GameData.open(retail_source(), FrogLordConfigLibrary.new().load_version("pc-retail-v3.0e"))


func after_all() -> void:
	if _data != null:
		_data.close()


func _digest(values: PackedInt32Array) -> String:
	return GoldenFiles.list_digest32(values) if not values.is_empty() else "-"


func _bytes_digest(values: PackedByteArray) -> String:
	return _digest(PackedInt32Array(Array(values)))


func _match_golden(label: String, got: Array[PackedStringArray], file_name: String) -> void:
	var differences: PackedStringArray = GoldenFiles.differences(label, got, GoldenFiles.rows(file_name))
	for difference: String in differences:
		fail_test(difference)
	assert_eq(differences.size(), 0, "%s matches" % file_name)


func _part_row(resource_id: int, static_index: int, part: MofPart) -> PackedStringArray:
	var indices := PackedInt32Array()
	var uvs := PackedByteArray()
	var image_ids := PackedInt32Array()
	var colours := PackedInt32Array()
	for polygon: MofPolygon in part.polygons:
		indices.append(polygon.type)
		indices.append_array(polygon.vertices)
		indices.append_array(polygon.environment_normals)
		indices.append_array(polygon.normals)
		if polygon.is_textured():
			uvs.append_array(polygon.uvs)
			image_ids.append(polygon.image_id)
		colours.append_array(PackedInt32Array([polygon.red, polygon.green, polygon.blue, polygon.code]))
	var by_type := PackedStringArray()
	for count: int in part.polygons_by_type():
		by_type.append(str(count))
	var own: bool = not part.borrows
	var hilites := PackedInt32Array()
	if own:
		for hilite: MofPart.Hilite in part.hilites:
			hilites.append_array(PackedInt32Array([hilite.type, hilite.attach, hilite.index]))
	var cel: MofPart.Partcel = part.static_partcel() if own else null
	return PackedStringArray([str(resource_id), str(static_index), str(part.index), str(part.flags),
		str(part.partcel_count), str(part.vertex_count), str(part.normal_count), str(part.polygon_count),
		str(part.hilite_count), str(part.collprims.size() if own else 0), str(part.matrix_count),
		str(part.flipbook_action_count), str(part.texture_animation_target_count),
		str(part.texture_animation_count), str(part.bounding_box_count), ",".join(by_type),
		_digest(cel.vertices if cel != null else PackedInt32Array()),
		_digest(cel.normals if cel != null else PackedInt32Array()),
		_digest(cel.bounding_box if cel != null else PackedInt32Array()),
		_digest(indices), _bytes_digest(uvs), _digest(image_ids), _digest(colours), _digest(hilites),
		_digest(part.texture_animation_image_ids)])


func test_every_model_matches() -> void:
	var model_rows: Array[PackedStringArray] = []
	var part_rows: Array[PackedStringArray] = []
	var problems := PackedStringArray()
	var kinds: Dictionary[String, int] = {"dummy": 0, "static": 0, "animated": 0}
	var incomplete: int = 0
	var started: int = Time.get_ticks_usec()
	for entry: MwiEntry in _data.model_entries():
		var model: MofFile = _data.read_model(entry.index, problems)
		if model == null:
			continue
		kinds[model.kind_name()] += 1
		var totals: Dictionary[String, int] = {"partcels": 0, "vertices": 0, "normals": 0, "textured": 0,
			"hilites": 0, "collprims": 0, "matrices": 0, "flipbook": 0, "targets": 0, "animations": 0}
		for static_index: int in model.static_models.size():
			for part: MofPart in model.static_models[static_index].parts:
				totals["partcels"] += part.partcel_count
				totals["vertices"] += part.vertex_count
				totals["normals"] += part.normal_count
				totals["hilites"] += part.hilite_count
				totals["collprims"] += 0 if part.borrows else part.collprims.size()
				totals["matrices"] += part.matrix_count
				totals["flipbook"] += part.flipbook_action_count
				totals["targets"] += part.texture_animation_target_count
				totals["animations"] += part.texture_animation_count
				for polygon: MofPolygon in part.polygons:
					if polygon.is_textured():
						totals["textured"] += 1
				part_rows.append(_part_row(entry.index, static_index, part))
		if model.is_incomplete:
			incomplete += 1
		var image_ids: PackedInt32Array = model.image_ids()
		model_rows.append(PackedStringArray([str(entry.index), entry.display_name(), str(entry.type_id),
			str(model.size), model.kind_name(), model.signature, GoldenFiles.hex(model.flags),
			str(int(model.is_incomplete)), str(_data.counterpart_of(entry.index) if model.is_incomplete else -1),
			str(model.static_models.size()), str(model.animated.model_set_count if model.animated != null else 0),
			str(model.part_count()), str(totals["partcels"]), str(totals["vertices"]), str(totals["normals"]),
			str(model.polygon_count()), str(totals["textured"]), str(totals["hilites"]), str(totals["collprims"]),
			str(totals["matrices"]), str(totals["flipbook"]), str(totals["targets"]), str(totals["animations"]),
			str(image_ids.size()), _digest(image_ids)]))
	print("TIMING: read %d models (%d parts) in %.0f ms" % [
		model_rows.size(), part_rows.size(), (Time.get_ticks_usec() - started) / 1000.0])
	assert_eq(problems.size(), 0, ", ".join(problems))
	var facts: Dictionary[String, String] = GoldenFiles.facts("mof_summary.txt")
	assert_eq(str(model_rows.size()), facts["models"], "models")
	assert_eq(str(kinds["dummy"]), facts["dummy"], "placeholders")
	assert_eq(str(kinds["static"]), facts["static"], "static models")
	assert_eq(str(kinds["animated"]), facts["animated"], "animated models")
	assert_eq(str(incomplete), facts["incomplete"], "incomplete models")
	_match_golden("models", model_rows, "mof_models.tsv")
	_match_golden("parts", part_rows, "mof_parts.tsv")


func test_summary_facts() -> void:
	var facts: Dictionary[String, String] = GoldenFiles.facts("mof_summary.txt")
	var parts: int = 0
	var polygons: int = 0
	for row: PackedStringArray in GoldenFiles.rows("mof_models.tsv"):
		parts += row[11].to_int()
		polygons += row[15].to_int()
	assert_eq(str(parts), facts["parts"])
	assert_eq(str(polygons), facts["polygons"])
	assert_eq(str(GoldenFiles.rows("mof_parts.tsv").size()), facts["parts"])
	assert_eq(str(GoldenFiles.rows("mof_forms.tsv").size()), facts["form_rows"])


func _form_rows(level: int, code: String, theme: int, multiplayer_general: bool) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var as_level: int = level if level >= 0 else (5 if multiplayer_general else 0)
	for form: FormBookEntry in _data.theme_book_entry(theme).forms:
		var row := PackedStringArray([str(level), code, FroggerIds.theme_name(theme), str(form.local_id),
			form.form_name, str(form.model_id), str(int(form.has_flag(FormBookEntry.FLAG_NO_MODEL))),
			str(int(form.uses_general_wad())), str(form.wad_index())])
		for low_poly: bool in [false, true]:
			var wad: int = _data.model_wad_for(form, as_level, low_poly)
			var resource_id: int = _data.model_resource_at(wad, form.wad_index())
			var kind: String = "none"
			if resource_id >= 0:
				var entry: MwiEntry = _data.mwi.get_entry(resource_id)
				kind = "other"
				if GameData.is_model_entry(entry):
					kind = MofFile.KIND_NAMES[MofReader.kind_of(_data.read_resource(resource_id))]
			row.append_array(PackedStringArray([str(wad), str(resource_id), kind]))
		rows.append(row)
	return rows


func test_every_form_finds_its_model() -> void:
	var rows: Array[PackedStringArray] = []
	rows.append_array(_form_rows(-1, "GENERAL", FroggerIds.THEME_GENERAL, false))
	rows.append_array(_form_rows(-1, "GENERAL_MULTIPLAYER", FroggerIds.THEME_GENERAL, true))
	for row: MapBookEntry in _data.tables.map_book().entries:
		if row.is_dummy() or row.high_map_id <= 0:
			continue
		rows.append_array(_form_rows(row.level, row.code(), FroggerIds.theme_of_level(row.level), false))
	_match_golden("forms", rows, "mof_forms.tsv")


func test_an_incomplete_model_takes_its_shape_from_the_complete_one() -> void:
	var complete: MwiEntry = _data.find_resource("GEN_CHECKPOINT_1.XMR")
	var incomplete: MwiEntry = _data.find_resource("GEN_CHECKPOINT_2.XMR")
	assert_not_null(complete)
	assert_not_null(incomplete)
	var problems := PackedStringArray()
	var first: MofFile = _data.read_model(complete.index, problems)
	var second: MofFile = _data.read_model(incomplete.index, problems)
	assert_eq(problems.size(), 0, ", ".join(problems))
	assert_false(first.is_incomplete)
	assert_true(second.is_incomplete)
	assert_eq(_data.counterpart_of(incomplete.index), complete.index)
	var own: MofPart = second.static_models[0].parts[0]
	var lent: MofPart = first.static_models[0].parts[0]
	assert_true(own.borrows)
	assert_eq(own.static_partcel().vertices, lent.static_partcel().vertices, "same vertices")
	assert_eq(own.polygons.size(), lent.polygons.size(), "same number of polygons")
	var recoloured: int = 0
	for i: int in own.polygons.size():
		if own.polygons[i].red != lent.polygons[i].red or own.polygons[i].image_id != lent.polygons[i].image_id:
			recoloured += 1
	assert_gt(recoloured, 0, "but polygons of its own")


func test_texture_banks_of_model_wads() -> void:
	var general: ThemeBookEntry = _data.theme_book_entry(FroggerIds.THEME_GENERAL)
	assert_eq(_data.texture_bank_for_wad(general.wad_id()), general.vlo_id())
	assert_eq(_data.texture_bank_for_wad(general.wad_id(false, true)), general.vlo_id(false, true))
	var sub1: MapBookEntry = _data.map_book_entry(FroggerIds.level_from_code("SUB1"))
	var suburbia: ThemeBookEntry = _data.theme_book_entry(FroggerIds.theme_of_level(sub1.level))
	assert_eq(_data.texture_bank_for_wad(sub1.wad_id()), suburbia.vlo_id())
	assert_eq(_data.texture_bank_for_wad(sub1.wad_id(true)), suburbia.vlo_id(false, true))
	var options: MwiEntry = _data.find_resource("OPTIONSH.WAD")
	assert_not_null(options)
	assert_eq(_data.texture_bank_for_wad(options.index), _data.find_resource("OPT_VRAM.VLO").index)

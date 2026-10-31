class_name ExplorationInputs
extends RefCounted
## Checks that supplied resources match the facts an exploration preset file was generated from.

## Checks the imported build, resource mappings, source-ordered books, scripts
## and model counterparts.
static func validate(data: AssetCatalog, map: MapFile, proof: Dictionary, level: int) -> String:
	var source_issue: String = provenance_error(data, proof)
	if not source_issue.is_empty():
		return source_issue
	var row: MapBookEntry = data.map_book_entry(level)
	if row == null or row.map_id(false) != _integer(proof.map_resource_id):
		return "High-detail MAP resource identity"
	var book: ThemeBook = data.tables.theme_book()
	var theme: ThemeBookEntry = data.theme_book_entry(map.general.theme)
	var general: ThemeBookEntry = data.theme_book_entry(FroggerIds.THEME_GENERAL)
	if theme == null or general == null or map.general.theme != _integer(proof.theme_index) or theme.death_height != _integer(proof.theme_death_height) or general.wad_id(false, false) != _integer(proof.general_high_wad):
		return "theme or GENERAL resource table"
	var book_rows := PackedStringArray()
	var expected_models: Array = proof.get("entity_model_resources", [])
	if expected_models.size() != map.entities.size():
		return "authored entity/model inventory"
	for index: int in map.entities.size():
		var entity: MapEntitySpan = map.entities[index]
		var form: FormBookEntry = book.get_form(map.general.theme, entity.form_id)
		if form == null:
			return "EMTP[%d] offset %d has no resolved form" % [index, entity.source_offset]
		var model_id: int = -1 if form.has_flag(FormBookEntry.FLAG_NO_MODEL) else data.model_resource_at(data.model_wad_for(form, level, false), form.wad_index())
		if model_id != _integer(expected_models[index]):
			return "EMTP[%d] offset %d model resource mapping" % [index, entity.source_offset]
		book_rows.append(_numeric_row([index, entity.unique_id, entity.form_grid_id, entity.form_id, entity.flags, form.entity_type, form.model_id, form.script_id, form.flags, form.collision_callback, form.radius_squared, form.death_type, form.bonus_callback]))
	if ("\n".join(book_rows) + "\n").sha256_text() != proof.form_book_rows_sha256:
		return "source-ordered form identities, behaviors or callbacks"
	var scripts: ScriptTable = data.tables.scripts()
	if not scripts.error.is_empty():
		return "entity script table: " + scripts.error
	var script_rows := PackedStringArray()
	for script: EntityScript in scripts.scripts:
		var words: PackedInt32Array = script.words()
		var values: Array = [script.id, words.size()]
		values.append_array(Array(words))
		script_rows.append(_numeric_row(values))
	if ("\n".join(script_rows) + "\n").sha256_text() != proof.script_rows_sha256:
		return "entity script instructions used by the neighbor exclusion proof"
	var model_facts: Array = proof.model_resources
	for value: Variant in model_facts:
		var model: Dictionary = value
		var model_id: int = _integer(model.resource_id)
		var record: MofFile = data.read_model(model_id)
		if record == null:
			return "model resource %d is unavailable" % model_id
		var counterpart: int = data.counterpart_of(model_id) if record.is_incomplete else -1
		if counterpart != _integer(model.get("counterpart_resource_id", -1)):
			return "model resource %d counterpart mapping" % model_id
	return ""


## Checks that [param data] comes from the retail executable and archive
## [param proof] was generated from, by the SHA-256 digests the catalog
## reports ([method AssetCatalog.source_digests]). Returns the reason, or "".
static func provenance_error(data: AssetCatalog, proof: Dictionary) -> String:
	var digests: Dictionary[String, String] = data.source_digests()
	var exe: String = digests.get("exe", "")
	var mwd: String = digests.get("mwd", "")
	if exe.is_empty() or mwd.is_empty():
		return "the catalog does not report its retail source digests"
	if exe != proof.get("exe_sha256", "") or mwd != proof.get("mwd_sha256", ""):
		return "the catalog does not come from the audited executable and archive"
	return ""

static func _numeric_row(values: Array) -> String:
	var strings := PackedStringArray()
	for value: Variant in values:
		strings.append(str(_integer(value)))
	return ",".join(strings)

static func _integer(value: Variant) -> int:
	var number: float = value
	return int(number)

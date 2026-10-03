class_name Jun1ExplorationSetup
extends RefCounted
## Admits only the independently audited JUN1 inputs for bounded bank/log inspection.

const MANIFEST_PATH: String = "res://src/presentation/setup/jun1_exploration_admission.json"
const PRESET: String = "jun1-log-bank"

## Validates proof dependencies and copies decoded zones into an inspection guard.
static func apply(scenario: TerrainScenario, data: GameData) -> String:
	if scenario.level_code.to_upper() != "JUN1" or scenario.entity_lifecycle:
		return "jun1-log-bank requires high-detail JUN1 and all-attached lifetime"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary:
		return "JUN1 exploration admission manifest is unavailable"
	var proof: Dictionary = parsed
	if proof.get("schema", "") != "jun1-route-admission-v1" or data.version.internal_name != proof.get("build", ""):
		return "jun1-log-bank requires audited pc-retail-v3.0e inputs"
	var issue: String = _validate_inputs(data, scenario.map_scene.map, proof)
	if not issue.is_empty():
		return "JUN1 exploration proof inputs changed: " + issue
	var zones: ZoneSetup = ZoneSetup.from_map(scenario.map_scene.map, scenario.level.source_id, scenario.level.resource_id, data.version.internal_name)
	if not zones.error.is_empty():
		return zones.error
	var guard := ExplorationGuard.new()
	var bounds_x: Array = proof.admitted_x
	var bounds_z: Array = proof.admitted_z
	guard.world_bounds = Rect2i(_integer(bounds_x[0]), _integer(bounds_z[0]), _integer(bounds_x[1]) - _integer(bounds_x[0]), _integer(bounds_z[1]) - _integer(bounds_z[0]))
	for zone: ZoneDefinition in zones.definitions:
		guard.zones.append(zone.copy())
	issue = guard.validate()
	if not issue.is_empty():
		return issue
	scenario.level.exploration_guard = guard
	scenario.initial.spawn_cell = Vector2i(22, 10)
	scenario.initial.spawn_direction = 3
	scenario.initial.controller_directions = PackedInt32Array()
	scenario.initial.camera_startup = false
	scenario.identifier = PRESET
	if not scenario.tick_limit_override and not scenario.authored_fixture:
		scenario.tick_limit = 60
	if not scenario.authored_fixture:
		scenario.commands.clear()
	scenario.diagnostics.append("JUN1 bounded exploration: audited inputs only; all-attached lifetime; active camera zones unsupported")
	scenario.diagnostics.append("World boundary X[1900,2304), Z[-5376,-4864); rejected ticks roll back and pause")
	return ""

static func _validate_inputs(data: GameData, map: MapFile, proof: Dictionary) -> String:
	var row: MapBookEntry = data.map_book_entry(18)
	if row == null or row.map_id(false) != _integer(proof.map_resource_id):
		return "JUN1 high-detail MAP resource identity"
	var problems := PackedStringArray()
	if _digest(data.read_resource(row.map_id(false), problems)) != proof.map_sha256:
		return "MAP resource %d geometry, entity, path or zone records" % row.map_id(false)
	var book: ThemeBook = data.tables.theme_book()
	var theme: ThemeBookEntry = data.theme_book_entry(map.general.theme)
	var general: ThemeBookEntry = data.theme_book_entry(FroggerIds.THEME_GENERAL)
	if theme == null or general == null or map.general.theme != _integer(proof.theme_index) or theme.death_height != _integer(proof.theme_death_height) or general.wad_id(false, false) != _integer(proof.general_high_wad):
		return "theme or GENERAL resource table"
	var book_rows := PackedStringArray()
	var expected_models: Array = proof.get("entity_model_resources", [])
	if expected_models.size() != map.entities.size():
		return "authored entity/model admission inventory"
	for index: int in map.entities.size():
		var entity: MapEntitySpan = map.entities[index]
		var form: FormBookEntry = book.get_form(map.general.theme, entity.form_id)
		if form == null:
			return "EMTP[%d] offset %d has no resolved form" % [index, entity.source_offset]
		var model_id: int = -1 if form.has_flag(FormBookEntry.FLAG_NO_MODEL) else data.model_resource_at(data.model_wad_for(form, 18, false), form.wad_index())
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
		var bytes: PackedByteArray = data.read_resource(model_id, problems)
		if _digest(bytes) != model.sha256:
			return "model resource %d geometry or primitive facts" % model_id
		var counterpart: int = data.counterpart_of(model_id) if MofFile.needs_counterpart(bytes) else -1
		if counterpart != _integer(model.get("counterpart_resource_id", -1)):
			return "model resource %d counterpart mapping" % model_id
	return "; ".join(problems)

static func _numeric_row(values: Array) -> String:
	var strings := PackedStringArray()
	for value: Variant in values:
		strings.append(str(_integer(value)))
	return ",".join(strings)

static func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

static func _integer(value: Variant) -> int:
	var number: float = value
	return int(number)

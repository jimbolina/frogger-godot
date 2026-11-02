class_name LevelSupportReport
extends RefCounted
## Inventory of the forms, entities, scripts, callbacks and texture remaps a catalog's levels use.
##
## A mod can only repoint data to behaviors the port implements. Every item a
## selected level places becomes one [LevelSupportReport.Row], marked mapped
## (empty reason) or unmapped (the reason the port cannot play it). Forms of
## the levels' themes and GENERAL that no selected level places are checked
## too and listed only when unmapped, with the level list [code]-[/code];
## those rows are counted apart from [method unmapped], since no level needs them.

## Entity setup diagnostics that describe supported records and are not reported.
const INFORMATIONAL_DIAGNOSTICS: PackedStringArray = ["entity_override", "unexecuted_hooks"]
## Entity setup diagnostics that restate an unmapped form or entity row of the same entity.
const RESTATED_DIAGNOSTICS: PackedStringArray = ["invalid_form", "unknown_behavior"]
## Level list of rows for forms no selected level places.
const UNPLACED_LEVEL: String = "-"
## Reason prefix of rows for forms no selected level places.
const UNPLACED_PREFIX: String = "unplaced: "


## One inventoried item and the levels that use it.
class Row extends RefCounted:
	## One of form, entity, script, callback or remap.
	var kind: String = ""
	## The item's identity within its kind.
	var key: String = ""
	## Codes of the levels using the item, in visiting order.
	var levels: PackedStringArray = PackedStringArray()
	## Why the port cannot play the item, or "" when it can.
	var reason: String = ""
	## The form-book entry the item belongs to, or "" for form and remap rows.
	var form: String = ""

	## True when the port implements the item.
	func is_mapped() -> bool:
		return reason.is_empty()

	## True when a selected level uses the item.
	func is_placed() -> bool:
		return not levels.has(LevelSupportReport.UNPLACED_LEVEL)

	## The row as tab-separated kind, key, comma-joined levels and reason.
	func to_tsv() -> String:
		return "%s\t%s\t%s\t%s" % [kind, key, ",".join(levels), reason]


## Rows sorted by kind, then key.
var rows: Array[Row] = []
## Levels whose row, map, banks or models could not be read; these are not rows.
var problems: PackedStringArray = PackedStringArray()
## Number of levels whose map was read.
var level_count: int = 0
var _by_key: Dictionary[String, Row] = {}
var _placed: Dictionary[int, bool] = {}
var _themes: Dictionary[int, bool] = {}
var _banks: Dictionary[int, VloFile] = {}
var _models: Dictionary[int, MofFile] = {}


## Reports every playable level of [param data], or the levels named in [param level_codes].
static func from_catalog(data: AssetCatalog, level_codes: PackedStringArray = PackedStringArray()) -> LevelSupportReport:
	var report := LevelSupportReport.new()
	if data == null or not data.is_valid() or data.tables == null or data.tables.theme_book() == null:
		report.problems.append("The catalog is not readable: %s" % (data.error if data != null else "no catalog"))
		return report
	var codes: PackedStringArray = level_codes if not level_codes.is_empty() else data.playable_level_codes()
	for code: String in codes:
		report._level(data, code.to_upper())
	report._unplaced(data)
	report.rows.sort_custom(_row_before)
	return report


## The rows a selected level uses that the port cannot play.
func unmapped() -> Array[Row]:
	var found: Array[Row] = []
	for row: Row in rows:
		if not row.is_mapped() and row.is_placed():
			found.append(row)
	return found


## The rows of forms no selected level places that the port could not play.
func unplaced() -> Array[Row]:
	var found: Array[Row] = []
	for row: Row in rows:
		if not row.is_placed():
			found.append(row)
	return found


## A header line, then one tab-separated line per row.
func to_tsv_lines() -> PackedStringArray:
	var lines := PackedStringArray(["# kind\tkey\tlevels\treason"])
	for row: Row in rows:
		lines.append(row.to_tsv())
	return lines


## One line counting levels, rows, unmapped and unplaced rows and any problems.
func summary() -> String:
	var text: String = "%d levels, %d rows, %d unmapped, %d unplaced" % [level_count, rows.size(), unmapped().size(), unplaced().size()]
	if not problems.is_empty():
		text += ", %d problems" % problems.size()
	return text


static func _row_before(a: Row, b: Row) -> bool:
	return a.kind < b.kind if a.kind != b.kind else a.key < b.key


func _level(data: AssetCatalog, code: String) -> void:
	var number: int = FroggerIds.level_from_code(code)
	var book: MapBookEntry = data.map_book_entry(number) if number >= 0 else null
	if book == null or book.is_dummy() or book.map_id(false) <= 0:
		problems.append("%s has no map-book row with a map" % code)
		return
	var reasons := PackedStringArray()
	var map: MapFile = data.read_map(book.map_id(false), reasons)
	if map == null or not map.error.is_empty():
		problems.append("%s map %d could not be read: %s" % [code, book.map_id(false), map.error if map != null else "; ".join(reasons)])
		return
	level_count += 1
	_themes[map.general.theme] = true
	var setup: EntitySetup = EntitySetup.from_map(map, data.tables.theme_book(), data.version_name + ":" + code, book.map_id(false), data.version_name, true, data.names)
	if not setup.error.is_empty():
		problems.append("%s entity setup failed: %s" % [code, setup.error])
	var reported: Dictionary[int, bool] = _forms(data, code, map)
	_diagnostics(code, setup, reported)
	_scripts(data, number, code, map, setup)
	_remaps(data, number, code, map, book.map_id(false))


func _forms(data: AssetCatalog, code: String, map: MapFile) -> Dictionary[int, bool]:
	var reported: Dictionary[int, bool] = {}
	for index: int in map.entities.size():
		var span: MapEntitySpan = map.entities[index]
		var form: FormBookEntry = data.tables.theme_book().get_form(map.general.theme, span.form_id)
		if form == null:
			_add("form", "%s/%d" % [FroggerIds.theme_name(map.general.theme), span.form_id], code, "form id %d does not resolve in theme %s or GENERAL" % [span.form_id, FroggerIds.theme_name(map.general.theme)])
			reported[index] = true
			continue
		_placed[form.get_instance_id()] = true
		_add("form", _form_key(form), code, "")
		if not _check_form(data, form, code, ""):
			reported[index] = true
	return reported


func _diagnostics(code: String, setup: EntitySetup, reported: Dictionary[int, bool]) -> void:
	for diagnostic: EntitySetupDiagnostic in setup.diagnostics:
		if diagnostic.code in INFORMATIONAL_DIAGNOSTICS or (diagnostic.code in RESTATED_DIAGNOSTICS and reported.has(diagnostic.entity_index)):
			continue
		_add("entity", "%s#%d" % [diagnostic.form_name, diagnostic.entity_index], code, "%s: %s" % [diagnostic.code, diagnostic.message])


func _check_form(data: AssetCatalog, form: FormBookEntry, level: String, prefix: String) -> bool:
	var unknown: bool = EntityBehaviorCatalog.resolve(form.entity_name).kind == EntityBehavior.Kind.UNKNOWN
	_add("entity", form.entity_name, level, prefix + "no behavior implements entity %s (form %s)" % [form.entity_name, _form_key(form)] if unknown else "").form = _form_key(form)
	for bonus: bool in [false, true]:
		var address: int = form.bonus_callback if bonus else form.collision_callback
		var kind: FormCallback.Kind = FormCallbackCatalog.resolve(data.version_name, address, bonus)
		if kind == FormCallback.Kind.NONE:
			continue
		var role: String = "bonus" if bonus else "collision"
		_add("callback", "0x%X" % address, level, prefix + "%s callback 0x%X of form %s is not a verified %s callback" % [role, address, _form_key(form), data.version_name] if kind == FormCallback.Kind.UNKNOWN else "").form = _form_key(form)
	return not unknown


func _scripts(data: AssetCatalog, number: int, code: String, map: MapFile, setup: EntitySetup) -> void:
	var definitions: Dictionary[int, EntityDefinition] = {}
	for definition: EntityDefinition in setup.definitions:
		definitions[definition.entity_index] = definition
	var script_names: NameBank = data.names.scripts if data.names != null else null
	for index: int in map.entities.size():
		var span: MapEntitySpan = map.entities[index]
		var form: FormBookEntry = data.tables.theme_book().get_form(map.general.theme, span.form_id)
		if form == null or form.script_id == 0:
			continue
		var key: String = script_names.name_of(form.script_id) if script_names != null and script_names.has_name(form.script_id) else str(form.script_id)
		var definition: EntityDefinition = definitions[index] if definitions.has(index) else null
		var behavior: EntityBehavior = definition.behavior if definition != null else EntityBehaviorCatalog.resolve(form.entity_name)
		var scripts: EntityScriptSetup = EntityScriptSetup.from_tables(data.tables.scripts(), script_names, form.script_id, behavior, span.payload)
		var issue: String = scripts.error
		if issue.is_empty() and definition != null:
			scripts.definition.original_turtle_splashes = map.general.theme == FroggerIds.THEMES.find("ORIGINAL")
			var lengths: PackedInt32Array = _action_lengths(data, number, code, form, definition)
			issue = scripts.definition.validate(lengths, span.form_id, definition.path_definition != null)
		_add("script", key, code, "" if issue.is_empty() else "%s#%d: %s" % [form.form_name, index, issue])


func _action_lengths(data: AssetCatalog, number: int, code: String, form: FormBookEntry, definition: EntityDefinition) -> PackedInt32Array:
	var model_id: int = EntityModelSelection.resource_for(data, number, form, definition)
	if model_id < 0:
		return PackedInt32Array()
	if not _models.has(model_id):
		var reasons := PackedStringArray()
		_models[model_id] = data.read_model(model_id, reasons)
		for reason: String in reasons:
			problems.append("%s model %d: %s" % [code, model_id, reason])
	var model: MofFile = _models[model_id]
	if model == null or model.kind == MofFile.Kind.DUMMY:
		return PackedInt32Array()
	if form.has_flag(FormBookEntry.FLAG_NO_MODEL) and definition.behavior.kind != EntityBehavior.Kind.VOL_COLOUR_SWITCH:
		return PackedInt32Array()
	return GameplaySetup.model_action_lengths(model)


func _remaps(data: AssetCatalog, number: int, code: String, map: MapFile, map_id: int) -> void:
	var remap: TextureRemap = data.remap_for_resource(map_id)
	if remap == null:
		_add("remap", "map %d" % map_id, code, "map resource %d has no texture remap" % map_id)
		return
	var banks: Array[VloFile] = _level_banks(data, number, code, map.general.theme)
	if banks.is_empty():
		return
	var locals: Dictionary[int, bool] = {}
	for polygon: MapPolygon in map.polygons:
		if polygon.texture_id >= 0:
			locals[polygon.texture_id] = true
	for animation: MapAnimation in map.animations:
		for local_id: int in animation.texture_ids:
			locals[local_id] = true
	var slots: Array[int] = []
	slots.assign(locals.keys())
	slots.sort()
	var remap_name: String = remap.name if not remap.name.is_empty() else "map %d" % map_id
	var complete: bool = true
	for slot: int in slots:
		var reason: String = _slot_issue(remap, slot, banks)
		if not reason.is_empty():
			complete = false
			_add("remap", "%s/%d" % [remap_name, slot], code, reason)
	if complete:
		_add("remap", remap_name, code, "")


func _slot_issue(remap: TextureRemap, slot: int, banks: Array[VloFile]) -> String:
	var global_id: int = remap.global_id(slot)
	if global_id < 0:
		return "local texture %d is outside the remap's %d ids" % [slot, remap.size()]
	for bank: VloFile in banks:
		if bank.find_texture(global_id) != null:
			return ""
	return "global texture %d of local texture %d is in neither the GENERAL nor the theme bank" % [global_id, slot]


func _level_banks(data: AssetCatalog, number: int, code: String, theme: int) -> Array[VloFile]:
	var banks: Array[VloFile] = []
	var multiplayer: bool = AssetCatalog.is_multiplayer_level(number)
	for owner: int in [FroggerIds.THEME_GENERAL, theme]:
		var entry: ThemeBookEntry = data.theme_book_entry(owner)
		var bank_id: int = 0
		if entry != null:
			bank_id = entry.vlo_id(multiplayer, false) if entry.vlo_id(multiplayer, false) != 0 else entry.vlo_id(false, false)
		if not _banks.has(bank_id):
			var reasons := PackedStringArray()
			_banks[bank_id] = data.read_texture_bank(bank_id, reasons) if bank_id != 0 else null
			if _banks[bank_id] == null:
				problems.append("%s %s texture bank %d could not be read: %s" % [code, FroggerIds.theme_name(owner), bank_id, "; ".join(reasons)])
		if _banks[bank_id] == null:
			return []
		banks.append(_banks[bank_id])
	return banks


func _unplaced(data: AssetCatalog) -> void:
	if level_count == 0:
		return
	var owners: Array[int] = [FroggerIds.THEME_GENERAL]
	var themes: Array[int] = []
	themes.assign(_themes.keys())
	themes.sort()
	for theme: int in themes:
		if theme not in owners:
			owners.append(theme)
	for owner: int in owners:
		var entry: ThemeBookEntry = data.theme_book_entry(owner)
		if entry == null:
			continue
		for form: FormBookEntry in entry.forms:
			if not _placed.has(form.get_instance_id()):
				_check_unplaced(data, form)


func _check_unplaced(data: AssetCatalog, form: FormBookEntry) -> void:
	var probe := LevelSupportReport.new()
	probe._check_form(data, form, UNPLACED_LEVEL, UNPLACED_PREFIX)
	for row: Row in probe.rows:
		if not row.is_mapped() and not _by_key.has(_identity(row.kind, row.key)):
			_by_key[_identity(row.kind, row.key)] = row
			rows.append(row)


func _add(kind: String, key: String, level: String, reason: String) -> Row:
	var identity: String = _identity(kind, key)
	var row: Row = _by_key[identity] if _by_key.has(identity) else null
	if row == null:
		row = Row.new()
		row.kind = kind
		row.key = key
		_by_key[identity] = row
		rows.append(row)
	if level not in row.levels:
		row.levels.append(level)
	if row.reason.is_empty():
		row.reason = reason
	return row


static func _identity(kind: String, key: String) -> String:
	return kind + "\t" + key


static func _form_key(form: FormBookEntry) -> String:
	return form.form_name if not form.form_name.is_empty() else "%s/%d" % [FroggerIds.theme_name(form.theme), form.local_id]

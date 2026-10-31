class_name EntityCollisionSetup
extends RefCounted
## Copies source-ordered entity transforms, FORM geometry and reaction facts.

var definition: EntityCollisionDefinition = null
var diagnostics: Array[EntitySetupDiagnostic] = []
var error: String = ""

## Composes the independent transform and contact adapters for a decoded map.
static func from_map(map: MapFile, book: ThemeBook, models_by_form: Dictionary[int, MofFile], source_id: String = "", resource_id: int = -1, build_id: String = "", platforms_enabled: bool = false, visibility_enabled: bool = false) -> EntityCollisionSetup:
	var result := EntityCollisionSetup.new()
	if map == null or book == null:
		result.error = "Entity collision requires a map and theme book"
		return result
	var zones: MapPacket = map.packets.get("ZONE")
	if visibility_enabled and zones != null and zones.count > 0:
		result.error = "Visibility lifecycle requires a map without authored zones"
		return result
	if visibility_enabled and map.groups.size() < map.group_dimensions.x * map.group_dimensions.y:
		result.error = "Visibility lifecycle requires every authored map group"
		return result
	var entities: EntitySetup = EntitySetup.from_map(map, book, source_id, resource_id, build_id)
	result.diagnostics.append_array(entities.diagnostics)
	if not entities.error.is_empty():
		result.error = entities.error
		return result
	var contacts: FormContactSetup = FormContactSetup.from_map(map, book, entities.definitions, models_by_form, source_id, resource_id, build_id)
	result.diagnostics.append_array(contacts.diagnostics)
	if not contacts.error.is_empty():
		result.error = contacts.error
		return result
	var assembled := EntityCollisionDefinition.new()
	assembled.platforms_enabled = platforms_enabled
	assembled.group_base = map.group_base
	assembled.group_dimensions = map.group_dimensions
	assembled.group_size = map.group_size
	if visibility_enabled:
		var lifecycle: EntityLifecycleSetup = EntityLifecycleSetup.from_map(map)
		if not lifecycle.error.is_empty():
			result.error = lifecycle.error
			return result
		assembled.lifecycle = lifecycle.definition
	for index: int in entities.definitions.size():
		var entity: EntityDefinition = entities.definitions[index]
		var contact: FormContactDefinition = contacts.definitions[index].copy()
		var form: FormBookEntry = book.get_form(map.general.theme, entity.form_id)
		if form == null:
			result.error = "Accepted entity has no form-book entry"
			return result
		contact.death_type = form.death_type
		contact.form_book_flags = form.flags
		if entity.script_id != 0:
			contact.reaction_unsupported_reason = "Entity script may alter state before contact"
			result._issue("unexecuted_entity_script", contact.reaction_unsupported_reason, entity, "Geometry remains inspectable; reaction omitted")
			if visibility_enabled:
				result._issue("lifecycle_dormant_script", "Entity script has no verified visibility behavior", entity, "Entity remains dormant in visibility mode")
		if entity.bonus_callback != 0:
			result._issue("unexecuted_bonus_callback", "Bonus callback is not dispatched for tongue pickup", entity, "FORM reaction remains available")
		if contact.unsupported_reason.is_empty() and contact.reaction_unsupported_reason.is_empty():
			var seen: Dictionary[int, bool] = {}
			for cell_flags: int in contact.grid_flags:
				if seen.has(cell_flags):
					continue
				seen[cell_flags] = true
				var sample := FormContactResult.new()
				sample.status = FormContactResult.CONTACT
				sample.entity_index = contact.entity_index
				sample.unique_id = contact.unique_id
				sample.form_grid_id = contact.form_grid_id
				sample.form_id = contact.form_id
				sample.cell_flags = cell_flags
				var reaction: FormReactionResult = FormReaction.evaluate(contact, sample, platforms_enabled)
				if reaction.status == FormReactionResult.UNSUPPORTED:
					result._issue("unsupported_form_reaction", "%s (cell flags 0x%X)" % [reaction.reason, cell_flags], entity, "Geometry remains inspectable; reaction omitted")
		assembled.entities.append(entity.copy())
		assembled.contacts.append(contact)
	result.error = assembled.validate()
	if result.error.is_empty():
		result.definition = assembled
	return result

## Reads player high-detail resources and detaches every accepted base entity.
static func from_data(data: AssetCatalog, level: int, low_poly: bool = false, platforms_enabled: bool = false, visibility_enabled: bool = false) -> EntityCollisionSetup:
	var result := EntityCollisionSetup.new()
	if data == null or not data.is_valid():
		result.error = "Entity collision requires valid player data"
		return result
	var row: MapBookEntry = data.map_book_entry(level)
	if row == null or row.map_id(low_poly) <= 0:
		result.error = "Level has no selected map"
		return result
	var problems := PackedStringArray()
	var map: MapFile = data.read_map(row.map_id(low_poly), problems)
	if map == null:
		result.error = "Cannot read selected map: %s" % "; ".join(problems)
		return result
	var book: ThemeBook = data.tables.theme_book()
	var models: Dictionary[int, MofFile] = {}
	for span: MapEntitySpan in map.entities:
		if models.has(span.form_id):
			continue
		var form: FormBookEntry = book.get_form(map.general.theme, span.form_id)
		if form == null:
			continue
		var model_id: int = data.model_resource_at(data.model_wad_for(form, level, low_poly), form.wad_index()) if form.has_flag(FormBookEntry.FLAG_NO_MODEL) and form.model_id >= 0 else data.model_resource_for(form, level, low_poly)
		if model_id >= 0:
			var model: MofFile = data.read_model(model_id, problems)
			if model != null:
				models[span.form_id] = model
	return from_map(map, book, models, data.version_name + ":" + row.code(), row.map_id(low_poly), data.version_name, platforms_enabled, visibility_enabled)

func _issue(code: String, message: String, entity: EntityDefinition, fallback: String) -> void:
	var diagnostic := EntitySetupDiagnostic.new()
	diagnostic.code = code
	diagnostic.source_id = entity.source_id
	diagnostic.build_id = entity.build_id
	diagnostic.resource_id = entity.resource_id
	diagnostic.entity_index = entity.entity_index
	diagnostic.form_id = entity.form_id
	diagnostic.form_name = entity.form_name
	diagnostic.source_offset = entity.source_offset
	diagnostic.message = message
	diagnostic.fallback = fallback
	diagnostics.append(diagnostic)

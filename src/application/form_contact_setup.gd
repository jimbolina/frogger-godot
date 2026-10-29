class_name FormContactSetup
extends RefCounted
## Resolves source FORM grids and model bounds for bounded entity contact.

var definitions: Array[FormContactDefinition] = []
var diagnostics: Array[EntitySetupDiagnostic] = []
var error: String = ""

## Resolves authored writers; whole-map callers opt into skeletal and decorative model contacts.
static func from_map(map: MapFile, theme_book: ThemeBook, entities: Array[EntityDefinition], models_by_form: Dictionary[int, MofFile], source_id: String = "", resource_id: int = -1, build_id: String = "", primitive_contacts: bool = false, complete_model_contacts: bool = false, models_by_entity: Dictionary[int, MofFile] = {}) -> FormContactSetup:
	var result := FormContactSetup.new()
	if map == null or theme_book == null:
		result.error = "Form contact setup requires a map and theme book"
		return result
	if not map.error.is_empty() or not theme_book.error.is_empty():
		result.error = "Cannot set up form contact from invalid data: %s %s" % [map.error, theme_book.error]
		return result
	var packet: MapPacket = map.packets.get("EMTP")
	var form_packet: MapPacket = map.packets.get("FORM")
	if packet == null or packet.count != map.entities.size() or packet.offsets.size() != packet.count:
		result.error = "EMTP record count does not match its pointer table"
		return result
	if form_packet == null or form_packet.count != map.forms.size():
		result.error = "FORM record count does not match its pointer table"
		return result
	var max_y_by_grid: Dictionary[int, int] = {}
	var unresolved_by_grid: Dictionary[int, String] = {}
	for index: int in map.entities.size():
		var span: MapEntitySpan = map.entities[index]
		if span == null or span.source_offset != packet.offsets[index]:
			result.error = "EMTP source identity does not match its pointer table"
			return result
		if span.form_grid_id < 0 or span.form_grid_id >= map.forms.size():
			continue
		var form: FormBookEntry = theme_book.get_form(map.general.theme, span.form_id)
		if form == null:
			unresolved_by_grid[span.form_grid_id] = "Authored form does not resolve"
			continue
		var model: MofFile = models_by_form.get(span.form_id)
		if model == null:
			unresolved_by_grid[span.form_grid_id] = "Determining model is unavailable"
			continue
		if not model.error.is_empty():
			unresolved_by_grid[span.form_grid_id] = "Determining model is invalid"
			continue
		if model.kind == MofFile.Kind.DUMMY:
			continue
		var maximum: Array[int] = _maximum_y(form, model)
		if maximum.is_empty():
			unresolved_by_grid[span.form_grid_id] = "Determining model has no usable maximum Y"
			continue
		max_y_by_grid[span.form_grid_id] = maximum[0]
		unresolved_by_grid.erase(span.form_grid_id)
	for entity: EntityDefinition in entities:
		if entity == null:
			result.error = "Null detached entity definition"
			return result
		if entity.entity_index < 0 or entity.entity_index >= map.entities.size():
			result.error = "Detached entity index is outside EMTP"
			return result
		var span: MapEntitySpan = map.entities[entity.entity_index]
		if span.source_offset != entity.source_offset or span.form_grid_id != entity.form_grid_id or span.form_id != entity.form_id or span.unique_id != entity.unique_id or span.flags != entity.flags:
			result.error = "Detached entity identity differs from EMTP"
			return result
		var definition := FormContactDefinition.new()
		definition.source_id = source_id if not source_id.is_empty() else entity.source_id
		definition.build_id = build_id if not build_id.is_empty() else entity.build_id
		definition.resource_id = resource_id if resource_id >= 0 else entity.resource_id
		definition.entity_index = entity.entity_index
		definition.unique_id = entity.unique_id
		definition.form_grid_id = span.form_grid_id
		definition.form_id = span.form_id
		definition.form_name = entity.form_name
		definition.source_offset = span.source_offset
		definition.entity_flags = entity.flags
		var grid: MapForm = map.forms[span.form_grid_id] if span.form_grid_id >= 0 and span.form_grid_id < map.forms.size() else null
		if grid != null:
			definition.dimensions = grid.dimensions
			definition.offsets = grid.offsets
		var form: FormBookEntry = theme_book.get_form(map.general.theme, span.form_id)
		var selected_model: MofFile = models_by_entity.get(entity.entity_index, models_by_form.get(span.form_id))
		var bounds_model: MofFile = models_by_form.get(span.form_id)
		if form != null:
			definition.death_type = form.death_type
			definition.callback_kind = FormCallbackCatalog.resolve(entity.build_id, form.collision_callback)
		var reason: String = ""
		if form != null and form.has_flag(FormBookEntry.FLAG_NO_MODEL) and definition.callback_kind not in [FormCallback.Kind.NONE, FormCallback.Kind.UNKNOWN]:
			definition.sphere_callback = true
			definition.has_form_data = false
			definition.radius_squared = form.radius_squared
		elif form != null and form.has_flag(FormBookEntry.FLAG_NO_MODEL) and definition.callback_kind == FormCallback.Kind.NONE:
			definition.has_form_data = false
			definition.radius_squared = form.radius_squared
		elif grid == null:
			reason = "Entity references an invalid FORM grid"
		elif form == null:
			reason = "Authored form does not resolve"
		elif not entity.behavior.has_form_contact():
			reason = "Entity behavior has no bounded contact transform"
		elif definition.callback_kind == FormCallback.Kind.UNKNOWN:
			reason = "Form collision callback address has no verified mapping"
		elif form.has_flag(FormBookEntry.FLAG_NO_MODEL):
			reason = "Form has no model"
		elif primitive_contacts and grid.data_count == 0 and grid.data.is_empty() and _primitive_model(selected_model):
			var model: MofFile = selected_model
			var primitives: EntityPrimitiveSetup = EntityPrimitiveSetup.from_model(model)
			var radius: Array[int] = _radius_squared(form, bounds_model)
			if not primitives.error.is_empty():
				reason = primitives.error
			elif radius.is_empty():
				reason = "Model has no usable bounding radius"
			else:
				definition.radius_squared = radius[0]
				definition.primitives = primitives.primitives
				definition.primitive_part = primitives.part
				definition.has_form_data = false
		elif grid.data_count == 0 and grid.data.is_empty() and selected_model != null and selected_model.kind == MofFile.Kind.DUMMY:
			definition.has_form_data = false
			definition.radius_squared = form.radius_squared
		elif complete_model_contacts and grid.data_count == 0 and grid.data.is_empty() and selected_model != null and selected_model.error.is_empty() and selected_model.kind in [MofFile.Kind.STATIC, MofFile.Kind.ANIMATED] and selected_model.static_models.size() == 1 and not _has_collprims(selected_model):
			var radius: Array[int] = _radius_squared(form, bounds_model)
			if radius.is_empty():
				reason = "Model has no usable bounding radius"
			else:
				definition.has_form_data = false
				definition.radius_squared = radius[0]
		elif grid.data_count < 1 or grid.data.size() != grid.data_count:
			reason = "FORM grid has no usable data record"
		elif grid.dimensions.x <= 0 or grid.dimensions.y <= 0:
			reason = "FORM grid has invalid dimensions"
		elif grid.data[0].height_type != 0:
			reason = "FORM_DATA height mode is unsupported"
		elif grid.data[0].grid_flags.size() != grid.dimensions.x * grid.dimensions.y:
			reason = "FORM_DATA grid flags are unavailable"
		elif unresolved_by_grid.has(span.form_grid_id):
			reason = unresolved_by_grid[span.form_grid_id]
		elif not max_y_by_grid.has(span.form_grid_id):
			reason = "FORM grid has no resolved runtime maximum Y"
		else:
			var model: MofFile = models_by_entity.get(entity.entity_index, models_by_form.get(span.form_id))
			if model == null or not model.error.is_empty() or (model.kind != MofFile.Kind.STATIC and not (complete_model_contacts and model.kind == MofFile.Kind.ANIMATED)) or model.static_models.size() != 1:
				reason = "Contact requires one static, flipbook or skeletal model"
			elif _has_collprims(model) and not primitive_contacts:
				reason = "Model collision primitives take precedence over FORM"
			else:
				var radius: Array[int] = _radius_squared(form, bounds_model)
				if radius.is_empty():
					reason = "Model has no usable bounding radius"
				else:
					definition.radius_squared = radius[0]
					definition.max_y = max_y_by_grid[span.form_grid_id]
					definition.height = grid.data[0].height
					definition.grid_flags = grid.data[0].grid_flags.duplicate()
					if _has_collprims(model):
						var primitives: EntityPrimitiveSetup = EntityPrimitiveSetup.from_model(model)
						if not primitives.error.is_empty():
							reason = primitives.error
						else:
							definition.primitives = primitives.primitives
							definition.primitive_part = primitives.part
		definition.unsupported_reason = reason
		result.definitions.append(definition)
		if not reason.is_empty():
			result._issue(reason, entity, definition)
		elif grid != null and grid.data_count > 1:
			result._issue("Additional FORM_DATA records are retained; contact uses the first", entity, definition, "additional_form_data")
	return result

static func _primitive_model(model: MofFile) -> bool:
	return model != null and model.error.is_empty() and model.kind in [MofFile.Kind.STATIC, MofFile.Kind.ANIMATED] and model.static_models.size() == 1 and _has_collprims(model)

## Reads the selected map and all authored form models, including omitted entities.
static func from_data(data: GameData, level: int, low_poly: bool, entities: Array[EntityDefinition]) -> FormContactSetup:
	var result := FormContactSetup.new()
	if data == null or not data.is_valid():
		result.error = "Valid game data is required for form contact"
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
	result = from_map(map, book, entities, models, data.version.internal_name + ":" + row.code(), row.map_id(low_poly), data.version.internal_name)
	return result

static func _maximum_y(form: FormBookEntry, model: MofFile) -> Array[int]:
	var maximum: Array[int] = []
	if form.has_flag(FormBookEntry.FLAG_THICK):
		maximum.append(0x7fff)
		return maximum
	if form.has_flag(FormBookEntry.FLAG_UNIT_FORM):
		maximum.append(0x100)
		return maximum
	var box := PackedInt32Array()
	if model.kind == MofFile.Kind.STATIC and model.static_models.size() > 0:
		var static_model: MofStatic = model.static_models[0]
		if static_model.parts.size() > 0 and static_model.parts[0].partcels.size() > 0:
			box = static_model.parts[0].partcels[0].bounding_box
	elif model.kind == MofFile.Kind.ANIMATED and model.animated != null and model.animated.model_sets.size() > 0:
		var set: MofAnimated.ModelSet = model.animated.model_sets[0]
		if set.models.size() > 0:
			box = set.models[0].bounding_box
	if box.size() == 24:
		maximum.append(box[22])
	return maximum

static func _has_collprims(model: MofFile) -> bool:
	for static_model: MofStatic in model.static_models:
		for part: MofPart in static_model.parts:
			if not part.collprims.is_empty():
				return true
	return false

static func _radius_squared(form: FormBookEntry, model: MofFile) -> Array[int]:
	var result: Array[int] = []
	if model == null:
		return result
	if form.radius_squared != 0:
		result.append(form.radius_squared)
		return result
	var radius: int = 0
	var found: bool = false
	var boxes: Array[PackedInt32Array] = []
	if model.kind == MofFile.Kind.ANIMATED:
		if model.animated == null or model.animated.model_sets.is_empty() or model.animated.model_sets[0].models.is_empty():
			return result
		boxes.append(model.animated.model_sets[0].models[0].bounding_box)
	else:
		for static_model: MofStatic in model.static_models:
			for part: MofPart in static_model.parts:
				for cel: MofPart.Partcel in part.partcels:
					boxes.append(cel.bounding_box)
	for box: PackedInt32Array in boxes:
		if box.size() != 24:
			continue
		found = true
		for corner: int in 8:
			var at: int = corner * 3
			var distance: int = (box[at] * box[at] + box[at + 1] * box[at + 1] + box[at + 2] * box[at + 2]) & 0xffffffff
			if distance >= 0x80000000:
				distance -= 0x100000000
			radius = maxi(radius, distance)
	if model.kind != MofFile.Kind.ANIMATED:
		for static_model: MofStatic in model.static_models:
			for part: MofPart in static_model.parts:
				for primitive: MofPart.Collprim in part.collprims:
					found = true
					var extent: int = 0
					match primitive.type:
						0:
							extent = primitive.size.x * primitive.size.x + primitive.size.y * primitive.size.y + primitive.size.z * primitive.size.z
						1, 2, 3:
							var length: int = primitive.size[primitive.type - 1]
							extent = length * length + primitive.radius_squared
						4:
							extent = primitive.radius_squared
					var distance: int = primitive.offset.x * primitive.offset.x + primitive.offset.y * primitive.offset.y + primitive.offset.z * primitive.offset.z
					radius = maxi(radius & 0xffffffff, (distance + extent) & 0xffffffff)
	if not found:
		return result
	radius = (radius + 100) & 0xffffffff
	result.append(radius - 0x100000000 if radius >= 0x80000000 else radius)
	return result

func _issue(reason: String, entity: EntityDefinition, definition: FormContactDefinition, code: String = "unsupported_form_contact") -> void:
	var diagnostic := EntitySetupDiagnostic.new()
	diagnostic.code = code
	diagnostic.source_id = definition.source_id
	diagnostic.build_id = definition.build_id
	diagnostic.resource_id = definition.resource_id
	diagnostic.entity_index = entity.entity_index
	diagnostic.form_id = entity.form_id
	diagnostic.form_name = entity.form_name
	diagnostic.source_offset = entity.source_offset
	diagnostic.message = reason
	diagnostic.fallback = "First FORM_DATA used for contact" if code == "additional_form_data" else "Base entity transform remains available; contact omitted"
	diagnostics.append(diagnostic)

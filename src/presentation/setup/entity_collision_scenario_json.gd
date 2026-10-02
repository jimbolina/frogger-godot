class_name EntityCollisionScenarioJson
extends RefCounted
## Parses detached entity collision stimuli from authored scenario JSON.

## Returns a validated aggregate or an error string in the supplied output array.
static func decode(value: Variant, errors: PackedStringArray) -> EntityCollisionDefinition:
	if not value is Dictionary:
		errors.append("level.entity_collision must be an object")
		return null
	var row: Dictionary = value
	for key: String in ["group_base", "group_dimensions", "group_size"]:
		if not _vector(row.get(key), 3 if key == "group_base" else 2):
			errors.append("entity_collision.%s must contain integers" % key)
			return null
	if not row.get("entities") is Array or not row.get("contacts") is Array:
		errors.append("entity_collision requires entities and contacts arrays")
		return null
	var result := EntityCollisionDefinition.new()
	var group_base: Array = row.group_base
	var group_dimensions: Array = row.group_dimensions
	var group_size: Array = row.group_size
	result.group_base = _v3(group_base)
	result.group_dimensions = _v2(group_dimensions)
	result.group_size = _v2(group_size)
	for value_entity: Variant in row.entities:
		var entity: EntityDefinition = _entity(value_entity, errors)
		if entity == null:
			return null
		result.entities.append(entity)
	for value_contact: Variant in row.contacts:
		var contact: FormContactDefinition = _contact(value_contact, errors)
		if contact == null:
			return null
		result.contacts.append(contact)
	var issue: String = result.validate()
	if not issue.is_empty():
		errors.append(issue)
		return null
	return result

static func _entity(value: Variant, errors: PackedStringArray) -> EntityDefinition:
	if not value is Dictionary:
		errors.append("Entity must be an object")
		return null
	var row: Dictionary = value
	var entity := EntityDefinition.new()
	for key: String in ["entity_index", "unique_id", "form_grid_id", "form_id", "flags"]:
		if not _integer(row.get(key)):
			errors.append("Entity %s must be an integer" % key)
			return null
		entity.set(key, _number(row[key]))
	for key: String in ["form_name", "entity_name"]:
		if not row.get(key) is String:
			errors.append("Entity %s must be a string" % key)
			return null
		entity.set(key, row[key])
	if entity.entity_name == "STATIC":
		if not _vector(row.get("matrix12"), 12):
			errors.append("Static entity matrix12 must contain 12 integers")
			return null
		var matrix: Array = row.matrix12
		entity.matrix12 = PackedInt32Array(matrix)
	elif entity.entity_name == "MOVING":
		if not row.get("path_definition") is Dictionary or not row.get("path_start") is Dictionary:
			errors.append("Moving entity requires path_definition and path_start")
			return null
		var authored_path: Dictionary = row.path_definition
		if not _integer(authored_path.get("path_index")) or not authored_path.get("segments") is Array:
			errors.append("Path requires index and segments")
			return null
		var path := PathDefinition.new()
		path.path_index = _number(authored_path.path_index)
		for value_segment: Variant in authored_path.segments:
			if not value_segment is Dictionary:
				errors.append("Path segment must be an object")
				return null
			var segment_row: Dictionary = value_segment
			if not _integer(segment_row.get("segment_type")) or not _integer(segment_row.get("length")) or not _vector(segment_row.get("start"), 3) or not _vector(segment_row.get("end"), 3):
				errors.append("Path segment needs integer type, length, start and end")
				return null
			var segment := PathSegmentDefinition.new()
			segment.segment_type = _number(segment_row.segment_type)
			segment.length = _number(segment_row.length)
			var start_vector: Array = segment_row.start
			var end_vector: Array = segment_row.end
			segment.start = _v3(start_vector)
			segment.end = _v3(end_vector)
			path.segments.append(segment)
		entity.path_definition = path
		var authored_start: Dictionary = row.path_start
		var start := PathStart.new()
		for key: String in ["segment_index", "distance", "speed", "flags"]:
			if not _integer(authored_start.get(key)):
				errors.append("Path start %s must be an integer" % key)
				return null
			start.set(key, _number(authored_start[key]))
		entity.path_start = start
	else:
		errors.append("Entity behavior must be STATIC or MOVING")
		return null
	return entity

static func _contact(value: Variant, errors: PackedStringArray) -> FormContactDefinition:
	if not value is Dictionary:
		errors.append("Contact must be an object")
		return null
	var row: Dictionary = value
	var contact := FormContactDefinition.new()
	for key: String in ["entity_index", "unique_id", "form_grid_id", "form_id", "entity_flags", "height", "max_y", "radius_squared", "death_type"]:
		if not _integer(row.get(key)):
			errors.append("Contact %s must be an integer" % key)
			return null
		contact.set(key, _number(row[key]))
	if not row.get("form_name") is String or not row.get("reaction_unsupported_reason", "") is String or not row.get("unsupported_reason", "") is String:
		errors.append("Contact names and reasons must be strings")
		return null
	contact.form_name = row.form_name
	contact.reaction_unsupported_reason = row.get("reaction_unsupported_reason", "")
	contact.unsupported_reason = row.get("unsupported_reason", "")
	if not _vector(row.get("dimensions"), 2) or not _vector(row.get("offsets"), 2) or not row.get("grid_flags") is Array:
		errors.append("Contact needs dimensions, offsets and grid_flags")
		return null
	var dimensions: Array = row.dimensions
	var offsets: Array = row.offsets
	contact.dimensions = _v2(dimensions)
	contact.offsets = _v2(offsets)
	for flag: Variant in row.grid_flags:
		if not _integer(flag):
			errors.append("Contact grid_flags must contain integers")
			return null
		contact.grid_flags.append(_number(flag))
	return contact

static func _vector(value: Variant, count: int) -> bool:
	if not value is Array:
		return false
	var array: Array = value
	if array.size() != count:
		return false
	for item: Variant in array:
		if not _integer(item):
			return false
	return true

static func _integer(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = value
	return is_finite(number) and number == floor(number) and number >= -2147483648.0 and number <= 2147483647.0

static func _v2(values: Array) -> Vector2i:
	return Vector2i(_number(values[0]), _number(values[1]))

static func _v3(values: Array) -> Vector3i:
	return Vector3i(_number(values[0]), _number(values[1]), _number(values[2]))

static func _number(value: Variant) -> int:
	var number: float = value
	return int(number)

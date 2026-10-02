class_name EntityTrace
extends RefCounted
## External JSONL facts for a detached attached-entity run.

var rows: PackedStringArray = PackedStringArray()
var _contacts: Array[FormContactDefinition] = []
var _probe_world: Vector3i = Vector3i.ZERO

## Begins a trace with source identities, hook metadata and diagnostics.
func configure(scenario: EntityScenario) -> void:
	_contacts.clear()
	for contact: FormContactDefinition in scenario.contact_definitions:
		_contacts.append(contact.copy())
	_probe_world = scenario.probe_world
	var identities: Array[Dictionary] = []
	var contact_rows: Array[Dictionary] = []
	for contact: FormContactDefinition in _contacts:
		contact_rows.append({"source_id": contact.source_id, "build_id": contact.build_id,
			"resource_id": contact.resource_id, "entity_index": contact.entity_index,
			"source_offset": contact.source_offset, "unique_id": contact.unique_id,
			"form_grid_id": contact.form_grid_id, "form_id": contact.form_id,
			"form_name": contact.form_name, "entity_flags": contact.entity_flags,
			"dimensions": [contact.dimensions.x, contact.dimensions.y],
			"offsets": [contact.offsets.x, contact.offsets.y], "height": contact.height,
			"max_y": contact.max_y, "radius_squared": contact.radius_squared,
			"grid_flags": Array(contact.grid_flags), "unsupported_reason": contact.unsupported_reason})
	for definition: EntityDefinition in scenario.definitions:
		identities.append({"source_id": definition.source_id, "build_id": definition.build_id,
			"resource_id": definition.resource_id, "entity_index": definition.entity_index,
			"source_offset": definition.source_offset, "unique_id": definition.unique_id,
			"form_grid_id": definition.form_grid_id, "form_id": definition.form_id,
			"form_name": definition.form_name, "entity_name": definition.entity_name,
			"flags": definition.flags, "script_id": definition.script_id,
			"collision_callback": definition.collision_callback,
			"bonus_callback": definition.bonus_callback,
			"path_index": definition.path_definition.path_index if definition.path_definition != null else -1})
	rows = PackedStringArray([JSON.stringify({"schema": "entity-contact-v1", "scenario": scenario.name,
		"level_code": scenario.level_code, "tick_limit": scenario.tick_limit,
		"entities": identities, "contacts": contact_rows,
		"probe_world": [_probe_world.x, _probe_world.y, _probe_world.z],
		"contact_entity_index": scenario.contact_entity_index,
		"diagnostics": Array(scenario.diagnostics)})])

## Appends one complete tick of source-ordered transforms and path cursors.
func append_snapshot(snapshot: EntityRunSnapshot) -> void:
	var entities: Array[Dictionary] = []
	for entity: EntitySnapshot in snapshot.entities:
		var row: Dictionary = {"entity_index": entity.entity_index, "unique_id": entity.unique_id,
			"matrix12": Array(entity.matrix12), "path": null}
		var contact: FormContactDefinition = _contact_for(entity.entity_index)
		if contact != null:
			var result: FormContactResult = FormContactQuery.query(contact, entity, _probe_world)
			row["contact"] = {"status": result.status, "entity_index": result.entity_index,
				"unique_id": result.unique_id, "form_grid_id": result.form_grid_id,
				"form_id": result.form_id, "form_name": result.form_name,
				"local_position": [result.local_position.x, result.local_position.y, result.local_position.z],
				"cell": [result.cell.x, result.cell.y], "height": result.height,
				"cell_flags": result.cell_flags}
		else:
			row["contact"] = null
		if entity.path != null:
			var path: PathSnapshot = entity.path
			row["path"] = {"tick_index": path.tick_index, "segment_index": path.segment_index,
				"segment_type": path.segment_type, "segment_distance": path.segment_distance,
				"segment_length": path.segment_length, "segment_param": path.segment_param,
				"total_distance": path.total_distance, "speed": path.speed, "flags": path.flags,
				"position": [path.position.x, path.position.y, path.position.z],
				"tangent": [path.tangent.x, path.tangent.y, path.tangent.z]}
		entities.append(row)
	rows.append(JSON.stringify({"tick_index": snapshot.tick_index, "entities": entities}))

func _contact_for(index: int) -> FormContactDefinition:
	for contact: FormContactDefinition in _contacts:
		if contact.entity_index == index:
			return contact
	return null

## Writes the trace only to an absolute destination outside the checkout.
func save(path: String) -> String:
	if not ViewerCapture.external_folder(path.get_base_dir()):
		return "Entity trace requires an absolute external destination"
	var failure: String = ViewerCapture.prepare_folder(path.get_base_dir())
	if not failure.is_empty():
		return failure
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Cannot write entity trace '%s': %s" % [path, error_string(FileAccess.get_open_error())]
	file.store_string("\n".join(rows) + "\n")
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return "" if write_error == OK else "Entity trace write failed: " + path

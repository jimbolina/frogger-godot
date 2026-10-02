class_name EntityTrace
extends RefCounted
## External JSONL facts for a detached attached-entity run.

var rows: PackedStringArray = PackedStringArray()

## Begins a trace with source identities, hook metadata and diagnostics.
func configure(scenario: EntityScenario) -> void:
	var identities: Array[Dictionary] = []
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
	rows = PackedStringArray([JSON.stringify({"schema": "entity-run-v1", "scenario": scenario.name,
		"level_code": scenario.level_code, "tick_limit": scenario.tick_limit,
		"entities": identities, "diagnostics": Array(scenario.diagnostics)})])

## Appends one complete tick of source-ordered transforms and path cursors.
func append_snapshot(snapshot: EntityRunSnapshot) -> void:
	var entities: Array[Dictionary] = []
	for entity: EntitySnapshot in snapshot.entities:
		var row: Dictionary = {"entity_index": entity.entity_index, "unique_id": entity.unique_id,
			"matrix12": Array(entity.matrix12), "path": null}
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

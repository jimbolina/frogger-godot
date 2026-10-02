class_name PathTrace
extends RefCounted
## External JSONL observations of one detached path runner.

var rows: PackedStringArray = PackedStringArray()

## Begins a trace with source identity and authored start metadata.
func configure(scenario: PathScenario) -> void:
	rows = PackedStringArray([JSON.stringify({
		"schema": "path-run-v1", "scenario": scenario.name,
		"source_id": scenario.definition.source_id,
		"resource_id": scenario.definition.resource_id,
		"path_index": scenario.definition.path_index,
		"source_offset": scenario.definition.source_offset,
		"level_code": scenario.level_code,
		"tick_limit": scenario.tick_limit,
		"start": {"segment_index": scenario.start.segment_index,
			"distance": scenario.start.distance, "speed": scenario.start.speed,
			"flags": scenario.start.flags},
		"diagnostics": Array(scenario.diagnostics)
	})])

## Appends all authoritative fields from a detached runner snapshot.
func append_snapshot(snapshot: PathSnapshot) -> void:
	rows.append(JSON.stringify({
		"tick_index": snapshot.tick_index,
		"segment_index": snapshot.segment_index,
		"segment_type": snapshot.segment_type,
		"segment_distance": snapshot.segment_distance,
		"segment_length": snapshot.segment_length,
		"segment_param": snapshot.segment_param,
		"total_distance": snapshot.total_distance,
		"speed": snapshot.speed,
		"flags": snapshot.flags,
		"position": [snapshot.position.x, snapshot.position.y, snapshot.position.z],
		"tangent": [snapshot.tangent.x, snapshot.tangent.y, snapshot.tangent.z]
	}))

## Saves rows to an absolute destination outside the checkout and frozen source.
func save(path: String) -> String:
	if not ViewerCapture.external_folder(path.get_base_dir()):
		return "Path trace requires an absolute destination outside the repository"
	var failure: String = ViewerCapture.prepare_folder(path.get_base_dir())
	if not failure.is_empty():
		return failure
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Cannot write path trace '%s': %s" % [path, error_string(FileAccess.get_open_error())]
	file.store_string("\n".join(rows) + "\n")
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return "" if write_error == OK else "Path trace write failed: " + path

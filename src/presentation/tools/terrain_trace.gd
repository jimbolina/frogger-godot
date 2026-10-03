class_name TerrainTrace
extends RefCounted
## External CSV transport for the frozen control/movement component comparison.

const HEADER: String = "scenario,tick,component,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,input,direction,animation_requests,sound_requests,score_requests,buffered_keys,buffered_input_count,pad_pressed,pad_held"
var rows: PackedStringArray = [HEADER]
var full_rows: PackedStringArray = PackedStringArray()
var _entity_reactions: bool = false

## Records the supplied scenario identity and explicit component omissions once.
func configure(scenario: TerrainScenario) -> void:
	_entity_reactions = scenario.entity_reactions
	var metadata: Dictionary = {"schema": "entity-platform-v1" if scenario.platforms_enabled else "entity-pop-v1" if scenario.entity_reactions else "terrain-run-v1", "scenario": scenario.identifier,
		"source_id": scenario.level.source_id, "resource_id": scenario.level.resource_id, "map_index": scenario.level.map_index,
		"seed": scenario.initial.seed, "tick_limit": scenario.tick_limit, "start": facts(scenario.initial),
		"camera_definition": facts(scenario.level.camera) if scenario.level.camera != null else null,
		"action_lengths": Array(scenario.level.frog_action_lengths),
		"omitted": ["platforms", "scripts", "zones", "audio", "effects", "game_flow", "particle_simulation", "visibility_driven_lifecycle"] if scenario.entity_reactions else ["entities", "forms", "zones", "audio", "effects", "game_flow"],
		"diagnostics": Array(scenario.diagnostics)}
	if scenario.entity_reactions:
		if scenario.platforms_enabled:
			metadata["omitted"] = ["scripts", "zones", "audio", "effects", "game_flow", "particle_simulation", "visibility_driven_lifecycle", "entity_sliding_bouncing", "multiplayer"]
		metadata["entity_collision"] = facts(scenario.level.entity_collision) if scenario.level.entity_collision != null else null
		metadata["entity_lifetime"] = "all_attached"
	full_rows = PackedStringArray([JSON.stringify(metadata)])

## Records actual rule phase observations; never advances or edits a run.
func append_result(scenario: int, command: TickCommand, result: TickResult) -> void:
	_append(scenario, command, "control", result.control_snapshot)
	_append(scenario, command, "move", result.move_snapshot)
	for phase: String in ["control", "move", "collision", "camera", "final"]:
		var snapshot: RunSnapshot = result.get(phase + "_snapshot")
		if snapshot != null:
			var record: Dictionary = {"tick": command.tick_index, "phase": phase,
				"pressed": command.pressed_mask, "held": command.held_mask,
				"command": facts(command),
				"state": facts(snapshot),
				"outcomes": Array(result.events) if phase == "final" else [],
				"rng_consumers": Array(result.rng_consumers) if phase == "final" else [], "error": result.error}
			if _entity_reactions:
				record["entity_contacts"] = _value(result.entity_contacts) if phase == "final" else []
			full_rows.append(JSON.stringify(record))

## Saves text evidence only to a caller-selected external directory.
func save(path: String) -> String:
	return _save_lines(path, rows)

## Saves all represented integer state and ordered outcomes for replay comparisons.
func save_full(path: String) -> String:
	return _save_lines(path, full_rows)

func _save_lines(path: String, lines: PackedStringArray) -> String:
	if not ViewerCapture.external_folder(path.get_base_dir()):
		return "Terrain trace requires an absolute destination outside the repository"
	var frozen: String = ProjectSettings.globalize_path("res://../froggy").replace("\\", "/").simplify_path().to_lower()
	var resolved: String = path.replace("\\", "/").simplify_path().to_lower()
	if resolved == frozen or resolved.begins_with(frozen + "/"):
		return "Terrain trace cannot write inside the frozen reference repository"
	var failure: String = ViewerCapture.prepare_folder(path.get_base_dir())
	if not failure.is_empty():
		return failure
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Cannot write terrain trace '%s': %s" % [path, error_string(FileAccess.get_open_error())]
	file.store_string("\n".join(lines) + "\n")
	return "" if file.get_error() == OK else "Terrain trace write failed: " + path

func _append(scenario: int, command: TickCommand, phase: String, state: RunSnapshot) -> void:
	var fields: Array = [scenario, command.tick_index, phase, state.position_16.x, state.position_16.y, state.position_16.z,
		state.velocity_16.x, state.velocity_16.y, state.velocity_16.z, state.cell.x, state.cell.y,
		state.remaining_ticks, state.flags, state.mode, state.current_input, state.direction,
		state.animation_requests, state.sound_requests, state.score_requests, state.buffered_keys,
		state.buffered_input_count, command.pressed_mask, command.held_mask]
	var strings := PackedStringArray()
	for value: Variant in fields:
		strings.append(str(value))
	rows.append(",".join(strings))

## Serializes detached rule records only; this reflection remains outside gameplay.
static func facts(record: RefCounted) -> Dictionary:
	var values: Dictionary = {}
	for property: Dictionary in record.get_property_list():
		var usage: int = property.usage
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var key: String = property.name
			values[key] = _value(record.get(key))
	return values

static func _value(value: Variant) -> Variant:
	if value is Vector3i:
		var vector: Vector3i = value
		return [vector.x, vector.y, vector.z]
	if value is Vector2i:
		var vector: Vector2i = value
		return [vector.x, vector.y]
	if value is PackedInt32Array:
		var integers: PackedInt32Array = value
		return Array(integers)
	if value is PackedInt64Array:
		var integers: PackedInt64Array = value
		return Array(integers)
	if value is PackedStringArray:
		var strings: PackedStringArray = value
		return Array(strings)
	if value is Array:
		var source: Array = value
		var array: Array = []
		for item: Variant in source:
			array.append(_value(item))
		return array
	if value is RefCounted:
		var child: RefCounted = value
		return facts(child)
	if value == null or value is int or value is bool or value is String or value is StringName:
		return value
	push_error("Unsupported rule trace value type %d" % typeof(value))
	return "unsupported"

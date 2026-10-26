class_name TerrainTrace
extends RefCounted
## External CSV transport for the frozen control/movement component comparison.

const HEADER: String = "scenario,tick,component,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,input,direction,animation_requests,sound_requests,score_requests,buffered_keys,buffered_input_count,pad_pressed,pad_held"
var rows: PackedStringArray = [HEADER]
var full_rows: PackedStringArray = PackedStringArray()
var _entity_reactions: bool = false
var _entity_lifecycle: bool = false
var _guarded_exploration: bool = false
var _scripted_exploration: bool = false
var _primitive_exploration: bool = false
var _full_stream: FileAccess = null
var _full_path: String = ""

## Records the supplied scenario identity and explicit component omissions once.
func configure(scenario: TerrainScenario) -> void:
	_entity_reactions = scenario.options.entity_reactions
	_entity_lifecycle = scenario.options.entity_lifecycle
	_guarded_exploration = scenario.level.tick_guard != null
	_scripted_exploration = scenario.options.exploration_preset in [Org1ExplorationSetup.PRESET, Org1ExplorationSetup.ROAD_PRESET, Org1ExplorationSetup.VISIBILITY_PRESET]
	_primitive_exploration = scenario.level.entity_collision != null and scenario.level.entity_collision.frog_collision != null
	var metadata: Dictionary = {"schema": "entity-exploration-v1" if _guarded_exploration else "entity-lifecycle-v1" if scenario.options.entity_lifecycle else "entity-platform-v1" if scenario.options.platforms_enabled else "entity-pop-v1" if scenario.options.entity_reactions else "terrain-run-v1", "scenario": scenario.identifier,
		"source_id": scenario.level.source_id, "resource_id": scenario.level.resource_id, "map_index": scenario.level.map_index,
		"seed": scenario.initial.seed, "tick_limit": scenario.tick_limit, "start": facts(scenario.initial),
		"camera_definition": facts(scenario.level.camera) if scenario.level.camera != null else null,
		"action_lengths": Array(scenario.level.frog_action_lengths),
		"omitted": ["platforms", "scripts", "zones", "audio", "effects", "game_flow", "particle_simulation", "visibility_driven_lifecycle"] if scenario.options.entity_reactions else ["entities", "forms", "zones", "audio", "effects", "game_flow"],
		"diagnostics": Array(scenario.diagnostics)}
	if not scenario.level.camera_zones.is_empty():
		var zone_facts: Array[Dictionary] = []
		for zone: ZoneDefinition in scenario.level.camera_zones:
			zone_facts.append(facts(zone))
		metadata["camera_zones"] = zone_facts
	if scenario.options.entity_reactions:
		if scenario.options.platforms_enabled:
			metadata["omitted"] = ["scripts", "zones", "audio", "effects", "game_flow", "particle_simulation", "visibility_driven_lifecycle", "entity_sliding_bouncing", "multiplayer"]
		if scenario.options.entity_lifecycle:
			metadata["omitted"] = ["scripts", "zones", "audio", "effects", "game_flow", "particle_simulation", "entity_sliding_bouncing", "multiplayer"]
		metadata["entity_collision"] = facts(scenario.level.entity_collision, _entity_lifecycle) if scenario.level.entity_collision != null else null
		metadata["entity_lifetime"] = "visibility" if scenario.options.entity_lifecycle else "all_attached"
	if scenario.level.tick_guard != null:
		metadata["exploration"] = scenario.options.exploration_preset
		metadata["exploration_guard"] = facts(scenario.level.tick_guard)
		metadata["omitted"] = ["scripts", "active_camera_zones", "custom_behaviors", "primitives", "audio", "effects", "game_flow", "particle_simulation", "visibility_driven_lifecycle", "entity_sliding_bouncing", "multiplayer"]
		if _scripted_exploration:
			metadata["omitted"] = ["unsupported_scripts_and_custom_behaviors", "active_camera_zones", "primitives", "audio_playback", "splash_rendering", "game_flow", "particle_simulation", "visibility_driven_lifecycle", "entity_sliding_bouncing", "multiplayer"]
		if _entity_lifecycle:
			var omissions: Array = metadata["omitted"]
			omissions.erase("visibility_driven_lifecycle")
		if _primitive_exploration:
			var omissions: Array = metadata["omitted"]
			omissions.erase("primitives")
			omissions.append("unsupported_primitive_shapes_and_reactions")
	if not scenario.level.camera_zones.is_empty():
		var active_omissions: Array = metadata["omitted"]
		active_omissions.erase("zones")
		active_omissions.erase("active_camera_zones")
	full_rows = PackedStringArray([JSON.stringify(metadata)])

## Records actual rule phase observations; never advances or edits a run.
func append_result(scenario: int, command: TickCommand, result: TickResult) -> void:
	_append(scenario, command, "control", result.control_snapshot)
	_append(scenario, command, "move", result.move_snapshot)
	var phases: Array[String] = ["control", "move", "collision", "camera", "final"]
	if _guarded_exploration:
		phases.insert(4, "scripts")
	for phase: String in phases:
		var snapshot: GameplayState = result.get(phase + "_snapshot")
		if snapshot != null:
			var record: Dictionary = {"tick": command.tick_index, "phase": phase,
				"pressed": command.pressed_mask, "held": command.held_mask,
				"command": facts(command),
				"state": facts(snapshot, _entity_lifecycle or _scripted_exploration),
				"outcomes": Array(TickEvent.trace_lines(result.events)) if phase == "final" else [],
				"rng_consumers": Array(result.rng_consumers) if phase == "final" else [], "error": result.error}
			if _entity_reactions:
				record["entity_contacts"] = _value(result.entity_contacts) if phase == "final" else []
				if _primitive_exploration:
					record["primitive_contacts"] = _value(result.primitive_contacts) if phase == "final" else []
				if _entity_lifecycle:
					record["entity_lifecycle"] = facts(snapshot.entities, true) if snapshot.entities != null else null
			var line: String = JSON.stringify(record)
			if _full_stream != null:
				_full_stream.store_line(line)
			else:
				full_rows.append(line)

## Streams long inspection evidence externally without retaining it in memory.
func stream_full(path: String) -> String:
	var issue: String = _save_lines(path, full_rows)
	if not issue.is_empty():
		return issue
	_full_stream = FileAccess.open(path, FileAccess.READ_WRITE)
	if _full_stream == null:
		return "Cannot open full trace stream: " + path
	_full_path = path
	_full_stream.seek_end()
	full_rows.clear()
	return ""

## Saves text evidence only to a caller-selected external directory.
func save(path: String) -> String:
	return _save_lines(path, rows)

## Saves all represented integer state and ordered outcomes for replay comparisons.
func save_full(path: String) -> String:
	if _full_stream != null:
		_full_stream.flush()
		var issue: String = "" if _full_stream.get_error() == OK and path == _full_path else "Full trace stream failed: " + path
		_full_stream.close()
		_full_stream = null
		return issue
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

func _append(scenario: int, command: TickCommand, phase: String, state: GameplayState) -> void:
	var fields: Array = [scenario, command.tick_index, phase, state.frog.position_16.x, state.frog.position_16.y, state.frog.position_16.z,
		state.frog.velocity_16.x, state.frog.velocity_16.y, state.frog.velocity_16.z, state.frog.cell.x, state.frog.cell.y,
		state.frog.remaining_ticks, state.frog.flags, state.frog.mode, state.frog.current_input, state.frog.direction,
		state.requests.animation_requests, state.requests.sound_requests, state.requests.score_requests, state.frog.buffered_keys,
		state.frog.buffered_input_count, command.pressed_mask, command.held_mask]
	var strings := PackedStringArray()
	for value: Variant in fields:
		strings.append(str(value))
	rows.append(",".join(strings))

## Serializes detached rule records only; this reflection remains outside gameplay.
static func facts(record: RefCounted, include_lifecycle: bool = false) -> Dictionary:
	var values: Dictionary = {}
	if record is GameplayState:
		var state: GameplayState = record
		for part: RefCounted in [state.frog, state.attachment, state.requests, state.diagnostics]:
			values.merge(facts(part, include_lifecycle))
	for property: Dictionary in record.get_property_list():
		var usage: int = property.usage
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var key: String = property.name
			if record is GameplayState and key in ["frog", "attachment", "requests", "diagnostics"]:
				continue
			if record is EntityDefinition and key == "behavior":
				var entity: EntityDefinition = record
				values["animation_one_shot"] = entity.behavior.one_shot
				values["background_admitted"] = entity.behavior.has_custom_update()
				values["pink_frog_pickup"] = entity.behavior.execution == EntityBehavior.Execution.CONTACT
				continue
			if not include_lifecycle and _lifecycle_key(record, key):
				continue
			values["fixture_lives" if record is FrogState and key == "lives" else "admission_exclusion" if key == "disabled_reason" else "exploration_guard" if key == "tick_guard" else key] = _value(record.get(key), include_lifecycle)
	return values

static func _lifecycle_key(record: RefCounted, key: String) -> bool:
	if record is EntityCollisionDefinition:
		return key == "lifecycle"
	if record is EntityRunSnapshot:
		return key in ["lifecycle_enabled", "live_order", "selected_groups", "lifecycle_events"]
	if record is EntitySnapshot:
		return key in ["lifecycle_supported", "live", "destroy_pending", "generation"]
	return false

static func _value(value: Variant, include_lifecycle: bool = false) -> Variant:
	if value is TickEvent:
		var event: TickEvent = value
		return event.to_trace_line()
	if value is Dictionary:
		var source: Dictionary = value
		var result: Dictionary = {}
		for key: Variant in source:
			result[str(key)] = _value(source[key], include_lifecycle)
		return result
	if value is Rect2i:
		var rectangle: Rect2i = value
		return [rectangle.position.x, rectangle.position.y, rectangle.size.x, rectangle.size.y]
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
			array.append(_value(item, include_lifecycle))
		return array
	if value is RefCounted:
		var child: RefCounted = value
		return facts(child, include_lifecycle)
	if value == null or value is int or value is bool or value is String or value is StringName:
		return value
	push_error("Unsupported rule trace value type %d" % typeof(value))
	return "unsupported"
